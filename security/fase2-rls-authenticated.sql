-- Estoque Fácil — Fase 2: remover leitura pública e restringir public ao admin.
--
-- TESTE: execute este arquivo inteiro como está. A transação termina em ROLLBACK.
-- APLICAÇÃO: só depois de revisar todas as verificações do teste, troque a
-- última linha (ROLLBACK) por COMMIT e execute exatamente este mesmo arquivo.
-- Requer PostgreSQL 15+ (security_invoker em views).
-- A identidade autorizada é o JWT com email exato:
--   balancacoperacel1@gmail.com

BEGIN;
SET LOCAL search_path = pg_catalog, public;

-- ---------------------------------------------------------------------------
-- 0. Pré-condições: falhar sem alterar nada se o banco não suportar o plano.
-- ---------------------------------------------------------------------------
DO $preflight$
DECLARE
  v_version integer := current_setting('server_version_num')::integer;
BEGIN
  IF v_version < 150000 THEN
    RAISE EXCEPTION 'Esta blindagem exige PostgreSQL 15 ou superior (versão atual: %).', v_version;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION 'As roles anon e authenticated precisam existir.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('m', 'f')
  ) THEN
    RAISE EXCEPTION
      'Há materialized views ou foreign tables no schema public. Revise-as antes: elas não podem receber o mesmo gate de RLS/security_invoker.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
  ) THEN
    RAISE EXCEPTION 'Nenhuma tabela física foi encontrada no schema public.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'authenticated' AND (rolsuper OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'A role authenticated não pode ser superuser nem ter BYPASSRLS.';
  END IF;
END;
$preflight$;

-- Sem USAGE no schema e sem grants nos objetos, anon não consegue consultar
-- o schema pelo PostgREST. authenticated recebe somente USAGE, sem CREATE.
REVOKE ALL ON SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;

-- Remove grants de tabela/view e eventuais grants por coluna. A segunda
-- revogação cobre SELECT/INSERT/UPDATE/REFERENCES concedidos coluna a coluna.
DO $revoke_relations$
DECLARE
  v_rel record;
  v_columns text;
BEGIN
  FOR v_rel IN
    SELECT c.oid, n.nspname, c.relname
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
    ORDER BY c.relkind, c.relname
  LOOP
    EXECUTE format(
      'REVOKE ALL PRIVILEGES ON TABLE %I.%I FROM PUBLIC, anon, authenticated',
      v_rel.nspname, v_rel.relname
    );

    SELECT string_agg(format('%I', a.attname), ', ' ORDER BY a.attnum)
    INTO v_columns
    FROM pg_attribute AS a
    WHERE a.attrelid = v_rel.oid
      AND a.attnum > 0
      AND NOT a.attisdropped;

    IF v_columns IS NOT NULL THEN
      EXECUTE format(
        'REVOKE ALL PRIVILEGES (%s) ON TABLE %I.%I FROM PUBLIC, anon, authenticated',
        v_columns, v_rel.nspname, v_rel.relname
      );
    END IF;
  END LOOP;
END;
$revoke_relations$;

-- RLS: substitui políticas antigas para que nenhuma política permissiva
-- anterior amplie o acesso. A policy permissiva abre a operação para
-- authenticated; a restritiva exige o e-mail administrativo em cada comando.
DO $secure_tables$
DECLARE
  v_table record;
  v_policy record;
BEGIN
  FOR v_table IN
    SELECT c.oid, n.nspname, c.relname
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
    ORDER BY c.relname
  LOOP
    FOR v_policy IN
      SELECT polname
      FROM pg_policy
      WHERE polrelid = v_table.oid
    LOOP
      EXECUTE format(
        'DROP POLICY %I ON %I.%I',
        v_policy.polname, v_table.nspname, v_table.relname
      );
    END LOOP;

    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',
                   v_table.nspname, v_table.relname);
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %I.%I TO authenticated',
      v_table.nspname, v_table.relname
    );
    EXECUTE format(
      'CREATE POLICY ef_authenticated_access ON %I.%I AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true)',
      v_table.nspname, v_table.relname
    );
    EXECUTE format(
      'CREATE POLICY ef_admin_identity_gate ON %I.%I AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT auth.jwt() ->> ''email'') = ''balancacoperacel1@gmail.com'') WITH CHECK ((SELECT auth.jwt() ->> ''email'') = ''balancacoperacel1@gmail.com'')',
      v_table.nspname, v_table.relname
    );
  END LOOP;
