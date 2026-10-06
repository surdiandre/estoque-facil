-- Estoque Fácil — 2.4.2: RPCs idempotentes da fila offline
--
-- O que esta migração faz:
--   1. Substitui as assinaturas antigas das RPCs por versões com
--      p_idempotency_key UUID DEFAULT NULL.
--   2. Reutiliza o saldo/resultados registrados quando a mesma chave é
--      enviada novamente, sem repetir a alteração de estoque.
--   3. Serializa chamadas concorrentes que usam a mesma chave.
--   4. Preserva RETURNS numeric, SECURITY DEFINER, search_path vazio,
--      validação administrativa e FOR UPDATE no registro de estoque.
--
-- A chave foi acrescentada no fim dos parâmetros para manter chamadas
-- antigas compatíveis: clientes que omitem p_idempotency_key recebem NULL.
--
-- O DROP das assinaturas antigas é necessário porque a nova assinatura tem
-- quantidade/tipos diferentes de parâmetros. Manter as duas pode deixar o
-- PostgREST sem saber qual overload escolher quando a chave opcional é omitida.
--
-- TESTE DE INSTALAÇÃO:
--   Execute com o ROLLBACK ativo. As funções e grants podem ser consultados
--   dentro da transação, e o ROLLBACK descarta a migração no fim.
--
-- TESTE DE REPETIÇÃO:
--   Depois de aprovar e persistir a migração, use uma UUID nova por teste.
--   1. Chame ef_confirmar_baixa_manual com p_id, p_quantidade e chave X.
--      O saldo deve diminuir uma vez.
--   2. Repita a mesma chamada com a chave X. O saldo não deve mudar e a RPC
--      deve retornar o mesmo saldo_resultante da primeira chamada.
--   3. Chame ef_alterar_saldo no modo ajuste com chave Y. O saldo deve mudar
--      para o saldo contado e ef_ajustes_saldo deve registrar uma linha.
--   4. Repita a chamada de ajuste com a chave Y. O saldo não deve mudar e a
--      RPC deve retornar o mesmo saldo_novo.
--   5. Para testar entrada, repita o fluxo com modo 'entrada'; a segunda
--      chamada deve retornar historico_entradas.saldo_resultante.
--
-- Exemplos de payloads REST (substitua o id e use UUIDs inéditos):
--   POST /rest/v1/rpc/ef_confirmar_baixa_manual
--   {"p_id":123,"p_quantidade":1,
--    "p_idempotency_key":"11111111-1111-4111-8111-111111111111"}
--
--   POST /rest/v1/rpc/ef_alterar_saldo
--   {"p_id":123,"p_modo":"ajuste","p_quantidade":10,
--    "p_motivo":"Conferência do estoque","p_saldo_esperado":9,
--    "p_idempotency_key":"22222222-2222-4222-8222-222222222222"}
--
-- Para conferir os movimentos de um teste:
--   SELECT id, idempotency_key, qtd, saldo_resultante
--   FROM public.historico_saidas
--   WHERE idempotency_key = '11111111-1111-4111-8111-111111111111';
--
--   SELECT id, idempotency_key, saldo_anterior, saldo_novo
--   FROM public.ef_ajustes_saldo
--   WHERE idempotency_key = '22222222-2222-4222-8222-222222222222';
--
-- Rollback manual após uma aplicação persistente:
--   Recriar as definições anteriores das RPCs usando
--   security/baixa-manual-atomica.sql e security/ajuste-saldo-entradas.sql.
--   Não basta remover as novas funções: o rollback completo também restaura
--   as assinaturas e os privilégios antigos.
--
-- Pré-requisito: 2.4.1 aplicado, com as colunas e índices de idempotência.

BEGIN;

DROP FUNCTION IF EXISTS public.ef_confirmar_baixa_manual(bigint, integer);
DROP FUNCTION IF EXISTS public.ef_alterar_saldo(
  bigint, text, integer, text, text, numeric, date
);

CREATE FUNCTION public.ef_confirmar_baixa_manual(
  p_id bigint,
  p_quantidade integer,
  p_idempotency_key uuid DEFAULT NULL
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
BEGIN
  v_email := auth.jwt()->>'email';

  IF auth.uid() IS NULL OR v_email IS DISTINCT FROM 'balancacoperacel1@gmail.com' THEN
    RAISE EXCEPTION 'Acesso administrativo obrigatório.';
  END IF;

  IF p_id IS NULL OR p_id < 1 OR p_quantidade IS NULL OR p_quantidade <= 0 THEN
    RAISE EXCEPTION 'Pilha ou quantidade inválida.';
  END IF;

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
    idempotency_key, saldo_resultante
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
    v_novo_saldo
  );

  RETURN v_novo_saldo;
END;
$$;

COMMENT ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid) IS
  'Baixa manual transacional e idempotente: reutiliza o saldo_resultante quando a chave já foi processada.';

