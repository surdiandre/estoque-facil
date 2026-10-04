-- Estoque Fácil: baixa manual atômica (Bloco 2.2 / P1-01).
-- Antes, o HTML alterava/excluía estoque e depois inseria historico_saidas
-- em duas requisições. Esta RPC trava a linha com FOR UPDATE e realiza ambas
-- as alterações na mesma transação.
--
-- Rode primeiro no SQL Editor com o ROLLBACK final. Confira SECURITY DEFINER,
-- search_path vazio e os privilégios antes de persistir a função.
-- Não publique o HTML novo antes de aplicar esta função com COMMIT.
-- Após a revisão e seu OK explícito, substitua o ROLLBACK final por COMMIT.

BEGIN;

CREATE OR REPLACE FUNCTION public.ef_confirmar_baixa_manual(
  p_id bigint,
  p_quantidade integer
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
    data, produto, empresa, lote, pilha, qtd, unid, usuario
  )
  VALUES (
    (now() AT TIME ZONE 'America/Sao_Paulo')::date,
    v.produto,
    coalesce(v.empresa, ''),
    v.lote,
    v.pilha,
    p_quantidade,
    v.unid,
    v_email
  );

  RETURN v_novo_saldo;
END;
$$;

COMMENT ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer) IS
  'Baixa manual transacional: bloqueia o saldo, atualiza/exclui estoque e grava historico_saidas.';

-- CREATE FUNCTION concede EXECUTE a PUBLIC por padrão. Removemos os grants
-- e só autorizamos authenticated; a função valida o e-mail administrativo.
REVOKE ALL ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ef_confirmar_baixa_manual(bigint, integer)
  TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Confirme security_definer=true e que function_settings inclui search_path="".
SELECT
  p.oid::regprocedure AS assinatura,
  p.prosecdef AS security_definer,
  p.proconfig AS function_settings
FROM pg_catalog.pg_proc AS p
WHERE p.oid = 'public.ef_confirmar_baixa_manual(bigint, integer)'::regprocedure;

-- Resultado esperado: anon_can_execute=false e authenticated_can_execute=true.
SELECT
  has_function_privilege(
    'anon',
    'public.ef_confirmar_baixa_manual(bigint, integer)',
    'EXECUTE'
  ) AS anon_can_execute,
  has_function_privilege(
    'authenticated',
    'public.ef_confirmar_baixa_manual(bigint, integer)',
    'EXECUTE'
  ) AS authenticated_can_execute;

-- Este ROLLBACK descarta a função e os grants do teste.
-- Depois de validar e receber OK, substitua esta linha por COMMIT.
ROLLBACK;
