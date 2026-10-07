-- Estoque Fácil — Sprint 2.5.5.1
-- Atualiza as RPCs de carga para aceitar múltiplas NFs e propaga a data/hora
-- da carga para historico_saidas.data (como date no fuso America/Sao_Paulo).
-- Este arquivo é exclusivamente de teste: a transação termina em ROLLBACK.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Verificações ANTES das alterações
-- ---------------------------------------------------------------------------

SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'cargas' AND column_name IN
      ('id', 'codigo', 'data_hora', 'quem_leva', 'usuario', 'idempotency_key', 'estornada'))
    OR
    (table_name = 'cargas_nfs' AND column_name IN
      ('nf', 'carga_id', 'origem', 'ordem_id', 'filial', 'serie'))
    OR
    (table_name = 'estoque' AND column_name IN
      ('id', 'qtd', 'produto', 'empresa', 'lote', 'pilha', 'unid', 'armazem', 'validade'))
    OR
    (table_name = 'historico_saidas' AND column_name IN
      ('id', 'data', 'carga_id', 'produto', 'lote', 'qtd', 'unid',
       'armazem', 'validade', 'idempotency_key', 'saldo_resultante'))
  )
ORDER BY table_name, ordinal_position;

-- Assinaturas atuais que esta migração substitui.
SELECT
  p.oid::regprocedure AS assinatura,
  pg_catalog.pg_get_function_arguments(p.oid) AS argumentos,
  pg_catalog.pg_get_function_result(p.oid) AS retorno
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('ef_confirmar_baixa_manual', 'ef_confirmar_baixa_carga')
ORDER BY p.proname, p.oid::regprocedure::text;

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

DO $$
DECLARE
  v_manual_old oid;
  v_charge_old oid;
  v_charge_count integer;
BEGIN
  IF pg_catalog.to_regclass('public.cargas') IS NULL
     OR pg_catalog.to_regclass('public.cargas_nfs') IS NULL
     OR pg_catalog.to_regclass('public.estoque') IS NULL
     OR pg_catalog.to_regclass('public.historico_saidas') IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: cargas, cargas_nfs, estoque ou historico_saidas não existe.';
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
      ('cargas_nfs', 'nf', 'text'),
      ('cargas_nfs', 'carga_id', 'bigint'),
      ('cargas_nfs', 'origem', 'text'),
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
      ('historico_saidas', 'data', 'date'),
      ('historico_saidas', 'carga_id', 'bigint'),
      ('historico_saidas', 'produto', NULL),
      ('historico_saidas', 'lote', NULL),
      ('historico_saidas', 'qtd', NULL),
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
      'Pré-requisito inválido: colunas/tipos usados pelas RPCs não conferem.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.cargas_nfs'::regclass
      AND conname = 'cargas_nfs_pkey'
      AND contype = 'p'
  ) THEN
    RAISE EXCEPTION 'Pré-requisito ausente: PK global em cargas_nfs.nf.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.cargas'::regclass
      AND conname = 'cargas_idempotency_key_key'
      AND contype = 'u'
  ) THEN
    RAISE EXCEPTION 'Pré-requisito ausente: UNIQUE em cargas.idempotency_key.';
  END IF;

  v_manual_old := pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
  );
  IF v_manual_old IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: ef_confirmar_baixa_manual(bigint, integer, uuid, bigint).';
  END IF;

  IF pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamptz)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION
      'Estado inválido: a assinatura nova de ef_confirmar_baixa_manual já existe.';
  END IF;

  v_charge_old := pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, text, text, text, text, jsonb, uuid)'
  );
  IF v_charge_old IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: assinatura original 2.5.3 de ef_confirmar_baixa_carga.';
  END IF;

  SELECT count(*)
  INTO v_charge_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_confirmar_baixa_carga';
  IF v_charge_count <> 1 THEN
    RAISE EXCEPTION
      'Pré-requisito inválido: esperada uma assinatura de ef_confirmar_baixa_carga; encontradas %.',
      v_charge_count;
  END IF;

  IF NOT has_function_privilege('authenticated', v_manual_old, 'EXECUTE')
     OR has_function_privilege('anon', v_manual_old, 'EXECUTE')
     OR has_function_privilege('service_role', v_manual_old, 'EXECUTE') THEN
    RAISE EXCEPTION 'Grants atuais inesperados em ef_confirmar_baixa_manual.';
  END IF;

  IF NOT has_function_privilege('authenticated', v_charge_old, 'EXECUTE')
     OR has_function_privilege('anon', v_charge_old, 'EXECUTE')
     OR has_function_privilege('service_role', v_charge_old, 'EXECUTE') THEN
    RAISE EXCEPTION 'Grants atuais inesperados em ef_confirmar_baixa_carga.';
  END IF;
