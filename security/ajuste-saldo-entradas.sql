-- Execute uma vez no SQL Editor. Ajustes e entradas em pilhas existentes
-- são feitos em uma transação, com trava da linha e histórico.
begin;
create table if not exists public.ef_ajustes_saldo (
  id bigint generated always as identity primary key,
  criado_em timestamptz not null default now(),
  estoque_id bigint not null,
  produto text not null,
  lote text not null,
  pilha text not null,
  armazem integer not null,
  saldo_anterior numeric not null,
  saldo_novo numeric not null,
  motivo text not null,
  usuario text not null
);
alter table public.ef_ajustes_saldo enable row level security;
alter table public.historico_entradas add column if not exists referencia text;
revoke all on public.ef_ajustes_saldo from anon, authenticated;
grant select on public.ef_ajustes_saldo to authenticated;
drop policy if exists ef_admin_read_adjustments on public.ef_ajustes_saldo;
create policy ef_admin_read_adjustments on public.ef_ajustes_saldo
  for select to authenticated using ((select auth.jwt()->>'email') = 'balancacoperacel1@gmail.com');

-- Remove a assinatura anterior para não deixar duas RPCs ambíguas no PostgREST.
drop function if exists public.ef_alterar_saldo(bigint,text,integer,text,text,numeric);

-- Preserva o retorno numeric existente; somente a validade foi adicionada.
create or replace function public.ef_alterar_saldo(
  p_id bigint,
  p_modo text,
  p_quantidade integer,
  p_motivo text default null,
  p_referencia text default null,
  p_saldo_esperado numeric default null,
  p_validade date default null
)
returns numeric language plpgsql security definer set search_path = '' as $$
declare v public.estoque%rowtype; v_novo numeric; v_email text;
begin
  v_email := auth.jwt()->>'email';
  if auth.uid() is null or v_email is distinct from 'balancacoperacel1@gmail.com' then
    raise exception 'Acesso administrativo obrigatório.';
  end if;
  if p_modo is null or p_modo not in ('entrada','ajuste') or p_quantidade is null or p_quantidade < 0
     or (p_modo='entrada' and p_quantidade=0) then
    raise exception 'Quantidade inválida.';
  end if;
  if length(coalesce(p_referencia,''))>80 then raise exception 'Referência muito longa.'; end if;
  if p_modo='ajuste' and (length(btrim(coalesce(p_motivo,''))) < 4 or length(p_motivo)>300) then
    raise exception 'Informe o motivo do ajuste (4 a 300 caracteres).';
  end if;
  select * into v from public.estoque where id=p_id for update;
  if not found then raise exception 'Pilha não encontrada. Atualize o estoque.'; end if;
  if p_saldo_esperado is not null and v.qtd is distinct from p_saldo_esperado then
    raise exception 'Saldo mudou desde a consulta. Atualize o estoque e confira novamente.';
  end if;
  v_novo := case when p_modo='entrada' then v.qtd+p_quantidade else p_quantidade end;
  if p_modo='ajuste' and v_novo=v.qtd then raise exception 'O saldo contado já é igual ao saldo atual.'; end if;
  update public.estoque
  set qtd=v_novo,
      validade=case when p_modo='entrada' and p_validade is not null then p_validade else v.validade end
  where id=p_id;
  if p_modo='entrada' then
    insert into public.historico_entradas (data,produto,lote,pilha,qtd,unid,empresa,usuario,referencia)
    values ((now() at time zone 'America/Sao_Paulo')::date,v.produto,v.lote,v.pilha,p_quantidade,v.unid,coalesce(v.empresa,''),v_email,nullif(btrim(p_referencia),''));
  else
    insert into public.ef_ajustes_saldo (estoque_id,produto,lote,pilha,armazem,saldo_anterior,saldo_novo,motivo,usuario)
    values (v.id,v.produto,v.lote,v.pilha,v.armazem,v.qtd,v_novo,btrim(p_motivo),v_email);
  end if;
  return v_novo;
end $$;
revoke all on function public.ef_alterar_saldo(bigint,text,integer,text,text,numeric,date) from public,anon;
grant execute on function public.ef_alterar_saldo(bigint,text,integer,text,text,numeric,date) to authenticated;
commit;
