-- Estoque Fácil: ativar baixa atômica por QR. Execute uma vez no SQL Editor do Supabase.
-- Revise o e-mail do administrador e faça um backup antes de executar em produção.
begin;

alter table public.historico_saidas add column if not exists nf text;
alter table public.historico_saidas add column if not exists ordem_id text;

create table if not exists public.baixas_qr (
  id bigint generated always as identity primary key,
  ordem_id text not null unique,
  filial text not null,
  serie text not null default '',
  nf text not null,
  usuario text not null,
  criado_em timestamptz not null default now(),
  constraint baixas_qr_nf_unica unique (filial, serie, nf)
);
alter table public.baixas_qr enable row level security;
revoke all on public.baixas_qr from anon, authenticated;
grant select, insert on public.baixas_qr to authenticated;
grant usage on sequence public.baixas_qr_id_seq to authenticated;
drop policy if exists ef_qr_admin_read on public.baixas_qr;
drop policy if exists ef_qr_admin_insert on public.baixas_qr;
create policy ef_qr_admin_read on public.baixas_qr for select to authenticated
 using ((select auth.jwt()->>'email')='balancacoperacel1@gmail.com');
create policy ef_qr_admin_insert on public.baixas_qr for insert to authenticated
 with check ((select auth.jwt()->>'email')='balancacoperacel1@gmail.com');

create or replace function public.ef_confirmar_baixa_qr(
 p_ordem text, p_nf text, p_filial text, p_serie text, p_itens jsonb
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 entry jsonb;
 stock public.estoque%rowtype;
 stock_id bigint;
 quantity numeric;
 item_count integer:=0;
 user_email text:=auth.jwt()->>'email';
begin
 if user_email is distinct from 'balancacoperacel1@gmail.com' then
   raise exception 'Acesso administrativo obrigatório.';
 end if;
 if nullif(btrim(p_ordem),'') is null or nullif(btrim(p_nf),'') is null or nullif(btrim(p_filial),'') is null
    or length(p_ordem)>100 or length(p_nf)>50 or length(p_filial)>50 or length(coalesce(p_serie,''))>50 then
   raise exception 'Identificação da ordem inválida.';
 end if;
 if jsonb_typeof(p_itens) is distinct from 'array' then raise exception 'Itens da ordem inválidos.'; end if;
 if jsonb_array_length(p_itens) not between 1 and 50 then raise exception 'Quantidade de itens inválida.'; end if;
 -- A chave da ordem e a identificação da NF impedem uma segunda baixa.
 insert into public.baixas_qr(ordem_id,filial,serie,nf,usuario)
 values (btrim(p_ordem),btrim(p_filial),btrim(coalesce(p_serie,'')),btrim(p_nf),user_email);

 for entry in select value from jsonb_array_elements(p_itens) loop
   stock_id:=(entry->>'estoque_id')::bigint;
   quantity:=(entry->>'qtd')::numeric;
   if stock_id is null or quantity is null or quantity<>trunc(quantity) or quantity<1 then
     raise exception 'Quantidade ou pilha inválida.';
   end if;
   select * into stock from public.estoque where id=stock_id for update;
   if not found then raise exception 'Pilha % não encontrada. Atualize o estoque.',stock_id; end if;
   if upper(btrim(stock.produto))<>upper(btrim(coalesce(entry->>'produto','')))
      or upper(btrim(stock.lote))<>upper(btrim(coalesce(entry->>'lote','')))
      or upper(btrim(stock.unid))<>upper(btrim(coalesce(entry->>'unid',''))) then
     raise exception 'Produto, lote ou unidade não conferem com a pilha %.',stock_id;
   end if;
   if stock.qtd<quantity then raise exception 'Saldo insuficiente na pilha %.',stock.pilha; end if;
   insert into public.historico_saidas(data,produto,empresa,lote,pilha,qtd,unid,usuario,nf,ordem_id)
   values (current_date,stock.produto,coalesce(stock.empresa,''),stock.lote,stock.pilha,quantity,stock.unid,user_email,btrim(p_nf),btrim(p_ordem));
   if stock.qtd=quantity then
     delete from public.estoque where id=stock_id;
   else
     update public.estoque set qtd=stock.qtd-quantity where id=stock_id;
   end if;
   item_count:=item_count+1;
 end loop;
 return jsonb_build_object('nf',p_nf,'ordem',p_ordem,'itens',item_count);
end $$;
revoke all on function public.ef_confirmar_baixa_qr(text,text,text,text,jsonb) from public,anon;
grant execute on function public.ef_confirmar_baixa_qr(text,text,text,text,jsonb) to authenticated;
commit;
