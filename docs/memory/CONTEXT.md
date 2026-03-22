# Memória de Longo Prazo

> **NÃO carregar automaticamente.** Consultar via busca (`grep`, `rg`) apenas quando necessário.

## O que vive aqui

| Diretório | Conteúdo | Quando arquivar |
|-----------|----------|-----------------|
| `decisions/` | Decisões arquiteturais antigas que saíram do MEMORY.md | Quando uma decisão ratificada é substituída |
| `resolved_bugs/` | Bugs já resolvidos que saíram de "Lições Aprendidas" | Após consolidação mensal do MEMORY.md |
| `archived/` | Contextos de fases/sprints passados | Ao final de cada fase de trabalho |

## Formato dos arquivos

Cada arquivo DEVE conter:
- `[YYYY-MM-DD]` no nome do arquivo
- Data, descrição, referência ao arquivo/classe afetado
- Motivo da decisão ou resolução

Exemplo: `2026-03-14_solid_queue_vs_sidekiq.md`

## Regras

1. **NUNCA** carregar esta pasta automaticamente — só buscar sob demanda
2. **NUNCA** deletar sem registrar no Log de Mudanças do MEMORY.md
3. Arquivos são **append-only** — corrigir imprecisões adicionando nota no final