END;
$$;

-- Confirma explicitamente a assinatura antiga do helper 2.5.2 antes do DROP.
SELECT pg_catalog.pg_get_function_arguments(
  'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'::regprocedure
) AS assinatura_manual_antes;

-- ---------------------------------------------------------------------------
-- 1. Substituição das funções
-- ---------------------------------------------------------------------------

-- A assinatura antiga é removida para que chamadas PostgREST não encontrem
-- sobrecarga concorrente. As permissões serão reaplicadas abaixo.
DROP FUNCTION public.ef_confirmar_baixa_carga(
  text, timestamptz, text, text, text, text, text, jsonb, uuid
);
DROP FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint);

CREATE OR REPLACE FUNCTION public.ef_confirmar_baixa_manual(
  p_id bigint,
  p_quantidade integer,
  p_idempotency_key uuid DEFAULT NULL,
  p_carga_id bigint DEFAULT NULL,
  p_data_hora timestamptz DEFAULT NULL
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
    coalesce(
      (p_data_hora AT TIME ZONE 'America/Sao_Paulo')::date,
      (now() AT TIME ZONE 'America/Sao_Paulo')::date
    ),
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
  bigint, integer, uuid, bigint, timestamptz
) IS
  'Confirma baixa manual com idempotência, vínculo opcional à carga e data retroativa opcional.';

