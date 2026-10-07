-- Estoque Fácil — Sprint 2.5.2
-- Vincula a baixa manual a uma carga existente, mantendo idempotência,
-- snapshots de estoque, segurança da RPC e chamadas legadas sem p_carga_id.
--
-- IMPORTANTE SOBRE O TIPO:
-- public.cargas.id e public.historico_saidas.carga_id são bigint no 2.5.1.
-- Por isso p_carga_id também é bigint. O parâmetro UUID já existente,
-- p_idempotency_key, permanece como terceiro parâmetro.
--
-- Este arquivo termina em COMMIT e aplica a migração se as guardas passarem.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Verificações ANTES das alterações
-- ---------------------------------------------------------------------------

-- Confirme as colunas e tipos esperados após os blocos 2.4.1 e 2.5.1.
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'cargas' AND column_name IN ('id', 'estornada'))
    OR
    (table_name = 'estoque' AND column_name IN (
      'id', 'qtd', 'armazem', 'validade', 'unid'
    ))
    OR
    (table_name = 'historico_saidas' AND column_name IN (
      'id', 'carga_id', 'armazem', 'validade', 'unid',
      'idempotency_key', 'saldo_resultante'
    ))
  )
ORDER BY table_name, ordinal_position;

-- A RPC antiga esperada é a versão do 2.4.2: bigint, integer, uuid.
SELECT
  p.oid::regprocedure AS assinatura_atual,
  pg_get_function_arguments(p.oid) AS argumentos_com_defaults,
  p.prosecdef AS security_definer,
  p.proconfig AS configuracao
FROM pg_catalog.pg_proc AS p
WHERE p.oid =
  to_regprocedure('public.ef_confirmar_baixa_manual(bigint, integer, uuid)');

-- Confirme a FK e o índice criados pelo 2.5.1.
SELECT
  c.conname,
  pg_catalog.pg_get_constraintdef(c.oid) AS definicao
FROM pg_catalog.pg_constraint AS c
WHERE c.conrelid = 'public.historico_saidas'::regclass
  AND c.conname = 'historico_saidas_carga_id_fkey';

SELECT indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'historico_saidas'
  AND indexname = 'idx_historico_saidas_carga';

-- Grants atualmente concedidos à assinatura antiga.
SELECT
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
    'EXECUTE'
  ) AS anon_execute,
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
    'EXECUTE'
  ) AS authenticated_execute,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
    'EXECUTE'
  ) AS service_role_execute;

-- Interrompe antes de qualquer alteração se o estado não corresponder
-- ao esperado ou se houver uma sobrecarga que causaria ambiguidade.
DO $$
BEGIN
  IF pg_catalog.to_regclass('public.cargas') IS NULL
     OR pg_catalog.to_regclass('public.estoque') IS NULL
     OR pg_catalog.to_regclass('public.historico_saidas') IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: cargas, estoque ou historico_saidas não existe.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'cargas'
      AND column_name = 'id' AND data_type = 'bigint'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'cargas'
      AND column_name = 'estornada' AND data_type = 'boolean'
  ) THEN
    RAISE EXCEPTION
      'Tipo/coluna inesperado em public.cargas; esperado id bigint e estornada boolean.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'historico_saidas'
      AND column_name = 'carga_id' AND data_type = 'bigint'
  ) THEN
    RAISE EXCEPTION
      'historico_saidas.carga_id precisa ser bigint para referenciar cargas.id.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.historico_saidas'::regclass
      AND confrelid = 'public.cargas'::regclass
      AND conname = 'historico_saidas_carga_id_fkey'
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION
      'FK historico_saidas_carga_id_fkey para cargas(id) não encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'historico_saidas'
      AND indexname = 'idx_historico_saidas_carga'
  ) THEN
    RAISE EXCEPTION
      'Índice idx_historico_saidas_carga não encontrado.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'estoque'
      AND column_name = 'qtd'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'estoque'
      AND column_name = 'armazem'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'estoque'
      AND column_name = 'validade'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'estoque'
      AND column_name = 'unid'
  ) THEN
    RAISE EXCEPTION
      'A tabela estoque precisa ter qtd, armazem, validade e unid para a baixa e os snapshots.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'historico_saidas'
      AND column_name = 'armazem'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'historico_saidas'
      AND column_name = 'validade'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'historico_saidas'
      AND column_name = 'unid'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'historico_saidas'
      AND column_name = 'idempotency_key'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'historico_saidas'
      AND column_name = 'saldo_resultante'
  ) THEN
    RAISE EXCEPTION
      'Faltam snapshots ou colunas de idempotência em historico_saidas.';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid)'
     ) IS NULL THEN
    RAISE EXCEPTION
      'Assinatura antiga ef_confirmar_baixa_manual(bigint, integer, uuid) não encontrada.';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ef_confirmar_baixa_manual(bigint, integer)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION
      'A sobrecarga antiga de dois parâmetros ainda existe; remova/revise antes de continuar.';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION
      'A assinatura nova já existe; revise o estado antes de reaplicar esta migração.';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION
      'O role authenticated não tem EXECUTE na assinatura antiga; grants inesperados.';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
       'EXECUTE'
     ) OR has_function_privilege(
       'service_role',
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION
      'Grants inesperados na assinatura antiga: anon/service_role não devem executar a RPC.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Substituição da RPC
-- ---------------------------------------------------------------------------

-- Remove a assinatura exata do 2.4.2 antes de recriar a função,
-- evitando overload ambíguo no PostgREST.
DROP FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid);

