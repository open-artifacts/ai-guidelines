# AGENTS.md

Guia para agentes de IA e para pessoas que alteram este repositório. Leia também o [README](README.md).

## Em uma frase

Site estático (`web/`, GitHub Pages) + API de votos (`api/`, Node 22 e SQLite, em Docker numa VPS). Sem dependências npm, sem framework e sem etapa de build no site.

## Comandos (rode antes de abrir um PR)

| Para quê | Comando |
|----------|---------|
| Testes da API | `docker compose -f compose.dev.yaml run --rm api npm test` (ou `cd api && npm test`, com Node >= 22.13) |
| Rodar tudo local | `docker compose -f compose.dev.yaml up --build` e abra http://localhost:8080 |
| Encerrar e apagar os dados de teste | `docker compose -f compose.dev.yaml down -v` |
| Validar os compose | `ALLOWED_ORIGIN=https://exemplo.org docker compose config -q` e `docker compose -f compose.dev.yaml config -q` |
| Lint dos scripts shell | `shellcheck deploy/*.sh` |

O CI (`.github/workflows/ci.yml`) roda os mesmos passos em cada PR.

## Mapa

| Pasta | O que mexer ali |
|-------|-----------------|
| `web/` | site: `diretrizes.json` (conteúdo), `js/app.js`, `css/`, `js/config.js` (URL da API) |
| `api/` | rotas e validação (`app.js`), banco (`db.js`), testes (`app.test.js`). Detalhes em [api/README.md](api/README.md) |
| `deploy/` | scripts do servidor. Guia em [docs/vps.md](docs/vps.md) |
| `docs/` | site, VPS e segurança |

## Convenções

- **Commits** em inglês, no estilo `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, explicando o porquê.
- **Textos**: comentários de código e mensagens de log em ASCII, sem acentos (padrão atual); interface e documentação em português, com acentos.
- **Dependências**: não adicione nenhuma (npm, imagem ou ação do GitHub) sem um motivo forte. A simplicidade é um requisito do projeto.
- **Scripts shell**: `set -euo pipefail`, validar tudo antes de alterar o servidor, desfazer sozinhos se falharem, passar no `shellcheck` e ter só ASCII (são colados em terminais web).
- **Quebras de linha** LF (`.gitattributes`).

## Segurança e privacidade (não negociável)

- Gravar só `(diretriz, UUID anônimo, nota, datas)`. Nunca IP, user-agent, cookies, analytics nem scripts de terceiros. Nenhum log de acesso.
- SQL sempre com consultas preparadas; toda entrada validada em `api/app.js`.
- No site, conteúdo dinâmico só por `escapeHtml` ou `textContent`.
- Nunca commitar: `.env`, chaves, tokens, exports de votos (`votes*.json`), backups (`backups*/`), arquivos `deploy/*.txt`, IPs, nomes de pessoas ou dados da VPS. O repositório é usado em **blind review**: nada pode identificar autores, instituições ou terceiros.
- Autor dos commits: o do repositório (e-mail noreply do GitHub). Não altere a configuração git global e não reescreva histórico publicado.
- A VPS pode ser administrada por outra pessoa: os scripts não mexem em firewall nem em sites e serviços existentes. O que exige root vira um script para o administrador rodar (`deploy/gerar-colar.sh`), nunca um atalho pelo grupo `docker`.
- Peça confirmação antes de: `git push`, merge, mudar configurações do GitHub e qualquer comando na VPS.

## Fluxos

- **Mudar o site**: edite `web/`, teste local e abra um PR para a `main`. O merge publica no GitHub Pages sozinho.
- **Mudar a API**: se as rotas mudarem, atualize também `web/js/app.js`, `api/README.md` e os testes.
- **Adicionar uma diretriz**: ids são sequenciais (1 a N) em `web/diretrizes.json`; suba o `MAX_RATING_ID` da API junto (veja [docs/site.md](docs/site.md)).
- **Deploy da API**: na VPS, `git pull && docker compose build --pull && docker compose up -d` (veja [docs/vps.md](docs/vps.md)).
- Nada de push direto na `main`: branch e PR.

## Armadilhas

- O GitHub Pages deixa JS em cache por cerca de 10 minutos: depois de um deploy, teste com o cache renovado.
- A API confia no **último** valor de `X-Forwarded-For`: rode sempre atrás de um proxy e não exponha a porta 3000 diretamente (a compose já a prende em `127.0.0.1`).
- O limite por IP usa o endereço exato. Hoje a API só é alcançável por IPv4; se um dia houver registro AAAA, o limite deve passar a usar o prefixo /64.
- `docker compose down -v` apaga o volume com os votos. Faça backup antes (`deploy/baixar-backup.sh`).
- `web/js/config.js` guarda a URL de produção da API. No ambiente local, a `compose.dev.yaml` a substitui sozinha.
