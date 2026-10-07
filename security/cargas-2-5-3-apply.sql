-- Estoque Fácil — Sprint 2.5.3
-- RPC transacional para confirmar uma carga com uma NF e vários itens.
-- As verificações finais precisam passar para que o COMMIT seja executado.
--
-- A RPC usa cargas_nfs.nf como trava global compartilhada com a baixa QR.
-- Não insere em baixas_qr e não altera o trigger de NF global.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Verificações ANTES das alterações
-- ---------------------------------------------------------------------------

-- Estado estrutural esperado após 2.4.1, 2.5.1 e 2.5.2.
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'cargas' AND column_name IN (
      'id', 'codigo', 'data_hora', 'quem_leva', 'usuario',
      'idempotency_key', 'estornada'
    ))
    OR
    (table_name = 'cargas_nfs' AND column_name IN (
      'nf', 'carga_id', 'origem', 'ordem_id', 'filial', 'serie'
    ))
    OR
    (table_name = 'estoque' AND column_name IN (
      'id', 'qtd', 'produto', 'empresa', 'lote', 'pilha',
      'unid', 'armazem', 'validade'
    ))
    OR
    (table_name = 'historico_saidas' AND column_name IN (
      'id', 'carga_id', 'produto', 'lote', 'qtd', 'unid',
      'armazem', 'validade', 'idempotency_key', 'saldo_resultante'
    ))
  )
ORDER BY table_name, ordinal_position;

-- Chaves usadas para impedir repetição da carga, da NF e das baixas dos itens.
SELECT conrelid::regclass AS tabela, conname, contype,
       pg_catalog.pg_get_constraintdef(oid) AS definicao
FROM pg_catalog.pg_constraint
WHERE (conrelid = 'public.cargas'::regclass
       AND conname = 'cargas_idempotency_key_key')
   OR (conrelid = 'public.cargas_nfs'::regclass
       AND conname = 'cargas_nfs_pkey');

SELECT tablename, indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'historico_saidas'
  AND indexname IN (
    'idx_historico_saidas_idempotency',
    'idx_historico_saidas_carga'
  )
ORDER BY indexname;

-- A RPC de baixa 2.5.2 é usada para aplicar locks, saldo e snapshots.
SELECT
  p.oid::regprocedure AS assinatura,
  pg_catalog.pg_get_function_arguments(p.oid) AS argumentos,
  p.prosecdef AS security_definer,
  p.proconfig AS configuracao
FROM pg_catalog.pg_proc AS p
WHERE p.oid = pg_catalog.to_regprocedure(
  'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
);

-- O gatilho legado QR deve continuar habilitado.
SELECT t.tgname AS trigger_name, t.tgenabled AS enabled,
       c.relname AS table_name
FROM pg_catalog.pg_trigger AS t
JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'baixas_qr'
  AND t.tgname = 'trg_baixas_qr_nf_global'
  AND NOT t.tgisinternal;

-- A função nova não deve existir antes deste bloco.
SELECT p.oid::regprocedure AS sobrecarga_existente
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'ef_confirmar_baixa_carga';

-- Confirma os grants atuais do helper 2.5.2.
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
  ) AS service_role_execute;

DO $$
DECLARE
  v_overload_count integer;
