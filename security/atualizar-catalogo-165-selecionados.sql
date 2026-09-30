-- Importa SOMENTE os 165 produtos que permaneceram na planilha revisada.
-- Execute no SQL Editor do Supabase, antes de excluir o estoque antigo.
-- Não altera nem remove lotes, saldos, histórico, empresa, bula_url ou bula_dados.
begin;
alter table public.ef_produtos_codigos add column if not exists empresa text;
alter table public.ef_produtos_codigos add column if not exists bula_url text;
alter table public.ef_produtos_codigos add column if not exists bula_dados jsonb not null default '{}'::jsonb;

create temporary table ef_selecionados (
  codigo text primary key, produto text not null unique
) on commit drop;
insert into ef_selecionados (codigo,produto) values
  ('5323', '+AERIS 5LT'),
  ('5158', '+CA 5 LT'),
  ('5813', '+COMONI ULTRA 5L'),
  ('5373', '+MIX PRO 20L'),
  ('5334', '+MOL 5L'),
  ('1', 'ABACUS HS 5LT'),
  ('5487', 'ABSOLUTO FIX 20LT'),
  ('5805', 'ACQUAMAX FULL+ 01 LT'),
  ('4', 'ACTELLIC 500 EC 5 LT'),
  ('5324', 'ADITIVO INOC CRI-S BLD 20L'),
  ('5326', 'ADITIVO INOC POWER MAX BLD 20L'),
  ('5667', 'AGR OLEO 5LT'),
  ('2409', 'ALADE 5 LT'),
  ('5394', 'ALL-OK 5LT'),
  ('607', 'AMPLIGO GL 5LT'),
  ('2432', 'APROACH POWER 10LT'),
  ('5665', 'ARKEIRO NORTOX 5KG'),
  ('5332', 'ATTILA 5L'),
  ('667', 'AUREO GL 5 LT'),
  ('2180', 'AURORA 400CE LITRO'),
  ('5650', 'AVICTA 500 FS 5LT'),
  ('2403', 'BEAUVE CONTROL 5 KG'),
  ('631', 'BELT SC LT'),
  ('5498', 'BELYAN 10 LT'),
  ('5377', 'BIAGRO ATTAK 1KG'),
  ('5514', 'BIAGRO IMPACTO 5LT'),
  ('5433', 'BIAGRO SOLO GL 5 LT'),
  ('5642', 'BIOASIS POWER LIQ 5LT'),
  ('5724', 'BIOATTACK 5LT'),
  ('2267', 'BIOMA BRADY SOJA 2 LT 40 DOSES'),
  ('2254', 'BIOMA MAIS MILHO 2 LT 20 DOSES'),
  ('5641', 'BIOTRIO LIQ 5LT'),
  ('5666', 'BLAVITY 10L'),
  ('5254', 'BLAVITY 5L'),
  ('2316', 'BLEND 1 LT'),
  ('5784', 'BORO 1 LT'),
  ('5047', 'BORO 20 LT'),
  ('5261', 'BORO 5 LT'),
  ('5104', 'BRAVONIL 720 20LT'),
  ('5488', 'BRAVONIL TOP 20LT'),
  ('2386', 'CALARIS 20 LT'),
  ('119', 'CALLISTO 5 LITROS'),
  ('5030', 'CERTERO LT'),
  ('5463', 'CLAVENGO 20 LT'),
  ('2051', 'CONCORDE FERTIL 20 LT'),
  ('368', 'CONNECT 5 LT'),
  ('5651', 'CRUISER 600 FS 20LT'),
  ('5742', 'CRUISER ADVANCED 5LT'),
  ('2420', 'CURBIX SC 200 5 LT'),
  ('2079', 'CYPRESS 5LT'),
  ('2321', 'DS DRY 1 KG'),
  ('2449', 'DUAL GOLD 20 LT'),
  ('2077', 'DUAL GOLD 5 LT'),
  ('5354', 'EDDUS 20L'),
  ('5509', 'ENCHIMENTO 20LT'),
  ('5510', 'ENCHIMENTO 5LT'),
  ('147', 'ENGEO PLENO 5 LITROS'),
  ('2322', 'EVO K 10 LT'),
  ('2056', 'EVO MOP 5 LT'),
  ('1091', 'EXALT INSETICIDA 1 LT'),
  ('5512', 'EXCALIA MAX 5LT'),
  ('304', 'EXPEDITION BTLCOX 5LT'),
  ('5329', 'EXTRAVON 5L'),
  ('1125', 'FERT ESSENCE BLD 10 LT'),
  ('164', 'FERTOX PCT 1 KG'),
  ('2454', 'FERTOX PCT 1,5 KG'),
  ('5489', 'FINALE 20 LT'),
  ('165', 'FLEX 5 LITROS'),
  ('5609', 'FLEXSTAR GT 20LT'),
  ('5265', 'FOAM 1L'),
  ('5375', 'FOX SUPRA 5L'),
  ('2285', 'FOX XPRO SC450 5 LT'),
  ('2430', 'FX PROTECTION 5 LT'),
  ('590', 'HEAT 700 FR 350 GR'),
  ('5570', 'HERB ENLIST COLEX-D 20LT'),
  ('5338', 'HERBICIDA PAXEO 220GR'),
  ('5467', 'INOC AZOMAX 3,0 LT'),
  ('5325', 'INOC LIQ SOJA OPTIMIZE PCT 10L'),
  ('5502', 'INOC UTRISHA SC 5KG'),
  ('1084', 'INSETICIDA CLORPIRIFOS 20 LT'),
  ('5466', 'INTREPID240SC 5 LT'),
  ('5605', 'ISCA FORMICIDA DINAGRO-S RESISTENTE 500GR'),
  ('1021', 'K OBIOL 25 EC 5 LT'),
  ('5808', 'K OBIOL 2P 01KG'),
  ('195', 'KARATE ZEON 250CS LITRO'),
  ('5508', 'KBT AMINO 20LT'),
  ('5765', 'KEEPDRY ORG 20KG'),
  ('5556', 'KEYRA 5 LT'),
  ('5669', 'KS 20LT'),
  ('5719', 'LANNATE BLD 20 LT'),
  ('216', 'MATCH 5 LITROS'),
  ('5652', 'MAXIM QUATTRO 20LT'),
  ('2306', 'MEES 5 LT'),
  ('2250', 'MICROGEO SACO 25 KG'),
  ('318', 'MIRATO 20LT'),
  ('5297', 'MIRAVIS 4X5 LT BRA'),
  ('5257', 'MIRAVIS DUO 5 LT'),
  ('2397', 'MITRION 5 LT'),
  ('5721', 'MOLUSTAREX BIO 20KG'),
  ('5603', 'N390 20LT'),
  ('1175', 'NATIVO SC 300 20 LT'),
  ('2172', 'NATIVO SC 300 5 LT'),
  ('2088', 'NOMOLT 5 LT'),
  ('2307', 'NUFURON PCT 10G'),
  ('5507', 'NUTRIL BORO MEL 20LT'),
  ('5256', 'NUTRIL MOLIBDENIO 270 GL 05 LT'),
  ('2260', 'OCHIMA 5 LT'),
  ('5225', 'OLEO MINERAL LUBROPPA BD 20LT'),
  ('5473', 'ORANIS 10LT'),
  ('665', 'ORKESTRA GL 5 LITROS'),
  ('5668', 'OUTARD 20LT'),
  ('1161', 'PERITO 10 KG'),
  ('5697', 'PIRATE 1LT'),
  ('5698', 'POLIMERO ADESIVO COLORSEED INTENSIVE VERDE 20LT'),
  ('5699', 'POLYDRY GRAF 5KG'),
  ('5315', 'POLYTEK LIQUID RED PB 20L BR'),
  ('5316', 'POLYTEK POWDER BOX 25X20KG BR'),
  ('2401', 'POQUER 20 LT'),
  ('5240', 'PREMAX LLI 4 X 2 L'),
  ('264', 'PRIMOLEO 20 LITRO'),
  ('269', 'PRIORI XTRA 5 LITRO'),
  ('2200', 'PROGEN DETOX 10 LT'),
  ('5552', 'PROGEN DETOX 5 LT'),
  ('379', 'RASS 32 1 LT'),
  ('276', 'REGLONE 20 LITROS'),
  ('277', 'REGLONE 5 LITROS'),
  ('5658', 'REVERB 4X5 L BRA'),
  ('5239', 'RIZOLIQ LLI BR X 10 L'),
  ('301', 'SCORE FLEXI GL 5LT'),
  ('5745', 'SEEKER 5LT'),
  ('2323', 'SIGNAL 05 LT'),
  ('532', 'SOBERAN SC 630 GL 05 LT'),
  ('418', 'SPECTRO 20 LITROS'),
  ('1177', 'SPHERE MAX SC 5 LT'),
  ('537', 'SPIDER 840 PCT 210 GR'),
  ('5465', 'SPIDER 840WG PCT 420 GR'),
  ('2234', 'SPIN 1LT'),
  ('2084', 'SPOT SC 5LT'),
  ('5671', 'STONE 05 LT'),
  ('5722', 'SUMYZIN 500SC 1LT'),
  ('5335', 'SUPPORT 5LT'),
  ('5280', 'SUPPORT BB 20LT'),
  ('5151', 'TA 35 LT'),
  ('386', 'TA 35 ULTRA 5LT'),
  ('506', 'TILT GL 5 LT'),
  ('444', 'TOPIK 240 EC LT'),
  ('5788', 'TRICHOCOMBAT PRO 1KG'),
  ('2041', 'TRICHODERMIL SSC 1LT'),
  ('5764', 'TRILLER EC 5LT'),
  ('5670', 'TRIZEB 10LT'),
  ('5677', 'TSBIO PRIME 1LT'),
  ('5806', 'TSN COMONI PLUS 10 LT'),
  ('2299', 'UBYFOL KIMON 20 LT'),
  ('1099', 'UNIZEB GOLD 15 KG'),
  ('5815', 'VECTOR PROTECTION 2LT'),
  ('5342', 'VERDAVIS 5L'),
  ('2136', 'VERSATILIS 5 LT'),
  ('5279', 'VERTIMEC 84 SC 5 LT'),
  ('2456', 'VIOVAN 10 LT'),
  ('5392', 'XTEND PROTEC COPACK BR BLD 10 LT'),
  ('5766', 'XTEND PROTECT 2 MAX 2 10 LT'),
  ('5393', 'XTENDICAM COPAK BR BLD 10 LT'),
  ('5767', 'XTENDIMAX 2 COPACK 10 LT'),
  ('469', 'ZAPP PRO 20L BRA'),
  ('5439', 'ZAPP WG 720 5 KG');