REVOKE ALL ON FUNCTION public.ef_confirmar_baixa_manual(
  bigint, integer, uuid, bigint, timestamptz
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.ef_confirmar_baixa_manual(
  bigint, integer, uuid, bigint, timestamptz
) TO authenticated;

CREATE OR REPLACE FUNCTION public.ef_confirmar_baixa_carga(
  p_codigo text,
  p_data_hora timestamptz,
  p_quem_leva text,
  p_nfs jsonb,
  p_origem text,
  p_serie text,
  p_filial text,
  p_itens jsonb,
  p_idempotency_key uuid
)
RETURNS TABLE (
  carga_id bigint,
  nfs text[],
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
  v_nf_index bigint;
  v_nfs text[] := ARRAY[]::text[];
  v_origem text;
  v_carga_id bigint;
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
    SELECT coalesce(
             pg_catalog.array_agg(cn.nf ORDER BY cn.nf),
             ARRAY[]::text[]
           )
    INTO v_nfs
    FROM public.cargas_nfs AS cn
    WHERE cn.carga_id = v_carga_id;

    IF pg_catalog.cardinality(v_nfs) < 1 THEN
      RAISE EXCEPTION
        'Carga existente % não tem NFs registradas para retornar idempotência.',
        v_carga_id;
    END IF;

    SELECT
      count(hs.id),
      count(hs.saldo_resultante),
      sum(hs.saldo_resultante)
    INTO
      v_history_count,
      v_saldo_count,
      v_saldo_total
    FROM public.historico_saidas AS hs
    WHERE hs.carga_id = v_carga_id;

    IF v_history_count = 0 OR v_saldo_count <> v_history_count THEN
      RAISE EXCEPTION
        'Carga existente % não tem histórico completo para retornar idempotência.',
        v_carga_id;
    END IF;

    RETURN QUERY SELECT v_carga_id, v_nfs, v_saldo_total;
    RETURN;
  END IF;

  v_codigo := nullif(pg_catalog.btrim(p_codigo), '');
  v_quem_leva := nullif(pg_catalog.btrim(p_quem_leva), '');
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

  IF p_nfs IS NULL OR pg_catalog.jsonb_typeof(p_nfs) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'p_nfs precisa ser um array JSON de textos.';
  END IF;

  IF pg_catalog.jsonb_array_length(p_nfs) < 1 THEN
    RAISE EXCEPTION 'Informe ao menos uma NF para a carga.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.jsonb_array_elements(p_nfs) AS item(value)
    WHERE pg_catalog.jsonb_typeof(item.value) IS DISTINCT FROM 'string'
  ) THEN
    RAISE EXCEPTION 'Cada elemento de p_nfs precisa ser uma string.';
  END IF;

  FOR v_nf, v_nf_index IN
    SELECT pg_catalog.btrim(item.value), item.ordinality
    FROM pg_catalog.jsonb_array_elements_text(p_nfs)
      WITH ORDINALITY AS item(value, ordinality)
    ORDER BY item.ordinality
  LOOP
    v_nf := nullif(v_nf, '');
    IF v_nf IS NULL THEN
      RAISE EXCEPTION 'A NF na posição % está vazia.', v_nf_index;
    END IF;

    IF v_nf = ANY(v_nfs) THEN
      RAISE EXCEPTION 'A NF % está repetida no payload da carga.', v_nf;
    END IF;

    v_nfs := pg_catalog.array_append(v_nfs, v_nf);
  END LOOP;

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
  -- A chave primária serializa concorrência entre cargas e QR antigo.
  FOREACH v_nf IN ARRAY v_nfs
  LOOP
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
  END LOOP;

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
      v_carga_id,
      p_data_hora
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

  RETURN QUERY SELECT v_carga_id, v_nfs, v_saldo_total;
END;
$$;

COMMENT ON FUNCTION public.ef_confirmar_baixa_carga(
  text, timestamptz, text, jsonb, text, text, text, jsonb, uuid
) IS
  'Cria uma carga com uma ou mais NFs globais e confirma todos os itens vinculados usando a data/hora informada.';

REVOKE ALL ON FUNCTION public.ef_confirmar_baixa_carga(
  text, timestamptz, text, jsonb, text, text, text, jsonb, uuid
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.ef_confirmar_baixa_carga(
  text, timestamptz, text, jsonb, text, text, text, jsonb, uuid
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
WHERE p.oid IN (
  pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamptz)'
  ),
  pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, jsonb, text, text, text, jsonb, uuid)'
  )
)
ORDER BY p.proname;

SELECT
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamptz)',
    'EXECUTE'
  ) AS manual_authenticated_execute,
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamptz)',
    'EXECUTE'
  ) AS manual_anon_execute,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamptz)',
    'EXECUTE'
  ) AS manual_service_role_execute,
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, jsonb, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS carga_authenticated_execute,
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, jsonb, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS carga_anon_execute,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, jsonb, text, text, text, jsonb, uuid)',
    'EXECUTE'
  ) AS carga_service_role_execute;

DO $$
DECLARE
  v_manual oid;
  v_charge oid;
  v_manual_arguments text;
  v_charge_arguments text;
  v_charge_result text;
  v_manual_count integer;
  v_charge_count integer;
