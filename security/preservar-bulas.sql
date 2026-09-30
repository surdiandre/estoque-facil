-- Execute uma vez antes de apagar os registros antigos de estoque.
alter table public.ef_produtos_codigos add column if not exists bula_url text;
alter table public.ef_produtos_codigos add column if not exists bula_dados jsonb not null default '{}'::jsonb;

-- Copia os links de bulas já existentes para o cadastro permanente do código.
update public.ef_produtos_codigos as cadastro
set bula_url = antigo.bula_url
from (
  select distinct on (upper(btrim(produto))) upper(btrim(produto)) as nome, bula_url
  from public.estoque
  where nullif(btrim(bula_url), '') is not null
  order by upper(btrim(produto)), id desc
) as antigo
where upper(btrim(cadastro.produto)) = antigo.nome
  and nullif(btrim(cadastro.bula_url), '') is null;
