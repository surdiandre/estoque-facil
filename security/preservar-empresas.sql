-- Execute antes de excluir os lotes antigos. Pode ser executado novamente.
alter table public.ef_produtos_codigos add column if not exists empresa text;

-- Copia empresas de produtos cujo nome já é igual no catálogo e no estoque.
update public.ef_produtos_codigos as cadastro
set empresa = antigo.empresa
from (
  select distinct on (upper(btrim(produto))) upper(btrim(produto)) as nome, empresa
  from public.estoque
  where nullif(btrim(empresa), '') is not null
  order by upper(btrim(produto)), id desc
) antigo
where upper(btrim(cadastro.produto)) = antigo.nome
  and nullif(btrim(cadastro.empresa), '') is null;

-- Quatro nomes antigos conhecidos que diferem do relatório da empresa.
with mapa(codigo, nome_antigo) as (
  values ('4','ACTELLIC 500 EC - 4X5 LT'), ('2409','ALADE'),
         ('607','AMPLIGO - 4X5 LT'), ('2432','APROCH POWER 10 LT')
)
update public.ef_produtos_codigos as cadastro
set empresa = (
  select estoque.empresa from public.estoque
  where upper(btrim(estoque.produto)) = mapa.nome_antigo
    and nullif(btrim(estoque.empresa), '') is not null
  order by estoque.id desc limit 1
)
from mapa
where cadastro.codigo = mapa.codigo
  and nullif(btrim(cadastro.empresa), '') is null
  and exists (
    select 1 from public.estoque
    where upper(btrim(estoque.produto)) = mapa.nome_antigo
      and nullif(btrim(estoque.empresa), '') is not null
  );
