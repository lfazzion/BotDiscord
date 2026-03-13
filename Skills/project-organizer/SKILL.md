---
name: project-organizer
description: Organiza e estrutura projetos de software usando um sistema de pastas e arquivos markdown inspirado na metodologia "Folder System" de Jake Van Clief. Use esta skill sempre que o usuário mencionar organização de projeto, estrutura de pastas, criação de PRDs, specs, gerenciamento de tarefas, setup de projeto, planejamento de features, ou quiser reorganizar a base de código. Também acione quando o usuário pedir para criar documentação de projeto, definir convenções, ou estruturar um novo módulo.
---

# Project Organizer

Skill para organizar projetos de software utilizando um sistema baseado em **pastas e arquivos markdown** como infraestrutura de coordenação. A filosofia central: **o arquivo é o sistema** — a estrutura de diretórios, as convenções de nomes e os documentos markdown são a metodologia, não ferramentas externas.

Este sistema é inspirado no design de pipelines Unix, na programação literária e no conceito de "information hiding" — cada pasta encapsula um contexto específico, e a IA navega entre elas para assumir diferentes papéis sem precisar de múltiplos agentes.

## Hierarquia de Contexto em 5 Camadas

Toda organização de projeto segue esta hierarquia, da camada mais estável à mais volátil:

### 1. Identity (Memória do Projeto)

Um arquivo na **raiz** do projeto que funciona como "cérebro" persistente. Ele garante que qualquer IA que abra o projeto entenda imediatamente o contexto completo.

Crie um arquivo `CLAUDE.md` (ou `GEMINI.md`, dependendo da IA principal) contendo:
- Stack técnica e versões
- Convenções de código (linguagem, estilo, patterns)
- Arquitetura macro do sistema
- Regras invioláveis do projeto (ex: "NULL nunca é zero", "tools retornam Hashes puros")
- Links para documentação essencial dentro do repo

Este arquivo deve ser **conciso** (máximo 100-150 linhas). Se precisar de mais detalhes, aponte para arquivos em `Documentations/`. A IA carrega este arquivo toda sessão — ele é o equivalente a um onboarding instantâneo.

**Exemplo para o projeto BotDiscord:**
```markdown
# BotDiscord - Sistema de Data Mining para Influencers

## Stack
- Rails 8.1 Headless (Solid Queue, Solid Cache)
- SQLite3 em WAL mode
- Docker Compose (app, jobs, chrome)
- Discord Bot (discordrb)
- LLM: Gemini 3.1 Flash Lite (batch) + Gemma 3 27B (chat)

## Regras Invioláveis
- NULL != 0 — métricas sem dados são nil, nunca zero
- Tools retornam Hashes/Arrays puros, nunca strings formatadas
- Clamping obrigatório em todos os parâmetros LLM
- Erros em Tools retornam {status: :error}, nunca raise

## Documentação
- Requisitos: Requisitos_Projeto_Data_Mining.md
- Plano: Plano_Prioridade_Implementacao.md
- AI Strategy: Documentations/estrategia_multi_model_ai.md
```

### 2. Routing (Estrutura de Pastas)

A estrutura de pastas **é** o roteamento. Cada diretório representa um domínio funcional, e ao navegar para ele, a IA muda de contexto automaticamente. Organize por **funcionalidade/workflow**, não por tipo de arquivo.

Para a estrutura de pastas recomendada deste projeto, consulte `references/folder-structure.md`.

**Princípios de Routing:**
- Cada pasta deve ter propósito claro e auto-descritivo
- Convenções de nomes substituem bancos de dados — nomes descritivos em `snake_case`
- Profundidade máxima de 3 níveis para evitar complexidade
- Pastas são baratas, crie uma nova ao invés de misturar contextos

### 3. Stage Contracts (PRDs e Specs)

Cada mudança significativa no projeto passa por um pipeline de documentos que funcionam como **contratos** entre etapas. Isso evita o problema de "IA codando sem contexto".

O fluxo é sequencial e disciplinado:

```
Pesquisa → PRD → /clear → SPEC → /clear → Implementação
```

O `/clear` entre etapas é intencional — limpar o contexto da IA entre fases evita que informações de pesquisa "sujem" a execução tática. Cada documento carrega apenas o que a próxima fase precisa.

**Quando usar Stage Contracts:**
- Features novas que afetam múltiplos arquivos
- Mudanças arquiteturais
- Integração com APIs externas
- Qualquer tarefa onde "começar a codar direto" geraria retrabalho

**Quando pular direto para implementação:**
- Bugfixes simples e isolados
- Refatorações mecânicas (rename, extract method)
- Mudanças em 1-2 arquivos com escopo óbvio

