-- Execute antes de apagar os lotes antigos.
-- Corrige os nomes divergentes do relatório usando os códigos permanentes.
-- Não substitui links nem dados já preenchidos no cadastro.
begin;
with mapa(codigo, nome_antigo) as (
  values
    ('4', 'ACTELLIC 500 EC - 4X5 LT'),
    ('2409', 'ALADE'),
    ('607', 'AMPLIGO - 4X5 LT'),
    ('2432', 'APROCH POWER 10 LT')
), origem as (
  select mapa.codigo,
    (select s.bula_url
     from public.estoque s
     where upper(btrim(s.produto)) = mapa.nome_antigo
       and nullif(btrim(s.bula_url), '') is not null
     order by s.id desc limit 1) as bula_url,
    (select to_jsonb(s)->'bula_dados'
     from public.estoque s
     where upper(btrim(s.produto)) = mapa.nome_antigo
       and jsonb_typeof(to_jsonb(s)->'bula_dados') = 'object'
       and to_jsonb(s)->'bula_dados' <> '{}'::jsonb
     order by s.id desc limit 1) as dados
  from mapa
)
update public.ef_produtos_codigos as cadastro
set bula_url = coalesce(nullif(btrim(cadastro.bula_url), ''), nullif(btrim(origem.bula_url), '')),
    bula_dados = case
      when cadastro.bula_dados is not null and cadastro.bula_dados <> '{}'::jsonb
        then cadastro.bula_dados
      when jsonb_typeof(origem.dados) = 'object'
        then origem.dados
      else '{}'::jsonb
    end
from origem
where cadastro.codigo = origem.codigo;

select codigo, produto,
       nullif(btrim(bula_url), '') is not null as pdf_vinculado,
       bula_dados is not null and bula_dados <> '{}'::jsonb as dados_vinculados
from public.ef_produtos_codigos
where codigo in ('4', '2409', '607', '2432')
order by codigo::integer;
commit;
