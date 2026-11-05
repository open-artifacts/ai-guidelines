# API de votos

Node 22 puro (`node:http` e `node:sqlite`), sem dependências npm. Guarda os votos em um único arquivo SQLite.

| Arquivo | Papel |
|---------|-------|
| `app.js` | rotas HTTP, validação, CORS e limite por IP |
| `db.js` | banco: tabela `votes`, consultas preparadas, importação e backup |
| `index.js` | sobe o servidor, faz o backup diário e encerra limpo no `SIGTERM` |
| `import-votes.js` | importa votos de um JSON (usado na migração do Supabase, já concluída) |
| `app.test.js` | testes (`node --test`, banco em memória) |
| `Dockerfile` | imagem `node:22-slim`, usuário `node`, healthcheck |

## Rotas

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/state?voter=<uuid>` | Médias de todas as diretrizes e os votos do votante: `{ ratings: [{id, votes, average}], myVotes: {id: score} }` |
| PUT | `/api/votes/:id` | Corpo `{ "voter": "<uuid>", "score": 1-5 }`. Cria ou atualiza o voto |
| DELETE | `/api/votes/:id?voter=<uuid>` | Remove o voto |
| GET | `/api/health` | `{ "ok": true }` (monitoramento; não conta no limite) |

PUT e DELETE respondem `{ ratingId, votes, average }`. Erros vêm como `{ "error": "<codigo>" }` com HTTP 400, 404, 405, 413, 429 ou 500.

**Validação:** diretriz entre 1 e `MAX_RATING_ID`, nota inteira de 1 a 5, `voter` em formato UUID, corpo de até 1 KB.

## Dados

Uma tabela, `votes`, em um único arquivo SQLite:

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `rating_id` | INTEGER | ID da diretriz (1 a N) |
| `voter_id` | TEXT | UUID anônimo do votante |
| `score` | INTEGER | Nota de 1 a 5 |
| `created_at` / `updated_at` | TEXT (ISO 8601) | Primeiro voto / última alteração |

Chave primária `(rating_id, voter_id)`: no máximo um voto por pessoa por diretriz.

## Configuração (variáveis de ambiente)

| Variável | Padrão | Para quê |
|----------|--------|----------|
| `ALLOWED_ORIGIN` | vazio | Origem do site liberada no CORS (sem barra final). Vazia = nenhum site liberado |
| `MAX_RATING_ID` | `17` | Maior id de diretriz aceito. Acompanha o total em `web/diretrizes.json` |
| `RATE_LIMIT_READS` | `300` | Leituras por minuto por IP (HTTP 429 depois disso) |
| `RATE_LIMIT_WRITES` | `120` | Votos por minuto por IP |
| `PORT` | `3000` | Porta HTTP |
| `DB_PATH` | `./data/votes.db` | Arquivo do banco (no container: `/data/votes.db`, num volume) |
| `BACKUP_DIR` | `<pasta do banco>/backups` | Onde ficam os backups |

O limite é por IP e usa o **último** valor de `X-Forwarded-For` (o que o proxy da frente acrescenta). Os contadores vivem só na memória. Os limites padrão cabem uma turma inteira atrás do mesmo IP (rede de universidade), e votar não exige login, então o limite freia abuso mas não impede quem usa vários IPs (veja [docs/seguranca.md](../docs/seguranca.md)).

## Backup

Ao iniciar e a cada 24 h a API gera uma cópia consistente (`VACUUM INTO`) em `BACKUP_DIR/votes-AAAA-MM-DD.db` e mantém as 14 mais recentes. Como ficam no mesmo volume dos votos, copie-as para fora do servidor (veja [docs/vps.md](../docs/vps.md)).

## Testes

```bash
docker compose -f compose.dev.yaml run --rm api npm test     # na raiz do repositório
cd api && npm test                                           # com Node >= 22.13
```

Cobrem o fluxo de voto, a validação, o CORS, o limite por IP (inclusive `X-Forwarded-For` forjado), a importação e o backup.
