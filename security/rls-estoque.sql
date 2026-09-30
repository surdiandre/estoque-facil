-- Estoque Fácil: políticas para visualização pública e escrita da conta administrativa.
-- Execute no SQL Editor do projeto Supabase SOMENTE depois de revisar o resultado
-- de security/inspecionar-acesso.sql. Esta migração para se encontrar políticas
-- existentes de outro nome: políticas permissivas antigas poderiam liberar escrita.

begin;

do $$
declare tabela text;
begin
  foreach tabela in array array['estoque','historico_entradas','historico_saidas'] loop
    if to_regclass(format('public.%I', tabela)) is null then
      raise exception 'Tabela public.% não encontrada. Confira o esquema antes de continuar.', tabela;
    end if;
    if exists (
      select 1 from pg_policies
      where schemaname='public' and tablename=tabela
        and policyname not in ('ef_public_read','ef_admin_insert','ef_admin_update','ef_admin_delete')
    ) then
      raise exception 'public.% possui políticas preexistentes. Revise-as antes de aplicar esta migração.', tabela;
    end if;
  end loop;
end $$;

alter table public.estoque enable row level security;
alter table public.historico_entradas enable row level security;
alter table public.historico_saidas enable row level security;

revoke all on public.estoque, public.historico_entradas, public.historico_saidas from anon, authenticated;
grant select on public.estoque, public.historico_entradas, public.historico_saidas to anon, authenticated;
grant insert, update, delete on public.estoque, public.historico_entradas, public.historico_saidas to authenticated;

do $$
declare tabela text;
begin
  foreach tabela in array array['estoque','historico_entradas','historico_saidas'] loop
    execute format('drop policy if exists ef_public_read on public.%I', tabela);
    execute format('drop policy if exists ef_admin_insert on public.%I', tabela);
    execute format('drop policy if exists ef_admin_update on public.%I', tabela);
    execute format('drop policy if exists ef_admin_delete on public.%I', tabela);
    execute format('create policy ef_public_read on public.%I for select to anon, authenticated using (true)', tabela);
    execute format(
      'create policy ef_admin_insert on public.%I for insert to authenticated with check ((select auth.jwt()->>''email'') = ''balancacoperacel1@gmail.com'')', tabela
    );
    execute format(
      'create policy ef_admin_update on public.%I for update to authenticated using ((select auth.jwt()->>''email'') = ''balancacoperacel1@gmail.com'') with check ((select auth.jwt()->>''email'') = ''balancacoperacel1@gmail.com'')', tabela
    );
    execute format(
      'create policy ef_admin_delete on public.%I for delete to authenticated using ((select auth.jwt()->>''email'') = ''balancacoperacel1@gmail.com'')', tabela
    );
  end loop;
end $$;

commit;
