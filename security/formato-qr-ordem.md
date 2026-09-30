# QR da ordem de saída — formato v1

Após emitir a NF, o sistema da empresa imprime um QR para toda a ordem no canto inferior direito. O conteúdo é JSON UTF-8 com NF, sequência de saída e itens. A cooperativa opera com uma filial, portanto ela não precisa constar no QR.

```json
{"tipo":"EF-BAIXA","v":1,"nf":"74447","seq_saida":"75630","itens":[{"codigo":"469","produto":"ZAPP PRO 20LT BRA","lote":"0059-26-35100","qtd":1,"unid":"BLD"},{"codigo":"2401","produto":"POQUER 20 LT","lote":"106-26-22940","qtd":2,"unid":"BLD"}]}
```

O exemplo transcreve uma ordem antiga apenas para teste de leitura: não confirme uma baixa com esses dados. A cada impressão, preencher o número final da NF (`nf`), a sequência de saída (`seq_saida`), e para cada item o código do sistema emissor como texto (`codigo`), nome impresso do produto, lote, quantidade inteira na unidade do estoque e sigla da unidade. A sequência de saída deve ser única e nunca reutilizada. O aplicativo mostra `NF 74447 · Seq. saída 75630` e registra internamente a ordem `SAIDA-1-75630`. O banco bloqueia tanto uma sequência de saída repetida quanto uma NF repetida.

O administrador vincula cada código ao produto no editor do Estoque Fácil, após executar `security/codigos-produtos.sql` no Supabase. O código é único e vale para todos os lotes e pilhas do produto. O leitor identifica o produto pelo código e confere o lote e a unidade antes de permitir a baixa. Se o código ainda não estiver cadastrado, o operador precisa escolher o produto; códigos ausentes em QRs antigos usam o nome e o lote como antes. QRs antigos que já incluem `ordem`, `filial` e `serie` continuam aceitos. Se a cooperativa passar a ter mais de uma filial ou séries de NF que repetem numeração, revisar a identificação antes de usar o formato simplificado.

Cada item deve caber em uma pilha; para separar uma quantidade por pilhas, emitir linhas distintas para o mesmo produto e lote. O operador seleciona as pilhas e confirma a baixa. Testar com uma NF fictícia, verificando saldo, histórico e bloqueio de repetição.