END;
$secure_tables$;

-- Views comuns passam a usar permissões e RLS do usuário que consulta.
DO $secure_views$
DECLARE
  v_view record;
BEGIN
  FOR v_view IN
    SELECT c.oid, n.nspname, c.relname
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'v'
    ORDER BY c.relname
  LOOP
    EXECUTE format('ALTER VIEW %I.%I SET (security_invoker = true)',
                   v_view.nspname, v_view.relname);
    EXECUTE format('GRANT SELECT ON TABLE %I.%I TO authenticated',
                   v_view.nspname, v_view.relname);
  END LOOP;
END;
$secure_views$;

-- Sequences: sem acesso de anon/PUBLIC; authenticated recebe USAGE e SELECT
-- para que operações autorizadas com colunas identity continuem funcionando.
DO $secure_sequences$
DECLARE
  v_sequence record;
BEGIN
  FOR v_sequence IN
    SELECT n.nspname, c.relname
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'S'
    ORDER BY c.relname
  LOOP
    EXECUTE format(
      'REVOKE ALL PRIVILEGES ON SEQUENCE %I.%I FROM PUBLIC, anon, authenticated',
      v_sequence.nspname, v_sequence.relname
    );
    EXECUTE format(
      'GRANT USAGE, SELECT ON SEQUENCE %I.%I TO authenticated',
      v_sequence.nspname, v_sequence.relname
    );
  END LOOP;
END;
$secure_sequences$;

-- Nenhuma função pública fica executável por anon/PUBLIC/authenticated por
-- padrão. Em seguida, liberamos somente as RPCs usadas pelo app. As quatro
-- RPCs centrais são obrigatórias e precisam ter validação própria do admin.
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public
  FROM PUBLIC, anon, authenticated;

DO $grant_admin_rpcs$
DECLARE
  v_signature text;
  v_oid oid;
  v_proc record;
  v_required text[] := ARRAY[
    'public.ef_alterar_saldo(bigint, text, integer, text, text, numeric, date, uuid)',
    'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamp with time zone)',
    'public.ef_confirmar_baixa_carga(text, timestamp with time zone, text, jsonb, text, text, text, jsonb, uuid)',
    'public.ef_estornar_carga(bigint, text)'
  ];
BEGIN
  FOREACH v_signature IN ARRAY v_required LOOP
    v_oid := to_regprocedure(v_signature)::oid;
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'RPC obrigatória ausente; nada será aplicado: %', v_signature;
    END IF;

    SELECT p.oid, p.prosecdef, p.prosrc, p.proconfig, p.proname
    INTO v_proc
    FROM pg_proc AS p
    WHERE p.oid = v_oid;

    IF NOT v_proc.prosecdef
       OR position('balancacoperacel1@gmail.com' IN v_proc.prosrc) = 0 THEN
      RAISE EXCEPTION
        'RPC % não tem SECURITY DEFINER e validação própria do e-mail admin; nada será aplicado.',
        v_signature;
    END IF;

    IF NOT coalesce(v_proc.proconfig @> ARRAY['search_path=""'], false) THEN
      RAISE EXCEPTION
        'RPC % não fixa search_path vazio; revise antes de aplicar.', v_signature;
    END IF;

    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated',
      'public', v_proc.proname, pg_get_function_identity_arguments(v_proc.oid)
    );
  END LOOP;

  -- Compatibilidade: a RPC antiga de QR é SECURITY INVOKER e não é usada pelo
  -- fluxo atual. Se ainda existir, só fica disponível se conservar seu gate.
  v_oid := to_regprocedure(
    'public.ef_confirmar_baixa_qr(text, text, text, text, jsonb)'
  )::oid;
  IF v_oid IS NOT NULL THEN
    SELECT p.prosecdef, p.prosrc, p.proname
    INTO v_proc
    FROM pg_proc AS p
    WHERE p.oid = v_oid;
    IF position('balancacoperacel1@gmail.com' IN v_proc.prosrc) = 0 THEN
      RAISE EXCEPTION
        'A RPC legada ef_confirmar_baixa_qr existe sem validação do e-mail admin; nada será aplicado.';
    END IF;
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated',
      'public', v_proc.proname, pg_get_function_identity_arguments(v_oid)
    );
  END IF;
