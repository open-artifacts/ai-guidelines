# Diretrizes IA

Catálogo interativo de diretrizes para o uso de IA Generativa no ensino de programação. Cada diretriz recebe notas de 1 a 5 estrelas, de forma anônima, e a média da comunidade aparece para todos.

**Site:** https://open-artifacts.github.io/ai-guidelines/

## Como funciona

```
 GitHub Pages                         VPS (Docker)
┌────────────────┐  HTTPS / JSON  ┌──────────────────────────────────┐
│ web/           │ ─────────────► │ proxy (Apache, nginx ou Caddy)   │
│ site estático  │                │   └─► api ──► SQLite (volume)    │
└────────────────┘                └──────────────────────────────────┘
```

- O **site** (`web/`) é estático e não precisa de build.
- A **API** (`api/`) guarda os votos em um arquivo SQLite e não tem dependências npm.
- Cada navegador gera um UUID anônimo, e o banco aceita **um voto por UUID e diretriz**. Sem login, sem cookies e sem IP gravado.

## Mapa do repositório

| Pasta ou arquivo | Papel |
|------------------|-------|
| `web/` | Site: HTML, CSS, JS e `diretrizes.json` (o conteúdo). Publicado no GitHub Pages |
| `api/` | API de votos em Node 22, com testes e `Dockerfile` |
| `deploy/` | Scripts da VPS: dar acesso ao deploy, publicar a API por HTTPS e baixar backups |
| `proxy/` | Caddy opcional, com HTTPS automático, para servidores sem outro proxy |
| `compose.yaml` | **Produção** (VPS): a `api` e, se quiser, o `proxy` |
| `compose.dev.yaml` | **Local**: `api` e `web` juntos, sem HTTPS e sem `.env` |
| `docs/` | Guias de [site](docs/site.md), [VPS](docs/vps.md) e [segurança](docs/seguranca.md) |
| `AGENTS.md` | Guia para quem altera o código, pessoas e agentes de IA |

## Rodar localmente

Requer só o Docker.

```bash
docker compose -f compose.dev.yaml up --build              # abra http://localhost:8080
docker compose -f compose.dev.yaml run --rm api npm test   # testes da API
docker compose -f compose.dev.yaml down -v                 # encerra e apaga os dados de teste
```

Edite `web/` e recarregue a página (sem rebuild). Mudou algo em `api/`? Rode o `up --build` de novo.

## Documentação

| Quero... | Leia |
|----------|------|
| entender as rotas, os dados e a configuração da API | [api/README.md](api/README.md) |
| editar ou acrescentar uma diretriz | [docs/site.md](docs/site.md) |
| instalar, atualizar, fazer backup ou desligar na VPS | [docs/vps.md](docs/vps.md) |
| saber o que está protegido e o que não está | [docs/seguranca.md](docs/seguranca.md) |
| contribuir (com ou sem agente de IA) | [AGENTS.md](AGENTS.md) |

## Segurança e privacidade, em resumo

- O banco guarda só `(diretriz, UUID, nota, datas)`. Nenhum IP, cookie ou analytics.
- Toda entrada da API é validada, o SQL usa consultas preparadas e o container roda sem privilégios, com o sistema de arquivos somente leitura.
- Os scripts de `deploy/` não alteram firewall, serviços nem sites existentes no servidor, e se desfazem sozinhos se algo falhar.

## Limitações conhecidas

Sem login, o UUID vive só no navegador: quem limpar os dados ou usar outro aparelho pode votar de novo, e é possível votar várias vezes de propósito. Os números indicam a opinião da comunidade, mas **não servem para decisões que exijam votação auditável**. Para este contexto acadêmico isso é aceitável, e exigir autenticação acrescentaria complexidade e dados pessoais sem necessidade.
