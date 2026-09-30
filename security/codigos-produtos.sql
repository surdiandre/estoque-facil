-- Execute no SQL Editor do projeto Supabase do Estoque Fácil.
-- O código é texto para preservar zeros à esquerda.
create table if not exists public.ef_produtos_codigos (
  codigo text primary key check (codigo ~ '^[0-9]{1,16}$'),
  produto text not null unique check (length(btrim(produto)) > 0),
  empresa text,
  bula_url text,
  bula_dados jsonb not null default '{}'::jsonb
);
alter table public.ef_produtos_codigos add column if not exists bula_url text;
alter table public.ef_produtos_codigos add column if not exists bula_dados jsonb not null default '{}'::jsonb;
alter table public.ef_produtos_codigos add column if not exists empresa text;
alter table public.ef_produtos_codigos enable row level security;
grant select on public.ef_produtos_codigos to anon, authenticated;
grant insert, update, delete on public.ef_produtos_codigos to authenticated;
drop policy if exists ef_codigos_leitura on public.ef_produtos_codigos;
drop policy if exists ef_codigos_escrita on public.ef_produtos_codigos;
create policy ef_codigos_leitura on public.ef_produtos_codigos
for select to anon, authenticated using (true);
create policy ef_codigos_escrita on public.ef_produtos_codigos
for all to authenticated
using ((select auth.jwt()->>'email') = 'balancacoperacel1@gmail.com')
with check ((select auth.jwt()->>'email') = 'balancacoperacel1@gmail.com');
