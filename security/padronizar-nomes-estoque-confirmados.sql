-- Padroniza SOMENTE os 45 nomes marcados CONFIRMAR na planilha de revisão.
-- Os 15 marcados NÃO ALTERAR ficam intactos. Não altera lote, pilha, quantidade, empresa ou validade.
-- Requer primeiro a importação do catálogo de 165 produtos por código.
begin;
alter table public.ef_produtos_codigos add column if not exists empresa text;
alter table public.ef_produtos_codigos add column if not exists bula_url text;
alter table public.ef_produtos_codigos add column if not exists bula_dados jsonb not null default '{}'::jsonb;
create temporary table ef_nomes_seguros (
  antigo text primary key, codigo text not null, nome_sistema text not null
) on commit drop;
insert into ef_nomes_seguros (antigo,codigo,nome_sistema) values
  ('.+AERIS - 4X5 LT','5323','+AERIS 5LT'),
  ('.+CA - 4X5 LT','5158','+CA 5 LT'),
  ('.+MIX PRO - 20 LT','5373','+MIX PRO 20L'),
  ('.+MOL - 4X5 LT','5334','+MOL 5L'),
  ('ACQUAMAX FULL+ - 1LT','5805','ACQUAMAX FULL+ 01 LT'),
  ('ADITIVO INOC. CRI-S - 20 LT','5324','ADITIVO INOC CRI-S BLD 20L'),
  ('ADITIVO INOC. POWER MAX - 20 LT','5326','ADITIVO INOC POWER MAX BLD 20L'),
  ('ALL-OK - 4X5','5394','ALL-OK 5LT'),
  ('AUREO EC 720 - 4X5 LT','667','AUREO GL 5 LT'),
  ('BIAGRO IMPACTO - 2X5LT','5514','BIAGRO IMPACTO 5LT'),
  ('BIOATTACK - 4X5LT','5724','BIOATTACK 5LT'),
  ('BIOMA BRADY SOJA - 2LT 40DS','2267','BIOMA BRADY SOJA 2 LT 40 DOSES'),
  ('BIOTRIO LIQ - 4X5 LT','5641','BIOTRIO LIQ 5LT'),
  ('BLEND - 12X1 LT','2316','BLEND 1 LT'),
  ('CONCORDE - 20 LT','2051','CONCORDE FERTIL 20 LT'),
  ('CONNECT - 4X5 LT','368','CONNECT 5 LT'),
  ('DS DRY - 12X1 KG','2321','DS DRY 1 KG'),
  ('ENCHIMENTO - 4X5 LT','5510','ENCHIMENTO 5LT'),
  ('EXTRAVON - 4X5 LT','5329','EXTRAVON 5L'),
  ('INOC. AZOMAX PLUS - 6X3 LT','5467','INOC AZOMAX 3,0 LT'),
  ('INOC. AZOMAX PLUS - 6X3 LT AMOSTRA','5467','INOC AZOMAX 3,0 LT'),
  ('INOC. UTRISHA N SACO - 2X5KG','5502','INOC UTRISHA SC 5KG'),
  ('INOC.LIQ SOJA OPTIMIZE PCT 10LT','5325','INOC LIQ SOJA OPTIMIZE PCT 10L'),
  ('INTREPID240SC - 4X5 LT','5466','INTREPID240SC 5 LT'),
  ('KEYRA - 4X5 LT','5556','KEYRA 5 LT'),
  ('MEES - 4X5 LT','2306','MEES 5 LT'),
  ('MICROGEO - 25 KG','2250','MICROGEO SACO 25 KG'),
  ('NUTRIL MOLIBDENIO 270 - GL 5 LT','5256','NUTRIL MOLIBDENIO 270 GL 05 LT'),
  ('OCHIMA - 4X5 LT','2260','OCHIMA 5 LT'),
  ('OLEO MINERAL LUBROPPA - 20 LT','5225','OLEO MINERAL LUBROPPA BD 20LT'),
  ('POLIMERO ADESIVO COLORSEED VERDE - 20LT','5698','POLIMERO ADESIVO COLORSEED INTENSIVE VERDE 20LT'),
  ('POLYDRY GRAF - 4X5KG','5699','POLYDRY GRAF 5KG'),
  ('POLYTEK LIQUID RED - 20 LT','5315','POLYTEK LIQUID RED PB 20L BR'),
  ('RASS 32 12X1','379','RASS 32 1 LT'),
  ('REVERB - 4X5 LT BRA','5658','REVERB 4X5 L BRA'),
  ('RIZOLIQ LLI BR X 10LT','5239','RIZOLIQ LLI BR X 10 L'),
  ('SIGNAL - 3X5 LT','2323','SIGNAL 05 LT'),
  ('SPIN - 1X12 LT','2234','SPIN 1LT'),
  ('TA 35 - 12X1 LT','5151','TA 35 LT'),
  ('TA 35 ULTRA 4X5 LT','386','TA 35 ULTRA 5LT'),
  ('TS BIO PRIME','5677','TSBIO PRIME 1LT'),
  ('TSBIO PRIME - 12X1LT','5677','TSBIO PRIME 1LT'),
  ('XTEND PROTEC COPACK - 2X10 LT','5392','XTEND PROTEC COPACK BR BLD 10 LT'),
  ('XTEND PROTECT 2 MAX 2X10','5766','XTEND PROTECT 2 MAX 2 10 LT'),
  ('ZAPP PRO QI 620 - 20 LT','469','ZAPP PRO 20L BRA');

