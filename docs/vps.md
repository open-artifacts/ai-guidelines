# Instalação e operação na VPS

Guia do servidor: dar acesso ao deploy, subir a API, publicar o site e operar (atualizar, fazer backup, restaurar e desligar). Serve para Ubuntu ou Debian.

## 1. Quem faz o quê

- **Quem administra a VPS** (pode ser outra pessoa) roda dois scripts como administrador, **uma vez cada**: `bootstrap-vps.sh` (dá o acesso) e, se o servidor já tiver Apache, `apache-proxy.sh` (HTTPS).
- **Quem faz o deploy** entra por SSH como o usuário `deploy`, que não tem `sudo`, e cuida do resto.

## 2. Primeira vez: acesso para o deploy

Gere uma chave SSH na sua máquina (`ssh-keygen -t ed25519`) e entregue a chave **pública** a quem administra a VPS, que roda:

```bash
sudo bash deploy/bootstrap-vps.sh 'ssh-ed25519 AAAA... comentario'
```

O script instala Docker (repositório oficial) e git se faltarem, cria o usuário `deploy` (sem senha e sem sudo, no grupo `docker`), autoriza a chave com `restrict` (sem encaminhamento de portas, de agente nem de X11) e imprime um resumo para colar de volta: sistema, IP, porta do SSH, versões e portas 80/443 em uso. Não altera o firewall do sistema (`ufw`), serviços nem sites existentes (ao ser instalado, o Docker cria as próprias regras de rede) e pode rodar de novo sem efeitos colaterais.

Ele se recusa a rodar, sem alterar nada, se o usuário `deploy` já existir com poderes de administrador (grupo `sudo`/`admin` ou regra em `sudoers`), ou se o servidor encaminhar pacotes (VPN/NAT) sem ter Docker, porque o Docker mexe nas regras de rede (para seguir mesmo assim: `ALLOW_FORWARDING=1`).

> **Atenção:** quem está no grupo `docker` equivale a administrador da máquina. Dê esse acesso só a quem merece essa confiança. Como o deploy faz `git pull` da `main`, **quem consegue publicar na `main` também passa a controlar esse usuário**: ative a verificação em duas etapas na conta do GitHub e proteja a branch (exigir PR).

Para remover o acesso: `sudo deluser --remove-home deploy` (isso não para os containers que já estão rodando; veja a seção 7).

### Quando o administrador não usa git

Gere um texto para ele colar no terminal da VPS:

```bash
bash deploy/gerar-colar.sh deploy/bootstrap-vps.sh 'ssh-ed25519 AAAA... comentario' > deploy/colar-bootstrap.txt
```

Ele abre o arquivo, copia tudo e cola no terminal: o texto grava o script em `/tmp` e o executa com `sudo`. Os arquivos `deploy/*.txt` ficam fora do git. O mesmo vale para o `apache-proxy.sh`.

## 3. Subir a API

Pré-requisito: Docker com o plugin Compose (o `bootstrap-vps.sh` instala). Como `deploy`:

```bash
git clone https://github.com/open-artifacts/ai-guidelines.git
cd ai-guidelines
cp .env.example .env        # edite ALLOWED_ORIGIN (e API_DOMAIN, se usar o proxy HTTPS)
```

No `.env`, `ALLOWED_ORIGIN` é a origem do site (`https://<usuario>.github.io`, sem barra final).

**Opção A: a VPS não tem nada nas portas 80/443.** O `proxy` (Caddy) emite o certificado sozinho. Antes, crie um registro DNS do tipo A de `API_DOMAIN` para o IP da VPS.

```bash
docker compose --profile https up -d --build
```

**Opção B: a VPS já tem Apache, nginx ou Traefik.** Suba só a `api`, que fica em `127.0.0.1:3000` (inacessível de fora), e aponte o proxy existente para ela:

```bash
docker compose up -d --build
```

