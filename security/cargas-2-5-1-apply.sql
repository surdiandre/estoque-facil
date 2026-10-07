-- Estoque Fácil — Sprint 2.5.1
-- Cargas, vínculo com saídas, snapshots para estorno, NF global única
-- e view pública agrupada por carga.
--
-- IMPORTANTE:
-- 1. Este arquivo termina em COMMIT para aplicar o bloco 2.5.1.
-- 2. Execute somente depois de conferir os diagnósticos iniciais sem linhas.
-- 3. A unicidade global da NF fica em public.cargas_nfs, uma linha por
--    documento. Não crie UNIQUE em historico_saidas.nf: várias linhas de
--    produtos da mesma NF são saídas legítimas e devem poder compartilhar
--    o mesmo número.
-- 4. A RPC QR existente insere em public.baixas_qr com NF não vazia.
--    O trigger abaixo registra a NF no mesmo índice global usado pela futura
--    RPC de carga; assim a regra também cobre o cliente QR antigo.
-- 5. A futura ef_confirmar_baixa_carga deve inserir apenas uma linha em
--    cargas_nfs por NF distinta da carga e gravar a NF em cada item de saída.
--    Ela não deve inserir a mesma NF também em baixas_qr.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Diagnóstico dos dados existentes
-- ---------------------------------------------------------------------------

-- Deve retornar zero linhas. Duplicatas aqui significam que a mesma NF já foi
-- registrada em mais de uma ordem QR (inclusive quando série/filial diferem).
SELECT
  btrim(nf) AS nf_normalizada,
  count(*) AS registros,
  string_agg(
    DISTINCT concat_ws('/', filial, serie, ordem_id),
    ' | ' ORDER BY concat_ws('/', filial, serie, ordem_id)
  ) AS referencias_qr
FROM public.baixas_qr
WHERE nullif(btrim(nf), '') IS NOT NULL
GROUP BY btrim(nf)
HAVING count(*) > 1
ORDER BY btrim(nf);

-- Deve retornar zero linhas. Repetir a NF nas linhas de itens de uma mesma
-- ordem/carga é válido; aparecer associada a ordens ou cargas diferentes não.
SELECT
  btrim(nf) AS nf_normalizada,
  count(*) AS linhas_de_itens,
  count(DISTINCT nullif(btrim(ordem_id), '')) AS ordens
FROM public.historico_saidas
WHERE nullif(btrim(nf), '') IS NOT NULL
GROUP BY btrim(nf)
HAVING count(DISTINCT nullif(btrim(ordem_id), '')) > 1
ORDER BY btrim(nf);

-- Deve retornar zero linhas para NF ausente/inválida.
-- NULL em historico_saidas é esperado para baixas manuais antigas sem campo NF;
-- aqui são listadas NF vazias em QR e strings vazias no histórico.
SELECT
  'baixas_qr'::text AS tabela,
  btrim(q.nf) AS nf,
  concat_ws('/', q.filial, q.serie, q.ordem_id) AS referencia
FROM public.baixas_qr AS q
WHERE nullif(btrim(q.nf), '') IS NULL
UNION ALL
SELECT
  'historico_saidas'::text AS tabela,
  btrim(h.nf) AS nf,
  nullif(btrim(h.ordem_id), '') AS referencia
FROM public.historico_saidas AS h
WHERE h.nf IS NOT NULL
  AND nullif(btrim(h.nf), '') IS NULL
ORDER BY tabela, nf;

