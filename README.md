# Diretrizes IA: GitHub Pages + Supabase

Catálogo interativo de diretrizes para uso de IA Generativa no ensino de programação, com sistema de avaliação (rating) compartilhado e controle de voto único por usuário.

## Arquitetura

```
GitHub Pages (estático)          Supabase (persistência)
┌──────────────────────┐         ┌───────────────────────┐
│  index.html          │   REST  │  PostgreSQL           │
│  css/styles.css      │◄───────►│  tabela: votes        │
│  js/config.js        │   API   │  tabela: heartbeat    │
│  js/app.js           │         │  view: ratings_summary│
│  diretrizes.json     │         │  RPCs: submit_vote,   │
└──────────────────────┘         │        remove_vote,   │
     ▲                           │        get_voter_votes│
     │                           │        keepalive      │
 localStorage                    └───────────────────────┘
 (voter_id UUID)                          ▲
                                          │ ping diário
                            ┌─────────────────────────────┐
                            │ GitHub Actions (keepalive)  │
                            └─────────────────────────────┘
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

**PK**: `(rating_id, voter_id)`, garante no máximo 1 voto por pessoa por diretriz.

### View `ratings_summary`
Agregação calculada automaticamente a partir dos votos individuais: `rating_id`, `votes` (COUNT) e `average` (AVG).

### Tabela `heartbeat`
Linha única (singleton) usada apenas para o keep-alive (ver seção abaixo). Não cresce: cada ping atualiza o `last_ping` e incrementa o contador `pings`.

## Estrutura de arquivos

```
├── index.html                       # Estrutura da página (sem CSS/JS inline)
├── css/
│   └── styles.css                   # Estilos
├── js/
│   ├── config.js                    # Credenciais do Supabase (o que você edita)
│   └── app.js                       # Lógica: i18n, render, votação, acessibilidade
├── diretrizes.json                  # Dados das 17 diretrizes (PT-BR e EN-US)
├── supabase-setup.sql               # Tabelas, view, RPCs, RLS e keepalive
├── .github/
│   └── workflows/
│       └── keepalive.yml            # Ping agendado para o Supabase não pausar
└── README.md
```

A separação entre `config.js` (o que muda por projeto) e `app.js` (a lógica que você não precisa tocar) deixa claro onde mexer depois de clonar.

## Setup rápido

### 1. Criar projeto no Supabase

1. Acesse [supabase.com](https://supabase.com) e crie uma conta (gratuita)
2. Clique em **New Project** e dê um nome (ex: `diretrizes-ia`)
3. Aguarde o provisionamento (cerca de 2 min)

### 2. Executar o script SQL

1. No painel do Supabase, vá em **SQL Editor**
2. Clique em **New Query**
3. Cole todo o conteúdo de `supabase-setup.sql`
4. Clique em **Run**
5. Verifique se apareceu "Success" para cada comando

### 3. Copiar as credenciais

1. No Supabase, vá em **Settings** > **API**
2. Copie:
   - **Project URL** (ex: `https://xyzabc.supabase.co`)
   - **anon public key** (a chave longa que começa com `eyJ...`)

> A anon key é pública por design: ela vai embutida no front-end e é protegida pelas policies de RLS. Não confunda com a `service_role`, essa sim secreta e que nunca deve ir para o cliente nem para o repositório.

### 4. Configurar o projeto

Abra `js/config.js` e substitua as duas constantes:

```javascript
const APP_CONFIG = {
  SUPABASE_URL: 'https://SEU_PROJETO.supabase.co',
  SUPABASE_ANON_KEY: 'SUA_ANON_KEY_AQUI',
};
```

### 5. Publicar no GitHub Pages

```bash
git init
git add index.html css js diretrizes.json supabase-setup.sql .github README.md
git commit -m "deploy inicial"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/diretrizes-ia.git
git push -u origin main
```

No repositório: **Settings** > **Pages** > Source: `main` / `/` (root) > **Save**.

## Mantendo o banco ativo (keep-alive)

Projetos no plano Free do Supabase são pausados após 7 dias sem atividade. O detalhe importante: o que conta como atividade é uma query que realmente chega ao Postgres. Visitar o dashboard ou receber respostas em cache não conta. Por isso a solução é uma escrita periódica de verdade no banco.

A estratégia usada aqui tem duas peças, ambas gratuitas e dentro do próprio repositório:

1. A função `keepalive()` no `supabase-setup.sql`, que faz um `UPSERT` numa tabela singleton (`heartbeat`). É uma escrita real, impossível de cachear, e que não gera crescimento de dados.
2. O workflow `.github/workflows/keepalive.yml`, que chama essa função uma vez por dia. Rodar diariamente dá uma folga enorme dentro da janela de 7 dias, mesmo que o GitHub atrase ou pule alguma execução agendada.

### Configurando o workflow

O workflow lê a URL e a anon key de **secrets** do repositório (boa prática, embora a anon key já seja pública). Para cadastrá-los:

1. No GitHub, vá em **Settings** > **Secrets and variables** > **Actions**
2. Clique em **New repository secret** e crie dois secrets:
   - `SUPABASE_URL` com a Project URL
   - `SUPABASE_ANON_KEY` com a anon key
3. Em **Actions**, confirme que os workflows estão habilitados
4. Para testar agora, abra a aba **Actions**, selecione **Supabase Keep-Alive** e clique em **Run workflow**

Você pode confirmar que funcionou consultando a tabela `heartbeat` no SQL Editor:

```sql
SELECT * FROM heartbeat;
```

### Detalhe sobre o agendamento

O GitHub desativa workflows agendados após 60 dias sem nenhum commit no repositório. Para um projeto em evolução isso não é problema. Se ele ficar dormente, o GitHub avisa por e-mail e basta reabilitar com um clique.

### Alternativas sem código

Se preferir não usar o GitHub Actions, qualquer monitor externo que faça uma requisição HTTP agendada resolve, apontando para a mesma URL da função:

```
POST https://SEU_PROJETO.supabase.co/rest/v1/rpc/keepalive
Headers: apikey e Authorization com a anon key
Body: {}
```

Serviços como cron-job.org ou UptimeRobot fazem isso de graça e não têm a limitação dos 60 dias.

## Como funciona o controle de votos

1. Na primeira visita, o browser gera um **UUID anônimo** e armazena no `localStorage`
2. Esse UUID é o `voter_id` usado em todas as interações com o Supabase
3. A chave primária `(rating_id, voter_id)` impede votos duplicados **no banco**
4. Se o usuário clicar em outra estrela, o voto é **atualizado** (UPSERT)
5. Se clicar na mesma estrela que já votou, o voto é **removido** (toggle)

### Feedback visual
- **Estrelas roxas**: voto do próprio usuário
- **Estrelas amarelas**: média da comunidade (quando o usuário ainda não votou)
- **Badge** com a nota do usuário aparece ao lado do contador de votos
- **Toast** confirma cada ação: voto registrado, atualizado ou removido

### Acessibilidade
O widget de avaliação segue a própria Diretriz A.17 do catálogo:
- As estrelas formam um `radiogroup` ARIA, navegável por teclado (setas, Home/End, Enter/Espaço)
- Cada estrela tem `aria-label` e foco visível
- O layout respeita `prefers-reduced-motion` para quem prefere menos animação

### Limitações conhecidas
- O `voter_id` vive no `localStorage`. Se o usuário limpar os dados do browser ou usar outro dispositivo, poderá votar novamente. Para o contexto acadêmico do projeto, isso é aceitável.
- Para controle mais rígido, seria necessário autenticação (Supabase Auth), o que adicionaria complexidade desnecessária para o caso de uso atual.
