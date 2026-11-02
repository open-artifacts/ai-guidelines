// Importa os votos exportados do Supabase (JSON) para o SQLite, mantendo
// voter_id e datas. Uso:
//   DB_PATH=./data/votes.db node import-votes.js votes-supabase.json
import { readFileSync } from 'node:fs';
import { openStore } from './db.js';

const file = process.argv[2];
if (!file) {
  console.error('Uso: node import-votes.js <arquivo.json>');
  process.exit(1);
}

const rows = JSON.parse(readFileSync(file, 'utf8'));
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

for (const r of rows) {
  const valid =
    Number.isInteger(r.rating_id) && r.rating_id >= 1 &&
    UUID_RE.test(r.voter_id) &&
    Number.isInteger(r.score) && r.score >= 1 && r.score <= 5 &&
    r.created_at && r.updated_at;
  if (!valid) {
    console.error('Linha invalida, nada foi importado:', JSON.stringify(r));
    process.exit(1);
  }
}

const store = openStore(process.env.DB_PATH ?? './data/votes.db');
const count = store.importVotes(rows.map((r) => ({ ...r, voter_id: r.voter_id.toLowerCase() })));
console.log(`${count} votos importados. Resumo por diretriz:`);
console.table(store.ratings());
store.close();