DO $$
BEGIN
  IF to_regclass('public.baixas_qr') IS NULL THEN
    RAISE EXCEPTION
      'Pré-requisito ausente: public.baixas_qr. Confira security/ativar-baixa-qr.sql antes de continuar.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.baixas_qr
    WHERE nullif(btrim(nf), '') IS NULL
  ) THEN
    RAISE EXCEPTION
      'Há NF vazia em public.baixas_qr. Corrija os dados antes de instalar a unicidade global.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.baixas_qr
    GROUP BY btrim(nf)
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Há NFs repetidas em public.baixas_qr, possivelmente entre série/filial. Revise o primeiro diagnóstico antes de continuar.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.historico_saidas
    WHERE nf IS NOT NULL
      AND nullif(btrim(nf), '') IS NULL
  ) THEN
    RAISE EXCEPTION
      'Há NF vazia em public.historico_saidas. Corrija os dados antes de continuar.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.historico_saidas
    WHERE nullif(btrim(nf), '') IS NOT NULL
    GROUP BY btrim(nf)
    HAVING count(DISTINCT nullif(btrim(ordem_id), '')) > 1
  ) THEN
    RAISE EXCEPTION
      'Há uma NF associada a mais de uma ordem no histórico. Revise o segundo diagnóstico antes de continuar.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Cargas
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cargas (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo text NOT NULL UNIQUE,
  data_hora timestamptz NOT NULL,
  quem_leva text NOT NULL,
  usuario text NOT NULL,
  idempotency_key uuid UNIQUE,
  criado_em timestamptz NOT NULL DEFAULT now(),
  estornada boolean NOT NULL DEFAULT false,
  estornada_em timestamptz,
  estornada_por text,
  motivo_estorno text
);

COMMENT ON TABLE public.cargas IS
  'Cabeçalho de uma carga de saída. A chave idempotente protege a repetição da criação; dados de estorno permanecem auditáveis.';

COMMENT ON COLUMN public.cargas.idempotency_key IS
  'UUID criado antes da primeira tentativa da RPC de carga. UNIQUE permite reenvio sem criar outra carga.';

COMMENT ON COLUMN public.cargas.data_hora IS
  'Data e hora operacional da carga; pode ser retroativa e é armazenada com fuso horário.';

-- ---------------------------------------------------------------------------
-- 2. Relacionamento das saídas e dados necessários para estorno
-- ---------------------------------------------------------------------------