- **Apache:** o administrador roda `sudo bash deploy/apache-proxy.sh api.exemplo.org`, com o nome já apontado para a VPS (se o `certbot` ainda não tiver conta no servidor, acrescente um e-mail: `... api.exemplo.org voce@exemplo.org`). O script cria um virtual host só para esse nome (`zz-ai-guidelines-api`, que fica depois dos demais para não virar o site padrão), sem log de acesso nem IP no log de erros, pede o certificado ao `certbot` e testa a API. Não altera os outros sites e se desfaz sozinho se o Apache recusar a configuração. Ele deixa habilitados os módulos `proxy` e `proxy_http`, que não abrem proxy aberto.
- **nginx** (certificado à parte, por exemplo `certbot --nginx`):

  ```nginx
  server {
      server_name api.exemplo.org;
      location / {
          proxy_pass http://127.0.0.1:3000;
          proxy_set_header X-Forwarded-For $remote_addr;   # necessário para o limite por IP
      }
  }
  ```

Conferir: `curl https://api.exemplo.org/api/health` deve responder `{"ok":true}`.

## 4. Publicar o site (GitHub Pages)

O workflow `.github/workflows/pages.yml` publica a pasta `web/` a cada merge na `main` que a altere. Na primeira vez:

1. Em `web/js/config.js`, troque `API_URL` pela URL pública da API.
2. No repositório: **Settings → Pages → Source: GitHub Actions** (antes do merge, para o site atual não sair do ar).
3. Faça o merge na `main` (ou rode o workflow em **Actions → Publicar site → Run workflow**).

O GitHub Pages deixa os arquivos JS em cache por cerca de 10 minutos: depois de um deploy, teste com o cache renovado.

## 5. Operação

Na pasta do projeto, na VPS, como `deploy`:

| Tarefa | Comando |
|--------|---------|
| Atualizar a API | `git pull && docker compose build --pull && docker compose up -d` |
| Ver logs | `docker compose logs -f api` |
| Status e saúde | `docker compose ps` |
| Reiniciar | `docker compose restart api` |

O `--pull` baixa a versão mais nova da imagem base (`node:22-slim`), que traz as correções de segurança. Os votos ficam no volume `ai-guidelines_api-data`: atualizar ou recriar o container não os apaga.

## 6. Backup e restauração

A API gera um backup ao iniciar e a cada 24 h em `/data/backups` (dentro do volume), mantendo os 14 mais recentes. Como ficam no mesmo volume dos votos, **não protegem contra perder o servidor**: copie-os para a sua máquina de vez em quando (uma vez por mês basta):

```bash
bash deploy/baixar-backup.sh deploy@<ip-da-vps> ../backups-votos
```

O script confere o cabeçalho SQLite de cada arquivo e não altera nada na VPS. Se o `ssh` do seu terminal não ler o `~/.ssh/config` (no Git Bash do Windows), aponte o do sistema: `SSH=/c/Windows/System32/OpenSSH/ssh.exe bash deploy/baixar-backup.sh ...`.

Restaurar um backup (copie o arquivo para `./backups/` na VPS antes):

```bash
docker compose stop api
docker compose run --rm --user root -v "$PWD/backups:/b:ro" --entrypoint sh api -c \
  'cp /b/votes-AAAA-MM-DD.db /data/votes.db && chown node:node /data/votes.db && rm -f /data/votes.db-wal /data/votes.db-shm'
docker compose start api
```

## 7. Desligar tudo (para quem administra a VPS)

Remover o usuário `deploy` **não** para a API. Para desligar de vez:

```bash
sudo -u deploy -H bash -c 'cd ~/ai-guidelines && docker compose down'   # para a API; os votos ficam no volume
# Só se quiser apagar também os votos (faça backup antes): docker compose down -v

# Com Apache:
sudo a2dissite zz-ai-guidelines-api zz-ai-guidelines-api-le-ssl
sudo rm /etc/apache2/sites-available/zz-ai-guidelines-api*.conf
sudo certbot delete --cert-name api.exemplo.org
sudo systemctl reload apache2

sudo deluser --remove-home deploy
```

## Apêndice: importar votos de um JSON

Usado uma vez, na migração do Supabase (já concluída). Com um arquivo `[{rating_id, voter_id, score, created_at, updated_at}, …]` na pasta atual, **antes** de divulgar a URL:

```bash
docker compose run --rm -v "$PWD/votes.json:/seed/votes.json:ro" \
  api node --disable-warning=ExperimentalWarning import-votes.js /seed/votes.json
```

A importação é idempotente (rodar de novo não duplica nada nem desfaz um voto mais novo) e mostra o resumo por diretriz. Depois do lançamento, porém, um voto que a pessoa removeu **volta** se o arquivo ainda o contiver. No ambiente local, use `-f compose.dev.yaml`.