END;
$grant_admin_rpcs$;

-- ---------------------------------------------------------------------------
-- 1. Verificações: qualquer falha levanta erro e a transação pode ser revertida.
-- ---------------------------------------------------------------------------
DO $assert_privileges$
DECLARE
  v_authenticated oid := (SELECT oid FROM pg_roles WHERE rolname = 'authenticated');
BEGIN
  IF has_schema_privilege('anon', 'public', 'USAGE') THEN
    RAISE EXCEPTION 'Falha: anon ainda tem USAGE no schema public.';
  END IF;
  IF has_schema_privilege('anon', 'public', 'CREATE')
     OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
    RAISE EXCEPTION 'Falha: anon ou authenticated ainda tem CREATE no schema public.';
  END IF;
  IF NOT has_schema_privilege('authenticated', 'public', 'USAGE') THEN
    RAISE EXCEPTION 'Falha: authenticated não tem USAGE no schema public.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
      AND (has_table_privilege('anon', c.oid, 'SELECT')
        OR has_table_privilege('anon', c.oid, 'INSERT')
        OR has_table_privilege('anon', c.oid, 'UPDATE')
        OR has_table_privilege('anon', c.oid, 'DELETE')
        OR has_table_privilege('anon', c.oid, 'TRUNCATE')
        OR has_table_privilege('anon', c.oid, 'REFERENCES')
        OR has_table_privilege('anon', c.oid, 'TRIGGER')
        OR has_any_column_privilege('anon', c.oid, 'SELECT')
        OR has_any_column_privilege('anon', c.oid, 'INSERT')
        OR has_any_column_privilege('anon', c.oid, 'UPDATE')
        OR has_any_column_privilege('anon', c.oid, 'REFERENCES'))
  ) THEN
    RAISE EXCEPTION 'Falha: anon ainda tem SELECT em uma tabela ou view do schema public.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
      AND NOT has_table_privilege('authenticated', c.oid, 'SELECT')
  ) THEN
    RAISE EXCEPTION 'Falha: authenticated não tem SELECT em uma tabela ou view do schema public.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      AND (NOT has_table_privilege('authenticated', c.oid, 'INSERT')
        OR NOT has_table_privilege('authenticated', c.oid, 'UPDATE')
        OR NOT has_table_privilege('authenticated', c.oid, 'DELETE')
        OR NOT c.relrowsecurity)
  ) THEN
    RAISE EXCEPTION 'Falha: falta CRUD para authenticated ou RLS não está ativa em uma tabela física.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'v'
      AND NOT coalesce(c.reloptions @> ARRAY['security_invoker=true'], false)
  ) THEN
    RAISE EXCEPTION 'Falha: uma view pública não está com security_invoker=true.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'S'
      AND (has_sequence_privilege('anon', c.oid, 'USAGE')
        OR has_sequence_privilege('anon', c.oid, 'SELECT')
        OR has_sequence_privilege('anon', c.oid, 'UPDATE')
        OR NOT has_sequence_privilege('authenticated', c.oid, 'USAGE')
        OR NOT has_sequence_privilege('authenticated', c.oid, 'SELECT'))
  ) THEN
    RAISE EXCEPTION 'Falha: grants de sequence inesperados.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'Falha: anon ainda pode executar uma função do schema public.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND p.proname NOT IN (
        'ef_alterar_saldo', 'ef_confirmar_baixa_manual',
        'ef_confirmar_baixa_carga', 'ef_estornar_carga',
        'ef_confirmar_baixa_qr'
      )
  ) THEN
    RAISE EXCEPTION 'Falha: authenticated tem EXECUTE em função pública fora da lista autorizada.';
  END IF;

  IF NOT has_function_privilege(
       'authenticated',
       'public.ef_alterar_saldo(bigint, text, integer, text, text, numeric, date, uuid)',
       'EXECUTE'
     ) OR NOT has_function_privilege(
       'authenticated',
       'public.ef_confirmar_baixa_manual(bigint, integer, uuid, bigint, timestamp with time zone)',
       'EXECUTE'
     ) OR NOT has_function_privilege(
       'authenticated',
       'public.ef_confirmar_baixa_carga(text, timestamp with time zone, text, jsonb, text, text, text, jsonb, uuid)',
       'EXECUTE'
     ) OR NOT has_function_privilege(
       'authenticated', 'public.ef_estornar_carga(bigint, text)', 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Falha: uma RPC necessária não está executável por authenticated.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      AND NOT EXISTS (
        SELECT 1 FROM pg_policy AS p
        WHERE p.polrelid = c.oid
          AND p.polname = 'ef_authenticated_access'
          AND p.polcmd = '*'
          AND p.polpermissive
          AND p.polroles @> ARRAY[v_authenticated]
      )
  ) THEN
    RAISE EXCEPTION 'Falha: policy permissiva ef_authenticated_access ausente.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      AND NOT EXISTS (
        SELECT 1 FROM pg_policy AS p
        WHERE p.polrelid = c.oid
          AND p.polname = 'ef_admin_identity_gate'
          AND p.polcmd = '*'
          AND NOT p.polpermissive
          AND p.polroles @> ARRAY[v_authenticated]
          AND lower(coalesce(pg_get_expr(p.polqual, p.polrelid), ''))
              LIKE '%balancacoperacel1@gmail.com%'
          AND lower(coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''))
              LIKE '%balancacoperacel1@gmail.com%'
      )
  ) THEN
    RAISE EXCEPTION 'Falha: policy restritiva ef_admin_identity_gate ausente ou incorreta.';
  END IF;