ALTER TABLE public.historico_saidas
  ADD COLUMN IF NOT EXISTS carga_id bigint,
  ADD COLUMN IF NOT EXISTS armazem integer,
  ADD COLUMN IF NOT EXISTS validade date,
  ADD COLUMN IF NOT EXISTS unid text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.historico_saidas'::regclass
      AND conname = 'historico_saidas_carga_id_fkey'
  ) THEN
    ALTER TABLE public.historico_saidas
      ADD CONSTRAINT historico_saidas_carga_id_fkey
      FOREIGN KEY (carga_id)
      REFERENCES public.cargas(id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_historico_saidas_carga
  ON public.historico_saidas (carga_id)
  WHERE carga_id IS NOT NULL;

COMMENT ON COLUMN public.historico_saidas.armazem IS
  'Snapshot do armazém da pilha no momento da saída, usado para restaurar o estoque em um estorno.';

COMMENT ON COLUMN public.historico_saidas.validade IS
  'Snapshot da validade da pilha no momento da saída, usado para restaurar o estoque em um estorno.';

-- ---------------------------------------------------------------------------
-- 3. Registro global: uma linha por NF, independente de origem/série/filial
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cargas_nfs (
  nf text PRIMARY KEY
    CHECK (nf <> '' AND nf = btrim(nf)),
  carga_id bigint REFERENCES public.cargas(id),
  origem text NOT NULL
    CHECK (origem IN ('carga', 'qr', 'legado')),
  ordem_id text,
  filial text,
  serie text,
  criado_em timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cargas_nfs IS
  'Registro único de NFs já usadas em baixas. Uma linha por NF, mesmo quando a NF contém vários itens.';

COMMENT ON COLUMN public.cargas_nfs.carga_id IS
  'Carga que registrou a NF. NULL em registros QR antigos que ainda não pertencem a uma carga agrupada.';

ALTER TABLE public.cargas_nfs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.cargas_nfs
  FROM PUBLIC, anon, authenticated, service_role;

-- Backfill: QR existentes (uma linha por ordem/NF) e NFs do histórico.
-- Linhas de itens repetidas com a mesma NF resultam em somente um registro.
INSERT INTO public.cargas_nfs
  (nf, carga_id, origem, ordem_id, filial, serie, criado_em)
SELECT DISTINCT ON (btrim(q.nf))
  btrim(q.nf),
  NULL,
  'qr',
  nullif(btrim(q.ordem_id), ''),
  nullif(btrim(q.filial), ''),
  nullif(btrim(q.serie), ''),
  q.criado_em
FROM public.baixas_qr AS q
WHERE nullif(btrim(q.nf), '') IS NOT NULL
ORDER BY btrim(q.nf), q.criado_em, q.ordem_id
ON CONFLICT (nf) DO NOTHING;

INSERT INTO public.cargas_nfs
  (nf, carga_id, origem, ordem_id)
SELECT
  btrim(h.nf),
  max(h.carga_id),
  'legado',
  min(nullif(btrim(h.ordem_id), ''))
FROM public.historico_saidas AS h
WHERE nullif(btrim(h.nf), '') IS NOT NULL
GROUP BY btrim(h.nf)
ON CONFLICT (nf) DO NOTHING;

-- O RPC QR atual insere primeiro em baixas_qr e depois processa os itens.
-- Este trigger registra a NF global antes de qualquer item ser baixado.
-- Uma repetição com a mesma NF falha pela PK de cargas_nfs, mesmo se mudar
-- série/filial. A transação do RPC antigo desfaz o insert e todas as baixas.
CREATE OR REPLACE FUNCTION public.ef_registrar_nf_global_baixa_qr()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_nf text;
BEGIN
  v_nf := nullif(pg_catalog.btrim(NEW.nf), '');

  IF v_nf IS NULL THEN
    RAISE EXCEPTION 'Informe uma NF válida antes de confirmar a baixa QR.';
  END IF;

  NEW.nf := v_nf;

  INSERT INTO public.cargas_nfs
    (nf, carga_id, origem, ordem_id, filial, serie)
  VALUES (
    v_nf,
    NULL,
    'qr',
    nullif(pg_catalog.btrim(NEW.ordem_id), ''),
    nullif(pg_catalog.btrim(NEW.filial), ''),
    nullif(pg_catalog.btrim(NEW.serie), '')
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.ef_registrar_nf_global_baixa_qr()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_baixas_qr_nf_global
  ON public.baixas_qr;

CREATE TRIGGER trg_baixas_qr_nf_global
BEFORE INSERT ON public.baixas_qr
FOR EACH ROW
EXECUTE FUNCTION public.ef_registrar_nf_global_baixa_qr();

-- ---------------------------------------------------------------------------
-- 4. RLS e privilégios de cargas
-- ---------------------------------------------------------------------------

ALTER TABLE public.cargas ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.cargas
  FROM PUBLIC, anon, authenticated, service_role;

-- A view invoker precisa ler somente estas colunas. Usuario, idempotency_key,
-- estornada_por e criado_em não recebem privilégio SELECT para os clientes.
GRANT SELECT (id, codigo, data_hora, quem_leva, estornada, estornada_em)
  ON TABLE public.cargas TO anon, authenticated;

-- Escrita limitada ao administrador. Campos de estorno só serão alterados
-- pela RPC SECURITY DEFINER do sub-bloco 2.5.4.
GRANT INSERT (codigo, data_hora, quem_leva, usuario, idempotency_key)
  ON TABLE public.cargas TO authenticated;
GRANT UPDATE (data_hora, quem_leva)
  ON TABLE public.cargas TO authenticated;

DO $$
DECLARE
  v_sequence text;
BEGIN
  v_sequence := pg_catalog.pg_get_serial_sequence('public.cargas', 'id');
  IF v_sequence IS NOT NULL THEN
    EXECUTE pg_catalog.format(
      'REVOKE ALL ON SEQUENCE %s FROM PUBLIC, anon, authenticated, service_role',
      v_sequence
    );
    EXECUTE pg_catalog.format(
      'GRANT USAGE ON SEQUENCE %s TO authenticated',
      v_sequence
    );
  END IF;
END;
$$;

DROP POLICY IF EXISTS ef_cargas_public_read ON public.cargas;
CREATE POLICY ef_cargas_public_read
  ON public.cargas
  FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS ef_cargas_admin_insert ON public.cargas;
CREATE POLICY ef_cargas_admin_insert
  ON public.cargas
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (SELECT auth.jwt() ->> 'email') = 'balancacoperacel1@gmail.com'
  );

DROP POLICY IF EXISTS ef_cargas_admin_update ON public.cargas;
CREATE POLICY ef_cargas_admin_update
  ON public.cargas
  FOR UPDATE
  TO authenticated
  USING (
    (SELECT auth.jwt() ->> 'email') = 'balancacoperacel1@gmail.com'
  )
  WITH CHECK (
    (SELECT auth.jwt() ->> 'email') = 'balancacoperacel1@gmail.com'
  );

-- A view security_invoker também precisa ler estas colunas. Os snapshots
-- armazem/validade e campos usuario/idempotency_key/saldo_resultante não são
-- concedidos por este bloco.
GRANT SELECT (id, carga_id, nf, produto, lote, pilha, qtd, unid)
  ON TABLE public.historico_saidas TO anon, authenticated;

DROP POLICY IF EXISTS ef_carga_saidas_public_read
  ON public.historico_saidas;
CREATE POLICY ef_carga_saidas_public_read
  ON public.historico_saidas
  FOR SELECT
  TO anon, authenticated
  USING (carga_id IS NOT NULL);

-- ---------------------------------------------------------------------------
-- 5. View pública: uma linha por carga, com itens agrupados
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.ef_cargas_public
WITH (security_invoker = true)
AS
SELECT
  c.id AS carga_id,
  c.codigo,
  c.data_hora,
  c.quem_leva,
  CASE WHEN c.estornada THEN 'ESTORNADA' ELSE 'ATIVA' END AS status_estorno,
  c.estornada_em,
  COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'nf', hs.nf,
        'produto', hs.produto,
        'lote', hs.lote,
        'pilha', hs.pilha,
        'qtd', hs.qtd,
        'unid', hs.unid
      )
      ORDER BY hs.id
    ) FILTER (WHERE hs.id IS NOT NULL),
    '[]'::jsonb
  ) AS itens
