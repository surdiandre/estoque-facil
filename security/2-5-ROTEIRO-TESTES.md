# Sprint 2.5.9 — roteiro de testes ponta a ponta do Sprint 2.5

**Aplicativo:** v237  
**Ambiente para movimentações:** homologação isolada  
**Uso em produção:** somente leitura e visualização do QR; não confirmar operações de teste.

Este roteiro valida o fluxo completo, da entrada até o estorno. Ele descreve os testes a executar; não registra que eles já foram executados. Faça cópia do banco de homologação antes de começar e anote os saldos iniciais das pilhas usadas.

> **Proteção do estoque real:** não confirme cargas ou baixas de teste em produção. As NFs reais 74531 e 74522 já podem estar registradas globalmente; uma nova confirmação pode ser recusada como duplicada. Para testar gravações, use uma cópia de homologação e os identificadores sintéticos deste roteiro. Na produção, leia o QR, confira a prévia e feche o modal sem adicionar/confirmar os itens.

## 1. Preparação

1. Confirme que está no endereço de homologação, com um banco separado do estoque real e uma conta administradora autorizada.
2. No aplicativo, abra **Configurações → Versão do aplicativo** e toque em **Verificar atualização**. O resultado esperado é **“Você está usando a versão mais recente: v237.”** Se uma atualização v237 for oferecida, aplique-a e confira novamente. Registre os saldos de todas as pilhas listadas abaixo.
3. Prepare no estoque de homologação as pilhas dos produtos/lotes necessários. Para o teste de divisão, deixe TA 35 LT, lote 701277, com saldo **1 lt na A-11** e **84 lt na A-1**. Para os demais produtos, garanta pelo menos a quantidade pedida.
4. Use, para as duas cópias de teste, estes identificadores únicos:
   - NF 74531 copiada: **T259-74531-20261009**
   - Saída 74531 copiada: **T259-S75717-20261009**
   - NF 74522 copiada: **T259-74522-20261009**
   - Saída 74522 copiada: **T259-S75709-20261009**
   - Código da carga principal: **T259-CARGA-01**
   - NF e código da carga para o subteste: **T259-SPLIT-20261009** e **T259-CARGA-SPLIT**
   - Responsável: **TESTE SPRINT 2.5.9**
5. Gere um QR para cada JSON abaixo usando qualquer gerador confiável de QR com opção de baixar PNG. Os JSONs mantêm os itens reais de teste, mas usam NFs e sequências exclusivas para não colidir com o cadastro global. Gere o QR somente em homologação. Para validityReview, use uma base isolada em que só exista esse item como pendente de validade; se houver outras pendências, não inicie o fluxo, pois ele pode percorrê-las também.

### Dados de referência dos QR

| Cópia de teste | Código | Produto | Lote (texto) | Quantidade inteira no QR |
|---|---:|---|---|---:|
| NF 74531 | 5151 | TA 35 LT | 701277 | 2 |
| NF 74531 | 5439 | ZAPP WG 720 5 KG | 082-24-192000 | 9 |
| NF 74531 | 590 | HEAT 700 FR 350 GR | 474-24-01450 | 4 |
| NF 74531 | 2306 | MEES 5 LT | 0522620000 | 4 |
| NF 74522 | 5151 | TA 35 LT | 701277 | 4 |
| NF 74522 | 1161 | PERITO 10 KG | 0076-25-5779 | 4 |
| NF 74522 | 1161 | PERITO 10 KG | 1940-25-5779 | 3 |
| NF 74522 | 264 | PRIMOLÉO 20 LITRO | 0059-26-86400 | 6 |
| NF 74522 | 667 | AUREO GL 5 LT | 036-25-047000 | 4 |

**Quantidade:** a vírgula da NF é decimal e os zeros finais representam precisão. Portanto, por exemplo, **4,000 lt vira quantidade 4**, nunca 4000. O QR contém uma quantidade inteira e não contém unidade; a unidade usada na saída vem da pilha escolhida.

