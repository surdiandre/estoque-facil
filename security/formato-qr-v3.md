# Especificação do QR v3 para Nota Fiscal

## Introdução

O QR v3 é um código QR que contém, como texto, um objeto JSON em UTF-8 referente a uma única Nota Fiscal de saída. O conteúdo identifica a sequência da saída e o número da NF e descreve cada item com código, nome do produto, lote e quantidade.

O formato permite transferir os dados da NF de maneira estruturada e conservar a separação entre linhas de produtos. Isso é necessário quando o mesmo produto aparece em mais de um lote: cada combinação de produto e lote precisa continuar identificável, com sua própria quantidade.

O QR v3 substitui o formato antigo v1. As versões não são compatíveis entre si: o emissor deve gerar somente a estrutura definida neste documento, com `"v": 3`. Um leitor compatível com esta especificação rejeita o formato v1 e qualquer estrutura diferente da definida abaixo. O campo `unid` foi removido. A unidade é obtida do cadastro do estoque, não do QR.

## 1. Conteúdo e estrutura

O QR Code deve conter diretamente o texto JSON abaixo, codificado em UTF-8. Não acrescente URL, prefixo, texto explicativo, aspas externas ou marcação Markdown. O exemplo mostra a estrutura; os valores devem ser substituídos pelos dados da NF.

```json
{
  "v": 3,
  "seq_saida": "75717",
  "nr_nf": "74531",
  "itens": [
    {
      "codigo": "5151",
      "produto": "TA 35 LT",
      "lote": "701277",
      "quantidade": 2000
    }
  ]
}
```

### Campos do objeto principal

Todos os campos desta tabela são obrigatórios. Não há campos opcionais.

| Campo | Tipo JSON | Regra |
|---|---|---|
| `v` | número inteiro | Deve ser exatamente `3`; não usar string. |
| `seq_saida` | string | Identificador não vazio da sequência de saída. Não reutilizar para saídas diferentes. |
| `nr_nf` | string | Número da Nota Fiscal, não vazio. Manter como texto, inclusive se contiver zeros à esquerda. |
| `itens` | array de objetos | Deve conter de 1 a 50 itens. |

### Campos de cada item

Todos os campos de cada item são obrigatórios. Não há campos opcionais.

| Campo | Tipo JSON | Regra |
|---|---|---|
| `codigo` | string | Código do produto, não vazio. |
| `produto` | string | Nome ou descrição do produto, não vazio. Deve ser texto UTF-8. |
| `lote` | string | Lote, não vazio. Sempre enviar como texto, preservando zeros à esquerda, letras e hífens. |
| `quantidade` | número inteiro | Quantidade entre `1` e `9007199254740991`, inclusive. Enviar sem aspas, separador de milhar ou parte fracionária. |
O objeto principal pode conter somente `v`, `seq_saida`, `nr_nf` e `itens`. Cada objeto de item pode conter somente `codigo`, `produto`, `lote` e `quantidade`. Qualquer outra chave, em qualquer nível, torna o JSON inválido para este formato.

### Limites do conteúdo

| Limite | Regra |
|---|---|
| Tamanho do texto JSON | No máximo 12.000 pontos de código Unicode na representação final que será colocada no QR, contando também espaços, aspas, chaves, colchetes, vírgulas e demais sinais. |
| Itens por NF | De 1 a 50 objetos no array `itens`. |