FROM public.cargas AS c
LEFT JOIN public.historico_saidas AS hs
  ON hs.carga_id = c.id
GROUP BY
  c.id,
  c.codigo,
  c.data_hora,
  c.quem_leva,
  c.estornada,
  c.estornada_em;

COMMENT ON VIEW public.ef_cargas_public IS
  'View security_invoker para leitura agrupada de cargas. Não retorna usuario, idempotency_key nem estornada_por.';

REVOKE ALL ON TABLE public.ef_cargas_public
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.ef_cargas_public TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Verificações
-- ---------------------------------------------------------------------------

-- Colunas da carga e snapshots.
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'cargas' AND column_name IN (
      'id', 'codigo', 'data_hora', 'quem_leva', 'usuario',
      'idempotency_key', 'criado_em', 'estornada',
      'estornada_em', 'estornada_por', 'motivo_estorno'
    ))
    OR
    (table_name = 'historico_saidas' AND column_name IN (
      'carga_id', 'armazem', 'validade', 'unid'
    ))
    OR
    (table_name = 'cargas_nfs' AND column_name IN (
      'nf', 'carga_id', 'origem', 'ordem_id', 'filial', 'serie', 'criado_em'
    ))
  )
ORDER BY table_name, ordinal_position;

-- Índices/constraints: cargos.idempotency_key e cargas_nfs.nf devem ser únicos.
SELECT tablename, indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('cargas', 'cargas_nfs', 'historico_saidas')
  AND indexname IN (
    'cargas_pkey',
    'cargas_codigo_key',
    'cargas_idempotency_key_key',
    'cargas_nfs_pkey',
    'idx_historico_saidas_carga'
  )
