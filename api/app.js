import { createServer } from 'node:http';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VOTE_PATH_RE = /^\/api\/votes\/(\d{1,4})$/;
const MAX_BODY_BYTES = 1024;

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

// API HTTP minima: sem framework, sem dependencias.
//   GET    /api/health
//   GET    /api/state?voter=<uuid>      -> { ratings, myVotes }
//   PUT    /api/votes/:id  { voter, score }
//   DELETE /api/votes/:id?voter=<uuid>
export function createApp({
  store,
  allowedOrigin = '',
  maxRatingId = 17,
  limits = { windowMs: 60_000, reads: 120, writes: 30 },
  clientIpHeader = 'x-forwarded-for',
}) {
  const hits = new Map(); // ip -> { reads, writes, resetAt } (somente em memoria)

  function clientIp(req) {
    // Vale o ultimo valor: e o que o proxy da frente (Apache, nginx, Caddy)
    // acrescentou. Os anteriores vieram do cliente e podem ser forjados.
    const forwarded = req.headers[clientIpHeader];
    if (forwarded) return String(forwarded).split(',').pop().trim();
    return req.socket.remoteAddress ?? 'unknown';
  }

  // true quando o IP estourou o limite da janela atual.
  function isLimited(ip, isWrite) {
    const now = Date.now();
    if (hits.size > 5000) {
      for (const [key, entry] of hits) if (entry.resetAt <= now) hits.delete(key);
    }
    let entry = hits.get(ip);
    if (!entry || entry.resetAt <= now) {
      entry = { reads: 0, writes: 0, resetAt: now + limits.windowMs };
      hits.set(ip, entry);
    }
    if (isWrite) entry.writes += 1;
    else entry.reads += 1;
    return entry.writes > limits.writes || entry.reads > limits.reads;
  }

  function send(res, status, body) {
    const payload = body === undefined ? '' : JSON.stringify(body);
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    res.end(payload);
  }

  function applyCors(req, res) {
    const origin = req.headers.origin;
    if (allowedOrigin && origin === allowedOrigin) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, DELETE, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
      res.setHeader('Access-Control-Max-Age', '86400');
    }
    res.setHeader('Vary', 'Origin');
  }

  async function readJson(req) {
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) throw new HttpError(413, 'body_too_large');
      chunks.push(chunk);
    }
    try {
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (body === null || typeof body !== 'object') throw new Error();
      return body;
    } catch {
      throw new HttpError(400, 'invalid_json');
    }
  }

  function parseRatingId(raw) {
    const id = Number(raw);
    if (!Number.isInteger(id) || id < 1 || id > maxRatingId) {
      throw new HttpError(400, 'invalid_rating_id');
    }
    return id;
  }

  function parseVoter(raw) {
    if (typeof raw !== 'string' || !UUID_RE.test(raw)) {
      throw new HttpError(400, 'invalid_voter');
    }
    return raw.toLowerCase();
  }

  async function route(req, res, url) {
    const { pathname, searchParams } = url;

    if (pathname === '/api/health') {
      if (req.method !== 'GET') throw new HttpError(405, 'method_not_allowed');
      return send(res, 200, { ok: true });
    }

    if (pathname === '/api/state') {
      if (req.method !== 'GET') throw new HttpError(405, 'method_not_allowed');
      const voter = parseVoter(searchParams.get('voter'));
      return send(res, 200, { ratings: store.ratings(), myVotes: store.votesOf(voter) });
    }

    const match = VOTE_PATH_RE.exec(pathname);
    if (match) {
      const ratingId = parseRatingId(match[1]);

      if (req.method === 'PUT') {
        const body = await readJson(req);
        const voter = parseVoter(body.voter);
        if (!Number.isInteger(body.score) || body.score < 1 || body.score > 5) {
          throw new HttpError(400, 'invalid_score');
        }
        return send(res, 200, store.submitVote(ratingId, voter, body.score));
      }

      if (req.method === 'DELETE') {
        const voter = parseVoter(searchParams.get('voter'));
        return send(res, 200, store.removeVote(ratingId, voter));
      }

      throw new HttpError(405, 'method_not_allowed');
    }

    throw new HttpError(404, 'not_found');
  }

  return createServer(async (req, res) => {
    applyCors(req, res);

    try {
      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        return res.end();
      }

      const url = new URL(req.url, 'http://localhost');
      if (url.pathname !== '/api/health' && isLimited(clientIp(req), req.method !== 'GET')) {
        throw new HttpError(429, 'rate_limited');
      }
      await route(req, res, url);
    } catch (error) {
      if (error instanceof HttpError) {
        send(res, error.status, { error: error.code });
      } else {
        console.error('erro inesperado:', error.message);
        send(res, 500, { error: 'internal' });
      }
    }
  });
}
