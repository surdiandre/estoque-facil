-- Correção documentada do gap de schema encontrado em produção.
-- A coluna public.estoque.dias continuava NOT NULL, mas o app deixou de gravá-la.
-- Ela fica nullable apenas para compatibilidade; public.estoque.validade é a fonte de validade.
-- Não converte nem altera os valores existentes.
-- Idempotente: DROP NOT NULL e COMMENT podem ser reaplicados na coluna existente.
-- Teste: execute com ROLLBACK; depois de validar a saída, troque somente por COMMIT.

BEGIN;

ALTER TABLE public.estoque
  ALTER COLUMN dias DROP NOT NULL;

COMMENT ON COLUMN public.estoque.dias IS 'OBSOLETO. Mantido por compatibilidade. Não é mais gravado. Usar validade.';

-- Verificação: is_nullable deve retornar YES.
SELECT
  table_schema,
  table_name,
  column_name,
  is_nullable,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'estoque'
  AND column_name = 'dias';

ROLLBACK;
