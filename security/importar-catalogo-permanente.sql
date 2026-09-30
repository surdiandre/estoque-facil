-- Catálogo permanente do Armazém 01; execute antes de apagar os lotes antigos.
-- Não altera linhas já cadastradas por código ou nome: preserva bula_url e bula_dados.
begin;
alter table public.ef_produtos_codigos add column if not exists bula_url text;
alter table public.ef_produtos_codigos add column if not exists bula_dados jsonb not null default '{}'::jsonb;
alter table public.ef_produtos_codigos add column if not exists empresa text;

create temporary table ef_importacao_produtos (codigo text primary key, produto text not null unique) on commit drop;
insert into ef_importacao_produtos (codigo,produto) values
  ('1', 'ABACUS HS 5LT'),
  ('5487', 'ABSOLUTO FIX 20LT'),
  ('4', 'ACTELLIC 500 EC 5 LT'),
  ('2409', 'ALADE 5 LT'),
  ('607', 'AMPLIGO GL 5LT'),
  ('2432', 'APROACH POWER 10LT'),
  ('5665', 'ARKEIRO NORTOX 5KG'),
  ('5332', 'ATTILA 5L'),
  ('2180', 'AURORA 400CE LITRO'),
  ('5650', 'AVICTA 500 FS 5LT'),
  ('2403', 'BEAUVE CONTROL 5 KG'),
  ('631', 'BELT SC LT'),
  ('5498', 'BELYAN 10 LT'),
  ('5377', 'BIAGRO ATTAK 1KG'),
  ('5433', 'BIAGRO SOLO GL 5 LT'),
  ('5666', 'BLAVITY 10L'),
  ('5254', 'BLAVITY 5L'),
  ('5104', 'BRAVONIL 720 20LT'),
  ('5488', 'BRAVONIL TOP 20LT'),
  ('2386', 'CALARIS 20 LT'),
  ('119', 'CALLISTO 5 LITROS'),
  ('5030', 'CERTERO LT'),
  ('5463', 'CLAVENGO 20 LT'),
  ('368', 'CONNECT 5 LT'),
  ('5651', 'CRUISER 600 FS 20LT'),
  ('5742', 'CRUISER ADVANCED 5LT'),
  ('2420', 'CURBIX SC 200 5 LT'),
  ('2079', 'CYPRESS 5LT'),
  ('2449', 'DUAL GOLD 20 LT'),
  ('2077', 'DUAL GOLD 5 LT'),
  ('5354', 'EDDUS 20L'),
  ('147', 'ENGEO PLENO 5 LITROS'),
  ('1091', 'EXALT INSETICIDA 1 LT'),
  ('5512', 'EXCALIA MAX 5LT'),
  ('304', 'EXPEDITION BTLCOX 5LT'),
  ('164', 'FERTOX PCT 1 KG'),
  ('2454', 'FERTOX PCT 1,5 KG'),
  ('5489', 'FINALE 20 LT'),
  ('165', 'FLEX 5 LITROS'),
  ('5609', 'FLEXSTAR GT 20LT'),
  ('5375', 'FOX SUPRA 5L'),
  ('2285', 'FOX XPRO SC450 5 LT'),
  ('2430', 'FX PROTECTION 5 LT'),
  ('590', 'HEAT 700 FR 350 GR'),
  ('5570', 'HERB ENLIST COLEX-D 20LT'),
  ('5338', 'HERBICIDA PAXEO 220GR'),
  ('1084', 'INSETICIDA CLORPIRIFOS 20 LT'),
  ('5466', 'INTREPID240SC 5 LT'),
  ('5605', 'ISCA FORMICIDA DINAGRO-S RESISTENTE 500GR'),
  ('1021', 'K OBIOL 25 EC 5 LT'),
  ('5808', 'K OBIOL 2P 01KG'),
  ('195', 'KARATE ZEON 250CS LITRO'),
  ('5556', 'KEYRA 5 LT'),
  ('5719', 'LANNATE BLD 20 LT'),
  ('216', 'MATCH 5 LITROS'),
  ('5652', 'MAXIM QUATTRO 20LT'),
  ('318', 'MIRATO 20LT'),
  ('5297', 'MIRAVIS 4X5 LT BRA'),
  ('5257', 'MIRAVIS DUO 5 LT'),
  ('2397', 'MITRION 5 LT'),
  ('5721', 'MOLUSTAREX BIO 20KG'),
  ('1175', 'NATIVO SC 300 20 LT'),
  ('2172', 'NATIVO SC 300 5 LT'),
  ('2088', 'NOMOLT 5 LT'),
  ('2307', 'NUFURON PCT 10G'),
  ('5473', 'ORANIS 10LT'),
  ('665', 'ORKESTRA GL 5 LITROS'),
  ('1161', 'PERITO 10 KG'),
  ('5697', 'PIRATE 1LT'),
  ('2401', 'POQUER 20 LT'),
  ('264', 'PRIMOLEO 20 LITRO'),
  ('269', 'PRIORI XTRA 5 LITRO'),
  ('276', 'REGLONE 20 LITROS'),
  ('277', 'REGLONE 5 LITROS'),
  ('301', 'SCORE FLEXI GL 5LT'),
  ('5745', 'SEEKER 5LT'),
  ('532', 'SOBERAN SC 630 GL 05 LT'),
  ('418', 'SPECTRO 20 LITROS'),
  ('1177', 'SPHERE MAX SC 5 LT'),
  ('537', 'SPIDER 840 PCT 210 GR'),
  ('5465', 'SPIDER 840WG PCT 420 GR'),
  ('2084', 'SPOT SC 5LT'),
  ('5671', 'STONE 05 LT'),
  ('5722', 'SUMYZIN 500SC 1LT'),
  ('5335', 'SUPPORT 5LT'),
  ('5280', 'SUPPORT BB 20LT'),
  ('506', 'TILT GL 5 LT'),
  ('444', 'TOPIK 240 EC LT'),
  ('5764', 'TRILLER EC 5LT'),
  ('5670', 'TRIZEB 10LT'),
  ('1099', 'UNIZEB GOLD 15 KG'),
  ('5342', 'VERDAVIS 5L'),
  ('2136', 'VERSATILIS 5 LT'),
  ('5279', 'VERTIMEC 84 SC 5 LT'),
  ('2456', 'VIOVAN 10 LT'),
  ('5393', 'XTENDICAM COPAK BR BLD 10 LT'),
  ('5767', 'XTENDIMAX 2 COPACK 10 LT'),
  ('469', 'ZAPP PRO 20L BRA'),
  ('5439', 'ZAPP WG 720 5 KG');

