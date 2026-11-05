# Diretrizes IA

Catálogo interativo de diretrizes para uso de IA Generativa no ensino de programação, com avaliação (rating) compartilhada e controle de voto único por usuário.

## Como as peças se encaixam

```
 GitHub Pages                       VPS (Docker)
┌───────────────┐   HTTPS / JSON   ┌───────────────────────────────┐
│  web/         │ ───────────────► │  proxy (opcional, HTTPS)      │
│  site estático│                  │     └─► api ──► SQLite (volume)│
└───────────────┘                  └───────────────────────────────┘
```

Cada pasta tem um papel, e cada serviço do Docker tem o nome da pasta que o define:

| Pasta / arquivo | Papel |
|-----------------|-------|
| `web/` | Site estático (HTML, CSS, JS e `diretrizes.json`). Publicado no GitHub Pages |
| `api/` | API de votos em Node, sem dependências npm, com SQLite. Tem o próprio `Dockerfile` e os testes |
| `proxy/` | Caddy com HTTPS automático na frente da API (opcional) |
| `compose.yaml` | **Produção** (VPS): `api` e, se quiser, `proxy` |
| `compose.dev.yaml` | **Local**: `api` e `web` juntos, sem HTTPS e sem `.env` |
| `.env.example` | Variáveis de produção |
| `.github/workflows/pages.yml` | Publica `web/` no GitHub Pages a cada push na `main` |

## Rodar localmente

Requer só o Docker.

```bash
docker compose -f compose.dev.yaml up --build           # abra http://localhost:8080
docker compose -f compose.dev.yaml run --rm api npm test  # 10 testes da API
docker compose -f compose.dev.yaml down -v                # encerra e apaga os dados de teste
```

- O site (`web/`) é montado direto no container: edite os arquivos e recarregue a página, sem rebuild.
- Mudou algo em `api/`? Rode o `up --build` de novo.
- No ambiente local o `web/js/config.js` é substituído por uma versão que aponta para `http://localhost:3000`.

## API

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/state?voter=<uuid>` | Médias de todas as diretrizes e os votos do votante: `{ ratings: [{id, votes, average}], myVotes: {id: score} }` |
| PUT | `/api/votes/:id` | Corpo `{ "voter": "<uuid>", "score": 1-5 }`. Cria ou atualiza o voto |
| DELETE | `/api/votes/:id?voter=<uuid>` | Remove o voto |
| GET | `/api/health` | `{ "ok": true }` (para monitoramento) |

PUT e DELETE respondem `{ ratingId, votes, average }`. Validações: diretriz entre 1 e 17, nota inteira de 1 a 5, `voter` em formato UUID, corpo de até 1 KB. Limite por IP: 120 leituras e 30 escritas por minuto (HTTP 429), usando o último valor de `X-Forwarded-For` (o que o proxy da frente acrescenta). CORS liberado só para a origem definida em `ALLOWED_ORIGIN`.

### Modelo de dados

Uma tabela, `votes`, em um único arquivo SQLite:

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| rating_id | INTEGER | ID da diretriz (1-17) |
| voter_id | TEXT | UUID anônimo do votante |
| score | INTEGER | Nota de 1 a 5 |
| created_at / updated_at | TEXT (ISO 8601) | Primeiro voto / última alteração |

**PK** `(rating_id, voter_id)`: no máximo um voto por pessoa por diretriz.

## Instalação na VPS

### Primeira vez: dar acesso para o deploy

Quem administra a VPS roda **uma única vez** o `deploy/bootstrap-vps.sh`, como administrador, informando a chave pública SSH de quem fará os deploys:

```bash
sudo bash deploy/bootstrap-vps.sh 'ssh-ed25519 AAAA... comentario'
```

O script instala Docker (repositório oficial) e git se faltarem, cria o usuário `deploy` (sem senha, sem sudo, só no grupo `docker`), autoriza a chave e imprime um resumo (sistema, IP, porta do SSH, portas 80/443 em uso). Não altera firewall, serviços nem configurações existentes e pode rodar de novo sem efeitos colaterais. Ele se recusa a rodar, sem alterar nada, se o usuário `deploy` já existir com poderes de administrador, ou se o servidor encaminhar pacotes (VPN/NAT) e ainda não tiver Docker, porque o Docker mexe nas regras de rede (para seguir mesmo assim: `ALLOW_FORWARDING=1`). Para desfazer o acesso: `sudo deluser --remove-home deploy`. A partir daí, os deploys são feitos por SSH com `deploy@<ip-da-vps>`, sem envolver quem administra o servidor.

Atenção: no Docker, quem está no grupo `docker` equivale a administrador da máquina. Dê esse acesso só a quem merece essa confiança.

### Deploy

Pré-requisito: Docker com o plugin Compose (`docker compose version`). Se faltar: `curl -fsSL https://get.docker.com | sh`.