CREATE OR REPLACE FUNCTION public.ef_confirmar_baixa_manual(
  p_id bigint,
  p_quantidade integer,
  p_idempotency_key uuid DEFAULT NULL,
  p_carga_id bigint DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v public.estoque%rowtype;
  v_email text;
  v_novo_saldo numeric;
  v_carga_estornada boolean;
BEGIN
  v_email := auth.jwt()->>'email';

  IF auth.uid() IS NULL OR v_email IS DISTINCT FROM 'balancacoperacel1@gmail.com' THEN
    RAISE EXCEPTION 'Acesso administrativo obrigatório.';
  END IF;

  IF p_id IS NULL OR p_id < 1 OR p_quantidade IS NULL OR p_quantidade <= 0 THEN
    RAISE EXCEPTION 'Pilha ou quantidade inválida.';
  END IF;

  -- A chave idempotente continua sendo verificada antes da baixa.
  IF p_idempotency_key IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext(p_idempotency_key::text)
    );

    SELECT hs.saldo_resultante
    INTO v_novo_saldo
    FROM public.historico_saidas AS hs
    WHERE hs.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      IF v_novo_saldo IS NULL THEN
        RAISE EXCEPTION 'A chave de idempotência da baixa não tem saldo_resultante.';
      END IF;
      RETURN v_novo_saldo;
    END IF;
  END IF;

  -- Serializa baixa manual e estorno para a mesma carga. Se a carga estiver
  -- ausente ou estornada, nenhum saldo nem histórico será alterado.
  IF p_carga_id IS NOT NULL THEN
    SELECT c.estornada
    INTO v_carga_estornada
    FROM public.cargas AS c
    WHERE c.id = p_carga_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Carga % não encontrada.', p_carga_id;
    END IF;

    IF v_carga_estornada THEN
      RAISE EXCEPTION
        'Carga % já está estornada; não é possível vincular uma nova baixa.',
        p_carga_id;
    END IF;
  END IF;

  SELECT e.*
  INTO v
  FROM public.estoque AS e
  WHERE e.id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pilha não encontrada. Atualize o estoque.';
  END IF;

  IF v.qtd IS NULL OR v.qtd < p_quantidade THEN
    RAISE EXCEPTION 'Saldo insuficiente. Atualize o estoque e tente novamente.';
  END IF;

  v_novo_saldo := v.qtd - p_quantidade;

  IF v_novo_saldo = 0 THEN
    DELETE FROM public.estoque AS e
    WHERE e.id = p_id;
  ELSE
    UPDATE public.estoque AS e
    SET qtd = v_novo_saldo
    WHERE e.id = p_id;
  END IF;

  INSERT INTO public.historico_saidas (
    data, produto, empresa, lote, pilha, qtd, unid, usuario,
    idempotency_key, saldo_resultante, carga_id, armazem, validade
  )
  VALUES (
    (now() AT TIME ZONE 'America/Sao_Paulo')::date,
    v.produto,
    coalesce(v.empresa, ''),
    v.lote,
    v.pilha,
    p_quantidade,
    v.unid,
    v_email,
    p_idempotency_key,
    v_novo_saldo,
    p_carga_id,
    v.armazem,
    v.validade
  );

  RETURN v_novo_saldo;