BEGIN
  IF pg_catalog.to_regclass('public.cargas') IS NULL
     OR pg_catalog.to_regclass('public.cargas_nfs') IS NULL
     OR pg_catalog.to_regclass('public.estoque') IS NULL
     OR pg_catalog.to_regclass('public.historico_saidas') IS NULL
     OR pg_catalog.to_regclass('public.baixas_qr') IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: cargas, cargas_nfs, estoque, historico_saidas ou baixas_qr.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('cargas', 'id', 'bigint'),
      ('cargas', 'codigo', 'text'),
      ('cargas', 'data_hora', 'timestamp with time zone'),
      ('cargas', 'quem_leva', 'text'),
      ('cargas', 'usuario', 'text'),
      ('cargas', 'idempotency_key', 'uuid'),
      ('cargas', 'estornada', 'boolean'),
      ('cargas_nfs', 'nf', 'text'),
      ('cargas_nfs', 'carga_id', 'bigint'),
      ('cargas_nfs', 'origem', 'text'),
      ('cargas_nfs', 'ordem_id', NULL),
      ('cargas_nfs', 'filial', 'text'),
      ('cargas_nfs', 'serie', 'text'),
      ('estoque', 'id', NULL),
      ('estoque', 'qtd', NULL),
      ('estoque', 'produto', NULL),
      ('estoque', 'empresa', NULL),
      ('estoque', 'lote', NULL),
      ('estoque', 'pilha', NULL),
      ('estoque', 'unid', NULL),
      ('estoque', 'armazem', NULL),
      ('estoque', 'validade', NULL),
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
      ('historico_saidas', 'saldo_resultante', 'numeric')
    ) AS req(table_name, column_name, data_type)
    LEFT JOIN information_schema.columns AS c
      ON c.table_schema = 'public'
     AND c.table_name = req.table_name
     AND c.column_name = req.column_name
    WHERE c.column_name IS NULL
       OR (req.data_type IS NOT NULL AND c.data_type <> req.data_type)
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito inválido: alguma coluna/tipo necessário para 2.5.3 não confere.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.cargas'::regclass
      AND conname = 'cargas_idempotency_key_key'
      AND contype = 'u'
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: UNIQUE em cargas.idempotency_key.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.cargas_nfs'::regclass
      AND conname = 'cargas_nfs_pkey'
      AND contype = 'p'
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: PRIMARY KEY global em cargas_nfs.nf.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'historico_saidas'
      AND indexname = 'idx_historico_saidas_idempotency'
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: índice idempotente de historico_saidas.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.historico_saidas'::regclass
      AND confrelid = 'public.cargas'::regclass
      AND conname = 'historico_saidas_carga_id_fkey'
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'historico_saidas'
      AND indexname = 'idx_historico_saidas_carga'
  ) THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: FK/índice de historico_saidas.carga_id.';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
     ) IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: ef_confirmar_baixa_manual(bigint, integer, uuid, bigint).';
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
      'Grants inesperados no helper 2.5.2.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS t
    JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'baixas_qr'
      AND t.tgname = 'trg_baixas_qr_nf_global'
      AND NOT t.tgisinternal
      AND t.tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION
      'O trigger trg_baixas_qr_nf_global precisa continuar habilitado.';
  END IF;

  SELECT count(*)
  INTO v_overload_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_confirmar_baixa_carga';

  IF v_overload_count <> 0 THEN
    RAISE EXCEPTION
      'A função ef_confirmar_baixa_carga já existe; revise antes de criar outra versão.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. RPC transacional de baixa de carga
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ef_confirmar_baixa_carga(
  p_codigo text,
  p_data_hora timestamptz,
  p_quem_leva text,
  p_nf text,
  p_origem text,
  p_serie text,
  p_filial text,
  p_itens jsonb,
  p_idempotency_key uuid
)
RETURNS TABLE (
  carga_id bigint,
  nf text,
  saldo_total numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_email text;
  v_codigo text;
  v_quem_leva text;
  v_nf text;
  v_origem text;
  v_carga_id bigint;
  v_existing_nf text;
  v_nf_count bigint;
  v_history_count bigint;
  v_saldo_count bigint;
  v_saldo_total numeric := 0;
  v_item jsonb;
  v_item_index bigint;
  v_id_text text;
  v_quantidade_text text;
  v_item_id bigint;
  v_quantidade integer;
  v_ids bigint[] := ARRAY[]::bigint[];
  v_item_idempotency_key uuid;
  v_item_saldo numeric;
  v_expected_failure boolean := false;
  v_duplicate_rejected boolean := false;
  v_error_message text;
BEGIN
  v_email := auth.jwt() ->> 'email';

  IF auth.uid() IS NULL
     OR v_email IS DISTINCT FROM 'balancacoperacel1@gmail.com' THEN
    RAISE EXCEPTION 'Acesso administrativo obrigatório.';
  END IF;

  IF p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'Informe uma chave de idempotência para a carga.';
  END IF;

  -- O advisory lock serializa duas tentativas concorrentes da mesma carga.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_idempotency_key::text)
  );

  -- Idempotência real: a segunda chamada retorna o resultado persistido e
  -- não valida/reprocessa o novo payload nem baixa estoque novamente.
  SELECT c.id
  INTO v_carga_id
  FROM public.cargas AS c
  WHERE c.idempotency_key = p_idempotency_key;

  IF FOUND THEN
    SELECT count(*)
    INTO v_nf_count
    FROM public.cargas_nfs AS cn
    WHERE cn.carga_id = v_carga_id;

    IF v_nf_count <> 1 THEN
      RAISE EXCEPTION
        'Carga existente % tem % NFs; esperado exatamente uma para idempotência.',
        v_carga_id, v_nf_count;
    END IF;

    SELECT
      cn.nf,
      count(hs.id),
      count(hs.saldo_resultante),
      sum(hs.saldo_resultante)
    INTO
      v_existing_nf,
      v_history_count,
      v_saldo_count,
      v_saldo_total
    FROM public.cargas_nfs AS cn
    LEFT JOIN public.historico_saidas AS hs
      ON hs.carga_id = cn.carga_id
    WHERE cn.carga_id = v_carga_id
    GROUP BY cn.nf;

    IF NOT FOUND OR v_history_count = 0 OR v_saldo_count <> v_history_count THEN
      RAISE EXCEPTION
        'Carga existente % não tem histórico completo para retornar idempotência.',
        v_carga_id;
    END IF;

    RETURN QUERY SELECT v_carga_id, v_existing_nf, v_saldo_total;
    RETURN;
  END IF;

  v_codigo := nullif(pg_catalog.btrim(p_codigo), '');
  v_quem_leva := nullif(pg_catalog.btrim(p_quem_leva), '');
  v_nf := nullif(pg_catalog.btrim(p_nf), '');
  v_origem := pg_catalog.lower(nullif(pg_catalog.btrim(p_origem), ''));

  IF v_codigo IS NULL THEN
    RAISE EXCEPTION 'Informe o código da carga.';
  END IF;

  IF p_data_hora IS NULL THEN
    RAISE EXCEPTION 'Informe a data e hora da carga.';
  END IF;

  IF v_quem_leva IS NULL THEN
    RAISE EXCEPTION 'Informe quem está levando a carga.';
  END IF;

  IF v_nf IS NULL THEN
    RAISE EXCEPTION 'Informe uma NF válida.';
  END IF;

  IF v_origem IS NULL OR v_origem NOT IN ('carga', 'qr', 'legado') THEN
    RAISE EXCEPTION
      'Origem da NF inválida; valores aceitos: carga, qr ou legado.';
  END IF;

  IF p_itens IS NULL OR pg_catalog.jsonb_typeof(p_itens) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'p_itens precisa ser um array JSON.';
  END IF;

  IF pg_catalog.jsonb_array_length(p_itens) = 0 THEN
    RAISE EXCEPTION 'Adicione ao menos um item à carga.';
  END IF;

  -- Valida todo o array antes de inserir carga/NF. IDs duplicados são
  -- rejeitados para que cada estoque tenha um saldo resultante inequívoco.
  FOR v_item, v_item_index IN
    SELECT item.value, item.ordinality
    FROM pg_catalog.jsonb_array_elements(p_itens)
      WITH ORDINALITY AS item(value, ordinality)
    ORDER BY item.ordinality
  LOOP
    IF pg_catalog.jsonb_typeof(v_item) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'Item % precisa ser um objeto JSON.', v_item_index;
    END IF;

    v_id_text := v_item ->> 'id';
    v_quantidade_text := v_item ->> 'quantidade';

    IF v_id_text IS NULL OR v_id_text !~ '^[0-9]{1,19}$' THEN
      RAISE EXCEPTION
        'Item %: id precisa ser um bigint positivo.', v_item_index;
    END IF;

    BEGIN
      v_item_id := v_id_text::bigint;
    EXCEPTION
      WHEN numeric_value_out_of_range THEN
        RAISE EXCEPTION
          'Item %: id excede o limite de bigint.', v_item_index;
    END;

    IF v_item_id < 1 THEN
      RAISE EXCEPTION 'Item %: id precisa ser positivo.', v_item_index;
    END IF;

    IF v_quantidade_text IS NULL
       OR v_quantidade_text !~ '^[0-9]{1,10}$'
       OR v_quantidade_text::numeric > 2147483647 THEN
      RAISE EXCEPTION
        'Item %: quantidade precisa ser um inteiro positivo válido.', v_item_index;
    END IF;

    v_quantidade := v_quantidade_text::integer;
    IF v_quantidade <= 0 THEN
      RAISE EXCEPTION
        'Item %: quantidade precisa ser maior que zero.', v_item_index;
    END IF;

    IF v_item_id = ANY(v_ids) THEN
      RAISE EXCEPTION
        'Pilha % aparece mais de uma vez em p_itens; consolide as quantidades.',
        v_item_id;
    END IF;
    v_ids := pg_catalog.array_append(v_ids, v_item_id);

    IF v_item ? 'produto'
       AND pg_catalog.jsonb_typeof(v_item -> 'produto') NOT IN ('string', 'null') THEN
      RAISE EXCEPTION 'Item %: produto opcional precisa ser texto.', v_item_index;
    END IF;

    IF v_item ? 'lote'
       AND pg_catalog.jsonb_typeof(v_item -> 'lote') NOT IN ('string', 'null') THEN
      RAISE EXCEPTION 'Item %: lote opcional precisa ser texto.', v_item_index;
    END IF;
  END LOOP;

  INSERT INTO public.cargas (
    codigo, data_hora, quem_leva, usuario, idempotency_key
  )
  VALUES (
    v_codigo,
    p_data_hora,
    v_quem_leva,
    v_email,
    p_idempotency_key
  )
  RETURNING id INTO v_carga_id;

  -- A PK em cargas_nfs é a trava global compartilhada com o trigger QR.
  -- Captura a corrida de duas origens e retorna mensagem clara ao cliente.
  BEGIN
    INSERT INTO public.cargas_nfs (
      nf, carga_id, origem, ordem_id, filial, serie
    )
    VALUES (
      v_nf,
      v_carga_id,
      v_origem,
      NULL,
      nullif(pg_catalog.btrim(p_filial), ''),
      nullif(pg_catalog.btrim(p_serie), '')
    );
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION
        'A NF % já foi registrada em uma baixa anterior.', v_nf
        USING ERRCODE = '23505';
  END;

  -- Cada item recebe uma chave estável derivada da chave da carga e de sua
  -- posição. A função 2.5.2 mantém locks, estoque, histórico e snapshots.
  FOR v_item, v_item_index IN
    SELECT item.value, item.ordinality
    FROM pg_catalog.jsonb_array_elements(p_itens)
      WITH ORDINALITY AS item(value, ordinality)
    ORDER BY item.ordinality
  LOOP
    v_item_id := (v_item ->> 'id')::bigint;
    v_quantidade := (v_item ->> 'quantidade')::integer;
    v_item_idempotency_key :=
      pg_catalog.md5(
        p_idempotency_key::text || ':carga-item:' || v_item_index::text
      )::uuid;

    v_item_saldo := public.ef_confirmar_baixa_manual(
      v_item_id,
      v_quantidade,
      v_item_idempotency_key,
      v_carga_id
    );

    -- A RPC 2.5.2 registra produto/lote do estoque. Os valores JSON opcionais
    -- só completam campos vazios; não sobrescrevem o cadastro do estoque.
    UPDATE public.historico_saidas AS hs
    SET
      produto = CASE
        WHEN nullif(pg_catalog.btrim(hs.produto), '') IS NULL
          THEN coalesce(
            nullif(pg_catalog.btrim(v_item ->> 'produto'), ''),
            hs.produto
          )
        ELSE hs.produto
      END,
      lote = CASE
        WHEN nullif(pg_catalog.btrim(hs.lote), '') IS NULL
          THEN coalesce(
            nullif(pg_catalog.btrim(v_item ->> 'lote'), ''),
            hs.lote
          )
        ELSE hs.lote
      END
    WHERE hs.idempotency_key = v_item_idempotency_key
      AND hs.carga_id = v_carga_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Não foi possível confirmar o histórico do item % na carga %.',
        v_item_id, v_carga_id;
    END IF;

    v_saldo_total := v_saldo_total + v_item_saldo;
  END LOOP;

  RETURN QUERY SELECT v_carga_id, v_nf, v_saldo_total;