```bash
git clone https://github.com/open-artifacts/ai-guidelines.git
cd ai-guidelines
cp .env.example .env        # edite ALLOWED_ORIGIN (e API_DOMAIN, se usar o proxy HTTPS)
```

**Opção A: a VPS não tem nada nas portas 80/443.** O `proxy` emite o certificado sozinho. Antes, crie um registro DNS do tipo A de `API_DOMAIN` para o IP da VPS.

```bash
docker compose --profile https up -d --build
```

**Opção B: a VPS já tem Nginx/Caddy/Traefik.** Suba só a `api` (fica em `127.0.0.1:3000`, inacessível de fora) e aponte o proxy existente para ela:

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

**Se o proxy existente for o Apache**, o `deploy/apache-proxy.sh` faz isso (como administrador, com o nome já apontado para a VPS e a API no ar):

```bash
sudo bash deploy/apache-proxy.sh api.exemplo.org
```

Ele cria um virtual host só para esse nome (`zz-ai-guidelines-api`, depois dos demais para não virar o site padrão), sem log de acesso, pede o certificado ao `certbot` e testa a API. Não altera os outros sites e se desfaz sozinho se o Apache recusar a configuração. As instruções para desfazer estão no cabeçalho do script.

Conferir: `curl https://api.exemplo.org/api/health` deve responder `{"ok":true}`.

### Importar os votos do Supabase (uma vez)

Com o arquivo exportado (`votes-supabase.json`) na pasta atual, **antes** de divulgar a URL:

```bash
docker compose run --rm -v "$PWD/votes-supabase.json:/seed/votes.json:ro" \
  api node --disable-warning=ExperimentalWarning import-votes.js /seed/votes.json
```

O comando mostra o resumo por diretriz. Rodar de novo não duplica nada (a importação é idempotente). O mesmo vale para o ambiente local, trocando por `-f compose.dev.yaml`.

### Operação

| Tarefa | Comando |
|--------|---------|
| Atualizar a API | `git pull && docker compose up -d --build` |
| Ver logs | `docker compose logs -f api` |
| Status / saúde | `docker compose ps` |
| Copiar os backups para o seu computador | `bash deploy/baixar-backup.sh deploy@<ip-da-vps> ./backups` (rode **na sua máquina**, não na VPS) |

A `api` gera um backup ao iniciar e depois a cada 24 h em `/data/backups` (dentro do volume), mantendo os 14 mais recentes. Como ficam no mesmo volume dos votos, **não protegem contra perder o servidor**: copie-os para fora da VPS de vez em quando com o `deploy/baixar-backup.sh` (ele confere o cabeçalho de cada arquivo e não altera nada na VPS). Se o `ssh` do seu terminal não ler o `~/.ssh/config`, aponte o do sistema: `SSH=/c/Windows/System32/OpenSSH/ssh.exe bash deploy/baixar-backup.sh ...`.

Restaurar um backup:

```bash
docker compose stop api
docker compose run --rm --user root -v "$PWD/backups:/b:ro" --entrypoint sh api -c \
  'cp /b/votes-AAAA-MM-DD.db /data/votes.db && chown node:node /data/votes.db && rm -f /data/votes.db-wal /data/votes.db-shm'
docker compose start api
```

Privacidade: o `proxy/Caddyfile` não grava logs de acesso, e o limite de requisições guarda IPs só em memória.

## Publicar o site (GitHub Pages)

O site é publicado pelo workflow `.github/workflows/pages.yml`, que envia a pasta `web/`. Na primeira vez:

1. Em `web/js/config.js`, troque `API_URL` pela URL pública da API (ex.: `https://api.exemplo.org`).
2. No repositório: **Settings** > **Pages** > Source: **GitHub Actions**.
3. Faça o merge na `main` (ou rode o workflow manualmente em **Actions** > **Publicar site** > **Run workflow**).

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