BEGIN
  v_manual := pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamptz)'
  );
  v_charge := pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_carga(text, timestamptz, text, jsonb, text, text, text, jsonb, uuid)'
  );

  IF v_manual IS NULL OR v_charge IS NULL THEN
    RAISE EXCEPTION 'Pós-verificação falhou: assinatura nova ausente.';
  END IF;

  v_manual_arguments := pg_catalog.regexp_replace(
    pg_catalog.pg_get_function_arguments(v_manual),
    ' DEFAULT NULL::[^,]+',
    ' DEFAULT NULL',
    'g'
  );
  IF v_manual_arguments IS DISTINCT FROM
    'p_id bigint, p_quantidade integer, p_idempotency_key uuid DEFAULT NULL, p_carga_id bigint DEFAULT NULL, p_data_hora timestamp with time zone DEFAULT NULL' THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: argumentos do helper inesperados: %',
      v_manual_arguments;
  END IF;

  IF pg_catalog.to_regprocedure(
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION 'Pós-verificação falhou: assinatura manual antiga ainda existe.';
  END IF;

  v_charge_arguments := pg_catalog.pg_get_function_arguments(v_charge);
  IF v_charge_arguments IS DISTINCT FROM
    'p_codigo text, p_data_hora timestamp with time zone, p_quem_leva text, p_nfs jsonb, p_origem text, p_serie text, p_filial text, p_itens jsonb, p_idempotency_key uuid' THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: argumentos da carga inesperados: %',
      v_charge_arguments;
  END IF;

  v_charge_result := pg_catalog.pg_get_function_result(v_charge);
  IF v_charge_result IS DISTINCT FROM
    'TABLE(carga_id bigint, nfs text[], saldo_total numeric)' THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: retorno da carga inesperado: %',
      v_charge_result;
  END IF;

  SELECT count(*) INTO v_manual_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_confirmar_baixa_manual';
  IF v_manual_count <> 1 THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: esperada uma sobrecarga manual, encontradas %.',
      v_manual_count;
  END IF;

  SELECT count(*) INTO v_charge_count
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ef_confirmar_baixa_carga';
  IF v_charge_count <> 1 THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: esperada uma sobrecarga de carga, encontradas %.',
      v_charge_count;
  END IF;

  IF NOT has_function_privilege('authenticated', v_manual, 'EXECUTE')
     OR has_function_privilege('anon', v_manual, 'EXECUTE')
     OR has_function_privilege('service_role', v_manual, 'EXECUTE') THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: grants do helper devem ser auth=true, anon/service_role=false.';
  END IF;

  IF NOT has_function_privilege('authenticated', v_charge, 'EXECUTE')
     OR has_function_privilege('anon', v_charge, 'EXECUTE')
     OR has_function_privilege('service_role', v_charge, 'EXECUTE') THEN
    RAISE EXCEPTION
      'Pós-verificação falhou: grants da carga devem ser auth=true, anon/service_role=false.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Teste transacional completo
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_stock_a public.estoque%rowtype;
  v_stock_b public.estoque%rowtype;
  v_result record;
  v_retry record;
  v_result_two record;
  v_result_three record;
  v_expected_failure boolean := false;
  v_payload_duplicate_rejected boolean := false;
  v_existing_nf_rejected boolean := false;
  v_error_message text;
  v_key_failure uuid;
  v_key_one uuid;
  v_key_two uuid;
  v_key_three uuid;
  v_key_payload_duplicate uuid;
  v_key_existing uuid;
  v_nf_one text;
  v_nf_two_a text;
  v_nf_two_b text;
  v_nf_three_a text;
  v_nf_three_b text;
  v_nf_three_c text;
  v_nf_existing text;
  v_nf_new text;
  v_code_failure text;
  v_code_one text;
  v_code_two text;
  v_code_three text;
  v_code_payload_duplicate text;
  v_code_existing text;
  v_retro_time timestamptz := '2026-10-05 14:30:00-03';
  v_expected_date date;
  v_before_a numeric;
  v_before_b numeric;
  v_first_carga_id bigint;
  v_after numeric;
  v_insufficient integer;
  v_count bigint;
BEGIN
  BEGIN
    PERFORM pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', '00000000-0000-4000-8000-000000002551',
        'email', 'balancacoperacel1@gmail.com',
        'role', 'authenticated'
      )::text,
      true
    );
    PERFORM pg_catalog.set_config(
      'request.jwt.claim.sub',
      '00000000-0000-4000-8000-000000002551',
      true
    );
    PERFORM pg_catalog.set_config(
      'request.jwt.claim.email',
      'balancacoperacel1@gmail.com',
      true
    );

    -- Duas pilhas com saldo finito garantem as baixas de 1, 2 e 3+ NFs.
    SELECT e.* INTO v_stock_a
    FROM public.estoque AS e
    WHERE e.qtd >= 3 AND e.qtd < 2000000000
    ORDER BY e.id
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Teste não executado: precisa haver uma pilha com saldo entre 3 e 2 bilhões.';
    END IF;

    SELECT e.* INTO v_stock_b
    FROM public.estoque AS e
    WHERE e.qtd >= 3 AND e.qtd < 2000000000
      AND e.id <> v_stock_a.id
    ORDER BY e.id
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Teste não executado: precisa haver duas pilhas distintas com saldo entre 3 e 2 bilhões.';
    END IF;

    v_before_a := v_stock_a.qtd;
    v_before_b := v_stock_b.qtd;
    v_insufficient := pg_catalog.ceil(v_stock_b.qtd)::integer + 1;

    v_key_failure := pg_catalog.md5(pg_catalog.clock_timestamp()::text || pg_catalog.random()::text)::uuid;
    v_key_one := pg_catalog.md5(pg_catalog.clock_timestamp()::text || pg_catalog.random()::text)::uuid;
    v_key_two := pg_catalog.md5(pg_catalog.clock_timestamp()::text || pg_catalog.random()::text)::uuid;
    v_key_three := pg_catalog.md5(pg_catalog.clock_timestamp()::text || pg_catalog.random()::text)::uuid;
    v_key_payload_duplicate := pg_catalog.md5(pg_catalog.clock_timestamp()::text || pg_catalog.random()::text)::uuid;
    v_key_existing := pg_catalog.md5(pg_catalog.clock_timestamp()::text || pg_catalog.random()::text)::uuid;

    v_nf_one := 'EF2551-1-' || pg_catalog.substr(pg_catalog.md5(v_key_one::text), 1, 16);
    v_nf_two_a := 'EF2551-2A-' || pg_catalog.substr(pg_catalog.md5(v_key_two::text), 1, 16);
    v_nf_two_b := 'EF2551-2B-' || pg_catalog.substr(pg_catalog.md5(v_key_two::text), 1, 16);
    v_nf_three_a := 'EF2551-3A-' || pg_catalog.substr(pg_catalog.md5(v_key_three::text), 1, 16);
    v_nf_three_b := 'EF2551-3B-' || pg_catalog.substr(pg_catalog.md5(v_key_three::text), 1, 16);
    v_nf_three_c := 'EF2551-3C-' || pg_catalog.substr(pg_catalog.md5(v_key_three::text), 1, 16);
    v_nf_existing := 'EF2551-EX-' || pg_catalog.substr(pg_catalog.md5(v_key_existing::text), 1, 16);
    v_nf_new := 'EF2551-NEW-' || pg_catalog.substr(pg_catalog.md5(v_key_existing::text), 1, 16);

    v_code_failure := 'EF2551-F-' || v_key_failure::text;
    v_code_one := 'EF2551-1-' || v_key_one::text;
    v_code_two := 'EF2551-2-' || v_key_two::text;
    v_code_three := 'EF2551-3-' || v_key_three::text;
    v_code_payload_duplicate := 'EF2551-PD-' || v_key_payload_duplicate::text;
    v_code_existing := 'EF2551-EX-' || v_key_existing::text;
    v_expected_date := (v_retro_time AT TIME ZONE 'America/Sao_Paulo')::date;

    -- Falha de saldo no segundo item reverte o primeiro item, a carga e suas NFs.
    BEGIN
      SELECT * INTO v_result
      FROM public.ef_confirmar_baixa_carga(
        v_code_failure, v_retro_time, 'TESTE 2.5.5.1',
        pg_catalog.jsonb_build_array('EF2551-FAIL'),
        'carga', 'TESTE', '1',
        pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('id', v_stock_a.id, 'quantidade', 1),
          pg_catalog.jsonb_build_object('id', v_stock_b.id, 'quantidade', v_insufficient)
        ),
        v_key_failure
      );
    EXCEPTION
      WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
        IF pg_catalog.strpos(v_error_message, 'Saldo insuficiente') = 0 THEN
          RAISE;
        END IF;
        v_expected_failure := true;
    END;

    IF NOT v_expected_failure THEN
      RAISE EXCEPTION 'Teste falhou: a baixa com saldo insuficiente foi aceita.';
    END IF;

    SELECT e.qtd INTO v_after FROM public.estoque AS e WHERE e.id = v_stock_a.id;
    IF NOT FOUND OR v_after IS DISTINCT FROM v_before_a THEN
      RAISE EXCEPTION 'Teste falhou: primeira pilha não reverteu após falha.';
    END IF;
    SELECT e.qtd INTO v_after FROM public.estoque AS e WHERE e.id = v_stock_b.id;
    IF NOT FOUND OR v_after IS DISTINCT FROM v_before_b THEN
      RAISE EXCEPTION 'Teste falhou: segunda pilha mudou após saldo insuficiente.';
    END IF;

    SELECT count(*) INTO v_count FROM public.cargas WHERE idempotency_key = v_key_failure;
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Teste falhou: cabeçalho da carga parcial permaneceu.';
    END IF;
    SELECT count(*) INTO v_count FROM public.cargas_nfs WHERE nf = 'EF2551-FAIL';
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Teste falhou: NF da carga parcial permaneceu.';
    END IF;
    SELECT count(*) INTO v_count
    FROM public.historico_saidas AS hs
    WHERE hs.idempotency_key IN (
      pg_catalog.md5(v_key_failure::text || ':carga-item:1')::uuid,
      pg_catalog.md5(v_key_failure::text || ':carga-item:2')::uuid
    );
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Teste falhou: histórico parcial permaneceu após erro.';
    END IF;

    -- (a) Uma NF e dois itens. A data de historico_saidas vem da carga retroativa.
    SELECT * INTO v_result
    FROM public.ef_confirmar_baixa_carga(
      v_code_one, v_retro_time, 'TESTE 2.5.5.1',
      pg_catalog.jsonb_build_array(v_nf_one),
      'carga', 'TESTE', '1',
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('id', v_stock_a.id, 'quantidade', 1),
        pg_catalog.jsonb_build_object('id', v_stock_b.id, 'quantidade', 1)
      ),
      v_key_one
    );

    v_first_carga_id := v_result.carga_id;

    IF v_result.carga_id IS NULL
       OR pg_catalog.cardinality(v_result.nfs) <> 1
       OR v_result.nfs[1] IS DISTINCT FROM v_nf_one
       OR v_result.saldo_total IS DISTINCT FROM ((v_before_a - 1) + (v_before_b - 1)) THEN
      RAISE EXCEPTION 'Teste falhou: retorno da carga com uma NF não confere.';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.historico_saidas AS hs
    WHERE hs.carga_id = v_result.carga_id
      AND hs.data IS DISTINCT FROM v_expected_date;
    IF v_count <> 0 THEN
      RAISE EXCEPTION
        'Teste falhou: data de historico_saidas diverge da data retroativa da carga.';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.cargas_nfs AS cn
    WHERE cn.carga_id = v_result.carga_id AND cn.nf = v_nf_one;
    IF v_count <> 1 THEN
      RAISE EXCEPTION 'Teste falhou: NF única não foi vinculada à carga.';
    END IF;

    -- Repetir a mesma chave devolve a mesma carga, NFs e saldo sem duplicar.
    SELECT * INTO v_retry
    FROM public.ef_confirmar_baixa_carga(
      v_code_one, v_retro_time, 'TESTE 2.5.5.1',
      pg_catalog.jsonb_build_array(v_nf_one),
      'carga', 'TESTE', '1',
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('id', v_stock_a.id, 'quantidade', 1),
        pg_catalog.jsonb_build_object('id', v_stock_b.id, 'quantidade', 1)
      ),
      v_key_one
    );
    IF v_retry.carga_id IS DISTINCT FROM v_result.carga_id
       OR v_retry.nfs IS DISTINCT FROM v_result.nfs
       OR v_retry.saldo_total IS DISTINCT FROM v_result.saldo_total THEN
      RAISE EXCEPTION 'Teste falhou: retorno da repetição idempotente diverge.';
    END IF;
    SELECT count(*) INTO v_count
    FROM public.historico_saidas AS hs WHERE hs.carga_id = v_result.carga_id;
    IF v_count <> 2 THEN
      RAISE EXCEPTION 'Teste falhou: retry duplicou as duas baixas.';
    END IF;

    -- (b) Duas NFs distintas numa carga.
    SELECT * INTO v_result_two
    FROM public.ef_confirmar_baixa_carga(
      v_code_two, v_retro_time, 'TESTE 2.5.5.1',
      pg_catalog.jsonb_build_array(v_nf_two_a, v_nf_two_b),
      'carga', 'TESTE', '1',
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('id', v_stock_a.id, 'quantidade', 1)
      ),
      v_key_two
    );
    IF v_result_two.carga_id IS NULL
       OR pg_catalog.cardinality(v_result_two.nfs) <> 2
       OR NOT (v_nf_two_a = ANY(v_result_two.nfs))
       OR NOT (v_nf_two_b = ANY(v_result_two.nfs)) THEN
      RAISE EXCEPTION 'Teste falhou: carga com duas NFs não retornou ambas.';
    END IF;
    SELECT count(*) INTO v_count
    FROM public.cargas_nfs AS cn
    WHERE cn.carga_id = v_result_two.carga_id
      AND cn.nf = ANY(ARRAY[v_nf_two_a, v_nf_two_b]::text[]);
    IF v_count <> 2 THEN
      RAISE EXCEPTION 'Teste falhou: as duas NFs não foram gravadas.';
    END IF;

    -- (c) Três NFs numa carga (cobertura para 3+).
    SELECT * INTO v_result_three
    FROM public.ef_confirmar_baixa_carga(
      v_code_three, v_retro_time, 'TESTE 2.5.5.1',
      pg_catalog.jsonb_build_array(v_nf_three_a, v_nf_three_b, v_nf_three_c),
      'carga', 'TESTE', '1',
      pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object('id', v_stock_b.id, 'quantidade', 1)
      ),
      v_key_three
    );
    IF v_result_three.carga_id IS NULL
       OR pg_catalog.cardinality(v_result_three.nfs) <> 3
       OR NOT (v_nf_three_a = ANY(v_result_three.nfs))
       OR NOT (v_nf_three_b = ANY(v_result_three.nfs))
       OR NOT (v_nf_three_c = ANY(v_result_three.nfs)) THEN
      RAISE EXCEPTION 'Teste falhou: carga com três NFs não retornou todas.';
    END IF;

    -- (d) Duplicata no mesmo payload, inclusive após trim.
    BEGIN
      SELECT * INTO v_result
      FROM public.ef_confirmar_baixa_carga(
        v_code_payload_duplicate, v_retro_time, 'TESTE 2.5.5.1',
        pg_catalog.jsonb_build_array('EF2551-DUP', ' EF2551-DUP '),
        'carga', 'TESTE', '1',
        pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('id', v_stock_a.id, 'quantidade', 1)
        ),
        v_key_payload_duplicate
      );
    EXCEPTION
      WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
        IF pg_catalog.strpos(v_error_message, 'repetida no payload') = 0 THEN
          RAISE;
        END IF;
        v_payload_duplicate_rejected := true;
    END;
    IF NOT v_payload_duplicate_rejected THEN
      RAISE EXCEPTION 'Teste falhou: NF repetida no payload foi aceita.';
    END IF;
    SELECT count(*) INTO v_count
    FROM public.cargas WHERE idempotency_key = v_key_payload_duplicate;
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Teste falhou: carga foi criada antes de rejeitar NFs repetidas.';
    END IF;

    -- (e) NF previamente registrada pelo fluxo QR: nenhuma parte da carga persiste.
    INSERT INTO public.cargas_nfs(nf, carga_id, origem, ordem_id, filial, serie)
    VALUES (v_nf_existing, NULL, 'qr', 'EF2551-QR-TEST', '1', 'TESTE');

    BEGIN
      SELECT * INTO v_result
      FROM public.ef_confirmar_baixa_carga(
        v_code_existing, v_retro_time, 'TESTE 2.5.5.1',
        pg_catalog.jsonb_build_array(v_nf_new, v_nf_existing),
        'carga', 'TESTE', '1',
        pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('id', v_stock_a.id, 'quantidade', 1)
        ),
        v_key_existing
      );
    EXCEPTION
      WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
        IF pg_catalog.strpos(v_error_message, 'já foi registrada') = 0 THEN
          RAISE;
        END IF;
        v_existing_nf_rejected := true;
    END;
    IF NOT v_existing_nf_rejected THEN
      RAISE EXCEPTION 'Teste falhou: NF que já existia foi aceita.';
    END IF;
    SELECT count(*) INTO v_count
    FROM public.cargas WHERE idempotency_key = v_key_existing;
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Teste falhou: carga com NF existente permaneceu.';
    END IF;
    SELECT count(*) INTO v_count
    FROM public.cargas_nfs WHERE nf = v_nf_new;
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Teste falhou: NF nova inserida antes da duplicata permaneceu.';
    END IF;

    -- Verifica também a data retroativa no histórico de todos os itens da carga 1.
    SELECT count(*) INTO v_count
    FROM public.historico_saidas AS hs
    WHERE hs.carga_id = v_first_carga_id
      AND hs.data IS DISTINCT FROM v_expected_date;
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Teste falhou: histórico não herdou data/hora da carga.';
    END IF;

    RAISE EXCEPTION 'ROLLBACK DE TESTE' USING ERRCODE = 'ZX551';
  EXCEPTION
    WHEN SQLSTATE 'ZX551' THEN
      RAISE NOTICE
        'ROLLBACK DE TESTE: multi-NF, idempotência e data retroativa passaram; dados desfeitos.';
  END;