O limite de 12.000 caracteres é um limite de validação do conteúdo, não uma garantia de que qualquer QR Code consiga armazenar todo esse texto em um único símbolo. A capacidade física depende dos bytes UTF-8, da versão do QR e do nível de correção de erro. Em modo byte, a capacidade máxima teórica de um QR padrão versão 40 é de 2.331 bytes no nível M e 1.663 bytes no nível Q; textos JSON longos podem exceder a capacidade de um único símbolo. A [tabela de capacidade do node-qrcode](https://github.com/soldair/node-qrcode#qr-code-capacity) documenta esses limites. A biblioteca deve informar falha de capacidade. Nunca corte o texto nem o divida silenciosamente em vários QR Codes.

## 2. Exemplos prontos

### Exemplo simples — uma linha

Valores ilustrativos para teste; não representam uma NF real.

```json
{
  "v": 3,
  "seq_saida": "TESTE-001",
  "nr_nf": "99999",
  "itens": [
    {
      "codigo": "00123",
      "produto": "PRODUTO TESTE 1 LT",
      "lote": "0007-26-12345",
      "quantidade": 1000
    }
  ]
}
```

### NF 74531 — quatro produtos diferentes

```json
{
  "v": 3,
  "seq_saida": "75717",
  "nr_nf": "74531",
  "itens": [
    {"codigo":"5151","produto":"TA 35 LT","lote":"701277","quantidade":2000},
    {"codigo":"5439","produto":"ZAPP WG 720,5 KG","lote":"082-24-192000","quantidade":9000},
    {"codigo":"590","produto":"HEAT 700 FR 350 GR","lote":"474-24-01450","quantidade":4000},
    {"codigo":"2306","produto":"MES 5 LT","lote":"052620000","quantidade":4000}
  ]
}
```

### NF 74522 — cinco linhas, dois lotes de PERITO

```json
{
  "v": 3,
  "seq_saida": "75709",
  "nr_nf": "74522",
  "itens": [
    {"codigo":"5151","produto":"TA 35 LT","lote":"701277","quantidade":4000},
    {"codigo":"1161","produto":"PERITO 10 KG","lote":"0076-25-5779","quantidade":4000},
    {"codigo":"1161","produto":"PERITO 10 KG","lote":"1940-25-5779","quantidade":3000},
    {"codigo":"264","produto":"PRIMOLÉO 20 LITRO","lote":"0059-26-86400","quantidade":6000},
    {"codigo":"667","produto":"AUREO GL 5 LT","lote":"036-25-047000","quantidade":4000}
  ]
}
```

## Caso especial: mesmo produto, lotes diferentes

O produto PERITO 10 KG, código `1161`, aparece em duas linhas independentes na NF 74522:

| Código | Produto | Lote | Quantidade |
|---|---|---|---:|
| 1161 | PERITO 10 KG | `0076-25-5779` | 4.000 |
| 1161 | PERITO 10 KG | `1940-25-5779` | 3.000 |

O emissor deve gerar as duas linhas como no exemplo. Não some as quantidades nem transforme os lotes diferentes em um item só. Os zeros à esquerda do primeiro lote fazem parte do valor.

## 3. Regras de validação e rejeição

O gerador deve produzir somente JSON válido que siga todas as regras desta tabela. Um leitor deve rejeitar o conteúdo quando qualquer uma delas for violada.

| Rejeitar quando… | Exemplo ou regra correta |
|---|---|
| O conteúdo não for JSON válido ou o valor principal não for um objeto. | Não aceitar texto livre, array no lugar do objeto ou JSON malformado. |
| `v` estiver ausente, não for número inteiro ou não for `3`. | Correto: `"v": 3`; incorreto: `"v": "3"` ou `"v": 2`. |
| `seq_saida` ou `nr_nf` estiver ausente, vazio, contiver apenas espaços ou não for string. | Os dois campos devem ser strings com conteúdo. |
| `itens` estiver ausente, não for array, estiver vazio ou tiver mais de 50 itens. | Usar de 1 a 50 objetos. |
| Um item não for objeto, ou faltar qualquer campo obrigatório. | Cada item deve conter os cinco campos definidos nesta especificação. |
| `codigo`, `produto` ou `lote` não for string ou estiver vazio/contiver apenas espaços. | Exemplo correto de lote: `"0076-25-5779"`. |
| `lote` for enviado como número JSON. | Correto: `"lote": "701277"`; incorreto: `"lote": 701277`. |
| `quantidade` não for número inteiro entre `1` e `9007199254740991`. | Rejeitar valores fracionários, zero, negativos, valores acima do limite e strings. Correto: `"quantidade": 4000`; incorretos: `4.5`, `0`, `-1` e `"4000"`. |
| `unid` estiver presente em um item. | Campo extra não permitido; rejeitar com a mensagem `campo não permitido no item: unid`. |
| O objeto principal ou um item tiver qualquer campo adicional. | Somente as chaves especificadas nas tabelas de campos são permitidas. |
| O texto JSON final tiver mais de 12.000 pontos de código Unicode. | Contar o texto serializado completo, incluindo pontuação e espaços. |

Para evitar diferenças entre emissores, grave `quantidade` na forma canônica de inteiro JSON, sem parte decimal ou expoente, por exemplo `4000`. Códigos e lotes devem permanecer como strings; não os converta para números, pois isso pode remover zeros à esquerda.

## 4. Geração e impressão do QR Code

| Configuração | Recomendação |
|---|---|
| Dados codificados | O texto JSON completo, em UTF-8. Não codificar como URL. |
| Correção de erro (ECC) | Usar M (aproximadamente 15%) como padrão. Usar Q (aproximadamente 25%) quando for importante ter mais tolerância a sujeira ou dano, lembrando que Q reduz a capacidade de dados. Os níveis e percentuais são descritos nas documentações do [node-qrcode](https://github.com/soldair/node-qrcode#error-correction-level) e do [python-qrcode](https://github.com/lincolnloop/python-qrcode). |
| Tamanho impresso | Começar com pelo menos 5 × 5 cm para as NFs de exemplo. Para símbolos mais densos, testar 6 × 6 cm ou maior. São tamanhos iniciais recomendados, não uma garantia: validar na impressora, etiqueta e distância reais de leitura. |
| Margem livre | Manter uma borda branca sem impressão de pelo menos 4 módulos ao redor do símbolo. O projeto [python-qrcode](https://github.com/lincolnloop/python-qrcode) documenta essa margem como o mínimo do padrão. |
| Aparência | Preferir módulos quadrados pretos em fundo branco, alto contraste e impressão nítida. Não recortar a borda, sobrepor logotipo ou aplicar efeitos que alterem os módulos. |
| Capacidade | Confirmar que a biblioteca conseguiu codificar o texto completo. Se não couber em um símbolo, interromper e revisar a solução; não truncar nem dividir o conteúdo sem uma especificação acordada. |

Bibliotecas sugeridas, como ponto de partida. São opções de implementação; não alteram o formato do JSON.

| Linguagem | Biblioteca sugerida | Repositório oficial |
|---|---|---|
| PHP | Endroid QR Code | [github.com/endroid/qr-code](https://github.com/endroid/qr-code) |
| Python | `qrcode` (python-qrcode) | [github.com/lincolnloop/python-qrcode](https://github.com/lincolnloop/python-qrcode) |
| Node.js | `qrcode` (node-qrcode) | [github.com/soldair/node-qrcode](https://github.com/soldair/node-qrcode) |
| Java | ZXing | [github.com/zxing/zxing](https://github.com/zxing/zxing) |

## 5. Checklist de implementação

1. Monte um objeto JSON por NF, com os quatro campos principais e os cinco campos em cada item.
2. Valide os tipos e as regras deste documento antes de gerar o QR. Não inclua chaves extras.
3. Preserve os dados como texto quando indicado. Em particular, mantenha zeros à esquerda em códigos e lotes e mantenha lotes diferentes em itens separados.
4. Gere a representação JSON em UTF-8 e confira os limites de 12.000 caracteres e de 1 a 50 itens.
5. Gere um único QR com ECC M ou Q. Confirme que a biblioteca não retornou erro de capacidade e que nenhum dado foi truncado.
6. Imprima primeiro em tamanho de teste de pelo menos 5 × 5 cm, mantendo a margem branca. Leia a impressão usando os equipamentos e a distância previstos para o uso real.
7. Decodifique o QR gerado com pelo menos dois leitores independentes. Compare o JSON lido com o conteúdo de origem: campos, tipos, acentos, códigos, lotes e quantidades devem coincidir. Confirme que cada item do JSON não contém `unid`.
8. Rode testes positivos com o exemplo simples e com as NFs 74531 e 74522 deste documento. Na NF 74522, confirme cinco linhas e duas linhas de PERITO, cada uma com seu lote e quantidade original. Após escolher cada pilha, confirme que a unidade usada corresponde ao cadastro daquela pilha.
9. Rode testes negativos para cada situação da tabela de rejeição: versão diferente, identificadores vazios, itens ausentes/vazios, quantidade fracionária ou em string, lote numérico, QR antigo com `unid`, outro campo extra e conteúdo acima do limite.
10. Faça um piloto em ambiente de homologação com dados representativos. Libere para produção somente depois que todos os QRs forem lidos integralmente e os testes positivos e negativos tiverem o resultado esperado.