### JSON de teste — cópia da NF 74531

~~~json
{
  "v": 3,
  "seq_saida": "T259-S75717-20261009",
  "nr_nf": "T259-74531-20261009",
  "itens": [
    {"codigo":"5151","produto":"TA 35 LT","lote":"701277","quantidade":2},
    {"codigo":"5439","produto":"ZAPP WG 720 5 KG","lote":"082-24-192000","quantidade":9},
    {"codigo":"590","produto":"HEAT 700 FR 350 GR","lote":"474-24-01450","quantidade":4},
    {"codigo":"2306","produto":"MEES 5 LT","lote":"0522620000","quantidade":4}
  ]
}
~~~

### JSON de teste — cópia da NF 74522

~~~json
{
  "v": 3,
  "seq_saida": "T259-S75709-20261009",
  "nr_nf": "T259-74522-20261009",
  "itens": [
    {"codigo":"5151","produto":"TA 35 LT","lote":"701277","quantidade":4},
    {"codigo":"1161","produto":"PERITO 10 KG","lote":"0076-25-5779","quantidade":4},
    {"codigo":"1161","produto":"PERITO 10 KG","lote":"1940-25-5779","quantidade":3},
    {"codigo":"264","produto":"PRIMOLÉO 20 LITRO","lote":"0059-26-86400","quantidade":6},
    {"codigo":"667","produto":"AUREO GL 5 LT","lote":"036-25-047000","quantidade":4}
  ]
}
~~~

## 2. Testes passo a passo

Em cada etapa, registre o resultado e, quando aplicável, tire uma captura de tela sem dados de acesso.

### 1) Entrada manual de um item novo no estoque

**Ação:** em homologação, toque em **Nova entrada**. Use um produto já existente no catálogo para criar uma nova linha de estoque: TA 35 LT, código 5151, lote **T259-ENT-20261009**, pilha **T259-A-1**, quantidade **12**, unidade herdada do cadastro e validade **31/12/2027**. Se a tela pedir referência, use **T259-ENTRADA**. Salve.

**Resultado esperado:** aparece confirmação de entrada; o novo lote aparece no estoque com saldo 12 e a validade informada.

**Como verificar:** procure o lote T259-ENT-20261009 na lista e confira produto, pilha, saldo e validade. No histórico de entradas, confirme a movimentação de 12.

### 2) Baixa manual avulsa, sem carga

**Ação:** o modal de v237 não tem um fluxo de baixa avulsa na interface: **Adicionar item manual** coloca o item no rascunho de uma carga. Para testar a baixa avulsa prevista no banco, use em homologação o endpoint autenticado **POST /rest/v1/rpc/ef_confirmar_baixa_manual**, com uma pilha de teste que tenha saldo conhecido. Exemplo de corpo; substitua o ID e gere uma UUID nova:

~~~json
{
  "p_id": 123,
  "p_quantidade": 1,
  "p_idempotency_key": "11111111-1111-4111-8111-111111111111",
  "p_carga_id": null,
  "p_data_hora": "2026-10-09T12:00:00Z"
}
~~~

**Resultado esperado:** a RPC devolve o novo saldo. Uma pilha que tinha 6 fica com 5. A saída não pertence a uma carga.

**Como verificar:** confira o saldo no estoque e consulte a linha em **public.historico_saidas** pela UUID enviada; **carga_id** deve ser **NULL**. Não envie tokens ou cabeçalhos de acesso em capturas ou documentos compartilhados. Se o teste precisar ser feito somente pela interface, marque esta etapa como **não disponível em v237**; não simule uma baixa avulsa usando o botão de carga.

### 3) Leitura do QR v3 — NF 74531, quatro itens

**Ação:** em homologação, abra **Dar baixa** → **Ler QR da ordem** → selecione a imagem do primeiro JSON de teste ou leia-o com a câmera. Confira a prévia e não confirme a carga nesta etapa.

