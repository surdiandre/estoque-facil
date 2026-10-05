# Edge Function upload-bula

Esta função recebe uma bula PDF do app Estoque Fácil, valida a sessão administrativa e o item do estoque, envia o arquivo ao Storage e retorna a URL pública. A extração das informações do PDF continua manual pelo ChatGPT; a função não usa Gemini nem tenta interpretar o documento.

## Contrato usado pelo app

O app chama esta função em index.html, enviando multipart/form-data com:

- file: arquivo recebido do operador/admin.
- produto: nome do produto.
- item_id: id da linha existente em estoque.

A requisição inclui o apikey público do projeto e Authorization: Bearer com o access token da sessão. O cliente espera HTTP de sucesso e uma resposta JSON com url. A resposta inclui success, url e path. Não inclui dados extraídos.

Depois do upload, o próprio app grava a URL no estoque e no cadastro permanente de produtos. A função não altera tabelas.

## Validações no servidor

- Exige POST e trata OPTIONS para CORS.
- Exige um bearer token aceito pelo Supabase Auth e compara o e-mail verificado com ADMIN_EMAIL.
- Limita o PDF a 20 MiB, rejeita arquivo vazio e confere a assinatura %PDF- nos primeiros 1.024 bytes.
- Não confia na extensão nem no MIME informado pelo navegador; o objeto é salvo com content-type application/pdf.
- Sanitiza o nome original e cria um caminho com id numérico e UUID.
- Exige produto e item_id e confirma que a linha existe em estoque e que o nome do produto corresponde.
- Usa a chave privilegiada somente no servidor para consultar estoque e salvar no Storage.

auth.jwt() é um helper de PostgreSQL e não está disponível como função TypeScript. A Edge Function verifica o JWT com supabase.auth.getUser(accessToken) e então aplica a mesma autorização administrativa baseada no e-mail que o app usa.

## Configuração

O runtime hospedado injeta SUPABASE_URL e as chaves do projeto. Esta implementação aceita os nomes legados SUPABASE_ANON_KEY e SUPABASE_SERVICE_ROLE_KEY e também os mapas atuais SUPABASE_PUBLISHABLE_KEYS e SUPABASE_SECRET_KEYS.

Configure estes valores:

- ADMIN_EMAIL: obrigatório. Use o mesmo e-mail autorizado pelo app; atualmente balancacoperacel1@gmail.com.
- BULA_BUCKET: opcional. Nome do bucket; padrão bulas.

### CORS

`APP_ORIGIN` é uma variável opcional. Quando definida, restringe o CORS à origem configurada (por exemplo, `https://estoque-facil.balancacoperacel1.workers.dev`). Quando não definida, a função usa `*`, permitindo chamadas de qualquer origem.

SUPABASE_SERVICE_ROLE_KEY ou SUPABASE_SECRET_KEYS só podem existir no ambiente da função. Nunca coloque a chave privilegiada no HTML, em variáveis do Cloudflare ou no repositório.

### Bucket

O bucket bulas precisa existir no projeto Supabase e ser público para que os operadores possam abrir a URL estável retornada pela função. Em um bucket público, qualquer pessoa que obtenha a URL pode ler o arquivo; uploads continuam sendo feitos apenas pela Edge Function com autenticação administrativa.

## Deploy

No terminal, autenticado no Supabase CLI e usando o project ref correto:

    npx supabase secrets set --project-ref <PROJECT_REF> ADMIN_EMAIL=balancacoperacel1@gmail.com BULA_BUCKET=bulas
    npx supabase functions deploy upload-bula --project-ref <PROJECT_REF>

Mantenha a verificação padrão de JWT ativa; não configure verify_jwt como false. O código também verifica o token e o e-mail admin.

## Teste local

O teste local precisa do Supabase CLI, Docker, um projeto local iniciado, bucket bulas público, um item de estoque existente e um access token de uma sessão administrativa válida.

Crie supabase/functions/.env localmente (não faça commit) com SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, ADMIN_EMAIL e BULA_BUCKET. Para desenvolvimento local, obtenha as chaves de teste com supabase status.

Inicie e sirva a função:

    npx supabase start
    npx supabase functions serve upload-bula --env-file supabase/functions/.env

Envie um PDF real usando um token administrativo e o id/nome de um item que já exista:

    curl -i \
      -H "apikey: $SUPABASE_ANON_KEY" \
      -H "Authorization: Bearer $ADMIN_ACCESS_TOKEN" \
      -F "file=@./bula.pdf;type=application/pdf" \
      -F "produto=Nome do produto" \
      -F "item_id=123" \
      http://127.0.0.1:54321/functions/v1/upload-bula

Uma resposta válida tem status 201 e JSON com success true, url e path. Token ausente/inválido deve retornar 401; usuário autenticado que não é admin deve retornar 403; item ausente deve retornar 404; arquivo acima de 20 MiB deve retornar 413; conteúdo sem a assinatura PDF deve retornar 415.

O arquivo supabase/functions/.env contém segredos e deve permanecer local. O .gitignore do repositório já ignora arquivos .env.
