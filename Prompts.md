# Prompts.md — Workflow de 3 Etapas (Research → Spec → Code)

> Workflow otimizado para o BotDiscord. Maximiza a janela de contexto limpando
> entre fases e usando arquivos como ponte (PRD.md → SPEC.md → implementação).
>
> Nota: `docs/MEMORY.md` é lido automaticamente via Memory Protocol no AGENTS.md.
> Os prompts abaixo NÃO precisam instruir a leitura — ela já acontece.

---

## Visão Geral

```
┌─────────────┐     /clear     ┌─────────────┐     /clear     ┌─────────────┐
│  1. Research │──────────────▶│  2. Spec     │──────────────▶│  3. Code     │
│              │  PRD.md       │              │  SPEC.md       │              │
│  Investigar  │  (ponte)      │  Planejar    │  (ponte)       │  Implementar │
└─────────────┘               └─────────────┘               └─────────────┘
```

**Regra de ouro:** nunca pule etapas. Nunca implemente direto sem PRD e SPEC.

---

## Etapa 1 — Research (Investigação)

### Quando usar
Nova feature, refatoração significativa, integração nova, bug complexo.

### Prompt

```xml
<task>
Preciso implementar [DESCRIÇÃO DA TAREFA].
Faça uma investigação completa antes de propor qualquer código.
</task>

<instructions>
1. Leia TODOS os arquivos relevantes do codebase profundamente — não superficialmente.
2. Consulte a Routing Table do AGENTS.md para saber quais CONTEXT.md ler.
3. Encontre padrões de implementação similares já existentes no projeto.
4. Se necessário, busque documentação externa sobre as tecnologias envolvidas.
5. Identifique constraints do projeto (Docker, SQLite WAL, Solid Queue, etc.).
6. Faça chamadas paralelas de ferramentas sempre que as leituras forem independentes.
</instructions>

<output_format>
Escreva o resultado em `PRD.md` seguindo EXATAMENTE esta estrutura:

## Objetivo
[O que queremos fazer e por quê — 1 parágrafo conciso]

## Arquivos Relevantes
| Arquivo | Relevância | Motivo |
|---------|------------|--------|
| path/to/file.rb | alta | [por quê] |

## Padrões Encontrados no Codebase
[Code snippets ou referências a implementações similares já existentes]
[Inclua path + line number de cada referência]

## Documentação Externa
[Resumo das referências técnicas encontradas com URLs quando disponíveis]

## Constraints
[Limitações do stack: Docker, SQLite, Solid Queue, métricas nil vs 0, etc.]

## Riscos / Pontos de Atenção
[O que pode dar errado, edge cases, 403/429/captcha rules, etc.]

## Decisões a Tomar
[Perguntas em aberto que precisam de resposta antes de planejar]
</output_format>

<constraints>
- Não escreva NENHUM código nesta etapa — apenas análise e documentação.
- Não especule sobre código que não abriu. LEIA os arquivos antes de fazer afirmações.
- Seja exaustivo na leitura — "deeply", não superficialmente.
- Inclua path + line number em toda referência a código existente.
</constraints>
```

### Output
`PRD.md` preenchido com a investigação completa.

### Após esta etapa
→ Limpe o contexto (`/clear`), inicie conversa nova para a Etapa 2.

---

## Etapa 2 — Spec (Planejamento)

### Quando usar
Sempre que houver um PRD.md pronto da Etapa 1.

### Prompt