**Resultado esperado:** a prévia mostra a NF sintética T259-74531-20261009 e quatro linhas: TA 35 LT, ZAPP WG 720 5 KG, HEAT 700 FR 350 GR e MEES 5 LT. As quantidades são 2, 9, 4 e 4.

**Como verificar:** compare produto, lote e quantidade com a tabela acima. O QR não deve mostrar nem solicitar unidade. O lote 0522620000 deve continuar como texto, com todos os zeros. Feche a prévia sem confirmar; no passo 5 os dois QRs serão lidos novamente no mesmo rascunho.

### 4) Leitura do QR v3 — NF 74522, cinco itens e PERITO em dois lotes

**Ação:** abra um rascunho limpo e leia a imagem do segundo JSON.

**Resultado esperado:** a prévia mostra cinco linhas. PERITO 10 KG aparece em **duas linhas separadas**, uma com lote 0076-25-5779 e quantidade 4, outra com lote 1940-25-5779 e quantidade 3. O alerta **“⚠ mesmo produto”** aparece para destacar que é o mesmo produto em lotes diferentes.

**Como verificar:** confira os cinco lotes e quantidades na tabela. Os zeros e hífens de 0076-25-5779 permanecem intactos. Não deve haver uma linha única de PERITO somando as duas quantidades, nem erro de lote numérico, campo **unid** ou quantidade decimal. Feche sem confirmar; no passo 5, os dois QRs serão adicionados juntos a uma carga de homologação.

### 5) Confirmação da carga pelo modal e chips de NFs

**Ação:** em um rascunho limpo, leia a cópia da NF 74531 e toque em **Adicionar itens à carga**. Leia a cópia da NF 74522 e adicione seus itens também. Preencha código T259-CARGA-01, data/hora de teste e responsável TESTE SPRINT 2.5.9. Confirme que as duas NFs aparecem como chips. Para o lote TA 35 LT 701277, a soma pedida pelas duas cópias é 6 lt; com a preparação indicada, selecione A-11 (aloca 1 lt) e depois A-1 (aloca os 5 lt restantes). Revise todos os itens antes de tocar em confirmar.

**Resultado esperado:** aparecem os chips T259-74531-20261009 e T259-74522-20261009. O item PERITO de cada lote segue separado. A divisão do TA 35 LT soma 6 lt, com 1 na A-11 e 5 na A-1. A unidade é a que consta nas pilhas do estoque. A confirmação informa sucesso e um código/identificador da carga.

**Como verificar:** confira na tela a conclusão dos itens e anote o ID retornado. Compare o saldo de cada pilha com o saldo inicial menos a quantidade alocada. Se aparecer saldo insuficiente, não tente confirmar repetidamente: confira os saldos e o ID das pilhas no estoque de homologação.

### 6) Verificação do histórico — aba Cargas

**Ação:** abra o histórico e selecione **Cargas**.

**Resultado esperado:** a carga T259-CARGA-01 aparece no topo como **ATIVA**. Ao expandir, são mostrados data/hora, responsável, código, os dois chips de NF e itens com lotes e quantidades.

**Como verificar:** confirme os chips T259-74531-20261009 e T259-74522-20261009, os itens de ambas as ordens e os dois lotes separados do PERITO. A carga deve estar ativa, com indicador verde e sem data de estorno. A baixa avulsa do passo 2 não deve aparecer como carga.

### 7) Verificação de idempotência

**Ação:** em homologação, guarde o corpo e a UUID da chamada **ef_confirmar_baixa_carga** feita no passo 5. Reenvie exatamente o mesmo corpo, com a mesma chave **p_idempotency_key**, usando a ferramenta autenticada de API. Faça isso antes de estornar a carga. **Não** clique novamente em confirmar para simular a repetição: uma nova operação pela tela pode gerar outra chave.

