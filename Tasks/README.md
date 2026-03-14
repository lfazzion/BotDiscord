# Tasks - Backlog do Projeto

> Tarefas individuais agrupadas por fase de implementação.

## Estrutura

```
Tasks/
├── P0_fundacao/        # Fase P0
├── P1_coleta/          # Fase P1 - Coleta
├── P1_cerebro_llm/     # Fase P1 - LLM
├── P2_oracle/          # Fase P2 - Oracle
├── P2_chatbot/         # Fase P2 - Chatbot
└── P3_operacao/        # Fase P3 - Operação
```

---

## Status Flow

```
pending ──→ in_progress ──→ done
    │              │
    │              └──→ blocked
    │
    └──────────────────┘
```

---

## Formato

Cada task é um arquivo JSON com:
- `id`: TASK-NNN
- `title`: Título descritivo
- `status`: pending | in_progress | done | blocked
- `phase`: P0/P1/P2/P3
- `priority`: critical | high | medium | low
- `blocked_by`: Array de task IDs
- `prd`: Link para PRD
- `spec`: Link para SPEC

---

## Como Criar Nova Task

1. Copie o template em `TASK_TEMPLATE.md`
2. Renomeie para `TASK-NNN_descricao.json`
3. Preencha os campos
4. Adicione na pasta da fase correspondente
