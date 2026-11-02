# Diretrizes IA: GitHub Pages + API própria

Catálogo interativo de diretrizes para uso de IA Generativa no ensino de programação, com sistema de avaliação (rating) compartilhado e controle de voto único por usuário.

## Arquitetura

```
GitHub Pages (estático)            VPS (Docker)
┌──────────────────────┐  HTTPS   ┌─────────────────────────┐
│  index.html          │◄────────►│  Caddy (opcional, TLS)  │
│  css/ js/            │   JSON   │    └─► API Node (server/)│
│  diretrizes.json     │          │          └─► SQLite      │
└──────────────────────┘          └─────────────────────────┘
        ▲
   localStorage (voter_id UUID)
```

- **Site**: arquivos estáticos, publicados pelo GitHub Pages (deploy = `git push`).
- **API**: ~200 linhas de Node, **sem dependências npm** (usa só `node:http` e `node:sqlite`).
- **Banco**: um único arquivo SQLite com uma tabela (`votes`), em um volume Docker. Não há serviço de banco para administrar e nada que "pause" por inatividade.

## Estrutura de arquivos

```
├── index.html, css/, js/, diretrizes.json   # Site (js/config.js: URL da API)
├── server/
│   ├── app.js            # Rotas HTTP, validação, CORS e limite de requisições
│   ├── db.js             # SQLite: schema, consultas, importação e backup
│   ├── index.js          # Inicialização + backup diário
│   ├── import-votes.js   # Importa votos exportados (migração do Supabase)
│   ├── app.test.js       # Testes (node --test)
│   └── Dockerfile
├── docker-compose.yml    # api (+ caddy opcional com --profile https)
├── Caddyfile             # HTTPS automático, sem logs de acesso
└── .env.example
```

## API

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/state?voter=<uuid>` | Médias de todas as diretrizes e os votos do votante: `{ ratings: [{id, votes, average}], myVotes: {id: score} }` |
| PUT | `/api/votes/:id` | Corpo `{ "voter": "<uuid>", "score": 1-5 }`. Cria ou atualiza o voto |
| DELETE | `/api/votes/:id?voter=<uuid>` | Remove o voto |
| GET | `/api/health` | `{ "ok": true }` (para monitoramento) |

PUT e DELETE respondem `{ ratingId, votes, average }`. Validações: diretriz entre 1 e 17, nota inteira de 1 a 5, `voter` em formato UUID, corpo de até 1 KB. Limite por IP: 120 leituras e 30 escritas por minuto (HTTP 429). CORS liberado só para a origem definida em `ALLOWED_ORIGIN`.

### Modelo de dados

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| rating_id | INTEGER | ID da diretriz (1-17) |
| voter_id | TEXT | UUID anônimo do votante |
| score | INTEGER | Nota de 1 a 5 |
| created_at / updated_at | TEXT (ISO 8601) | Primeiro voto / última alteração |

**PK** `(rating_id, voter_id)`: no máximo um voto por pessoa por diretriz.

## Desenvolvimento local

Requer Node 22.13 ou superior.

```bash
cd server
npm test                                  # 9 testes, sem instalar nada
ALLOWED_ORIGIN=http://localhost:8080 npm start    # API em http://localhost:3000
```

No PowerShell: `$env:ALLOWED_ORIGIN='http://localhost:8080'; npm start`.

Em outro terminal, na raiz do projeto: `python -m http.server 8080` e abra http://localhost:8080 (o `js/config.js` já aponta para `http://localhost:3000`).

## Instalação na VPS

Pré-requisito: Docker com o plugin Compose (`docker compose version`). Se faltar: `curl -fsSL https://get.docker.com | sh`.

```bash
git clone https://github.com/open-artifacts/ai-guidelines.git
cd ai-guidelines
cp .env.example .env        # edite ALLOWED_ORIGIN (e API_DOMAIN, se usar HTTPS pelo Caddy)
```

**Opção A: a VPS não tem nada nas portas 80/443.** O Caddy emite o certificado sozinho. Antes, crie um registro DNS do tipo A de `API_DOMAIN` para o IP da VPS.

```bash
docker compose --profile https up -d --build
```

**Opção B: a VPS já tem Nginx/Caddy/Traefik.** Suba só a API (fica em `127.0.0.1:3000`, inacessível de fora) e aponte o proxy existente para ela:

```bash
docker compose up -d --build
```

```nginx
server {
    server_name api.exemplo.org;            # + certificado (ex.: certbot --nginx)
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header X-Forwarded-For $remote_addr;   # necessário para o limite por IP
    }
}
```

Conferir: `curl https://api.exemplo.org/api/health` deve responder `{"ok":true}`.

### Importar os votos do Supabase (uma vez)

Com o arquivo exportado (`votes-supabase.json`) na pasta atual, **antes** de divulgar a URL:

```bash
docker compose run --rm -v "$PWD/votes-supabase.json:/seed/votes.json:ro" \
  api node --disable-warning=ExperimentalWarning import-votes.js /seed/votes.json
```

O comando mostra o resumo por diretriz. Rodar de novo não duplica nada (a importação é idempotente).

### Operação

| Tarefa | Comando |
|--------|---------|
| Atualizar a API | `git pull && docker compose up -d --build` |
| Ver logs | `docker compose logs -f api` |
| Status / saúde | `docker compose ps` |
| Copiar os backups | `docker compose cp api:/data/backups ./backups` |

O banco gera um backup ao iniciar e depois a cada 24 h em `/data/backups` (dentro do volume), mantendo os 14 mais recentes. Vale copiá-los para fora da VPS de vez em quando.

Restaurar um backup:

```bash
docker compose stop api
docker compose run --rm --user root -v "$PWD/backups:/b:ro" --entrypoint sh api -c \
  'cp /b/votes-AAAA-MM-DD.db /data/votes.db && chown node:node /data/votes.db && rm -f /data/votes.db-wal /data/votes.db-shm'
docker compose start api
```

Privacidade: o Caddyfile não grava logs de acesso, e o limite de requisições guarda IPs só em memória.

## Publicar o site (GitHub Pages)

1. Em `js/config.js`, troque `API_URL` pela URL pública da API (ex.: `https://api.exemplo.org`).
2. Faça o merge na `main`. No repositório: **Settings** > **Pages** > Source: `main` / `/` (root).

## Como funciona o controle de votos

1. Na primeira visita, o navegador gera um **UUID anônimo** e o guarda no `localStorage`.
2. Esse UUID é o `voter_id` em todas as chamadas à API.
3. A chave primária `(rating_id, voter_id)` impede votos duplicados **no banco**.
4. Clicar em outra estrela **atualiza** o voto; clicar na mesma estrela **remove** o voto.

### Feedback visual
- **Estrelas roxas**: voto do próprio usuário
- **Estrelas amarelas**: média da comunidade (quando o usuário ainda não votou)
- **Badge** com a nota do usuário ao lado do contador de votos
- **Toast** confirma cada ação: registrado, atualizado ou removido

### Acessibilidade
O widget de avaliação segue a própria Diretriz A.17 do catálogo:
- As estrelas formam um `radiogroup` ARIA, navegável por teclado (setas, Home/End, Enter/Espaço)
- Cada estrela tem `aria-label` e foco visível
- O layout respeita `prefers-reduced-motion`

### Limitações conhecidas
- O `voter_id` vive no `localStorage`: quem limpar os dados do navegador ou usar outro dispositivo poderá votar novamente. Para o contexto acadêmico do projeto, isso é aceitável.
- Para controle mais rígido seria necessária autenticação, o que adicionaria complexidade desnecessária para o caso de uso atual.
