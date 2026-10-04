# Estoque Fácil

Aplicação web/PWA para consulta e movimentação de estoque, com Supabase como fonte oficial dos dados e Cloudflare Workers para publicação.

## Dados e segurança

- Saldos, lotes e validades são carregados do Supabase. Nenhum saldo real é incluído nos arquivos HTML versionados.
- `estoque.dias` é obsoleta e permanece nullable apenas por compatibilidade; o app não a grava. Use `estoque.validade` como data absoluta. Valores antigos de `dias` não substituem a conferência manual da validade.
- `dados-estoque.json` é um arquivo local de apoio e está excluído do Git e da publicação pelo Cloudflare.
- O aplicativo mantém cache local após sincronizar para permitir consulta quando a conexão cai.
- Não inclua chaves secretas, exportações ou cópias do banco neste repositório.

## Configuração local

Copie o arquivo de exemplo e preencha os valores do seu projeto:

```bash
cp .env.example .env
```

Use a URL do projeto Supabase, a chave pública (publishable/anon) e o e-mail administrativo. A chave indicada no exemplo é pública e destinada ao cliente; não coloque chaves secretas nesse arquivo.

O arquivo `.env` é local e **NUNCA deve ser commitado**. Ele já é ignorado pelo Git. O `.env.example` contém apenas nomes e valores ilustrativos e pode ser versionado.

O app atual é servido como HTML estático: o navegador não carrega `.env` automaticamente e o Wrangler não injeta essas variáveis nos arquivos publicados. A configuração usada pelo cliente continua sendo a definida no próprio app; esta cópia serve como referência local para ferramentas/scripts que venham a consumir essas variáveis.

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
