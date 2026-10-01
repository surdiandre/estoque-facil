-- Observações internas reutilizáveis por número de NF.
-- Execute uma única vez no Supabase SQL Editor.
create table if not exists public.ef_observacoes_nf (
  referencia text primary key check (length(referencia) between 1 and 80),
  observacao text not null check (length(observacao) between 1 and 500),
  usuario text not null,
  atualizado_em timestamptz not null default now()
);

alter table public.ef_observacoes_nf enable row level security;
revoke all on table public.ef_observacoes_nf from anon, authenticated;
grant select, insert, update on table public.ef_observacoes_nf to authenticated;

drop policy if exists "admin consulta observacoes nf" on public.ef_observacoes_nf;
create policy "admin consulta observacoes nf"
  on public.ef_observacoes_nf for select to authenticated
  using (lower(auth.jwt() ->> 'email') = 'balancacoperacel1@gmail.com');

drop policy if exists "admin cria observacoes nf" on public.ef_observacoes_nf;
create policy "admin cria observacoes nf"
  on public.ef_observacoes_nf for insert to authenticated
  with check (lower(auth.jwt() ->> 'email') = 'balancacoperacel1@gmail.com');

drop policy if exists "admin altera observacoes nf" on public.ef_observacoes_nf;
create policy "admin altera observacoes nf"
  on public.ef_observacoes_nf for update to authenticated
  using (lower(auth.jwt() ->> 'email') = 'balancacoperacel1@gmail.com')
  with check (lower(auth.jwt() ->> 'email') = 'balancacoperacel1@gmail.com');