Para templates completos de PRD, SPEC e Tasks, consulte `references/templates.md`.

### 4. Reference Material (Documentação)

Documentação técnica viva que a IA consulta sob demanda. Não precisa estar no contexto o tempo todo — a IA busca quando relevante.

**Organização recomendada:**
```
Documentations/
├── arquitetura/           # Decisões arquiteturais
├── integrações/           # APIs externas, Docker setup
├── convenções/            # Style guides, patterns
└── pesquisas/             # Comparativos, benchmarks
```

Cada arquivo de referência deve ter:
- Um título claro descrevendo o conteúdo
- Contexto de quando foi escrito/atualizado
- Informação acionável (não apenas teoria)

### 5. Working Artifacts (Outputs)

Os outputs gerados durante o trabalho: código, análises, relatórios. Eles são o resultado das 4 camadas anteriores trabalhando juntas.

Artifacts de trabalho incluem:
- Código fonte em `app/`, `lib/`, `config/`
- PRDs e SPECs concluídos (movidos ou marcados como `done`)
- Relatórios de análise e pesquisas geradas pela IA
- Logs e resultados de testes

## Workflow Operacional

### Iniciando uma Nova Feature

1. **Pesquise** — Peça à IA para analisar a base de código, ler documentação externa e identificar arquivos afetados
2. **Gere o PRD** — Um documento focado em *o quê* e *por quê* (veja template em `references/templates.md`)
3. **Limpe contexto** e gere a **SPEC** — Um documento focado em *como*, com caminhos exatos e pseudocódigo
4. **Limpe contexto** e **implemente** — Seguindo a SPEC ao pé da letra

### Gerenciando Tarefas

Tarefas são armazenadas como arquivos (JSON ou Markdown) dentro de uma pasta `Tasks/` ou diretamente no PRD/SPEC. Cada tarefa tem:

```json
{
  "id": "TASK-001",
  "title": "Setup Docker Compose com Chrome Headless",
  "status": "pending",
  "phase": "P0-fundacao",
  "blocked_by": [],
  "description": "Montar docker-compose.yml com services app, jobs, chrome"
}
```

O campo `blocked_by` cria um grafo de dependências natural — a IA sabe que não pode iniciar uma tarefa até que suas dependências estejam concluídas.

**Status possíveis:** `pending` → `in_progress` → `done` | `blocked`

### Convenções de Nomes

Nomes são a interface entre humanos e IAs. Bons nomes eliminam a necessidade de metadados extras:

| Elemento | Convenção | Exemplo |
|----------|-----------|---------|
| Pastas | `snake_case`, descritivo | `coleta_scraping/`, `motor_llm/` |
| Documentos | `PascalCase` ou `snake_case` com contexto | `PRD_Discovery_Pipeline.md` |
| Tarefas | Prefixo `TASK-NNN` | `TASK-042_implementar_rate_limiter` |
| Configs | Agrupados por domínio | `config/prompts/`, `config/llm/` |
| Skills | `kebab-case` descritivo | `project-organizer`, `data-miner` |

### Reorganizando um Projeto Existente

Ao reorganizar a estrutura de um projeto já existente:

1. **Mapeie** o estado atual — liste todos os arquivos e identifique suas categorias
2. **Identifique gaps** — o que está faltando? (Identity file? PRDs? Convenções?)
3. **Proponha** a nova estrutura usando a hierarquia de 5 camadas como guia
4. **Migre incrementalmente** — mova arquivos em lotes lógicos, nunca tudo de uma vez
5. **Atualize referências** — garanta que links internos e imports não quebrem
6. **Documente** — atualize o Identity file com a nova estrutura

### Criando um Novo Módulo

Para cada novo módulo ou componente significativo:

1. Crie a pasta no local correto da hierarquia
2. Adicione um `README.md` interno explicando o propósito do módulo
3. Defina as interfaces (inputs/outputs) antes de implementar
4. Registre no Identity file se for um componente core

## Anti-Patterns a Evitar

- **Pasta "misc" ou "utils" gigante** — Se crescer acima de 5 arquivos, desmembre por domínio
- **Documentação órfã** — Todo doc deve ser referenciado de algum lugar (Identity file, PRD, ou README)
- **Over-nesting** — Mais de 3 níveis de profundidade indica que os domínios precisam ser repensados
- **Specs como ficção** — Uma SPEC que ninguém segue é pior que nenhuma SPEC. Mantenha-as atualizadas ou delete-as
- **PRDs sem data** — Sempre inclua `created_at` e `updated_at` nos documentos de projeto
