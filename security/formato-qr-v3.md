# Formato QR v3 — NF Coperacel

## Objetivo

Este documento define o JSON UTF-8 que o sistema emissor deve gravar no QR Code de cada NF de saída da Coperacel. O leitor do Estoque Fácil aceita somente a versão 3.

## Estrutura

~~~json
{
  "v": 3,
  "seq_saida": "75717",
  "nr_nf": "74531",
  "itens": [
    {
      "codigo": "5151",
      "produto": "TA 35 LT",
      "lote": "701277",
      "quantidade": 2000,
      "unid": "lt"
    }
  ]
}
~~~

## Exemplos reais

### NF 74531 — quatro produtos

~~~json
{
  "v": 3,
  "seq_saida": "75717",
  "nr_nf": "74531",
  "itens": [
    {"codigo":"5151","produto":"TA 35 LT","lote":"701277","quantidade":2000,"unid":"lt"},
    {"codigo":"5439","produto":"ZAPP WG 720,5 KG","lote":"082-24-192000","quantidade":9000,"unid":"pct"},
    {"codigo":"590","produto":"HEAT 700 FR 350 GR","lote":"474-24-01450","quantidade":4000,"unid":"fr"},
    {"codigo":"2306","produto":"MES 5 LT","lote":"052620000","quantidade":4000,"unid":"lt"}
  ]
}
~~~

### NF 74522 — cinco linhas

~~~json
{
  "v": 3,
  "seq_saida": "75709",
  "nr_nf": "74522",
  "itens": [
    {"codigo":"5151","produto":"TA 35 LT","lote":"701277","quantidade":4000,"unid":"lt"},
    {"codigo":"1161","produto":"PERITO 10 KG","lote":"0076-25-5779","quantidade":4000,"unid":"pct"},
    {"codigo":"1161","produto":"PERITO 10 KG","lote":"1940-25-5779","quantidade":3000,"unid":"pct"},
    {"codigo":"264","produto":"PRIMOLÉO 20 LITRO","lote":"0059-26-86400","quantidade":6000,"unid":"bld"},
    {"codigo":"667","produto":"AUREO GL 5 LT","lote":"036-25-047000","quantidade":4000,"unid":"gl"}
  ]
}
~~~

## Caso especial: mesmo produto, lotes diferentes

O produto PERITO 10 KG, código 1161, aparece em duas linhas da NF 74522:

| Código | Produto | Lote | Quantidade | Unidade |
|---|---|---|---:|---|
| 1161 | PERITO 10 KG | 0076-25-5779 | 4.000 | pct |
| 1161 | PERITO 10 KG | 1940-25-5779 | 3.000 | pct |

As linhas são itens independentes. O QR deve preservar cada lote e sua quantidade. Não some os valores em 7.000 nem transforme as duas linhas em um item só. O operador escolhe uma pilha para cada lote; o Estoque Fácil mostra o badge **⚠ mesmo produto** nas linhas que compartilham o código.

## Unidades válidas

| Valor no JSON | Unidade |
|---|---|
| lt | Litro |
| pct | Pacote |
| bld | Bombona |
| gl | Galão |
| fr | Frasco |
| kg | Quilograma |
| sc | Saca |

O valor precisa estar em letras minúsculas e corresponder exatamente a um item da tabela.

## Regras de validação

- **v**: número inteiro 3 (não enviar como string).
- **seq_saida**: string não vazia.
- **nr_nf**: string não vazia.
- **itens**: array com pelo menos 1 e no máximo 50 linhas. Recomenda-se limitar a 20 linhas por QR para facilitar leitura.
- **codigo**, **produto** e **lote**: strings não vazias.
- **lote**: sempre string. Preserve zeros à esquerda e hífens, por exemplo "0076-25-5779".
- **quantidade**: número inteiro positivo JSON, sem aspas, sem decimais e sem separador de milhar. Exemplo válido: 4000; inválidos: 4.5 e "4.000".
- **unid**: string minúscula de uma das sete unidades válidas.
- O JSON completo deve ter no máximo 12.000 caracteres.
- Não agrupe linhas com códigos iguais quando os lotes forem diferentes.
- Campos fora do formato definido são inválidos; o leitor não converte tipos nem tenta interpretar campos antigos.

## Campos que não devem ser incluídos

Não inclua **tipo**, **oper**, **ordem**, **filial**, **serie**, **qtd** ou **dias**. Use **nr_nf** para o número da nota, **quantidade** para a quantidade do item e **seq_saida** para identificar a saída.

## Correção do QR Code

Use codificação UTF-8. Para correção de erros (ECC), recomenda-se nível **M (15%)** ou **Q (25%)**. Garanta contraste alto, impressão nítida e tamanho suficiente para leitura por câmera.

## Como testar

Aplicativo em produção (v230): [https://estoque-facil.balancacoperacel1.workers.dev/](https://estoque-facil.balancacoperacel1.workers.dev/).

Para executar a suíte automatizada no checkout do repositório:

~~~bash
npm run test:html
~~~

Os testes incluem as 19 verificações anteriores e os casos A–I, os limites e o fallback do QR v3. Para uma conferência manual, abra a leitura QR no aplicativo e selecione uma imagem de teste. Leia o QR e revise os itens, lotes, quantidades, badges e seletores de pilha. Não confirme uma baixa com as NFs reais de exemplo na produção.
