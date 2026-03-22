# MEMORY.md — BotDiscord Write-Back Memory

> **Fonte de verdade viva do projeto.** Este arquivo é lido obrigatoriamente pela IA no
> início de toda tarefa sistêmica e atualizado autonomamente via Write-Back Protocol
> definido em `AGENTS.md`.

---

## Contexto Ativo do Projeto

> O que estamos construindo / investigando nas últimas 48h.

- **[2026-03-22]** Setup inicial do repositório: Headless Rails 8.1 + SQLite WAL +
  Solid Queue/Cache. Estrutura de pastas, AGENTS.md com routing table, e docs de
  estratégia (comparativo IA, scraping gratuito, Docker Chrome) já criados.

---

## Padrões Sistêmicos Ratificados

> Decisões de tecnologia **finais e imutáveis** (salvo re-ratificação explícita do usuário).

| Data | Padrão | Contexto |
|------|--------|----------|
| 2026-03-14 | Solid Queue em vez de Sidekiq/Redis | Reduz dependências; SQLite single-file |
| 2026-03-14 | Solid Cache em vez de Redis Cache | Mesma razão acima |
| 2026-03-14 | SQLite WAL mode, 3 databases (primary, queue, cache) | Performance + simplicidade operacional |
| 2026-03-14 | Headless Rails (sem ActionView/Sprockets) | API-only, sem frontend server-rendered |
| 2026-03-14 | Jobs idempotentes com dedup window de 2h | Safe to re-run sem duplicatas |
| 2026-03-13 | Gemini Flash como modelo primário de análise | Custo-benefício vs. capacidade — pesquisa em `docs/comparativo_IA_gemini_gemma.md` |

---

## Lições Aprendidas de Bugs Recorrentes

> Memória episódica: anti-padrões e erros clássicos que **nunca** devem ser repetidos.
> Cada entrada deve ter data, descrição do problema, causa raiz, e resolução.

| Data | Bug / Anti-padrão | Causa Raiz | Resolução |
|------|-------------------|------------|-----------|
| — | *(nenhuma entrada ainda)* | — | — |

<!-- Template para novas entradas:
| YYYY-MM-DD | Descrição concisa do bug | O que causou | Como foi resolvido (`arquivo.rb`, classe, método) |
-->

---

## Decisões de Arquitetura Pendentes

> Questões abertas aguardando validação do usuário ou mais investigação.

- [ ] Estratégia de rate-limiting para scraping multi-plataforma (Twitter vs. Instagram)
- [ ] Escolha final de browser headless para Docker: Ferrum vs. Nodriver (Python)

---

## Cold Tier Protocol

> Conhecimento arquivado em `docs/memory/`. **NÃO carregar automaticamente** — buscar via `grep`/`rg` apenas sob demanda.

### Quando arquivar

| O que | Para onde | Gatilho |
|-------|-----------|---------|
| Decisão ratificada substituída | `decisions/` | Nova decisão sobrescreve a anterior |
| Bug resolvido e consolidado | `resolved_bugs/` | Consolidação mensal do MEMORY.md |
| Contexto de fase/sprint finalizado | `archived/` | Início de nova fase de trabalho |

### Formato do arquivo arquivado

`YYYY-MM-DD_descricao_curta.md` com:
- Data original da entrada
- Descrição do quê foi decidido/descoberto
- Referência ao arquivo/classe afetado
- Motivo da decisão ou resolução

### Consulta

Quando o agente está no passo 3 das Escalation Rules (terceira falha), buscar:
```bash
rg "<palavra-chave do problema>" docs/memory/
```

---

## Log de Mudanças na Memória

> Registro cronológico de cada write-back realizado neste arquivo.

| Data | Ação | Seção Afetada |
|------|------|---------------|
| 2026-03-22 | Criação inicial do MEMORY.md com padrões ratificados extraídos do AGENTS.md e docs/ | Todas |
| 2026-03-22 | Adicionadas Definition of Done e Escalation Rules ao AGENTS.md | AGENTS.md |
| 2026-03-22 | Criado Cold Tier protocol em MEMORY.md + estrutura `docs/memory/` | Cold Tier Protocol |