insert into public.ef_produtos_codigos (codigo,produto)
select codigo,produto from ef_importacao_produtos
on conflict do nothing;

-- Aproveita a empresa informada nos lotes antigos com o mesmo nome.
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

-- Preserva URLs de bulas que ainda estejam vinculadas aos lotes antigos.
update public.ef_produtos_codigos as cadastro
set bula_url = antigo.bula_url
from (
  select distinct on (upper(btrim(produto))) upper(btrim(produto)) as nome, bula_url
  from public.estoque
  where nullif(btrim(bula_url), '') is not null
  order by upper(btrim(produto)), id desc
) antigo
where upper(btrim(cadastro.produto)) = antigo.nome
  and nullif(btrim(cadastro.bula_url), '') is null;

-- Se algum registro de estoque tiver bula_dados gravado, conserva o JSON.
-- to_jsonb lê a coluna quando existir e ignora os registros sem ela.
update public.ef_produtos_codigos as cadastro
set bula_dados = antigo.dados
from (
  select distinct on (upper(btrim(s.produto)))
    upper(btrim(s.produto)) as nome,
    to_jsonb(s)->'bula_dados' as dados
  from public.estoque s
  where jsonb_typeof(to_jsonb(s)->'bula_dados') = 'object'
    and to_jsonb(s)->'bula_dados' <> '{}'::jsonb
  order by upper(btrim(s.produto)), s.id desc
) antigo
where upper(btrim(cadastro.produto)) = antigo.nome
  and (cadastro.bula_dados is null or cadastro.bula_dados = '{}'::jsonb);

-- Resultado: nomes diferentes para o mesmo código ou nomes ligados a outro código
-- ficam para conferência; nada é sobrescrito automaticamente.
select fonte.codigo, fonte.produto as nome_do_relatorio,
       atual.produto as nome_ja_cadastrado,
       case when atual.codigo is null then 'NÃO INSERIDO: NOME USADO POR OUTRO CÓDIGO'
            else 'CÓDIGO JÁ EXISTIA COM OUTRO NOME' end as situacao
from ef_importacao_produtos fonte
left join public.ef_produtos_codigos atual on atual.codigo=fonte.codigo
where atual.codigo is null or upper(btrim(atual.produto)) <> upper(btrim(fonte.produto))
order by fonte.produto;
commit;
