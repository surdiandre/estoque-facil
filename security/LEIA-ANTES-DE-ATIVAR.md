# Acesso aos dados do Estoque Fácil

O site permite que visitantes consultem o estoque. Somente a conta administrativa configurada pode alterar `estoque`, `historico_entradas` e `historico_saidas`. A interface sozinha não protege o banco: a proteção precisa estar ativa no Supabase.

1. No SQL Editor do projeto correto, execute `inspecionar-acesso.sql`. Confira as políticas existentes das quatro tabelas, especialmente `usuarios`.
2. Se houver políticas anteriores para as três tabelas de estoque, revise-as antes de alterá-las. `rls-estoque.sql` interrompe a execução caso encontre políticas desconhecidas.
3. Execute `rls-estoque.sql` depois da revisão. Ele ativa RLS, concede leitura a visitantes e deixa escrita apenas para a sessão administrativa.
4. Confira a operação com uma sessão visitante e com a conta administrativa. Faça a conferência de gravação com um registro de teste que você possa remover depois.

O SQL não altera a tabela `usuarios`, funções Edge ou políticas de Storage. Esses recursos precisam de revisão separada se forem usados para dados restritos.

O aplicativo armazena alterações offline neste aparelho e as reenvia em sequência quando a conexão volta e a conta administrativa está ativa. A baixa manual na versão deste bloco usa `ef_confirmar_baixa_manual`: a função trava a linha do estoque, atualiza ou exclui o saldo e grava `historico_saidas` na mesma transação. As demais rotinas de movimentação seguem seus próprios fluxos; confira o resultado antes de repetir uma gravação após falha de conexão.

Referências: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) e [segurança da Data API](https://supabase.com/docs/guides/api/securing-your-api).


## Bloco 2.2 — baixa manual atômica

- [ ] Fazer backup manual do Supabase.
- [ ] Rodar `security/baixa-manual-atomica.sql` com `ROLLBACK` e conferir assinatura, `SECURITY DEFINER`, `search_path` vazio e privilégios (`anon=false`, `authenticated=true`).
- [ ] Após revisão e OK explícito, substituir o `ROLLBACK` final por `COMMIT` e aplicar a função no Supabase.
- [ ] Confirmar que a função existe e que o schema do PostgREST foi recarregado.
- [ ] Publicar o HTML atualizado somente depois do `COMMIT` da função; sem isso, a baixa manual receberá erro de RPC inexistente.
- [ ] Como administrador, testar uma baixa parcial, uma baixa que zera e exclui a linha, e uma tentativa acima do saldo.
- [ ] Confirmar que cada baixa aprovada altera o estoque e grava exatamente um registro em `historico_saidas`, com o e-mail do JWT.
- [ ] Confirmar que visitante sem sessão não consegue executar a RPC e que os fluxos de histórico continuam lendo as views públicas.
- [ ] Verificar o comportamento da fila offline e sincronizar qualquer operação pendente antes de novo teste.