CREATE FUNCTION public.ef_alterar_saldo(
  p_id bigint,
  p_modo text,
  p_quantidade integer,
  p_motivo text DEFAULT NULL,
  p_referencia text DEFAULT NULL,
  p_saldo_esperado numeric DEFAULT NULL,
  p_validade date DEFAULT NULL,
  p_idempotency_key uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v public.estoque%rowtype;
  v_novo numeric;
  v_existente numeric;
  v_email text;
BEGIN
  v_email := auth.jwt()->>'email';

  IF auth.uid() IS NULL OR v_email IS DISTINCT FROM 'balancacoperacel1@gmail.com' THEN
    RAISE EXCEPTION 'Acesso administrativo obrigatório.';
  END IF;

  IF p_modo IS NULL OR p_modo NOT IN ('entrada', 'ajuste') THEN
    RAISE EXCEPTION 'Modo inválido.';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext(p_idempotency_key::text)
    );

    IF p_modo = 'entrada' THEN
      SELECT he.saldo_resultante
      INTO v_existente
      FROM public.historico_entradas AS he
      WHERE he.idempotency_key = p_idempotency_key;

      IF FOUND THEN
        IF v_existente IS NULL THEN
          RAISE EXCEPTION 'A chave de idempotência da entrada não tem saldo_resultante.';
        END IF;
        RETURN v_existente;
      END IF;
    ELSE
      SELECT aa.saldo_novo
      INTO v_existente
      FROM public.ef_ajustes_saldo AS aa
      WHERE aa.idempotency_key = p_idempotency_key;

      IF FOUND THEN
        RETURN v_existente;
      END IF;
    END IF;
  END IF;

  IF p_id IS NULL OR p_id < 1 OR p_quantidade IS NULL OR p_quantidade < 0
     OR (p_modo = 'entrada' AND p_quantidade = 0) THEN
    RAISE EXCEPTION 'Quantidade inválida.';
  END IF;

  IF length(coalesce(p_referencia, '')) > 80 THEN
    RAISE EXCEPTION 'Referência muito longa.';
  END IF;

  IF p_modo = 'ajuste'
     AND (length(btrim(coalesce(p_motivo, ''))) < 4 OR length(p_motivo) > 300) THEN
    RAISE EXCEPTION 'Informe o motivo do ajuste (4 a 300 caracteres).';
  END IF;

  SELECT e.*
  INTO v
  FROM public.estoque AS e
  WHERE e.id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pilha não encontrada. Atualize o estoque.';
  END IF;

  IF p_saldo_esperado IS NOT NULL AND v.qtd IS DISTINCT FROM p_saldo_esperado THEN
    RAISE EXCEPTION 'Saldo mudou desde a consulta. Atualize o estoque e confira novamente.';
  END IF;

  v_novo := CASE
    WHEN p_modo = 'entrada' THEN v.qtd + p_quantidade
    ELSE p_quantidade
  END;

  IF p_modo = 'ajuste' AND v_novo = v.qtd THEN
    RAISE EXCEPTION 'O saldo contado já é igual ao saldo atual.';
  END IF;

  UPDATE public.estoque AS e
  SET qtd = v_novo,
      validade = CASE
        WHEN p_modo = 'entrada' AND p_validade IS NOT NULL THEN p_validade
        ELSE v.validade
      END
  WHERE e.id = p_id;

  IF p_modo = 'entrada' THEN
    INSERT INTO public.historico_entradas (
      data, produto, lote, pilha, qtd, unid, empresa, usuario, referencia,
      idempotency_key, saldo_resultante
    )
    VALUES (
      (now() AT TIME ZONE 'America/Sao_Paulo')::date,
      v.produto, v.lote, v.pilha, p_quantidade, v.unid,
      coalesce(v.empresa, ''), v_email, nullif(btrim(p_referencia), ''),
      p_idempotency_key, v_novo
    );
  ELSE
    INSERT INTO public.ef_ajustes_saldo (
      estoque_id, produto, lote, pilha, armazem,
      saldo_anterior, saldo_novo, motivo, usuario, idempotency_key
    )
    VALUES (
      v.id, v.produto, v.lote, v.pilha, v.armazem,
      v.qtd, v_novo, btrim(p_motivo), v_email, p_idempotency_key
    );
  END IF;

  RETURN v_novo;
END;
$$;

COMMENT ON FUNCTION public.ef_alterar_saldo(
  bigint, text, integer, text, text, numeric, date, uuid
) IS
  'Altera saldo transacionalmente e reutiliza o resultado quando a chave de idempotência já foi processada.';

REVOKE ALL ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer, uuid)
  TO authenticated;

REVOKE ALL ON FUNCTION public.ef_alterar_saldo(
  bigint, text, integer, text, text, numeric, date, uuid
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ef_alterar_saldo(
  bigint, text, integer, text, text, numeric, date, uuid
) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Assinaturas, argumentos/defaults e configurações de segurança.
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS argumentos_identidade,
  pg_get_function_arguments(p.oid) AS argumentos_com_defaults,
  p.prosecdef AS security_definer,
  p.proconfig AS configuracao
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('ef_confirmar_baixa_manual', 'ef_alterar_saldo')
ORDER BY p.proname;

-- Grants: anon=false, service_role=false, authenticated=true.
SELECT
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
    'EXECUTE'
  ) AS baixa_anon,
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
    'EXECUTE'
  ) AS baixa_authenticated,
  has_function_privilege(
    'service_role',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid)',
    'EXECUTE'
  ) AS baixa_service_role,
  has_function_privilege(
    'anon',
    'public.ef_alterar_saldo(bigint, text, integer, text, text, numeric, date, uuid)',
    'EXECUTE'
  ) AS alterar_anon,
  has_function_privilege(
    'authenticated',
    'public.ef_alterar_saldo(bigint, text, integer, text, text, numeric, date, uuid)',
    'EXECUTE'
  ) AS alterar_authenticated,
  has_function_privilege(
    'service_role',
    'public.ef_alterar_saldo(bigint, text, integer, text, text, numeric, date, uuid)',
    'EXECUTE'
  ) AS alterar_service_role;

-- Deve retornar uma linha por função, com overload_count = 1.
SELECT p.proname, count(*) AS overload_count
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('ef_confirmar_baixa_manual', 'ef_alterar_saldo')
GROUP BY p.proname
ORDER BY p.proname;

-- Para o teste inicial, descarta as funções e grants criados acima.
ROLLBACK;
