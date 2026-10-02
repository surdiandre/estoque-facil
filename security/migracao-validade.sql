-- ============================================================================
-- Tarefa 1.2 — migração estrutural da validade
-- Adiciona a coluna de data absoluta sem converter os valores antigos de "dias".
-- Os registros existentes ficam com validade = NULL para conferência manual
-- com o sistema da empresa. NULL significa "a conferir", não uma validade.
--
-- Este arquivo está preparado para teste: a transação termina em ROLLBACK e
-- não persiste alterações. Depois de validar os resultados, substitua o
-- ROLLBACK ativo por COMMIT para aplicar a estrutura.
-- ============================================================================

BEGIN;

ALTER TABLE public.estoque
    ADD COLUMN validade DATE;

COMMENT ON COLUMN public.estoque.validade IS
    'Data absoluta de validade. NULL = ainda não conferida manualmente no sistema da empresa.';

COMMENT ON COLUMN public.estoque.dias IS
    'OBSOLETO. Mantido por compatibilidade. Usar validade.';

CREATE INDEX idx_estoque_validade
    ON public.estoque (validade)
    WHERE validade IS NOT NULL;

-- Verificação: esperado nesta base — total = 298, com_validade = 0.
SELECT COUNT(*) AS total, COUNT(validade) AS com_validade
FROM public.estoque;

-- Verificação visual: validade deve aparecer como NULL nos registros existentes.
SELECT id, produto, lote, dias, validade
FROM public.estoque
LIMIT 5;

ROLLBACK;

-- Bloco de ROLLBACK comentado para referência do modo de teste:
-- ROLLBACK;