```xml
<task>
Leia `PRD.md` e gere um plano de implementação em `SPEC.md`.
Seja tático e preciso — file-level detail.
</task>

<context>
O projeto BotDiscord usa: Rails 8.1 headless, SQLite WAL, Solid Queue/Cache,
Docker, Minitest + FactoryBot. Veja AGENTS.md para convenções completas.
</context>

<instructions>
1. Liste TODOS os arquivos que precisam ser CRIADOS (com path completo).
2. Liste TODOS os arquivos que precisam ser MODIFICADOS.
3. Para CADA arquivo, descreva exatamente O QUE fazer nele.
4. Inclua code snippets quando a implementação exigir um padrão específico.
5. Crie um checklist de tarefas com checkboxes (- [ ]) para cada passo.
6. Ao final, adicione uma seção "## Perguntas" com decisões que precisam de validação humana.
</instructions>

<constraints>
- Respeite as convenções do projeto:
  - `# frozen_string_literal: true` em todo .rb
  - 2 espaços de indentação, aspas duplas, ~120 chars por linha
  - Métricas (likes, views, followers): `nil` no failure, nunca `0`
  - Prompts em YAML (`config/prompts/`), nunca string hardcoded
  - Naming: PascalCase classes, snake_case arquivos, *_test.rb para testes
- Considere a Definition of Done do AGENTS.md
- Não implemente NADA — apenas planeje
- Evite over-engineering: solução mínima que resolve o problema
</constraints>

<output_format>
## Arquivos a Criar
| Path | Tipo | Descrição |
|------|------|-----------|

## Arquivos a Modificar
| Path | Mudanças |
|------|----------|

## Checklist de Implementação
- [ ] Passo 1: [descrição]
  - Arquivo: `path/to/file.rb`
  - O que fazer: [detalhe]
- [ ] Passo 2: [descrição]

## Perguntas
- [Pergunta 1 que precisa de decisão humana antes de implementar]

## Validação
- [ ] `docker-compose -f docker/docker-compose.yml run --rm test` passa
- [ ] `ruby -cw <file>` sem warnings nos arquivos modificados
- [ ] Migration roda limpo se aplicável
</output_format>
```

### Output
`SPEC.md` com plano completo, checklist de tarefas, pronto para implementação.

### Annotation Cycle (Ciclo de Anotação)
> Padrão de Boris Tane — o passo mais poderoso do workflow.

Após o SPEC.md ser gerado, **NÃO pule direto para a Etapa 3**. Faça o ciclo:

1. Abra o `SPEC.md` no seu editor
2. Adicione notas inline diretamente no documento — corrija abordagens, rejeite opções, adicione constraints de negócio que a IA não tem
3. Envie de volta para a IA:

```xml
<task>
Adicionei notas inline no SPEC.md. Leia o documento e enderece TODAS as notas.
Atualize o documento de acordo.
</task>

<constraints>
Não implemente nada ainda — apenas atualize o spec.
</constraints>
```

4. Repita 1-6x até o plano estar correto
5. **Só então** avance para a Etapa 3

### Após esta etapa
→ Limpe o contexto (`/clear`), inicie conversa nova para a Etapa 3.

---

## Etapa 3 — Code (Implementação)

### Quando usar
Sempre que houver um SPEC.md pronto e APROVADO (após Annotation Cycle).

### Prompt

```xml
<task>
Implemente a `SPEC.md`.
Leia o arquivo e execute cada item do checklist na ordem definida.
</task>

<instructions>
1. Marque cada item como concluído no checklist ao completá-lo: `- [x]`
2. Crie/atualize os testes JUNTO com o código — não depois.
3. Após cada arquivo, rode `ruby -cw <file>` para checar syntax.
4. Ao final de cada bloco lógico, rode a suite:
   `docker-compose -f docker/docker-compose.yml run --rm test`
5. Se encontrar ambigüidade que o spec não cobre, PARE e pergunte.
6. Não declare completo até TODOS os checkboxes estarem marcados.
</instructions>

<constraints>
- Siga o spec à risca. Não invente além do que está descrito.
- Não adicione comentários, jsdocs ou anotações desnecessárias.
- Evite over-engineering: não crie abstrações, helpers ou flexibilidade não solicitada.
- Não adicione error handling para cenários impossíveis.
- Não hardcode valores — implemente a lógica real.
- Se algo no spec parece errado, me avise — não "corrija" sozinho.
- Ao final, valide contra TODOS os critérios da Definition of Done.
</constraints>