END;
$$;

COMMENT ON FUNCTION public.ef_confirmar_baixa_carga(
  text, timestamptz, text, text, text, text, text, jsonb, uuid
) IS
  'Cria uma carga para uma NF, registra a NF globalmente e confirma todos os itens em uma transação, com idempotência e snapshots.';

REVOKE ALL ON FUNCTION public.ef_confirmar_baixa_carga(
  text, timestamptz, text, text, text, text, text, jsonb, uuid
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.ef_confirmar_baixa_carga(
  text, timestamptz, text, text, text, text, text, jsonb, uuid
) TO authenticated;

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
  'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)'
);

SELECT
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS anon_execute,
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS authenticated_execute,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS service_role_execute;

-- Guarda as verificações estruturais que precisam abortar caso a criação
-- não tenha produzido a assinatura/retorno/grants esperados.
DO $$
DECLARE
  v_function oid;
  v_arguments text;
  v_result text;
BEGIN
  v_function := pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)'
  )::oid;

  IF v_function IS NULL THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: assinatura ef_confirmar_baixa_carga esperada não existe.';
  END IF;

  v_arguments := pg_catalog.pg_get_function_arguments(v_function);
  IF v_arguments IS DISTINCT FROM
     'p_codigo text, p_data_hora timestamp with time zone, p_quem_leva text, p_nf text, p_origem text, p_serie text, p_filial text, p_itens jsonb, p_idempotency_key uuid' THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: argumentos inesperados: %', v_arguments;
  END IF;

  v_result := pg_catalog.pg_get_function_result(v_function);
  IF v_result IS DISTINCT FROM 'TABLE(carga_id bigint, nf text, saldo_total numeric)' THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: retorno inesperado: %', v_result;
  END IF;

  IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE')
     OR has_function_privilege('anon', v_function, 'EXECUTE')
     OR has_function_privilege('service_role', v_function, 'EXECUTE') THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: grants deveriam ser auth=true, anon=false, service_role=false.';
  END IF;
