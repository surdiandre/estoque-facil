-- Estoque Fácil — Sprint 2.5.4
-- RPC atômica para estornar uma carga e restaurar o estoque.
-- As saídas originais permanecem em historico_saidas; cada reposição também
-- gera uma entrada auditável em historico_entradas.
-- Este arquivo é de validação e termina em ROLLBACK.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Verificações ANTES das alterações
-- ---------------------------------------------------------------------------

-- Estrutura necessária em cargas, estoque, históricos e vínculos.
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'cargas' AND column_name IN (
      'id', 'codigo', 'estornada', 'estornada_em', 'estornada_por',
      'motivo_estorno'
    ))
    OR
    (table_name = 'estoque' AND column_name IN (
      'id', 'produto', 'empresa', 'lote', 'pilha', 'qtd', 'unid',
      'validade', 'armazem'
    ))
    OR
    (table_name = 'historico_saidas' AND column_name IN (
      'id', 'data', 'produto', 'empresa', 'lote', 'pilha', 'qtd',
      'usuario', 'carga_id', 'unid', 'armazem', 'validade',
      'idempotency_key', 'saldo_resultante'
    ))
    OR
    (table_name = 'historico_entradas' AND column_name IN (
      'data', 'produto', 'empresa', 'lote', 'pilha', 'qtd', 'unid',
      'usuario', 'referencia', 'idempotency_key', 'saldo_resultante'
    ))
  )
ORDER BY table_name, ordinal_position;

-- A FK e o índice de carga devem existir para localizar/serializar as saídas.
SELECT
  c.conname,
  c.contype,
  pg_catalog.pg_get_constraintdef(c.oid) AS definicao
FROM pg_catalog.pg_constraint AS c
WHERE c.conrelid = pg_catalog.to_regclass('public.historico_saidas')
  AND c.confrelid = pg_catalog.to_regclass('public.cargas')
  AND c.conname = 'historico_saidas_carga_id_fkey';

SELECT indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'historico_saidas'
  AND indexname = 'idx_historico_saidas_carga';

-- RPCs usadas pelos sprints anteriores.
SELECT p.oid::regprocedure AS assinatura,
       pg_catalog.pg_get_function_arguments(p.oid) AS argumentos,
       p.prosecdef AS security_definer,
       p.proconfig AS configuracao
FROM pg_catalog.pg_proc AS p
WHERE p.oid IN (
  pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
  ),
  pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)'
  )
)
ORDER BY p.proname;

-- Grants atuais das RPCs anteriores: authenticated=true, anon/service_role=false.
SELECT
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
    'EXECUTE'
  ) AS manual_authenticated_execute,
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
    'EXECUTE'
  ) AS manual_anon_execute,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
    'EXECUTE'
  ) AS manual_service_role_execute,
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS carga_authenticated_execute,
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS carga_anon_execute,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS carga_service_role_execute;

-- Guardas estruturais: falha cedo se o banco não estiver no estado esperado.
DO $$
DECLARE
  v_invalid_column boolean;
  v_function_count integer;
