import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openStore } from './db.js';
import { createApp } from './app.js';

const ORIGIN = 'https://open-artifacts.github.io';
const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';

let store, server, base;

async function start(options = {}) {
  store = openStore(':memory:');
  server = createApp({ store, allowedOrigin: ORIGIN, maxRatingId: 17, ...options });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
}

async function stop() {
  await new Promise((resolve) => server.close(resolve));
  store.close();
}

// Cada teste parte de um banco vazio.
beforeEach(() => start());
afterEach(() => stop());

const put = (id, body) =>
  fetch(`${base}/api/votes/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
const del = (id, voter) => fetch(`${base}/api/votes/${id}?voter=${voter}`, { method: 'DELETE' });
const state = (voter) => fetch(`${base}/api/state?voter=${voter}`).then((r) => r.json());

test('estado inicial vazio', async () => {
  assert.deepEqual(await state(A), { ratings: [], myVotes: {} });
});

test('registra, atualiza e remove um voto', async () => {
  let res = await put(3, { voter: A, score: 4 });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ratingId: 3, votes: 1, average: 4 });

  res = await put(3, { voter: A, score: 2 });
  assert.deepEqual(await res.json(), { ratingId: 3, votes: 1, average: 2 });
  assert.deepEqual((await state(A)).myVotes, { 3: 2 });

  res = await del(3, A);
  assert.deepEqual(await res.json(), { ratingId: 3, votes: 0, average: 0 });
  assert.deepEqual(await state(A), { ratings: [], myVotes: {} });
});

test('media e contagem com dois votantes; votos de cada um sao isolados', async () => {
  await put(5, { voter: A, score: 5 });
  const res = await put(5, { voter: B, score: 4 });
  assert.deepEqual(await res.json(), { ratingId: 5, votes: 2, average: 4.5 });

  const s = await state(A);
  assert.deepEqual(s.ratings, [{ id: 5, votes: 2, average: 4.5 }]);
  assert.deepEqual(s.myVotes, { 5: 5 });
});

test('rejeita entradas invalidas', async () => {
  for (const [id, body] of [
    [3, { voter: A, score: 0 }],
    [3, { voter: A, score: 6 }],
    [3, { voter: A, score: 3.5 }],
    [3, { voter: A, score: '4' }],
    [3, { voter: 'nao-e-uuid', score: 3 }],
    [3, {}],
    [0, { voter: A, score: 3 }],
    [18, { voter: A, score: 3 }],
  ]) {
    const res = await put(id, body);
    assert.equal(res.status, 400, JSON.stringify([id, body]));
  }
  assert.equal((await fetch(`${base}/api/state`)).status, 400);
  assert.equal((await del(3, 'x')).status, 400);

  const bad = await fetch(`${base}/api/votes/3`, { method: 'PUT', body: '{nao json' });
  assert.equal(bad.status, 400);
  const big = await put(3, { voter: A, score: 3, lixo: 'x'.repeat(2000) });
  assert.equal(big.status, 413);
});

test('rotas e metodos desconhecidos', async () => {
  assert.equal((await fetch(`${base}/api/nada`)).status, 404);
  assert.equal((await fetch(`${base}/api/state`, { method: 'POST' })).status, 405);
  assert.equal((await fetch(`${base}/api/votes/3`)).status, 405);
  assert.equal((await fetch(`${base}/api/health`)).status, 200);
});

test('CORS so para a origem permitida', async () => {
  let res = await fetch(`${base}/api/votes/3`, {
    method: 'OPTIONS',
    headers: { Origin: ORIGIN, 'Access-Control-Request-Method': 'PUT' },
  });
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-origin'), ORIGIN);
  assert.match(res.headers.get('access-control-allow-methods'), /PUT/);

  res = await fetch(`${base}/api/health`, { headers: { Origin: 'https://outro.site' } });
  assert.equal(res.headers.get('access-control-allow-origin'), null);
});

test('limite de requisicoes por IP (o health nao conta)', async () => {
  await stop();
  await start({ limits: { windowMs: 60_000, reads: 3, writes: 2 } });
  const headers = { 'X-Forwarded-For': '203.0.113.9' };
  const get = () => fetch(`${base}/api/state?voter=${A}`, { headers }).then((r) => r.status);

  assert.deepEqual([await get(), await get(), await get(), await get()], [200, 200, 200, 429]);
  for (let i = 0; i < 10; i += 1) {
    assert.equal((await fetch(`${base}/api/health`, { headers })).status, 200);
  }

  // Outro IP nao e afetado.
  const other = await fetch(`${base}/api/state?voter=${A}`, {
    headers: { 'X-Forwarded-For': '198.51.100.7' },
  });
  assert.equal(other.status, 200);
});

test('limite por IP vale o ultimo X-Forwarded-For (o primeiro pode ser forjado)', async () => {
  await stop();
  await start({ limits: { windowMs: 60_000, reads: 2, writes: 2 } });
  const get = (forwarded) =>
    fetch(`${base}/api/state?voter=${A}`, { headers: { 'X-Forwarded-For': forwarded } }).then((r) => r.status);

  assert.deepEqual(
    [await get('1.1.1.1, 203.0.113.9'), await get('2.2.2.2, 203.0.113.9'), await get('3.3.3.3, 203.0.113.9')],
    [200, 200, 429],
  );
});

test('importacao preserva os votos e o backup e uma copia legivel', () => {
  store.importVotes([
    { rating_id: 1, voter_id: A, score: 5, created_at: '2026-03-14T10:00:00.000Z', updated_at: '2026-06-20T10:00:00.000Z' },
    { rating_id: 1, voter_id: B, score: 4, created_at: '2026-03-14T11:00:00.000Z', updated_at: '2026-03-14T11:00:00.000Z' },
  ]);
  assert.deepEqual(store.ratings(), [{ id: 1, votes: 2, average: 4.5 }]);

  const dir = mkdtempSync(join(tmpdir(), 'votes-backup-'));
  try {
    const file = store.backup(dir);
    const copy = openStore(file);
    assert.deepEqual(copy.ratings(), [{ id: 1, votes: 2, average: 4.5 }]);
    copy.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('backup mantem so os mais recentes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'votes-backup-'));
  try {
    for (const day of ['2020-01-01', '2020-01-02', '2020-01-03']) {
      writeFileSync(join(dir, `votes-${day}.db`), '');
    }
    writeFileSync(join(dir, 'outro-arquivo.txt'), '');

    const file = store.backup(dir, 2);
    const remaining = readdirSync(dir).sort();
    assert.equal(remaining.length, 3); // 2 backups + arquivo estranho preservado
    assert.ok(remaining.includes('outro-arquivo.txt'));
    assert.ok(remaining.includes(file.split(/[\\/]/).pop()));
    assert.ok(!remaining.includes('votes-2020-01-01.db'));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