END;
$$;

COMMENT ON FUNCTION public.ef_confirmar_baixa_manual(
  bigint, integer, uuid, bigint
) IS
  'Baixa manual transacional e idempotente; pode vincular a saída a uma carga ativa e grava snapshots para estorno.';

-- A assinatura anterior tinha EXECUTE apenas para authenticated.
-- Recriar o grant e remover os privilégios padrão de PUBLIC.
REVOKE ALL ON FUNCTION public.ef_confirmar_baixa_manual(
  bigint, integer, uuid, bigint
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.ef_confirmar_baixa_manual(
  bigint, integer, uuid, bigint
) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 2. Verificações DEPOIS das alterações
-- ---------------------------------------------------------------------------

-- Coluna de vínculo, snapshots, FK e índice.
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'historico_saidas'
  AND column_name IN ('carga_id', 'armazem', 'validade', 'unid')
ORDER BY ordinal_position;

SELECT
  c.conname,
  pg_catalog.pg_get_constraintdef(c.oid) AS definicao
FROM pg_catalog.pg_constraint AS c
WHERE c.conrelid = 'public.historico_saidas'::regclass
  AND c.conname = 'historico_saidas_carga_id_fkey';

SELECT indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'historico_saidas'
  AND indexname = 'idx_historico_saidas_carga';

-- Assinatura, argumentos com defaults e propriedades de segurança.
SELECT
  p.oid::regprocedure AS assinatura,
  pg_catalog.pg_get_function_identity_arguments(p.oid)
    AS argumentos_identidade,
  pg_catalog.pg_get_function_arguments(p.oid)
    AS argumentos_com_defaults,
  p.prosecdef AS security_definer,
  p.proconfig AS configuracao
FROM pg_catalog.pg_proc AS p
WHERE p.oid =
  to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
  );

-- Deve retornar authenticated=true, anon=false, service_role=false.
SELECT
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
    'EXECUTE'
  ) AS anon_execute,
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
    'EXECUTE'
  ) AS authenticated_execute,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
    'EXECUTE'
  ) AS service_role_execute,
  pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid)'
  ) IS NULL AS assinatura_antiga_removida;

-- ---------------------------------------------------------------------------
-- RESULTADO ESPERADO:
-- * Antes: cargas.id e historico_saidas.carga_id são bigint.
-- * Antes: assinatura antiga (bigint, integer, uuid), auth EXECUTE=true,
--   anon/service_role EXECUTE=false, FK e índice presentes.
-- * Depois: assinatura (bigint, integer, uuid, bigint), último argumento
--   p_carga_id bigint DEFAULT NULL; assinatura antiga ausente.
-- * Depois: authenticated_execute=true, anon_execute=false,
--   service_role_execute=false.
-- * A verificação final aborta a transação se assinatura, overload ou grants divergirem.

-- ---------------------------------------------------------------------------
-- 3. Verificação final obrigatória: qualquer divergência aborta antes do COMMIT
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_function oid;
  v_arguments text;
  v_overload_count integer;
BEGIN
  v_function := pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
  )::oid;

  IF v_function IS NULL THEN
    RAISE EXCEPTION
      'Verificação final falhou: assinatura nova (bigint, integer, uuid, bigint) não encontrada.';
  END IF;

  v_arguments := pg_catalog.pg_get_function_arguments(v_function);
  IF v_arguments !~
     '^p_id bigint, p_quantidade integer, p_idempotency_key uuid DEFAULT NULL(::uuid)?, p_carga_id bigint DEFAULT NULL(::bigint)?$' THEN
    RAISE EXCEPTION
      'Verificação final falhou: argumentos da RPC inesperados: %',
      v_arguments;
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION
      'Verificação final falhou: assinatura antiga (bigint, integer, uuid) ainda existe.';
  END IF;

  SELECT count(*)
  INTO v_overload_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_confirmar_baixa_manual';

  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION
      'Verificação final falhou: esperada exatamente uma sobrecarga pública, encontradas %.',
      v_overload_count;
  END IF;

  IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
    RAISE EXCEPTION
      'Verificação final falhou: authenticated não tem EXECUTE.';
  END IF;

  IF has_function_privilege('anon', v_function, 'EXECUTE') THEN
    RAISE EXCEPTION
      'Verificação final falhou: anon tem EXECUTE.';
  END IF;

  IF has_function_privilege('service_role', v_function, 'EXECUTE') THEN
    RAISE EXCEPTION
      'Verificação final falhou: service_role tem EXECUTE.';
  END IF;
