# Estoque Fácil

Aplicação web/PWA para consulta e movimentação de estoque, com Supabase como fonte oficial dos dados e Cloudflare Workers para publicação.

## Dados e segurança

- Saldos, lotes e validades são carregados do Supabase. Nenhum saldo real é incluído nos arquivos HTML versionados.
- `dados-estoque.json` é um arquivo local de apoio e está excluído do Git e da publicação pelo Cloudflare.
- O aplicativo mantém cache local após sincronizar para permitir consulta quando a conexão cai.
- Não inclua chaves secretas, exportações ou cópias do banco neste repositório.

## Atualizar versão

Antes de um deploy que altere o HTML, atualize a versão única do aplicativo na branch de trabalho:

```bash
npm run bump 225
```

Substitua `225` pelo novo número inteiro positivo. O script sincroniza `sw.js`, `app-version.json`, `assets/app-updates.js` e os parâmetros `?v=` de todos os recursos referenciados por `index.html` e `estoque-facil.html`. Ele valida as versões, calcula o SHA-256 dos dois HTMLs e só grava as alterações se os HTMLs forem idênticos. Em caso de falha de gravação, restaura os arquivos anteriores.

Confira o resumo exibido pelo script e, antes de publicar, rode:

```bash
npm run check:xss
sha256sum index.html estoque-facil.html
git diff --check
```

Os dois hashes precisam ser iguais. Rode o bump uma vez antes do deploy que inclui mudanças no HTML.

## Publicação

O projeto usa Cloudflare Workers Builds. Depois de conectar este repositório ao Worker `estoque-facil`, escolha `main` como branch de produção. Cada push nessa branch dispara uma publicação.
