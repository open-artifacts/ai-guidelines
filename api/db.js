import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';

const NOW = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

// Camada de dados: um unico arquivo SQLite, uma unica tabela.
export function openStore(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });

  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA busy_timeout = 5000;

    CREATE TABLE IF NOT EXISTS votes (
      rating_id  INTEGER NOT NULL CHECK (rating_id >= 1),
      voter_id   TEXT    NOT NULL,
      score      INTEGER NOT NULL CHECK (score BETWEEN 1 AND 5),
      created_at TEXT    NOT NULL DEFAULT (${NOW}),
      updated_at TEXT    NOT NULL DEFAULT (${NOW}),
      PRIMARY KEY (rating_id, voter_id)
    ) WITHOUT ROWID;

    CREATE INDEX IF NOT EXISTS idx_votes_voter ON votes (voter_id);
  `);

  const q = {
    summary: db.prepare(`
      SELECT rating_id AS id, COUNT(*) AS votes, ROUND(AVG(score), 2) AS average
      FROM votes GROUP BY rating_id ORDER BY rating_id`),
    byVoter: db.prepare('SELECT rating_id, score FROM votes WHERE voter_id = ?'),
    stats: db.prepare(`
      SELECT COUNT(*) AS votes, COALESCE(ROUND(AVG(score), 2), 0) AS average
      FROM votes WHERE rating_id = ?`),
    upsert: db.prepare(`
      INSERT INTO votes (rating_id, voter_id, score) VALUES (?, ?, ?)
      ON CONFLICT (rating_id, voter_id)
      DO UPDATE SET score = excluded.score, updated_at = ${NOW}`),
    remove: db.prepare('DELETE FROM votes WHERE rating_id = ? AND voter_id = ?'),
    restore: db.prepare(`
      INSERT INTO votes (rating_id, voter_id, score, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT (rating_id, voter_id)
      DO UPDATE SET score = excluded.score,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at`),
  };

  // Mesmo formato que o front-end ja consumia das RPCs do Supabase.
  const ratingResult = (ratingId) => ({ ratingId, ...q.stats.get(ratingId) });

  return {
    ratings: () => q.summary.all().map((r) => ({ ...r })),

    votesOf: (voterId) =>
      Object.fromEntries(q.byVoter.all(voterId).map((r) => [r.rating_id, r.score])),

    submitVote(ratingId, voterId, score) {
      q.upsert.run(ratingId, voterId, score);
      return ratingResult(ratingId);
    },

    removeVote(ratingId, voterId) {
      q.remove.run(ratingId, voterId);
      return ratingResult(ratingId);
    },

    // Importa votos preservando as datas originais (migracao do Supabase).
    importVotes(rows) {
      db.exec('BEGIN');
      try {
        for (const r of rows) {
          q.restore.run(r.rating_id, r.voter_id, r.score, r.created_at, r.updated_at);
        }
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
      return rows.length;
    },

    // Copia consistente do banco (VACUUM INTO) e rotacao dos mais antigos.
    backup(dir, keep = 14) {
      mkdirSync(dir, { recursive: true });
      const file = join(dir, `votes-${new Date().toISOString().slice(0, 10)}.db`);
      rmSync(file, { force: true });
      db.exec(`VACUUM INTO '${file.replaceAll("'", "''")}'`);

      readdirSync(dir)
        .filter((name) => /^votes-\d{4}-\d{2}-\d{2}\.db$/.test(name))
        .sort()
        .slice(0, -keep)
        .forEach((name) => rmSync(join(dir, name)));
      return file;
    },

    close: () => db.close(),
  };
}
