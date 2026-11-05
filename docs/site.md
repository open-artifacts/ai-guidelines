# Site

HTML, CSS e JavaScript puros, sem build. A pasta inteira é publicada no GitHub Pages pelo workflow `.github/workflows/pages.yml`.

| Arquivo | Papel |
|---------|-------|
| `index.html` | página única |
| `css/styles.css` | estilos |
| `js/app.js` | interface, idioma PT/EN e cliente da API |
| `js/config.js` | **URL da API** (o único lugar a editar ao mudar de servidor) |
| `diretrizes.json` | conteúdo das diretrizes, em português e inglês |

## Rodar e testar

Na raiz do repositório: `docker compose -f compose.dev.yaml up --build` e abra http://localhost:8080. A pasta `web/` é montada direto no container, então basta editar e recarregar. No ambiente local o `config.js` é trocado por uma versão que aponta para `http://localhost:3000`.

## Editar ou adicionar uma diretriz

Cada item de `diretrizes.json` tem o formato:

```json
{
  "id": 1,
  "pt": { "titulo": "…", "principio": "…", "aplicacao": "…" },
  "en": { "title": "…", "principle": "…", "application": "…" }
}
```

- Os `id` são sequenciais, de 1 a N. Os votos ficam ligados ao `id`, então **não renumere** diretrizes que já têm votos.
- Ao acrescentar a diretriz N+1, suba também o `MAX_RATING_ID` da API (padrão 17) no `.env` da VPS e reinicie a API. Sem isso, os votos nela são recusados.
- O texto é sempre escapado antes de ir para a página, então pode usar aspas e `<`.

## Como o voto funciona

1. Na primeira visita o navegador gera um UUID anônimo e o guarda no `localStorage`.
2. Esse UUID acompanha todas as chamadas à API, e o banco aceita um voto por UUID e diretriz.
3. Clicar em outra estrela atualiza o voto. Clicar na mesma estrela remove o voto.
4. Estrelas roxas mostram o voto da própria pessoa, e as amarelas, a média da comunidade. Um aviso confirma cada ação.

Quem limpar os dados do navegador ou usar outro aparelho pode votar de novo. Para este contexto acadêmico isso é aceitável, e exigir login acrescentaria complexidade sem necessidade.

## Acessibilidade

O widget de avaliação segue a própria Diretriz A.17 do catálogo: as estrelas formam um `radiogroup` ARIA, navegável por teclado (setas, Home/End, Enter e Espaço), com `aria-label` e foco visível, e respeita `prefers-reduced-motion`.
