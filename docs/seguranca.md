# Segurança e privacidade

Este documento diz o que o projeto protege, como, e onde estão os limites. O ponto de partida é que os votos são **anônimos e de baixo risco**: notas de 1 a 5 em diretrizes de ensino. A segurança serve para manter o servidor de pé, os dados íntegros na medida do possível e ninguém identificável.

## Resumo

| Ameaça | O que fazemos | Limite |
|--------|---------------|--------|
| Entrada maliciosa (injeção, corpo gigante, alvo de requisição malformado) | Validação estrita de cada campo, SQL com consultas preparadas, corpo de até 1 KB, erros viram HTTP 4xx sem detalhes | — |
| XSS no site | Todo texto dinâmico passa por `escapeHtml`, números por `Number()`, e uma CSP (`script-src 'self'`) bloqueia script inline. Sem bibliotecas nem scripts de terceiros | A CSP vem de uma tag `meta` (o GitHub Pages não deixa definir cabeçalhos) e aceita qualquer API em `https` |
| Uso abusivo da API | Limite por IP (padrão: 300 leituras e 120 votos por minuto), contado na memória | Quem usa vários IPs passa pelo limite. Hoje só há IPv4; com IPv6 o limite deveria usar o prefixo /64 |
| Outros sites chamando a API pelo navegador | CORS liberado só para a origem do site | CORS não vale para scripts fora do navegador |
| Voto duplicado | Chave primária `(diretriz, UUID)`: um voto por UUID e diretriz | O UUID fica no navegador; limpar os dados ou gerar UUIDs novos permite votar de novo |
| Encher o banco | Limite por IP e corpo pequeno | Não há teto de linhas: com muitos IPs, o banco e o backup crescem |
| Falha do servidor | Backup diário consistente, e `deploy/baixar-backup.sh` para copiá-lo para fora da VPS | Vale copiar de vez em quando |
| Container comprometido | Usuário sem privilégios, sistema de arquivos somente leitura, sem capabilities, limites de memória e processos, logs com tamanho máximo | — |

**Integridade dos votos:** sem login, qualquer pessoa pode votar mais de uma vez trocando de navegador ou gerando UUIDs, e o limite por IP só desacelera isso. Os números servem para ter uma ideia da opinião da comunidade, **não** para decisões que exijam votação auditável. Se isso mudar, o caminho é exigir autenticação, o que acrescenta complexidade e coleta de dados pessoais.

**Votos antigos do Supabase:** a tabela do projeto anterior aceitava leitura anônima, então os UUIDs importados (54 votos) podem ter sido copiados. Na API nova o UUID é a única credencial de um voto, e quem o tiver pode alterá-lo ou removê-lo. Trate esses votos como não confiáveis e apague o projeto do Supabase quando não precisar mais dele.

## Privacidade

- O banco guarda só `(diretriz, UUID aleatório, nota, datas)`. O UUID é gerado no navegador e não está ligado a nenhuma pessoa.
- **Nenhum IP é gravado pela API.** O limite por IP vive só na memória e some quando ela reinicia.
- Não há cookies, analytics nem scripts de terceiros no site.
- O `deploy/apache-proxy.sh` desliga o log de acesso (`CustomLog /dev/null`) e tira o IP do log de erros do virtual host. O `proxy/Caddyfile` não tem a diretiva `log`, mas o Caddy ainda pode registrar IP e URL das requisições que falham.
- Os logs da API trazem só o início, os backups e erros inesperados, e o Docker os rotaciona (3 arquivos de 10 MB).

## Anonimato do repositório (blind review)

O repositório é público e usado em avaliação cega. Por isso:

- Os commits usam o e-mail `noreply` do GitHub e um nome de autor neutro.
- Nenhum arquivo cita nomes de pessoas, instituições, o IP ou o provedor da VPS. A URL da API fica em `web/js/config.js` porque o site precisa dela; use um nome neutro, com registro privado.
- Não versione `.env`, chaves, bancos, exports de votos, backups nem os arquivos `deploy/*.txt`: o `.gitignore` já os cobre.
- Antes de divulgar, revise o histórico (`git log -p`): o que já foi publicado continua acessível mesmo depois de removido do código.
- O histórico antigo contém a chave `anon` do projeto Supabase. Ela era pública por desenho (ia no código do site), mas deixa de ter qualquer efeito quando o projeto é apagado.

## A VPS

- Os scripts de `deploy/` não alteram o firewall do sistema, serviços nem sites existentes. Cada um confere tudo antes de mudar algo e se desfaz sozinho se algo falhar.
- A API só escuta em `127.0.0.1:3000` no servidor. Quem fala com a internet é o proxy (Apache, nginx ou o Caddy opcional), e o limite por IP depende dele: a API usa o **último** valor de `X-Forwarded-For`, que é o que o proxy acrescenta. Nunca publique a porta 3000 diretamente.
- A chave do `deploy` entra com `restrict` (sem encaminhamento de portas, agente nem X11). O usuário não tem `sudo`, mas **estar no grupo `docker` equivale a ser administrador da máquina**, e o deploy roda o código da `main` (`git pull` e `docker compose up`). Na prática, quem controla a `main` controla esse acesso. Ative a verificação em duas etapas na conta do GitHub, proteja a branch (exigir PR) e remova o acesso (`sudo deluser --remove-home deploy`) quando acabar. Uma alternativa mais forte é o Docker rootless para esse usuário, ao custo de mais configuração.
- O certificado HTTPS é renovado pelo `certbot` do próprio servidor.

## Cadeia de suprimentos

- A API não tem dependências npm: nada para atualizar nem para ser comprometido.
- A imagem base (`node:22-slim`) e as actions do GitHub são acompanhadas pelo Dependabot, que abre um PR quando sai versão nova. Na VPS, `docker compose build --pull` traz as correções da imagem base.
- As actions usam tags (`@v4`), não SHAs. É aceitável com ações oficiais; fixar por SHA é uma opção se isso incomodar.
- Os workflows têm permissões mínimas (`contents: read`; o do Pages acrescenta só o necessário para publicar) e não guardam credenciais no checkout.

## Limites do hospedeiro

O site fica em `open-artifacts.github.io`, uma origem compartilhada por todos os sites da mesma conta, que podem ler o `localStorage` uns dos outros. Não publique ali páginas de terceiros.

## Como reportar um problema

Abra uma issue **sem detalhes que permitam explorar a falha**, ou use "Report a vulnerability" na aba Security do repositório, se estiver habilitado. Não inclua dados pessoais.
