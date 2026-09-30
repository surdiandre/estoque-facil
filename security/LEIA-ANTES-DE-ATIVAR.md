# Acesso aos dados do Estoque Fácil

O site permite que visitantes consultem o estoque. Somente a conta administrativa configurada pode alterar `estoque`, `historico_entradas` e `historico_saidas`. A interface sozinha não protege o banco: a proteção precisa estar ativa no Supabase.

1. No SQL Editor do projeto correto, execute `inspecionar-acesso.sql`. Confira as políticas existentes das quatro tabelas, especialmente `usuarios`.
2. Se houver políticas anteriores para as três tabelas de estoque, revise-as antes de alterá-las. `rls-estoque.sql` interrompe a execução caso encontre políticas desconhecidas.
3. Execute `rls-estoque.sql` depois da revisão. Ele ativa RLS, concede leitura a visitantes e deixa escrita apenas para a sessão administrativa.
4. Confira a operação com uma sessão visitante e com a conta administrativa. Faça a conferência de gravação com um registro de teste que você possa remover depois.

O SQL não altera a tabela `usuarios`, funções Edge ou políticas de Storage. Esses recursos precisam de revisão separada se forem usados para dados restritos.

O aplicativo armazena alterações offline neste aparelho e as reenvia em sequência quando a conexão volta e a conta administrativa está ativa. Movimentações de estoque e histórico ainda são duas chamadas separadas; para atomicidade entre as duas tabelas, é preciso uma função transacional no banco. Uma falha de conexão durante uma gravação online pede conferência do registro antes de reenviar.

Referências: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) e [segurança da Data API](https://supabase.com/docs/guides/api/securing-your-api).
