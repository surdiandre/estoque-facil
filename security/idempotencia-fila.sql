-- Estoque Fácil — 2.4.1: colunas e índices de idempotência
--
-- O que esta migração faz:
--   1. Adiciona idempotency_key às tabelas de movimentos.
--   2. Cria índices únicos parciais para impedir repetição da mesma chave.
--   3. Adiciona saldo_resultante aos históricos de entrada e saída para que
--      as RPCs possam devolver o mesmo saldo em uma repetição.
--   4. Lista as colunas, índices e amostras para conferência.
--
-- As colunas são nullable porque os movimentos antigos não têm chave de
-- idempotência nem saldo resultante registrado.
--
-- Os índices são parciais (WHERE idempotency_key IS NOT NULL) para indexar
-- somente operações novas com chave. Linhas antigas sem chave permanecem
-- fora do índice.
--
-- TESTE: execute o arquivo inteiro com o ROLLBACK ativo. As consultas de
-- verificação enxergam as alterações dentro da transação; ao final, o
-- ROLLBACK desfaz tudo.
--
-- Depois de revisar os resultados e autorizar a persistência, troque o
-- ROLLBACK final por COMMIT e execute novamente.
--
-- Rollback manual após uma futura aplicação persistente:
--   DROP INDEX IF EXISTS public.idx_historico_entradas_idempotency;
--   DROP INDEX IF EXISTS public.idx_historico_saidas_idempotency;
--   DROP INDEX IF EXISTS public.idx_ef_ajustes_saldo_idempotency;
--   ALTER TABLE public.historico_entradas
--     DROP COLUMN IF EXISTS idempotency_key,
--     DROP COLUMN IF EXISTS saldo_resultante;
--   ALTER TABLE public.historico_saidas
--     DROP COLUMN IF EXISTS idempotency_key,
--     DROP COLUMN IF EXISTS saldo_resultante;
--   ALTER TABLE public.ef_ajustes_saldo
--     DROP COLUMN IF EXISTS idempotency_key;

BEGIN;

ALTER TABLE public.historico_entradas
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS saldo_resultante numeric;

ALTER TABLE public.historico_saidas
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS saldo_resultante numeric;

ALTER TABLE public.ef_ajustes_saldo
  ADD COLUMN IF NOT EXISTS idempotency_key uuid;

CREATE UNIQUE INDEX IF NOT EXISTS idx_historico_entradas_idempotency
  ON public.historico_entradas (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_historico_saidas_idempotency
  ON public.historico_saidas (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ef_ajustes_saldo_idempotency
  ON public.ef_ajustes_saldo (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- Confirme que todas as colunas esperadas existem.
WITH required(table_name, column_name) AS (
  VALUES
    ('historico_entradas', 'idempotency_key'),
    ('historico_entradas', 'saldo_resultante'),
    ('historico_saidas', 'idempotency_key'),
    ('historico_saidas', 'saldo_resultante'),
    ('ef_ajustes_saldo', 'idempotency_key')
)
SELECT
  required.table_name,
  required.column_name,
  EXISTS (
    SELECT 1
    FROM information_schema.columns AS c
    WHERE c.table_schema = 'public'
      AND c.table_name = required.table_name
      AND c.column_name = required.column_name
  ) AS coluna_existe
FROM required
ORDER BY required.table_name, required.column_name;

-- Confirme a definição dos três índices únicos parciais.
SELECT tablename, indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'idx_historico_entradas_idempotency',
    'idx_historico_saidas_idempotency',
    'idx_ef_ajustes_saldo_idempotency'
  )
ORDER BY indexname;

-- Amostra de até 5 movimentos de cada tabela, sem expor usuário ou empresa.
SELECT id, data, produto, lote, pilha, qtd, idempotency_key, saldo_resultante
FROM public.historico_entradas
ORDER BY id DESC
LIMIT 5;

SELECT id, data, produto, lote, pilha, qtd, idempotency_key, saldo_resultante
FROM public.historico_saidas
ORDER BY id DESC
LIMIT 5;

SELECT
  id, produto, lote, pilha, saldo_anterior, saldo_novo, idempotency_key
FROM public.ef_ajustes_saldo
ORDER BY id DESC
LIMIT 5;

-- Ativo para o teste inicial: desfaz as mudanças ao terminar.
ROLLBACK;
