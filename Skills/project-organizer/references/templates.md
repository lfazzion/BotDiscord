# Templates de Documentação — Project Organizer

Templates reutilizáveis para os documentos do pipeline de organização. Copie e preencha conforme necessário.

---

## 1. Identity File (CLAUDE.md / GEMINI.md)

```markdown
# [Nome do Projeto]

> Atualizado em: [DATA]

## Stack Técnica
- **Framework:** [ex: Rails 8.1 Headless]
- **Banco:** [ex: SQLite3 WAL mode]
- **Infra:** [ex: Docker Compose]
- **Interface:** [ex: Discord Bot]
- **AI/LLM:** [ex: Gemini Flash Lite + Gemma 27B]

## Arquitetura
[Descrição em 3-5 linhas da arquitetura macro do sistema]

## Regras Invioláveis
1. [Regra crítica 1 — ex: NULL != 0 em métricas]
2. [Regra crítica 2 — ex: Tools retornam Hashes puros]
3. [Regra crítica 3 — ex: Clamping em parâmetros LLM]

## Convenções
- **Linguagem:** [ex: Ruby, snake_case]
- **Testes:** [ex: Minitest, mínimo 80% coverage]
- **Branches:** [ex: main, develop, feature/*]

## Navegação do Projeto
- Requisitos: [caminho]
- Plano: [caminho]
- Documentação técnica: [caminho para pasta]
- Tasks pendentes: [caminho para pasta]
```

---

## 2. PRD (Product Requirements Document)

```markdown
# PRD: [Nome da Feature]

> **Autor:** [nome]
> **Data:** [YYYY-MM-DD]
> **Status:** draft | review | approved | done
> **Fase:** [P0/P1/P2/P3]

## Contexto
[Por que esta feature é necessária? Qual problema resolve?]

## Objetivo
[O que o sistema deve fazer ao final desta implementação?]

## Requisitos Funcionais
1. [RF-01] [Descrição clara do requisito]
2. [RF-02] [Descrição clara do requisito]

## Requisitos Não-Funcionais
1. [RNF-01] [Performance, segurança, limites]

## Arquivos Afetados
- `[caminho/arquivo.rb]` — [o que muda]
- `[caminho/novo_arquivo.rb]` — [NEW] [propósito]

## Referências
- [Link para doc técnico relevante]
- [Link para API externa]

## Riscos e Decisões em Aberto
- [ ] [Risco ou decisão pendente]
```

---

## 3. SPEC (Especificação Tática)

```markdown
# SPEC: [Nome da Feature]

> **PRD de origem:** [caminho para o PRD]
> **Data:** [YYYY-MM-DD]
> **Status:** draft | approved | implementing | done

## Resumo
[1-2 linhas descrevendo o que será implementado]

## Plano de Execução

### Arquivo 1: `[caminho/completo/arquivo.rb]`
**Ação:** [CREATE | MODIFY | DELETE]

**Mudanças:**
- Linha/Método: `[nome_do_metodo]`
- Lógica:
  ```ruby
  # Pseudocódigo ou implementação esperada
  def nome_do_metodo(params)
    # 1. Validar entrada
    # 2. Buscar dados
    # 3. Retornar resultado formatado
  end
  ```

### Arquivo 2: `[caminho/completo/outro_arquivo.rb]`
**Ação:** [CREATE | MODIFY | DELETE]

**Mudanças:**
- [Descrição detalhada análoga ao Arquivo 1]

## Ordem de Implementação
1. [Arquivo X] — não tem dependências
2. [Arquivo Y] — depende de X
3. [Arquivo Z] — depende de X e Y

## Critérios de Conclusão
- [ ] [Critério verificável 1]
- [ ] [Critério verificável 2]
- [ ] Testes passando
```

---

## 4. Task (Tarefa Individual)

### Formato JSON (para automação)

```json
{
  "id": "TASK-NNN",
  "title": "Título descritivo da tarefa",
  "status": "pending",
  "phase": "P0-fundacao",
  "priority": "high",
  "blocked_by": [],
  "prd": "PRDs/PRD_Nome_Feature.md",
  "spec": "Specs/SPEC_Nome_Feature.md",
  "description": "Descrição detalhada do que precisa ser feito",
  "acceptance_criteria": [
    "Critério 1",
    "Critério 2"
  ],
  "created_at": "YYYY-MM-DD",
  "updated_at": "YYYY-MM-DD"
}
```

### Formato Markdown (para leitura humana)

```markdown
# TASK-NNN: [Título da Tarefa]

- **Status:** pending | in_progress | done | blocked
- **Fase:** P0 | P1 | P2 | P3
- **Prioridade:** critical | high | medium | low
- **Bloqueada por:** [TASK-XXX, TASK-YYY] ou nenhuma
- **PRD:** [link para PRD]
- **Spec:** [link para SPEC]

## Descrição
[O que precisa ser feito]

## Critérios de Aceite
- [ ] [Critério 1]
- [ ] [Critério 2]

## Notas
[Observações relevantes, links, decisões tomadas]
```

---

## 5. Quick Reference — Status Flow

```
pending ──→ in_progress ──→ done
   │              │
   │              └──→ blocked (esperando dependência)
   │                      │
   └──────────────────────┘ (dependência resolvida)
```

## 6. Checklist de Novo Projeto

Use esta checklist ao iniciar um projeto ou reorganizar um existente:

- [ ] Criar Identity file na raiz (`CLAUDE.md`)
- [ ] Definir regras invioláveis do projeto
- [ ] Criar pasta `Documentations/` com docs técnicos existentes
- [ ] Criar pasta `PRDs/` (pode começar vazia)
- [ ] Criar pasta `Specs/` (pode começar vazia)
- [ ] Criar pasta `Tasks/` com sub-pastas por fase
- [ ] Atualizar `README.md` com visão geral
- [ ] Documentar convenções de nomes no Identity file
