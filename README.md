# Diretrizes IA — GitHub Pages + Supabase

Catálogo interativo de diretrizes para uso de IA Generativa no ensino de programação, com sistema de avaliação (rating) compartilhado.

## Arquitetura

```
GitHub Pages (estático)          Supabase (persistência)
┌──────────────────────┐         ┌───────────────────────┐
│  index.html          │   REST  │  PostgreSQL           │
│  diretrizes.json     │◄───────►│  tabela: ratings      │
│  (JS puro, sem build)│   API   │  função: submit_rating│
└──────────────────────┘         └───────────────────────┘
```

## Setup rápido

### 1. Criar projeto no Supabase

1. Acesse [supabase.com](https://supabase.com) e crie uma conta (gratuita)
2. Clique em **New Project** e dê um nome (ex: `diretrizes-ia`)
3. Anote a **senha do banco** (não será usada no front, mas é necessária)
4. Aguarde o provisionamento (~2 min)

### 2. Executar o script SQL

1. No painel do Supabase, vá em **SQL Editor**
2. Clique em **New Query**
3. Cole todo o conteúdo de `supabase-setup.sql`
4. Clique em **Run**
5. Verifique se apareceu "Success" para cada comando

### 3. Copiar as credenciais

1. No Supabase, vá em **Settings** → **API**
2. Copie:
   - **Project URL** (ex: `https://xyzabc.supabase.co`)
   - **anon public key** (a chave longa que começa com `eyJ...`)

### 4. Configurar o projeto

Abra `index.html` e substitua as duas constantes no topo do `<script>`:

```javascript
const SUPABASE_URL = 'https://SEU_PROJETO.supabase.co';
const SUPABASE_ANON_KEY = 'SUA_ANON_KEY_AQUI';
```

### 5. Publicar no GitHub Pages

1. Crie um repositório no GitHub (público ou privado)
2. Faça push dos arquivos:
   ```bash
   git init
   git add index.html diretrizes.json
   git commit -m "deploy inicial"
   git branch -M main
   git remote add origin https://github.com/SEU_USUARIO/diretrizes-ia.git
   git push -u origin main
   ```
3. No repositório, vá em **Settings** → **Pages**
4. Em **Source**, selecione `main` branch e `/` (root)
5. Clique em **Save**
6. O site estará disponível em `https://SEU_USUARIO.github.io/diretrizes-ia/`

## Estrutura de arquivos

```
├── index.html          # Página única (HTML + CSS + JS inline)
├── diretrizes.json     # Dados estáticos das 17 diretrizes (PT-BR e EN-US)
├── supabase-setup.sql  # Script de criação da tabela + função RPC
└── README.md
```

## Como funciona a persistência

O `ratings.json` do servidor Node.js foi substituído por uma tabela PostgreSQL no Supabase. A submissão de votos usa uma **função RPC** (`submit_rating`) que executa a atualização de forma atômica no banco, equivalente ao mecanismo de lock que existia no `server.js`.

O front-end se comunica diretamente com a API REST do Supabase usando `fetch`, sem SDK ou dependências externas.

## Segurança

- A **anon key** é pública por design (exposta no front-end), exatamente como a chave de API do Firebase
- O **RLS** (Row Level Security) está configurado para permitir apenas leitura na tabela
- Escritas são feitas exclusivamente via a função RPC `submit_rating`, marcada como `SECURITY DEFINER`
- Não há dados sensíveis — apenas contadores de votos

## Notas

- **Projetos inativos no Supabase** são pausados após 7 dias sem atividade. Para reativar, basta acessar o dashboard. Projetos com uso recorrente (como este, em contexto acadêmico) não são afetados.
- O `supabase-setup.sql` já inclui a migração dos dados atuais do `ratings.json`.
- Nenhum passo de build é necessário. O deploy é literalmente copiar 2 arquivos para o repositório.
