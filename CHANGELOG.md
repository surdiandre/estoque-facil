# Changelog — Estoque Fácil

Todas as mudanças notáveis deste projeto.

## [2.5] — 09/10/2026 — Cargas, NF, estorno e QR

**Versão final: v237**

### Adicionado
- Vínculo global de NF única (tabela cargas_nfs, trigger, view ef_cargas_public) — 2.5.1
- Baixa manual com vínculo opcional a carga — 2.5.2
- Confirmação transacional de carga com múltiplos itens — 2.5.3
- Estorno transacional com restauração de estoque — 2.5.4
- Modal unificado de carga com multi-NF e data retroativa — 2.5.5 + 2.5.5.1
- Histórico agrupado por carga (aba Cargas) — 2.5.6
- Botão de estorno na interface — 2.5.7
- Parser QR v3 (formato baseado em NF real da Coperacel) — 2.5.8 + 2.5.8.1
- Alocação de item entre múltiplas pilhas — 2.5.8.1
- Roteiro de testes end-to-end — 2.5.9

### RPCs no banco
- ef_alterar_saldo
- ef_confirmar_baixa_manual (com p_carga_id e p_data_hora)
- ef_confirmar_baixa_qr (legado)
- ef_confirmar_baixa_carga (com p_nfs jsonb)
- ef_estornar_carga

### Views
- ef_cargas_public
- ef_historico_saidas_public
- ef_historico_entradas_public

### Triggers
- trg_baixas_qr_nf_global

### Documentação
- security/2-5-ROTEIRO-TESTES.md (roteiro E2E)
- security/formato-qr-v3.md (especificação do QR v3)

### Status
Sprint 2.5 fechado em 09/10/2026. Testes manuais em produção validaram os fluxos principais. A execução formal do roteiro fica documentada para auditoria futura, pois não havia ambiente de homologação.

---

## [2.4] — 05/10/2026 — Idempotência e fila offline

- Chaves de idempotência para entradas, saídas e ajustes de saldo.
- Fila offline com a mesma chave persistida entre tentativas, evitando duplicar movimentações durante novas tentativas de sincronização.
- Registro do saldo resultante das operações para conferir o resultado após repetição ou sincronização.

## [2.3] — 05/10/2026 — Edge Function de upload de bula

- Upload de bula em PDF por Edge Function, com validação de sessão/permissão, tamanho e assinatura do arquivo.
- Validação do produto associado e configuração de CORS por origem permitida.

## [2.2] — 04/10/2026 — Baixa manual atômica

- Baixa manual executada por RPC transacional, com conferência de saldo no banco e registro auditável do movimento.
- Proteção contra baixas concorrentes que poderiam consumir o mesmo saldo duas vezes.

## [2.1] — 30/09–04/10/2026 — RLS e views públicas

- Regras de segurança para restringir gravações diretas e expor leituras necessárias por views públicas controladas.
- Histórico de entradas e saídas consultado pelo aplicativo por views, mantendo os dados de escrita protegidos pelas RPCs autorizadas.

## [1.x] — 30/09–03/10/2026 — Sprints iniciais

- Base do PWA Estoque Fácil e estrutura inicial do repositório.
- Fluxos de estoque, cadastro de entradas e saídas, consulta de lotes, histórico, relatórios e interface adaptável a celular.
- Primeiras melhorias de validade, filtros, experiência de uso e funcionamento offline.
