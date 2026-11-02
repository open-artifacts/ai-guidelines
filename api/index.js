import { dirname, join } from 'node:path';
import { openStore } from './db.js';
import { createApp } from './app.js';

const port = Number(process.env.PORT ?? 3000);
const dbPath = process.env.DB_PATH ?? './data/votes.db';
const backupDir = process.env.BACKUP_DIR ?? join(dirname(dbPath), 'backups');

const store = openStore(dbPath);
const server = createApp({
  store,
  allowedOrigin: process.env.ALLOWED_ORIGIN ?? '',
  maxRatingId: Number(process.env.MAX_RATING_ID ?? 17),
});

server.listen(port, '0.0.0.0', () => console.log(`API ouvindo na porta ${port}`));

// Backup ao subir e depois uma vez por dia (mantem os 14 mais recentes).
function runBackup() {
  try {
    console.log('backup gerado:', store.backup(backupDir));
  } catch (error) {
    console.error('backup falhou:', error.message);
  }
}
runBackup();
setInterval(runBackup, 24 * 60 * 60 * 1000).unref();

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => server.close(() => {
    store.close();
    process.exit(0);
  }));
}