ORDER BY tablename, indexname;

-- A trigger deve estar anexada à tabela usada pela RPC QR antiga.
SELECT
  t.tgname AS trigger_name,
  t.tgenabled AS enabled,
  c.relname AS table_name
FROM pg_catalog.pg_trigger AS t
JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'baixas_qr'
  AND t.tgname = 'trg_baixas_qr_nf_global'
  AND NOT t.tgisinternal;

-- Privacidade: ambos devem ser false para anon/authenticated.
SELECT
  has_column_privilege('anon', 'public.cargas', 'usuario', 'SELECT')
    AS anon_le_usuario_carga,
  has_column_privilege('anon', 'public.cargas', 'idempotency_key', 'SELECT')
    AS anon_le_idempotency_carga,
  has_column_privilege('authenticated', 'public.cargas', 'usuario', 'SELECT')
    AS authenticated_le_usuario_carga,
  has_column_privilege('authenticated', 'public.cargas', 'idempotency_key', 'SELECT')
    AS authenticated_le_idempotency_carga,
  has_table_privilege('anon', 'public.ef_cargas_public', 'SELECT')
    AS anon_le_view,
  has_table_privilege('authenticated', 'public.ef_cargas_public', 'SELECT')
    AS authenticated_le_view;

-- RESULTADO ESPERADO:
-- * Diagnósticos iniciais sem linhas.
-- * Colunas, índice de carga e FK presentes.
-- * Trigger trg_baixas_qr_nf_global habilitada.
-- * anon/authenticated_le_view = true.
-- * Campos usuario/idempotency_key da tabela cargas = false para SELECT.

-- Aplicação real do bloco 2.5.1.
COMMIT;

-- ---------------------------------------------------------------------------
-- Rollback manual APÓS uma aplicação futura com COMMIT
-- ---------------------------------------------------------------------------
-- Só execute este rollback antes de usar cargas reais. Depois de haver
-- movimentações, exporte/preserve os registros de cargas_nfs e as saídas.
-- Não remova armazem/validade/unid caso a coluna já existisse antes desta
-- migração ou já contenha snapshots usados em estornos.
--
-- BEGIN;
-- DROP VIEW IF EXISTS public.ef_cargas_public;
-- DROP TRIGGER IF EXISTS trg_baixas_qr_nf_global ON public.baixas_qr;
-- DROP FUNCTION IF EXISTS public.ef_registrar_nf_global_baixa_qr();
-- DROP POLICY IF EXISTS ef_carga_saidas_public_read ON public.historico_saidas;
-- DROP POLICY IF EXISTS ef_cargas_public_read ON public.cargas;
-- DROP POLICY IF EXISTS ef_cargas_admin_insert ON public.cargas;
-- DROP POLICY IF EXISTS ef_cargas_admin_update ON public.cargas;
-- DROP TABLE IF EXISTS public.cargas_nfs;
-- ALTER TABLE public.historico_saidas DROP COLUMN IF EXISTS carga_id;
-- -- Só se criadas por esta migração e ainda sem dados que devam ser preservados:
-- -- ALTER TABLE public.historico_saidas DROP COLUMN IF EXISTS armazem;
-- -- ALTER TABLE public.historico_saidas DROP COLUMN IF EXISTS validade;
-- -- ALTER TABLE public.historico_saidas DROP COLUMN IF EXISTS unid;
-- DROP TABLE IF EXISTS public.cargas;
-- COMMIT;
