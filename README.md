# Diretrizes IA — GitHub Pages + Supabase

Catálogo interativo de diretrizes para uso de IA Generativa no ensino de programação, com sistema de avaliação (rating) compartilhado e controle de voto único por usuário.

## Arquitetura

```
GitHub Pages (estático)          Supabase (persistência)
┌──────────────────────┐         ┌───────────────────────┐
│  index.html          │   REST  │  PostgreSQL           │
│  diretrizes.json     │◄───────►│  tabela: votes        │
│  (HTML/CSS/JS puros) │   API   │  view: ratings_summary│
└──────────────────────┘         │  RPCs: submit_vote,   │
     ▲                           │        remove_vote,   │
     │                           │        get_voter_votes│
 localStorage                    └───────────────────────┘
 (voter_id UUID)
```

## Modelo de dados

### Tabela `votes`
| Coluna     | Tipo        | Descrição                          |
|------------|-------------|------------------------------------|
| rating_id  | INTEGER     | ID da diretriz (1-17)              |
| voter_id   | UUID        | Identificador anônimo do votante   |
| score      | INTEGER     | Nota de 1 a 5                      |
| created_at | TIMESTAMPTZ | Data do primeiro voto              |
| updated_at | TIMESTAMPTZ | Data da última alteração           |

**PK**: `(rating_id, voter_id)` — garante no máximo 1 voto por pessoa por diretriz.

### View `ratings_summary`
Agregação calculada automaticamente a partir dos votos individuais:
- `rating_id`, `votes` (COUNT), `average` (AVG)

## Setup rápido

### 1. Criar projeto no Supabase

1. Acesse [supabase.com](https://supabase.com) e crie uma conta (gratuita)
2. Clique em **New Project** e dê um nome (ex: `diretrizes-ia`)
3. Aguarde o provisionamento (~2 min)

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

```bash
git init
git add index.html diretrizes.json
git commit -m "deploy inicial"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/diretrizes-ia.git
git push -u origin main
```

No repositório: **Settings** → **Pages** → Source: `main` / `/` (root) → **Save**.

## Como funciona o controle de votos

1. Na primeira visita, o browser gera um **UUID anônimo** e armazena no `localStorage`
2. Esse UUID é o `voter_id` usado em todas as interações com o Supabase
3. A chave primária `(rating_id, voter_id)` impede votos duplicados **no banco**
4. Se o usuário clicar em outra estrela, o voto é **atualizado** (UPSERT)
5. Se clicar na mesma estrela que já votou, o voto é **removido** (toggle)

### Feedback visual
- **Estrelas roxas** = voto do próprio usuário
- **Estrelas amarelas** = média da comunidade (quando o usuário ainda não votou)
- **Badge** com a nota do usuário aparece ao lado do contador de votos
- **Toast** confirma cada ação: voto registrado, atualizado ou removido

### Limitações conhecidas
- O `voter_id` vive no `localStorage` — se o usuário limpar os dados do browser ou usar outro dispositivo, poderá votar novamente. Para o contexto acadêmico do projeto, isso é aceitável.
- Para controle mais rígido, seria necessário autenticação (Supabase Auth), o que adicionaria complexidade desnecessária para o caso de uso atual.

## Estrutura de arquivos

```
├── index.html          # Página única (HTML + CSS + JS inline)
├── diretrizes.json     # Dados estáticos das 17 diretrizes (PT-BR e EN-US)
├── supabase-setup.sql  # Script de criação: tabela, view, RPCs e RLS
└── README.md
```