END;
$$;

-- RESUMO DAS VERIFICAÇÕES:
-- * As verificações anteriores conferem pré-requisitos, RPC auxiliar e proteção global de NF.
-- * As verificações posteriores conferem assinatura, retorno, SECURITY DEFINER e grants.
-- * A guarda final exige argumentos e retorno exatos, grants esperados e uma única sobrecarga pública.

-- ---------------------------------------------------------------------------
-- 3. Guarda final obrigatória antes do COMMIT
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_function oid;
  v_arguments text;
  v_result text;
  v_overload_count bigint;
BEGIN
  v_function := pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)'
  )::oid;

  IF v_function IS NULL THEN
    RAISE EXCEPTION
      'Guarda final falhou: assinatura esperada de ef_confirmar_baixa_carga não existe.';
  END IF;

  v_arguments := pg_catalog.pg_get_function_arguments(v_function);
  IF v_arguments IS DISTINCT FROM
     'p_codigo text, p_data_hora timestamp with time zone, p_quem_leva text, p_nf text, p_origem text, p_serie text, p_filial text, p_itens jsonb, p_idempotency_key uuid' THEN
    RAISE EXCEPTION
      'Guarda final falhou: argumentos inesperados: %', v_arguments;
  END IF;

  v_result := pg_catalog.pg_get_function_result(v_function);
  IF v_result IS DISTINCT FROM 'TABLE(carga_id bigint, nf text, saldo_total numeric)' THEN
    RAISE EXCEPTION
      'Guarda final falhou: retorno inesperado: %', v_result;
  END IF;

  IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE')
     OR has_function_privilege('anon', v_function, 'EXECUTE')
     OR has_function_privilege('service_role', v_function, 'EXECUTE') THEN
    RAISE EXCEPTION
      'Guarda final falhou: grants deveriam ser authenticated=true, anon=false, service_role=false.';
  END IF;

  SELECT count(*)
  INTO v_overload_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_confirmar_baixa_carga'
    AND p.prokind = 'f';

  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION
      'Guarda final falhou: esperada exatamente 1 função pública ef_confirmar_baixa_carga; encontradas %.',
      v_overload_count;
  END IF;
END;
$$;

COMMIT;

-- ---------------------------------------------------------------------------
-- Rollback manual caso esta função seja aplicada futuramente
-- ---------------------------------------------------------------------------
-- Só execute fora do ROLLBACK de teste, se for necessário remover a RPC.
-- BEGIN;
-- DROP FUNCTION IF EXISTS public.ef_confirmar_baixa_carga(
--   text, timestamptz, text, text, text, text, text, jsonb, uuid
-- );
-- NOTIFY pgrst, 'reload schema';
-- COMMIT;