-- Exige que cada código corresponda a um único cadastro com o nome aprovado.
create temporary table ef_alvos as
select s.id, s.produto as antigo, m.codigo, m.nome_sistema
from public.estoque s
join ef_nomes_seguros m on upper(btrim(s.produto))=upper(btrim(m.antigo))
join public.ef_produtos_codigos c
  on coalesce(nullif(ltrim(c.codigo,'0'),''),'0')=m.codigo
 and upper(btrim(c.produto))=upper(btrim(m.nome_sistema))
where not exists (
  select 1 from public.ef_produtos_codigos outra
  where outra.codigo<>c.codigo
    and coalesce(nullif(ltrim(outra.codigo,'0'),''),'0')=m.codigo
);

-- Cópia dos nomes atuais para conferência e eventual reversão.
create schema if not exists ef_migracoes;
create table if not exists ef_migracoes.nomes_estoque_revisados_20260929 as
select s.id, s.produto as nome_anterior, now() as criado_em
from public.estoque s
join ef_nomes_seguros m on upper(btrim(s.produto))=upper(btrim(m.antigo));

-- Guarda os metadados antigos que ainda estiverem apenas nas linhas de estoque.
update public.ef_produtos_codigos as c
set empresa=coalesce(nullif(btrim(c.empresa),''),(
      select s.empresa from public.estoque s join ef_alvos a on a.id=s.id
      where a.codigo=coalesce(nullif(ltrim(c.codigo,'0'),''),'0')
        and nullif(btrim(s.empresa),'') is not null
      order by s.id desc limit 1)),
    bula_url=coalesce(nullif(btrim(c.bula_url),''),(
      select s.bula_url from public.estoque s join ef_alvos a on a.id=s.id
      where a.codigo=coalesce(nullif(ltrim(c.codigo,'0'),''),'0')
        and nullif(btrim(s.bula_url),'') is not null
      order by s.id desc limit 1)),
    bula_dados=case when c.bula_dados is not null and c.bula_dados<>'{}'::jsonb
      then c.bula_dados else coalesce((
      select to_jsonb(s)->'bula_dados' from public.estoque s
      join ef_alvos a on a.id=s.id
      where a.codigo=coalesce(nullif(ltrim(c.codigo,'0'),''),'0')
        and jsonb_typeof(to_jsonb(s)->'bula_dados')='object'
        and to_jsonb(s)->'bula_dados'<>'{}'::jsonb
      order by s.id desc limit 1),'{}'::jsonb) end
where exists (select 1 from ef_alvos a
              where a.codigo=coalesce(nullif(ltrim(c.codigo,'0'),''),'0'));

update public.estoque as s
set produto=a.nome_sistema
from ef_alvos a
where s.id=a.id and s.produto=a.antigo and s.produto<>a.nome_sistema;

select (select count(*) from ef_nomes_seguros) as correspondencias_preparadas,
       (select count(*) from ef_alvos where antigo<>nome_sistema) as lotes_com_nome_diferente,
       (select count(*) from ef_alvos a join public.estoque s on s.id=a.id
        where s.produto=a.nome_sistema) as lotes_padronizados,
       (select count(*) from ef_alvos a join public.estoque s on s.id=a.id
        where s.produto=a.antigo and a.antigo<>a.nome_sistema) as lotes_pendentes;
commit;