BEGIN
  IF pg_catalog.to_regclass('public.cargas') IS NULL
     OR pg_catalog.to_regclass('public.estoque') IS NULL
     OR pg_catalog.to_regclass('public.historico_saidas') IS NULL
     OR pg_catalog.to_regclass('public.historico_entradas') IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: cargas, estoque, historico_saidas ou historico_entradas não existe.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('cargas', 'id', 'bigint'),
      ('cargas', 'codigo', 'text'),
      ('cargas', 'estornada', 'boolean'),
      ('cargas', 'estornada_em', 'timestamp with time zone'),
      ('cargas', 'estornada_por', 'text'),
      ('cargas', 'motivo_estorno', 'text'),
      ('estoque', 'id', NULL),
      ('estoque', 'produto', NULL),
      ('estoque', 'empresa', NULL),
      ('estoque', 'lote', NULL),
      ('estoque', 'pilha', NULL),
      ('estoque', 'qtd', NULL),
      ('estoque', 'unid', 'text'),
      ('estoque', 'validade', 'date'),
      ('estoque', 'armazem', 'integer'),
      ('historico_saidas', 'id', NULL),
      ('historico_saidas', 'data', NULL),
      ('historico_saidas', 'produto', NULL),
      ('historico_saidas', 'empresa', NULL),
      ('historico_saidas', 'lote', NULL),
      ('historico_saidas', 'pilha', NULL),
      ('historico_saidas', 'qtd', NULL),
      ('historico_saidas', 'usuario', NULL),
      ('historico_saidas', 'carga_id', 'bigint'),
      ('historico_saidas', 'unid', 'text'),
      ('historico_saidas', 'armazem', 'integer'),
      ('historico_saidas', 'validade', 'date'),
      ('historico_saidas', 'idempotency_key', 'uuid'),
      ('historico_saidas', 'saldo_resultante', 'numeric'),
      ('historico_entradas', 'data', NULL),
      ('historico_entradas', 'produto', NULL),
      ('historico_entradas', 'empresa', NULL),
      ('historico_entradas', 'lote', NULL),
      ('historico_entradas', 'pilha', NULL),
      ('historico_entradas', 'qtd', NULL),
      ('historico_entradas', 'unid', NULL),
      ('historico_entradas', 'usuario', NULL),
      ('historico_entradas', 'referencia', NULL),
      ('historico_entradas', 'idempotency_key', 'uuid'),
      ('historico_entradas', 'saldo_resultante', 'numeric')
    ) AS req(table_name, column_name, data_type)
    LEFT JOIN information_schema.columns AS c
      ON c.table_schema = 'public'
     AND c.table_name = req.table_name
     AND c.column_name = req.column_name
    WHERE c.column_name IS NULL
       OR (req.data_type IS NOT NULL AND c.data_type <> req.data_type)
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito inválido: faltam colunas ou tipos necessários para 2.5.4.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = pg_catalog.to_regclass('public.historico_saidas')
      AND c.confrelid = pg_catalog.to_regclass('public.cargas')
      AND c.conname = 'historico_saidas_carga_id_fkey'
      AND c.contype = 'f'
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: FK historico_saidas.carga_id -> cargas.id.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'historico_saidas'
      AND indexname = 'idx_historico_saidas_carga'
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: índice idx_historico_saidas_carga.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'historico_entradas'
      AND indexname = 'idx_historico_entradas_idempotency'
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: índice idempotente de historico_entradas.';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
     ) IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: ef_confirmar_baixa_manual(bigint, integer, uuid, bigint).';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)'
     ) IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: ef_confirmar_baixa_carga(...) do Sprint 2.5.3.';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
       'EXECUTE'
     ) OR has_function_privilege(
       'anon',
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
       'EXECUTE'
     ) OR has_function_privilege(
       'service_role',
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION
      'Grants inesperados na RPC ef_confirmar_baixa_manual.';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
       'EXECUTE'
     ) OR has_function_privilege(
       'anon',
       'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
       'EXECUTE'
     ) OR has_function_privilege(
       'service_role',
       'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION
      'Grants inesperados na RPC ef_confirmar_baixa_carga.';
  END IF;

  SELECT count(*)
  INTO v_function_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_estornar_carga';

  IF v_function_count <> 0 THEN
    RAISE EXCEPTION
      'A função ef_estornar_carga já existe; revise antes de criar outra versão.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. RPC transacional de estorno de carga
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ef_estornar_carga(
  p_carga_id bigint,
  p_motivo text
)
RETURNS TABLE (
  carga_id bigint,
  itens_restaurados integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_email text;
  v_motivo text;
  v_carga public.cargas%rowtype;
  v_saida public.historico_saidas%rowtype;
  v_item_count bigint;
  v_itens_restaurados integer := 0;
  v_match_count bigint;
  v_stock_id bigint;
  v_new_stock_id bigint;
  v_new_saldo numeric;
  v_id_sequence text;
  v_entry_idempotency_key uuid;
BEGIN
  v_email := auth.jwt() ->> 'email';

  IF auth.uid() IS NULL
     OR v_email IS DISTINCT FROM 'balancacoperacel1@gmail.com' THEN
    RAISE EXCEPTION 'Acesso administrativo obrigatório.';
  END IF;

  IF p_carga_id IS NULL OR p_carga_id < 1 THEN
    RAISE EXCEPTION 'Carga % não encontrada.', p_carga_id;
  END IF;

  IF p_motivo IS NULL OR nullif(pg_catalog.btrim(p_motivo), '') IS NULL THEN
    RAISE EXCEPTION 'Informe o motivo do estorno.';
  END IF;
  v_motivo := pg_catalog.btrim(p_motivo);

  -- Serializa chamadas simultâneas de estorno para a mesma carga.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('ef_estornar_carga:' || p_carga_id::text)
  );

  SELECT c.*
  INTO v_carga
  FROM public.cargas AS c
  WHERE c.id = p_carga_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Carga % não encontrada.', p_carga_id;
  END IF;

  IF v_carga.estornada THEN
    RAISE EXCEPTION
      'Carga % já foi estornada em %.',
      p_carga_id, v_carga.estornada_em;
  END IF;

  SELECT count(*)
  INTO v_item_count
  FROM public.historico_saidas AS hs
  WHERE hs.carga_id = p_carga_id;

  IF v_item_count = 0 THEN
    RAISE EXCEPTION
      'Carga % não possui itens em historico_saidas; estorno cancelado.',
      p_carga_id;
  END IF;

  -- historico_saidas não armazena o antigo estoque.id. O vínculo seguro é
  -- reconstituído pelo conjunto de atributos da pilha. Este lock curto impede
  -- alterações concorrentes durante a busca e eventual recriação com max(id)+1.
  LOCK TABLE public.estoque IN SHARE ROW EXCLUSIVE MODE;

  v_id_sequence := pg_catalog.pg_get_serial_sequence(
    'public.estoque',
    'id'
  );

  FOR v_saida IN
    SELECT hs.*
    FROM public.historico_saidas AS hs
    WHERE hs.carga_id = p_carga_id
    ORDER BY hs.id
    FOR UPDATE OF hs
  LOOP
    IF v_saida.qtd IS NULL OR v_saida.qtd <= 0 THEN
      RAISE EXCEPTION
        'Histórico de saída % tem quantidade inválida; estorno cancelado.',
        v_saida.id;
    END IF;

    -- Produto + empresa + lote + pilha + snapshots identificam a pilha.
    SELECT count(*), min(e.id)
    INTO v_match_count, v_stock_id
    FROM public.estoque AS e
    WHERE e.produto IS NOT DISTINCT FROM v_saida.produto
      AND coalesce(e.empresa, '') =
          coalesce(v_saida.empresa, '')
      AND e.lote IS NOT DISTINCT FROM v_saida.lote
      AND e.pilha IS NOT DISTINCT FROM v_saida.pilha
      AND e.validade IS NOT DISTINCT FROM v_saida.validade
      AND e.armazem IS NOT DISTINCT FROM v_saida.armazem
      AND e.unid IS NOT DISTINCT FROM v_saida.unid;

    IF v_match_count > 1 THEN
      RAISE EXCEPTION
        'Estorno ambíguo: % pilhas correspondem ao histórico % da carga %.',
        v_match_count, v_saida.id, p_carga_id;
    END IF;

    IF v_match_count = 1 THEN
      UPDATE public.estoque AS e
      SET qtd = coalesce(e.qtd, 0) + v_saida.qtd
      WHERE e.id = v_stock_id
      RETURNING e.qtd INTO v_new_saldo;

      IF NOT FOUND THEN
        RAISE EXCEPTION
          'A pilha do histórico % mudou durante o estorno da carga %.',
          v_saida.id, p_carga_id;
      END IF;
      v_new_stock_id := v_stock_id;
    ELSE
      -- Se id não usa sequence/identity, max(id)+1 é calculado sob o lock
      -- da tabela, sem competir com novos lançamentos do estoque.
      IF v_id_sequence IS NULL THEN
        SELECT coalesce(pg_catalog.max(e.id), 0) + 1
        INTO v_new_stock_id
        FROM public.estoque AS e;

        INSERT INTO public.estoque (
          id, produto, empresa, lote, pilha, qtd, unid, validade, armazem
        )
        VALUES (
          v_new_stock_id,
          v_saida.produto,
          nullif(v_saida.empresa, ''),
          v_saida.lote,
          v_saida.pilha,
          v_saida.qtd,
          v_saida.unid,
          v_saida.validade,
          v_saida.armazem
        )
        RETURNING qtd INTO v_new_saldo;
      ELSE
        INSERT INTO public.estoque (
          produto, empresa, lote, pilha, qtd, unid, validade, armazem
        )
        VALUES (
          v_saida.produto,
          nullif(v_saida.empresa, ''),
          v_saida.lote,
          v_saida.pilha,
          v_saida.qtd,
          v_saida.unid,
          v_saida.validade,
          v_saida.armazem
        )
        RETURNING id, qtd INTO v_new_stock_id, v_new_saldo;
      END IF;
    END IF;

    -- Registra a reposição no livro de entradas, com chave determinística
    -- por saída para impedir duplicação do lançamento de auditoria.
    v_entry_idempotency_key :=
      pg_catalog.md5(
        'ef_estornar_carga:' || p_carga_id::text || ':' || v_saida.id::text
      )::uuid;

    INSERT INTO public.historico_entradas (
      data, produto, empresa, lote, pilha, qtd, unid, usuario,
      referencia, idempotency_key, saldo_resultante
    )
    VALUES (
      (now() AT TIME ZONE 'America/Sao_Paulo')::date,
      v_saida.produto,
      nullif(v_saida.empresa, ''),
      v_saida.lote,
      v_saida.pilha,
      v_saida.qtd,
      v_saida.unid,
      v_email,
      'Estorno carga ' || v_carga.codigo,
      v_entry_idempotency_key,
      v_new_saldo
    );

    v_itens_restaurados := v_itens_restaurados + 1;
  END LOOP;

  UPDATE public.cargas AS c
  SET estornada = true,
      estornada_em = now(),
      estornada_por = v_email,
      motivo_estorno = v_motivo
  WHERE c.id = p_carga_id;

  RETURN QUERY
  SELECT p_carga_id, v_itens_restaurados;
END;
$$;

COMMENT ON FUNCTION public.ef_estornar_carga(bigint, text) IS
  'Estorna uma carga ativa, restaura suas pilhas pelos snapshots de historico_saidas, registra entradas de auditoria e rejeita chamadas repetidas.';

REVOKE ALL ON FUNCTION public.ef_estornar_carga(bigint, text)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.ef_estornar_carga(bigint, text)
  TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 2. Verificações DEPOIS das alterações
-- ---------------------------------------------------------------------------

SELECT
  p.oid::regprocedure AS assinatura,
  pg_catalog.pg_get_function_arguments(p.oid) AS argumentos,
  pg_catalog.pg_get_function_result(p.oid) AS retorno,
  p.prosecdef AS security_definer,
  p.proconfig AS configuracao
FROM pg_catalog.pg_proc AS p
WHERE p.oid = pg_catalog.to_regprocedure(
  'public.ef_estornar_carga(bigint, text)'
);

SELECT
  has_function_privilege(
    'authenticated',
    'public.ef_estornar_carga(bigint, text)',
    'EXECUTE'
  ) AS authenticated_execute,
  has_function_privilege(
    'anon',
    'public.ef_estornar_carga(bigint, text)',
    'EXECUTE'
  ) AS anon_execute,
  has_function_privilege(
    'service_role',
    'public.ef_estornar_carga(bigint, text)',
    'EXECUTE'
  ) AS service_role_execute;

DO $$
DECLARE
  v_function oid;
  v_arguments text;
  v_result text;
  v_overload_count bigint;
BEGIN
  v_function := pg_catalog.to_regprocedure(
    'public.ef_estornar_carga(bigint, text)'
  )::oid;

  IF v_function IS NULL THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: ef_estornar_carga(bigint, text) não existe.';
  END IF;

  v_arguments := pg_catalog.pg_get_function_arguments(v_function);
  IF v_arguments IS DISTINCT FROM 'p_carga_id bigint, p_motivo text' THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: argumentos inesperados: %', v_arguments;
  END IF;

  v_result := pg_catalog.pg_get_function_result(v_function);
  IF v_result IS DISTINCT FROM
     'TABLE(carga_id bigint, itens_restaurados integer)' THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: retorno inesperado: %', v_result;
  END IF;

  IF NOT pg_catalog.has_function_privilege(
       'authenticated', v_function, 'EXECUTE'
     ) OR pg_catalog.has_function_privilege(
       'anon', v_function, 'EXECUTE'
     ) OR pg_catalog.has_function_privilege(
       'service_role', v_function, 'EXECUTE'
     ) THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: grants deveriam ser authenticated=true, anon=false, service_role=false.';
  END IF;

  SELECT count(*)
  INTO v_overload_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_estornar_carga'
    AND p.prokind = 'f';

  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: esperada exatamente 1 sobrecarga pública; encontradas %.',
      v_overload_count;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Teste transacional completo
-- ---------------------------------------------------------------------------

-- O teste cria uma carga sintética com duas saídas:
--   (a) uma pilha que continua no estoque deve receber qtd de volta;
--   (b) uma pilha deletada deve ser recriada com os snapshots do histórico.
-- A exceção sentinela desfaz carga, estoque e históricos do teste.
DO $$
DECLARE
  v_stock_a public.estoque%rowtype;
  v_stock_b public.estoque%rowtype;
  v_restored_a public.estoque%rowtype;
  v_restored_b public.estoque%rowtype;
  v_carga_id bigint;
  v_carga_key uuid;
  v_codigo text;
  v_saida_key_a uuid;
  v_saida_key_b uuid;
  v_saida_id_a bigint;
  v_saida_id_b bigint;
  v_entry_key_a uuid;
  v_entry_key_b uuid;
  v_result record;
  v_retry_result record;
  v_missing_result record;
  v_nonexistent_id bigint := 9223372036854775807;
  v_test_validade date := DATE '2099-12-31';
  v_current_saldo numeric;
  v_recreated_stock_id bigint;
  v_estornada boolean;
  v_estornada_por text;
  v_motivo_estorno text;
  v_match_count bigint;
  v_entry_count bigint;
  v_error_message text;
  v_retry_rejected boolean := false;
  v_missing_rejected boolean := false;
  v_email text := 'balancacoperacel1@gmail.com';
BEGIN
  BEGIN
    PERFORM pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', '00000000-0000-4000-8000-000000000254',
        'email', v_email,
        'role', 'authenticated'
      )::text,
      true
    );
    PERFORM pg_catalog.set_config(
      'request.jwt.claim.sub',
      '00000000-0000-4000-8000-000000000254',
      true
    );
    PERFORM pg_catalog.set_config(
      'request.jwt.claim.email',
      v_email,
      true
    );

    SELECT e.*
    INTO v_stock_a
    FROM public.estoque AS e
    WHERE e.qtd >= 2
    ORDER BY e.id
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Teste não executado: precisa haver uma pilha com saldo >= 2.';
    END IF;

    SELECT e.*
    INTO v_stock_b
    FROM public.estoque AS e
    WHERE e.qtd > 0
      AND e.id <> v_stock_a.id
      AND e.unid IS NOT NULL
      AND e.armazem IS NOT NULL
      AND ROW(
        e.produto, e.empresa, e.lote, e.pilha,
        e.validade, e.armazem, e.unid
      ) IS DISTINCT FROM ROW(
        v_stock_a.produto, v_stock_a.empresa, v_stock_a.lote, v_stock_a.pilha,
        v_stock_a.validade, v_stock_a.armazem, v_stock_a.unid
      )
    ORDER BY e.id
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Teste não executado: precisa haver uma segunda pilha distinta com saldo positivo.';
    END IF;

    v_carga_key :=
      pg_catalog.md5(
        pg_catalog.clock_timestamp()::text || pg_catalog.random()::text
      )::uuid;
    v_saida_key_a :=
      pg_catalog.md5(
        pg_catalog.clock_timestamp()::text || pg_catalog.random()::text
      )::uuid;
    v_saida_key_b :=
      pg_catalog.md5(
        pg_catalog.clock_timestamp()::text || pg_catalog.random()::text
      )::uuid;
    v_codigo := 'EF254-TEST-' || v_carga_key::text;

    INSERT INTO public.cargas (
      codigo, data_hora, quem_leva, usuario, idempotency_key, estornada
    )
    VALUES (
      v_codigo,
      pg_catalog.clock_timestamp(),
      'TESTE 2.5.4',
      v_email,
      v_carga_key,
      false
    )
    RETURNING id INTO v_carga_id;

    -- Item A: permaneceu uma pilha com saldo reduzido.
    UPDATE public.estoque AS e
    SET qtd = v_stock_a.qtd - 1
    WHERE e.id = v_stock_a.id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Teste falhou: não foi possível preparar a pilha A.';
    END IF;

    INSERT INTO public.historico_saidas (
      data, produto, empresa, lote, pilha, qtd, unid, usuario,
      idempotency_key, saldo_resultante, carga_id, armazem, validade
    )
    VALUES (
      (now() AT TIME ZONE 'America/Sao_Paulo')::date,
      v_stock_a.produto,
      coalesce(v_stock_a.empresa, ''),
      v_stock_a.lote,
      v_stock_a.pilha,
      1,
      v_stock_a.unid,
      v_email,
      v_saida_key_a,
      v_stock_a.qtd - 1,
      v_carga_id,
      v_stock_a.armazem,
      v_stock_a.validade
    )
    RETURNING id INTO v_saida_id_a;

    -- Item B: simula baixa total/deleção. Unidade e validade exclusivas no
    -- fixture permitem verificar que a recriação copia os snapshots exatos.
    IF EXISTS (
      SELECT 1
      FROM public.estoque AS e
      WHERE e.produto IS NOT DISTINCT FROM v_stock_b.produto
        AND coalesce(e.empresa, '') =
            coalesce(v_stock_b.empresa, '')
        AND e.lote IS NOT DISTINCT FROM v_stock_b.lote
        AND e.pilha IS NOT DISTINCT FROM v_stock_b.pilha
        AND e.validade IS NOT DISTINCT FROM v_test_validade
        AND e.armazem IS NOT DISTINCT FROM v_stock_b.armazem
        AND e.unid IS NOT DISTINCT FROM v_stock_b.unid
    ) THEN
      RAISE EXCEPTION
        'Teste não executado: já existe pilha com os snapshots artificiais do teste.';
    END IF;

    INSERT INTO public.historico_saidas (
      data, produto, empresa, lote, pilha, qtd, unid, usuario,
      idempotency_key, saldo_resultante, carga_id, armazem, validade
    )
    VALUES (
      (now() AT TIME ZONE 'America/Sao_Paulo')::date,
      v_stock_b.produto,
      coalesce(v_stock_b.empresa, ''),
      v_stock_b.lote,
      v_stock_b.pilha,
      v_stock_b.qtd,
      v_stock_b.unid,
      v_email,
      v_saida_key_b,
      0,
      v_carga_id,
      v_stock_b.armazem,
      v_test_validade
    )
    RETURNING id INTO v_saida_id_b;

    DELETE FROM public.estoque AS e
    WHERE e.id = v_stock_b.id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Teste falhou: não foi possível simular a exclusão da pilha B.';
    END IF;

    -- (a) Estorno feliz com dois itens e retorno da quantidade restaurada.
    SELECT *
    INTO v_result
    FROM public.ef_estornar_carga(v_carga_id, 'Teste transacional Sprint 2.5.4');

    IF v_result.carga_id IS DISTINCT FROM v_carga_id
       OR v_result.itens_restaurados IS DISTINCT FROM 2 THEN
      RAISE EXCEPTION
        'Teste falhou: retorno deveria informar a carga e 2 itens restaurados.';
    END IF;

    SELECT e.*
    INTO v_restored_a
    FROM public.estoque AS e
    WHERE e.id = v_stock_a.id;

    IF NOT FOUND
       OR v_restored_a.qtd IS DISTINCT FROM v_stock_a.qtd
       OR v_restored_a.armazem IS DISTINCT FROM v_stock_a.armazem
       OR v_restored_a.validade IS DISTINCT FROM v_stock_a.validade
       OR v_restored_a.unid IS DISTINCT FROM v_stock_a.unid THEN
      RAISE EXCEPTION
        'Teste falhou: pilha A não recuperou saldo e snapshots originais.';
    END IF;

    SELECT count(*), min(e.id)
    INTO v_match_count, v_recreated_stock_id
    FROM public.estoque AS e
    WHERE e.produto IS NOT DISTINCT FROM v_stock_b.produto
      AND e.empresa IS NOT DISTINCT FROM
          nullif(v_stock_b.empresa, '')
      AND e.lote IS NOT DISTINCT FROM v_stock_b.lote
      AND e.pilha IS NOT DISTINCT FROM v_stock_b.pilha
      AND e.validade IS NOT DISTINCT FROM v_test_validade
      AND e.armazem IS NOT DISTINCT FROM v_stock_b.armazem
      AND e.unid IS NOT DISTINCT FROM v_stock_b.unid;

    IF v_match_count <> 1 THEN
      RAISE EXCEPTION
        'Teste falhou: a pilha B deveria ser recriada exatamente uma vez.';
    END IF;

    SELECT e.*
    INTO v_restored_b
    FROM public.estoque AS e
    WHERE e.id = v_recreated_stock_id;

    IF NOT FOUND
       OR v_restored_b.qtd IS DISTINCT FROM v_stock_b.qtd
       OR v_restored_b.armazem IS DISTINCT FROM v_stock_b.armazem
       OR v_restored_b.validade IS DISTINCT FROM v_test_validade
       OR v_restored_b.unid IS DISTINCT FROM v_stock_b.unid THEN
      RAISE EXCEPTION
        'Teste falhou: pilha B não foi recriada com quantidade/snapshots corretos.';
    END IF;

    SELECT c.estornada, c.estornada_por, c.motivo_estorno
    INTO v_estornada, v_estornada_por, v_motivo_estorno
    FROM public.cargas AS c
    WHERE c.id = v_carga_id;

    IF NOT FOUND
       OR v_estornada IS DISTINCT FROM true
       OR v_estornada_por IS DISTINCT FROM v_email
       OR v_motivo_estorno IS DISTINCT FROM 'Teste transacional Sprint 2.5.4' THEN
      RAISE EXCEPTION 'Teste falhou: cabeçalho da carga não foi marcado estornado.';
    END IF;

    v_entry_key_a :=
      pg_catalog.md5(
        'ef_estornar_carga:' || v_carga_id::text || ':' || v_saida_id_a::text
      )::uuid;
    v_entry_key_b :=
      pg_catalog.md5(
        'ef_estornar_carga:' || v_carga_id::text || ':' || v_saida_id_b::text
      )::uuid;

    SELECT count(*)
    INTO v_entry_count
    FROM public.historico_entradas AS he
    WHERE he.idempotency_key IN (v_entry_key_a, v_entry_key_b)
      AND he.referencia = 'Estorno carga ' || v_codigo;

    IF v_entry_count <> 2 THEN
      RAISE EXCEPTION
        'Teste falhou: esperado um registro de entrada por item estornado.';
    END IF;

    -- (b) Uma segunda chamada deve falhar claramente e não duplicar entradas.
    BEGIN
      SELECT *
      INTO v_retry_result
      FROM public.ef_estornar_carga(v_carga_id, 'Segunda tentativa de teste');
    EXCEPTION
      WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
        IF pg_catalog.strpos(v_error_message, 'já foi estornada em') = 0 THEN
          RAISE;
        END IF;
        v_retry_rejected := true;
    END;

    IF NOT v_retry_rejected THEN
      RAISE EXCEPTION 'Teste falhou: segunda chamada de estorno foi aceita.';
    END IF;

    SELECT count(*)
    INTO v_entry_count
    FROM public.historico_entradas AS he
    WHERE he.idempotency_key IN (v_entry_key_a, v_entry_key_b);

    IF v_entry_count <> 2 THEN
      RAISE EXCEPTION 'Teste falhou: repetição duplicou histórico de entradas.';
    END IF;

    SELECT e.qtd INTO v_current_saldo
    FROM public.estoque AS e
    WHERE e.id = v_stock_a.id;
    IF NOT FOUND OR v_current_saldo IS DISTINCT FROM v_stock_a.qtd THEN
      RAISE EXCEPTION 'Teste falhou: repetição alterou novamente o saldo da pilha A.';
    END IF;

    SELECT e.qtd INTO v_current_saldo
    FROM public.estoque AS e
    WHERE e.id = v_recreated_stock_id;
    IF NOT FOUND OR v_current_saldo IS DISTINCT FROM v_stock_b.qtd THEN
      RAISE EXCEPTION 'Teste falhou: repetição alterou novamente o saldo da pilha B.';
    END IF;

    -- (c) Uma carga inexistente deve retornar a mensagem de não encontrada.
    WHILE EXISTS (
      SELECT 1 FROM public.cargas AS c WHERE c.id = v_nonexistent_id
    ) LOOP
      v_nonexistent_id := v_nonexistent_id - 1;
    END LOOP;

    BEGIN
      SELECT *
      INTO v_missing_result
      FROM public.ef_estornar_carga(v_nonexistent_id, 'Teste carga inexistente');
    EXCEPTION
      WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
        IF pg_catalog.strpos(v_error_message, 'não encontrada') = 0 THEN
          RAISE;
        END IF;
        v_missing_rejected := true;
    END;

    IF NOT v_missing_rejected THEN
      RAISE EXCEPTION 'Teste falhou: estorno de carga inexistente foi aceito.';
    END IF;

    RAISE EXCEPTION 'ROLLBACK DE TESTE' USING ERRCODE = 'ZX254';
  EXCEPTION
    WHEN SQLSTATE 'ZX254' THEN
      RAISE NOTICE
        'ROLLBACK DE TESTE: estornar_carga passou; dados de teste desfeitos.';
  END;
END;
$$;

-- RESULTADO ESPERADO:
-- * Antes: cargas, snapshots, FK/índice, histórico de entradas e RPCs 2.5.2/2.5.3 existem.
-- * Depois: função SECURITY DEFINER com argumentos p_carga_id/p_motivo e retorno tabular.
-- * Grants: authenticated_execute=true, anon_execute=false, service_role_execute=false.
-- * Teste: restauração em linha e recriação da pilha, snapshots, log de entradas,
--   rejeição de segunda chamada e de carga inexistente.
-- * NOTICE: "ROLLBACK DE TESTE: estornar_carga passou; dados de teste desfeitos."

ROLLBACK;

-- ---------------------------------------------------------------------------
-- Rollback manual caso esta função seja aplicada futuramente
-- ---------------------------------------------------------------------------
-- Execute apenas se for necessário remover a função já aplicada.
-- BEGIN;
-- DROP FUNCTION IF EXISTS public.ef_estornar_carga(bigint, text);
-- NOTIFY pgrst, 'reload schema';
-- COMMIT;