END;
$$;

-- Resultado esperado da guarda final: arguments terminam com
-- "p_carga_id bigint DEFAULT NULL"; assinatura antiga ausente;
-- uma única sobrecarga; authenticated=true, anon=false, service_role=false.

COMMIT;

-- ---------------------------------------------------------------------------
-- Rollback manual caso esta migração seja aplicada futuramente com COMMIT
-- ---------------------------------------------------------------------------
-- Use apenas se precisar restaurar a RPC 2.4.2.
-- Este rollback NÃO remove carga_id, snapshots, cargas ou cargas_nfs do 2.5.1.
--
-- BEGIN;
-- DROP FUNCTION IF EXISTS public.ef_confirmar_baixa_manual(
--   bigint, integer, uuid, bigint
-- );
--
-- CREATE OR REPLACE FUNCTION public.ef_confirmar_baixa_manual(
--   p_id bigint,
--   p_quantidade integer,
--   p_idempotency_key uuid DEFAULT NULL
-- )
-- RETURNS numeric
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = ''
-- AS $$
-- DECLARE
--   v public.estoque%rowtype;
--   v_email text;
--   v_novo_saldo numeric;
-- BEGIN
--   v_email := auth.jwt()->>'email';
--
--   IF auth.uid() IS NULL OR v_email IS DISTINCT FROM 'balancacoperacel1@gmail.com' THEN
--     RAISE EXCEPTION 'Acesso administrativo obrigatório.';
--   END IF;
--
--   IF p_id IS NULL OR p_id < 1 OR p_quantidade IS NULL OR p_quantidade <= 0 THEN
--     RAISE EXCEPTION 'Pilha ou quantidade inválida.';
--   END IF;
--
--   IF p_idempotency_key IS NOT NULL THEN
--     PERFORM pg_catalog.pg_advisory_xact_lock(
--       pg_catalog.hashtext(p_idempotency_key::text)
--     );
--
--     SELECT hs.saldo_resultante
--     INTO v_novo_saldo
--     FROM public.historico_saidas AS hs
--     WHERE hs.idempotency_key = p_idempotency_key;
--
--     IF FOUND THEN
--       IF v_novo_saldo IS NULL THEN
--         RAISE EXCEPTION 'A chave de idempotência da baixa não tem saldo_resultante.';
--       END IF;
--       RETURN v_novo_saldo;
--     END IF;
--   END IF;
--
--   SELECT e.*
--   INTO v
--   FROM public.estoque AS e
--   WHERE e.id = p_id
--   FOR UPDATE;
--
--   IF NOT FOUND THEN
--     RAISE EXCEPTION 'Pilha não encontrada. Atualize o estoque.';
--   END IF;
--
--   IF v.qtd IS NULL OR v.qtd < p_quantidade THEN
--     RAISE EXCEPTION 'Saldo insuficiente. Atualize o estoque e tente novamente.';
--   END IF;
--
--   v_novo_saldo := v.qtd - p_quantidade;
--
--   IF v_novo_saldo = 0 THEN
--     DELETE FROM public.estoque AS e
--     WHERE e.id = p_id;
--   ELSE
--     UPDATE public.estoque AS e
--     SET qtd = v_novo_saldo
--     WHERE e.id = p_id;
--   END IF;
--
--   INSERT INTO public.historico_saidas (
--     data, produto, empresa, lote, pilha, qtd, unid, usuario,
--     idempotency_key, saldo_resultante
--   )
--   VALUES (
--     (now() AT TIME ZONE 'America/Sao_Paulo')::date,
--     v.produto,
--     coalesce(v.empresa, ''),
--     v.lote,
--     v.pilha,
--     p_quantidade,
--     v.unid,
--     v_email,
--     p_idempotency_key,
--     v_novo_saldo
--   );
--
--   RETURN v_novo_saldo;
-- END;
-- $$;
--
-- COMMENT ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid) IS
--   'Baixa manual transacional e idempotente: reutiliza o saldo_resultante quando a chave já foi processada.';
--
-- REVOKE ALL ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid)
--   FROM PUBLIC, anon, authenticated, service_role;
-- GRANT EXECUTE ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid)
--   TO authenticated;
-- NOTIFY pgrst, 'reload schema';
-- COMMIT;