END;
$$;

-- RESULTADO ESPERADO:
-- * Assinatura manual: cinco parâmetros, com p_data_hora DEFAULT NULL.
-- * Assinatura de carga: p_nfs jsonb e retorno nfs text[].
-- * Grants nas duas RPCs: authenticated=true, anon=false, service_role=false.
-- * Teste: 1 NF/2 itens, retry idempotente, 2 NFs, 3 NFs, NF duplicada no payload,
--   NF já existente via QR, rollback após item insuficiente e data retroativa.
-- * NOTICE esperado: "ROLLBACK DE TESTE: multi-NF, idempotência e data retroativa passaram; dados desfeitos."

ROLLBACK;

-- ---------------------------------------------------------------------------
-- Rollback manual caso a alteração seja aplicada futuramente
-- ---------------------------------------------------------------------------
-- Execute fora do bloco de teste e em uma janela de manutenção:
-- BEGIN;
-- DROP FUNCTION IF EXISTS public.ef_confirmar_baixa_carga(
--   text, timestamptz, text, jsonb, text, text, text, jsonb, uuid
-- );
-- DROP FUNCTION IF EXISTS public.ef_confirmar_baixa_manual(
--   bigint, integer, uuid, bigint, timestamptz
-- );
-- Depois, restaure os corpos e grants anteriores (versões 2.5.2 e 2.5.3)
-- a partir das definições SQL versionadas no repositório antes do COMMIT manual.
-- NOTIFY pgrst, 'reload schema';
-- COMMIT;