**Resultado esperado:** a RPC devolve o mesmo **carga_id**, sem criar outra carga e sem baixar o estoque pela segunda vez.

**Como verificar:** consulte **public.cargas** pela chave, usando **WHERE idempotency_key = '<UUID original>'**, e confirme uma única carga. Confirme que o saldo permanece igual ao saldo já reduzido no primeiro envio e que não surgiram linhas duplicadas em **historico_saidas**.

### 8) Estorno da carga

**Ação:** no cartão da carga principal, toque em **Estornar carga**. Confira resumo, NFs e itens. Informe motivo **Teste E2E Sprint 2.5.9** e confirme o estorno.

**Resultado esperado:** a tela informa quantos itens foram restaurados. O cartão passa de ATIVA para ESTORNADA, mostra o indicador vermelho e a data do estorno; o botão de estornar desaparece.

**Como verificar:** atualize o histórico e confira que a carga permanece visível como estornada. Tente estornar a mesma carga novamente apenas uma vez em homologação: deve receber aviso de que já foi estornada, sem alterar o estoque.

### 9) Verificação do estoque restaurado e divisão entre pilhas

**Ação:** atualize a lista de estoque após o estorno da carga principal.

**Resultado esperado:** cada pilha usada volta ao saldo que tinha antes da carga. A reposição do estorno aparece no histórico de entradas com referência “Estorno carga …”.

**Como verificar:** compare os saldos anotados na preparação com os atuais por produto, lote e pilha. Confira também **itens_restaurados** retornado pela RPC e os movimentos de entrada de estorno. A baixa avulsa do passo 2 continua separada; reverta-a em homologação ao final.

**Subteste da divisão 1 + 3:** com os saldos iniciais restaurados (A-11 = 1 e A-1 = 84), abra um rascunho novo e leia este QR sintético:

~~~json
{
  "v": 3,
  "seq_saida": "T259-SPLIT-20261009",
  "nr_nf": "T259-SPLIT-20261009",
  "itens": [
    {"codigo":"5151","produto":"TA 35 LT","lote":"701277","quantidade":4}
  ]
}
~~~

Adicione os itens à carga T259-CARGA-SPLIT. Selecione A-11 e depois A-1. Deve alocar 1 lt + 3 lt e mostrar **Completo, 4 de 4**. Confirme, verifique a carga em **Cargas**, estorne-a e confirme que os dois saldos voltaram exatamente ao valor inicial.

### 10) Conferência de validade — validityReview

**Ação:** prepare uma linha de teste sem validade, por exemplo TA 35 LT, lote **T259-VALIDADE-20261009**, saldo 1 na pilha T259-A-1 e validade vazia. Em uma base isolada sem outras pendências, toque em **Conferir validades**. No formulário aberto para o item pendente, informe 31/12/2027 e salve.

**Resultado esperado:** o formulário aponta o item pendente; depois de salvar, a validade aparece na linha, o contador de pendências diminui e o item deixa de estar pendente. Se for o único item sem validade, o botão indica que tudo foi conferido.

**Como verificar:** filtre por pendências de validade e confirme que o lote T259-VALIDADE-20261009 não aparece mais. Esse fluxo grava uma alteração real no banco de homologação; não faça o teste em uma linha real de produção.

### 11) Fallback de correspondência do produto

**Ação:** teste três QR sintéticos separados, sem confirmar carga:
1. **Código:** código existente 5151; confirme a correspondência com TA 35 LT pelo catálogo.
2. **Nome + lote:** use código inexistente, nome PERITO 10 KG e lote existente 0076-25-5779.
3. **Somente nome:** use código inexistente e nome de produto existente, mas um lote que não exista no estoque de teste. Escolha manualmente uma das pilhas sugeridas do produto.

**Resultado esperado:** caso 1 usa o produto do catálogo; caso 2 encontra o produto pelo nome e lote; caso 3 mostra aviso de correspondência pelo nome e pede escolha manual da pilha. A unidade vem da pilha escolhida, nunca do QR.