-- Guarda no cadastro permanente os metadados dos lotes antes de ajustar nomes.
update public.ef_produtos_codigos as c
set empresa=coalesce(nullif(btrim(c.empresa),''),(
      select s.empresa from public.estoque s
      where upper(btrim(s.produto))=upper(btrim(c.produto))
        and nullif(btrim(s.empresa),'') is not null
      order by s.id desc limit 1)),
    bula_url=coalesce(nullif(btrim(c.bula_url),''),(
      select s.bula_url from public.estoque s
      where upper(btrim(s.produto))=upper(btrim(c.produto))
        and nullif(btrim(s.bula_url),'') is not null
      order by s.id desc limit 1)),
    bula_dados=case when c.bula_dados is not null and c.bula_dados<>'{}'::jsonb
      then c.bula_dados else coalesce((
      select to_jsonb(s)->'bula_dados' from public.estoque s
      where upper(btrim(s.produto))=upper(btrim(c.produto))
        and jsonb_typeof(to_jsonb(s)->'bula_dados')='object'
        and to_jsonb(s)->'bula_dados'<>'{}'::jsonb
      order by s.id desc limit 1),'{}'::jsonb) end
where exists (select 1 from ef_selecionados e
              where coalesce(nullif(ltrim(c.codigo,'0'),''),'0')=e.codigo);