<verification>
Antes de declarar pronto, verifique:
- [ ] Todos os checkboxes do SPEC.md estão marcados
- [ ] `docker-compose -f docker/docker-compose.yml run --rm test` passa (0 failures, 0 errors)
- [ ] `ruby -cw <file>` sem warnings em cada .rb modificado/criado
- [ ] Nenhum hardcoded secret ou credential
- [ ] Testes correspondentes existem para código novo
</verification>
```

### Output
Código implementado, testes passando, pronto para commit.

### Após esta etapa
- Se houver decisão arquitetural nova → atualizar `docs/MEMORY.md`
- Se o spec foi alterado durante implementação → atualizar `SPEC.md` com o que realmente foi feito (living spec)
- Commitar quando o usuário aprovar

---

## Variações por Tipo de Tarefa

### Nova Migration + Model

Etapa 1 (Research) — adicionar ao prompt:
```xml
<context>
Além do padrão, leia `app/models/CONTEXT.md` e `db/CONTEXT.md`.
Identifique se alguma tabela existente já tem colunas similares.
Verifique se a migration não conflita com o schema atual.
</context>
```

### Novo Job de Coleta

Etapa 1 (Research) — adicionar ao prompt:
```xml
<context>
Além do padrão, leia `app/jobs/CONTEXT.md` e `lib/scraping/CONTEXT.md`.
O job DEVE ser idempotente.
Verifique a dedup window de 2h.
Nunca retry em 403/429/captcha — backoff 6-12h.
</context>
```

### Integração LLM / Novo Prompt YAML

Etapa 1 (Research) — adicionar ao prompt:
```xml
<context>
Além do padrão, leia `lib/llm/CONTEXT.md` e `config/prompts/CONTEXT.md`.
O prompt DEVE ser em YAML em `config/prompts/`, nunca hardcoded.
Injetar timestamp: <current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>>
</context>
```

### Scraper (Python / Ferrum)

Etapa 1 (Research) — adicionar ao prompt:
```xml
<context>
Além do padrão, leia `lib/scraping/CONTEXT.md` e `scripts/python/CONTEXT.md`.
Sempre fechar conexões de browser em `ensure` blocks.
Log com prefixo [ClassName].
</context>
```

### Bug Fix

Para bugs simples, as 3 etapas podem ser condensadas:

```xml
<task>
Bug: [DESCRIÇÃO DO BUG]
</task>

<instructions>
1. Reproduza o problema — leia o código relevante profundamente.
2. Identifique a causa raiz (não trate sintoma).
3. Consulte a seção "Lições Aprendidas de Bugs Recorrentes" do MEMORY.md.
4. Corrija com a menor mudança possível.
5. Escreva/atualize teste que cobre o cenário.
6. Rode: `docker-compose -f docker/docker-compose.yml run --rm test`
</instructions>

<constraints>
- Não delete código existente para "fixar" algo que não entende.
- Não modifique testes para fazê-los passar sem entender a causa raiz.
- Não remova validações ou error handling para contornar o problema.
- Se após 3 tentativas não resolver: documente em "Decisões Pendentes" do MEMORY.md e PARE.
</constraints>
```

### Referência Externa (Padrão Boris Tane)

Quando você tem uma implementação de referência de outro projeto/repo:

```xml
<task>
Quero implementar [FEATURE] seguindo o padrão abaixo.
</task>

<reference_implementation>
[COLE O CÓDIGO DE REFERÊNCIA AQUI]
</reference_implementation>

<instructions>
Leia o PRD.md e o código de referência acima.
Gere o SPEC.md adotando uma abordagem similar, adaptada ao nosso codebase.
</instructions>
```

---

## Referências

- `AGENTS.md` — Routing Table, Commands, Definition of Done, Escalation Rules
- `docs/MEMORY.md` — Fonte de verdade viva do projeto (carregado automaticamente)
- `PRD.md` — Output da Etapa 1 (Research)
- `SPEC.md` — Output da Etapa 2 (Spec)
- Anthropic Prompt Engineering Docs — https://platform.claude.com/docs/en/build-with-claude/prompt-engineering