END;
$assert_privileges$;

-- Teste somente de leitura como authenticated com claims de teste do admin.
-- Não altera dados de estoque. Confirma que cada tabela e view pode ser aberta
-- com o gate e que as views security_invoker alcançam suas tabelas-base.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","email":"balancacoperacel1@gmail.com"}',
  true
);

DO $test_authenticated_reads$
DECLARE
  v_relation record;
BEGIN
  FOR v_relation IN
    SELECT n.nspname, c.relname
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
    ORDER BY c.relkind, c.relname
  LOOP
    EXECUTE format('SELECT 1 FROM %I.%I LIMIT 1',
                   v_relation.nspname, v_relation.relname);
  END LOOP;
END;
$test_authenticated_reads$;
RESET ROLE;

-- Resultado legível do teste: anon=false; authenticated=true; RLS e gate ativos.
SELECT
  c.relname AS objeto,
  CASE c.relkind WHEN 'v' THEN 'view' ELSE 'tabela' END AS tipo,
  has_table_privilege('anon', c.oid, 'SELECT')
    OR has_any_column_privilege('anon', c.oid, 'SELECT') AS anon_select,
  has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated_select,
  CASE WHEN c.relkind IN ('r', 'p') THEN c.relrowsecurity ELSE NULL END AS rls_ativa,
  CASE WHEN c.relkind = 'v'
    THEN coalesce(c.reloptions @> ARRAY['security_invoker=true'], false)
    ELSE NULL
  END AS security_invoker
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
ORDER BY tipo, objeto;

SELECT
  c.relname AS sequence,
  has_sequence_privilege('anon', c.oid, 'USAGE') AS anon_usage,
  has_sequence_privilege('anon', c.oid, 'SELECT') AS anon_select,
  has_sequence_privilege('authenticated', c.oid, 'USAGE') AS authenticated_usage,
  has_sequence_privilege('authenticated', c.oid, 'SELECT') AS authenticated_select
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'S'
ORDER BY c.relname;

SELECT
  p.proname AS rpc,
  pg_get_function_identity_arguments(p.oid) AS argumentos,
  p.prosecdef AS security_definer,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'ef_alterar_saldo', 'ef_confirmar_baixa_manual',
    'ef_confirmar_baixa_carga', 'ef_estornar_carga',
    'ef_confirmar_baixa_qr'
  )
ORDER BY p.proname, argumentos;

-- O evento só será entregue ao PostgREST quando COMMIT for usado.
NOTIFY pgrst, 'reload schema';

-- TESTE: ROLLBACK.
-- APLICAÇÃO: substitua apenas esta linha por COMMIT após o teste aprovado.
ROLLBACK;