-- Ajusta apenas o NOME dos códigos existentes quando não há colisão.
update public.ef_produtos_codigos as c
set produto=e.produto
from ef_selecionados e
where coalesce(nullif(ltrim(c.codigo,'0'),''),'0')=e.codigo
  and upper(btrim(c.produto))<>upper(btrim(e.produto))
  and not exists (select 1 from public.ef_produtos_codigos outro
                  where outro.codigo<>c.codigo
                    and (coalesce(nullif(ltrim(outro.codigo,'0'),''),'0')=e.codigo
                      or upper(btrim(outro.produto))=upper(btrim(e.produto))));

-- Insere os códigos ausentes; conflitos existentes ficam para revisão.
insert into public.ef_produtos_codigos (codigo,produto)
select e.codigo,e.produto from ef_selecionados e
where not exists (select 1 from public.ef_produtos_codigos c
                  where coalesce(nullif(ltrim(c.codigo,'0'),''),'0')=e.codigo
                     or upper(btrim(c.produto))=upper(btrim(e.produto)))
on conflict do nothing;

-- Uma linha de resumo; pendências listadas em JSON para você me mostrar.
select count(*) as selecionados,
       count(*) filter (where existe.codigo is not null
         and upper(btrim(existe.produto))=upper(btrim(e.produto))) as cadastrados_corretos,
       count(*) filter (where existe.codigo is null
         or upper(btrim(existe.produto))<>upper(btrim(e.produto))) as pendentes,
       coalesce(jsonb_agg(jsonb_build_object('codigo',e.codigo,'nome_planilha',e.produto,
         'nome_atual',existe.produto)) filter (where existe.codigo is null
         or upper(btrim(existe.produto))<>upper(btrim(e.produto))),'[]'::jsonb) as detalhes_pendentes
from ef_selecionados e
left join lateral (
  select c.codigo,c.produto from public.ef_produtos_codigos c
  where coalesce(nullif(ltrim(c.codigo,'0'),''),'0')=e.codigo
  order by c.codigo limit 1
) existe on true;
commit;
