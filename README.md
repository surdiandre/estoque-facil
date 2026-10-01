# Estoque Fácil

Aplicação web/PWA para consulta e movimentação de estoque, com Supabase como fonte oficial dos dados e Cloudflare Workers para publicação.

## Dados e segurança

- Saldos, lotes e validades são carregados do Supabase. Nenhum saldo real é incluído nos arquivos HTML versionados.
- `dados-estoque.json` é um arquivo local de apoio e está excluído do Git e da publicação pelo Cloudflare.
- O aplicativo mantém cache local após sincronizar para permitir consulta quando a conexão cai.
- Não inclua chaves secretas, exportações ou cópias do banco neste repositório.

## Publicação

O projeto usa Cloudflare Workers Builds. Depois de conectar este repositório ao Worker `estoque-facil`, escolha `main` como branch de produção. Cada push nessa branch dispara uma publicação.