**Como verificar:** compare a origem do match/aviso exibido e a pilha selecionada. Feche os rascunhos sem confirmar. Use um lote inexistente somente neste subteste controlado.

## 3. Consultas de conferência (somente leitura)

Execute em homologação, ou peça ao administrador do banco para executar. Ajuste o código para o usado no teste.

~~~sql
SELECT carga_id, codigo, data_hora, quem_leva, status_estorno, estornada_em, itens
FROM public.ef_cargas_public
WHERE codigo LIKE 'T259-%'
ORDER BY data_hora DESC;

SELECT c.id, c.codigo, c.estornada, c.estornada_em, c.motivo_estorno,
       h.produto, h.lote, h.pilha, h.qtd, h.unid, h.carga_id
FROM public.cargas AS c
LEFT JOIN public.historico_saidas AS h ON h.carga_id = c.id
WHERE c.codigo LIKE 'T259-%'
ORDER BY c.data_hora DESC, h.produto, h.lote, h.pilha;

SELECT id, produto, lote, pilha, qtd, validade
FROM public.estoque
WHERE lote LIKE 'T259-%'
ORDER BY produto, lote, pilha;
~~~

## 4. Limpeza pós-teste

1. **Produção:** não crie cargas, NFs, entradas, saídas ou validades fictícias. Não apague histórico real nem linhas de **cargas_nfs**. Um QR real pode ser lido para conferir a prévia, mas feche o modal sem confirmar.
2. **Homologação:** primeiro estorne todas as cargas de teste ativas pela interface e confirme que o saldo foi restaurado. A RPC de estorno restaura as quantidades e grava entradas auditáveis; não ajuste o saldo manualmente antes de comparar os valores.
3. Reverta a baixa avulsa do passo 2 com a RPC de ajuste autorizada, modo **ajuste**, definindo o saldo para o valor anotado antes do teste. Use motivo e referência identificáveis como **Compensação T259 E2E** e uma UUID nova. Reverta também o saldo da entrada de teste para o saldo-base anotado, com registro de auditoria.
4. Para apagar cargas de teste da base de homologação, prefira restaurar o snapshot criado antes dos testes. Se a equipe decidir limpar por SQL, faça primeiro uma consulta de conferência; use somente os códigos sintéticos exatos; confirme que as cargas estão estornadas; execute em transação; e revise todas as linhas afetadas antes do COMMIT. As saídas e os vínculos de NF precisam ser removidos antes da carga por causa das relações entre tabelas. Remova também as entradas de auditoria de estorno apenas em homologação e somente pela referência exata **Estorno carga T259-CARGA-01** ou **Estorno carga T259-CARGA-SPLIT**.
5. Remova os registros de estoque criados só para o teste ou restaure a cópia/snapshot. Preserve a auditoria em qualquer base produtiva.

Exemplo de sequência de limpeza **apenas em homologação** — troque o código pelo valor sintético exato. Rode o SELECT, confira que é a carga certa e estornada, então faça a transação. Se qualquer quantidade/linha não corresponder ao esperado, use ROLLBACK em vez de COMMIT.

~~~sql
SELECT id, codigo, estornada
FROM public.cargas
WHERE codigo = 'T259-CARGA-01';

BEGIN;

DELETE FROM public.historico_entradas
WHERE referencia = 'Estorno carga T259-CARGA-01';

DELETE FROM public.historico_saidas
WHERE carga_id IN (
  SELECT id FROM public.cargas
  WHERE codigo = 'T259-CARGA-01' AND estornada IS TRUE
);

DELETE FROM public.cargas_nfs
WHERE carga_id IN (
  SELECT id FROM public.cargas
  WHERE codigo = 'T259-CARGA-01' AND estornada IS TRUE
);

DELETE FROM public.cargas
WHERE codigo = 'T259-CARGA-01' AND estornada IS TRUE
RETURNING id, codigo;

