-- Consulta somente leitura para conferir o estado real antes de aplicar RLS.
select c.relname as tabela, c.relrowsecurity as rls_ativo,
       has_table_privilege('anon', c.oid, 'SELECT') as leitura_visitante,
       has_table_privilege('anon', c.oid, 'INSERT') as insercao_visitante,
       has_table_privilege('anon', c.oid, 'UPDATE') as edicao_visitante,
       has_table_privilege('anon', c.oid, 'DELETE') as exclusao_visitante
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('estoque','historico_entradas','historico_saidas','usuarios')
order by c.relname;

select tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname='public'
  and tablename in ('estoque','historico_entradas','historico_saidas','usuarios')
order by tablename, policyname;