-- COMMIT somente após confirmar o conjunto exato de linhas.
-- Se houver divergência: ROLLBACK;
~~~

A limpeza SQL acima é apenas para rastros de carga já estornada em homologação. Ela não apaga a entrada de estoque inicial, a baixa avulsa nem os registros de validade; reverta-os com a RPC adequada ou restaure o snapshot.

## 5. Checklist final do Sprint 2.5

### Entregas

- [x] 2.5.1 — vínculo global de NF e estrutura pública de consulta das cargas.
- [x] 2.5.2 — baixa manual vinculada à carga e suporte ao registro auditável.
- [x] 2.5.3 — confirmação transacional da carga com vários itens.
- [x] 2.5.4 — estorno transacional e restauração auditável do estoque.
- [x] 2.5.5 e 2.5.5.1 — modal unificado, múltiplas NFs e data/hora da carga.
- [x] 2.5.6 — aba Cargas no histórico, com itens e estado de estorno.
- [x] 2.5.7 — ação de estorno na interface.
- [x] 2.5.8 — leitura do QR v3, com lotes como texto, quantidade inteira e unidade obtida do estoque.
- [x] 2.5.8.1 — alocação de um item entre várias pilhas.
- [x] 2.5.9 — este roteiro de testes ponta a ponta.
- [ ] Execução e registro dos passos em homologação. Marque somente após guardar evidências/resultados.

### RPCs usadas pelo fluxo

| RPC | Uso |
|---|---|
| **ef_alterar_saldo** | Entrada/ajuste auditável do saldo e correções controladas. |
| **ef_confirmar_baixa_manual** | Baixa manual, com **p_carga_id** nulo para uma saída avulsa ou preenchido para vincular à carga. |
| **ef_confirmar_baixa_qr** | Caminho legado de baixa QR; não usar para testar QR v3. |
| **ef_confirmar_baixa_carga** | Confirma uma carga com NFs, itens e chave de idempotência. |
| **ef_estornar_carga** | Estorna carga ativa e repõe o estoque. |

### Trigger e views

| Objeto | Tipo | Papel |
|---|---|---|
| **trg_baixas_qr_nf_global** | Trigger antes de inserir em **baixas_qr** | Registra/verifica a NF global por meio de **ef_registrar_nf_global_baixa_qr()**. |
| **ef_cargas_public** | View | Uma linha por carga, com estado, NFs/itens e dados para a aba Cargas. |
| **ef_historico_saidas_public** | View | Consulta pública do histórico de saídas. |
| **ef_historico_entradas_public** | View | Consulta pública do histórico de entradas, inclusive reposições do estorno. |

As duas views de histórico são consumidas pelo aplicativo; a view de cargas foi criada para o histórico agrupado. A função do trigger é uma função interna, não uma chamada do aplicativo.

### Conferência das definições no banco

Rode em homologação para confirmar nomes e assinaturas instalados:

~~~sql
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid) AS retorno
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'ef_alterar_saldo',
    'ef_confirmar_baixa_manual',
    'ef_confirmar_baixa_qr',
    'ef_confirmar_baixa_carga',
    'ef_estornar_carga',
    'ef_registrar_nf_global_baixa_qr'
  )
ORDER BY p.proname;

SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name IN (
    'ef_cargas_public',
    'ef_historico_saidas_public',
    'ef_historico_entradas_public'
  )
ORDER BY table_name;

SELECT tgname, pg_get_triggerdef(oid)
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname = 'trg_baixas_qr_nf_global';
~~~

**Versão final do aplicativo:** **v237**. Este roteiro não altera a versão do app. O Sprint 2.5 só deve ser considerado oficialmente validado após executar e registrar o checklist de homologação, incluindo a etapa de baixa avulsa (que hoje exige chamada autorizada da RPC, pois não há ação avulsa no modal v237).
