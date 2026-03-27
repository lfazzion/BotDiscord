## Prompt

Você é um engenheiro de software sênior responsável por executar o workflow Git completo
de uma fase recém-implementada. Siga EXATAMENTE as etapas abaixo, em ordem, sem pular
nenhuma. Em caso de dúvida, pergunte — nunca assuma.

---

## PRÉ-REQUISITOS (preencha antes de submeter)

- [ ] `[BRANCH_BASE]` → branch base real (ex: `main` ou `develop`)
- [ ] `[NOME_DA_FASE]` → nome descritivo da fase implementada
- [ ] `[TIPO]` → tipo Conventional Commit (`feat` | `fix` | `refactor` | `chore` | `perf` | `docs`)
- [ ] `[NOME_DO_BRANCH]` → nome completo do branch (ex: `feat/add-instagram-scraper`)

---

## CONTEXTO DO PROJETO

- Projeto: BotDiscord (Router) — Rails 8.1 headless, Ruby ~> 4.0, SQLite3 WAL, Solid Queue/Cache
- Branch base: `[BRANCH_BASE]`
- Fase implementada: `[NOME_DA_FASE]`
- Tipo de mudança: `[TIPO]`

---

## ETAPA 0 — PRÉ-VERIFICAÇÃO DO ESTADO DO REPOSITÓRIO

Antes de qualquer ação, verifique o estado:

```bash
git branch          # confirmar branch atual
git status          # confirmar ausência de mudanças não relacionadas
git diff --check    # detectar erros de whitespace (trailing spaces, mixed tabs)
```

### Output esperado:
- Informe o branch atual
- Se houver mudanças **não relacionadas** à fase: execute `git stash` e reporte antes de continuar
- Se `git diff --check` reportar erros: corrija antes de continuar

---

## ETAPA 1 — LEITURA DE CONTEXTO (obrigatória antes de qualquer git action)

1. Leia `docs/MEMORY.md` — verificar decisões ratificadas, lições aprendidas, contexto ativo
2. Leia `AGENTS.md` — regras cross-cutting, Definition of Done, Naming Conventions
3. Identifique se a fase envolve migrations, novos models, jobs, ou scraping — leia os
   CONTEXT.md correspondentes conforme a Routing Table do AGENTS.md

### Output esperado:
- Confirme os 3 arquivos lidos
- Liste quaisquer decisões ratificadas ou lições aprendidas **relevantes a esta fase**

---

## ETAPA 2 — ANÁLISE DE MUDANÇAS

Execute e analise todos os outputs:

```bash
git status
git diff --stat
git diff
git log --oneline -5
```

### Output esperado:
- Liste TODOS os arquivos: modificados (M), criados (A), deletados (D), renomeados (R)
- Identifique o escopo de cada mudança (`model`, `service`, `job`, `migration`, `test`, `config`, `prompt`, `script`)
- Detecte se há mudanças **NÃO relacionadas** à fase — se sim, NÃO inclua no mesmo commit
- Verifique se há arquivos sensíveis (`.env`, credentials, secrets) — NUNCA inclua
- **Se detectar mistura de escopos**: proponha divisão em commits atômicos ANTES de prosseguir

### Se falhar:
- Se `git diff` mostrar conflitos de merge: **PARE**, reporte e aguarde instrução
- Se houver arquivos sensíveis staged: `git restore --staged <arquivo>` imediatamente

---

## ETAPA 3 — VALIDAÇÃO PRÉ-BRANCH (Definition of Done check)

Antes de criar o branch, confirme CADA item. Se algum falhar, CORRIJA antes de prosseguir:

| # | Check | Comando / Ação |
|---|-------|----------------|
| 1 | Todos os testes passam | `docker-compose -f docker/docker-compose.yml run --rm test` |
| 2 | Sem warnings de sintaxe nos .rb modificados | `ruby -cw <arquivo>` para cada `.rb` alterado |
| 3 | Migration roda limpo (se aplicável) | `docker-compose -f docker/docker-compose.yml exec app bin/rails db:migrate:status` |
| 4 | Novo código tem testes correspondentes | Verificar que `test/` espelha `app/` ou `lib/` |
| 5 | Sem secrets hardcoded | Revisão manual de todos os arquivos alterados |
| 6 | MEMORY.md atualizado (se decisão arquitetural) | Entrada com `[YYYY-MM-DD]` |

### Output esperado:
- Tabela com status ✅ / ❌ de cada item
- Para cada ❌: descreva o problema e como corrigiu antes de continuar

### Se falhar:
- Se testes falharem: corrija o código, não os testes
- Se não houver test correspondente: crie antes de continuar — nunca pule esta etapa

---

## ETAPA 4 — CRIAÇÃO DO BRANCH

```bash
git checkout [BRANCH_BASE]
git pull origin [BRANCH_BASE]
git checkout -b [NOME_DO_BRANCH]
```

Convenções de nomenclatura:
- Prefixo: `feat/`, `fix/`, `refactor/`, `chore/`, `perf/`, `docs/`, `test/`, `hotfix/`
- Formato: `[tipo]/[verbo]-[descricao-curta]` em kebab-case
- Exemplos válidos: `feat/add-instagram-scraper`, `fix/resolve-chrome-ws-timeout`, `refactor/extract-discovery-service`
- Exemplos INVÁLIDOS: `feature/update`, `branch1`, `changes`, `wip`

### Output esperado:
- Confirme branch criado com `git branch --show-current`

### Se falhar:
- Se branch já existir: **NÃO sobrescreva** — reporte e pergunte antes de prosseguir
- Se `git pull` falhar: reporte o erro exatamente como apareceu e aguarde instrução

---

## ETAPA 5 — STAGING INTELIGENTE

Regras:
- **NUNCA** use `git add -A` — adicione arquivos individualmente por grupo lógico
- Use `git add <arquivo>` para cada arquivo, verificando com `git status` após cada grupo
- Para arquivos com **mudanças mistas** (ex: fix + refactor no mesmo arquivo), use `git add -p <arquivo>`
  para staging seletivo por hunk — isso permite commits verdadeiramente atômicos
- Se houver múltiplos commits lógicos independentes, **DIVIDA em commits atômicos**
- Confirme staging com `git diff --cached --name-only` antes de commitar
- Se `git diff --cached --name-only` retornar vazio: **PARE** — nada está staged

### Output esperado:
- Lista de arquivos staged por grupo lógico
- Confirmação de `git diff --cached --name-only`

---

## ETAPA 6 — COMMIT (Conventional Commits)

Formato obrigatório:

```
<tipo>(<escopo>): <descrição concisa imperativa>

<corpo opcional: O QUE mudou e POR QUE — apenas se não óbvio>

<footer: Closes #N, Fixes #N, BREAKING CHANGE: ...>
```

Tipos: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`, `revert`
Escopo: componente afetado (`auth`, `scraper`, `models`, `jobs`, `discovery`, etc.)

Regras de formatação:
- Título: máximo 50 caracteres, imperativo (ex: "add", "fix", "remove"), sem ponto final
- Corpo: máximo 72 caracteres por linha, apenas se a mudança precisar de contexto
- Se `BREAKING CHANGE`, usar `!` após o tipo: `feat!: change API response format`

Exemplos:
```
feat(scraper): add Instagram reels collection via nodriver

Implement parallel collection of reels metadata including view count,
like count, and audio info. Uses Python nodriver sidecar container.

Closes #42
```

```
fix(chrome): resolve WebSocket timeout on cold start

Chrome headless container needs 3s warmup before accepting CDP
connections. Added retry with exponential backoff.

Fixes #87
```

Para mensagens com corpo/footer, use múltiplos `-m` ou heredoc:

```bash
# Opção A — múltiplos -m
git commit \
  -m "feat(scraper): add Instagram reels collection via nodriver" \
  -m "Implement parallel collection of reels metadata including view count,
like count, and audio info. Uses Python nodriver sidecar container." \
  -m "Closes #42"

# Opção B — heredoc (recomendado para corpos longos)
git commit -F- <<'COMMIT_MSG'
feat(scraper): add Instagram reels collection via nodriver

Implement parallel collection of reels metadata including view count,
like count, and audio info. Uses Python nodriver sidecar container.

Closes #42
COMMIT_MSG
```

Confirme com `git log -1 --format=fuller` que o commit está correto.

### Output esperado:
- A mensagem de commit completa usada
- Output de `git log -1 --format=fuller`

---

## ETAPA 7 — PUSH

```bash
git push -u origin [NOME_DO_BRANCH]
```

### Output esperado:
- URL do branch no GitHub (reportada pelo `git push`)

### Se falhar:
- Se push falhar por divergência: **NUNCA use `--force`** — reporte o erro e aguarde instrução
- Se falhar por auth: reporte e aguarde — nunca tente contornar

---

## ETAPA 8 — PULL REQUEST

Verifique autenticação antes de criar o PR:

```bash
gh auth status
```

### Se falhar:
- Se `gh` não estiver autenticado ou não instalado: forneça o template do PR manualmente para criar via interface GitHub e continue para a ETAPA 9

Use `gh pr create` com o template estruturado abaixo. Ajuste os campos ao contexto real da fase.

```bash
gh pr create \
  --base [BRANCH_BASE] \
  --title "<título descritivo, <70 chars>" \
  --label "[TIPO]" \
  --body "$(cat <<'EOF'
## Resumo
[2-3 sentenças: O que esta fase implementa e por quê]

## Tipo de Mudança
- [ ] feat — nova funcionalidade
- [ ] fix — correção de bug
- [ ] refactor — refatoração sem mudança de comportamento
- [ ] perf — melhoria de performance
- [ ] chore — tarefa de manutenção
- [ ] docs — documentação

## O que mudou

### Arquivos Criados
| Arquivo | Propósito |
|---------|-----------|
| `app/services/exemplo_service.rb` | [descrição] |
| `test/services/exemplo_service_test.rb` | [teste correspondente] |

### Arquivos Modificados
| Arquivo | Natureza da Mudança |
|---------|---------------------|
| `app/models/social_profile.rb` | [o que mudou e por quê] |
| `db/migrate/20260326000001_add_field.rb` | [nova coluna / tabela] |

### Arquivos Deletados
| Arquivo | Motivo |
|---------|--------|
| `app/services/old_service.rb` | [substituído por / obsoleto] |

### Migrações (se aplicável)
- Migration: `[nome]` — [descrição do que faz]
- Reversível: [sim/não]
- Risco de downtime: [nenhum / baixo / médio]

## Pontos Importantes
- [Decisão de arquitetura 1 e motivo]
- [Decisão de arquitetura 2 e motivo]
- [Possíveis breaking changes]

## Como Testar
1. [Passo específico para verificar funcionalidade no contexto Rails/Docker]
2. [Comando para rodar testes relevantes]
3. [Verificação manual se aplicável]

## Checklist
- [ ] Tests passam: `docker-compose -f docker/docker-compose.yml run --rm test`
- [ ] Syntax clean: `ruby -cw <arquivo>` para cada `.rb`
- [ ] Migration status OK
- [ ] MEMORY.md atualizado (se aplicável)
- [ ] Sem secrets hardcoded
- [ ] Branch naming segue convenção
- [ ] Commit message segue Conventional Commits

## Riscos / Atenção Manual
- [Item que precisa de revisão humana ou depende de infra externa]
- [Nenhum, se tudo está coberto por testes]

## Dependências
- [Migrations adicionadas]
- [Dependências Ruby/Python adicionadas ou removidas]
- [Impactos em outros serviços (discord-bot, jobs, chrome)]

## Breaking Changes
[Nenhum] ou [descrição + migração necessária]

---
🤖 Generated with AI Assistant | Branch: [NOME_DO_BRANCH]
EOF
)"
```

### Output esperado:
- URL do PR criado

---

## ETAPA 9 — VERIFICAÇÃO FINAL

```bash
gh pr view          # confirmar PR criado corretamente
git status          # confirmar branch limpo, sem staged files esquecidos
git log --oneline -3
```

### Output esperado (relatório final):

1. ✅ Branch criado: `[nome]`
2. ✅ Commits: `[hash] [mensagem]`
3. ✅ PR URL: `[link]`
4. ✅ Resumo executivo (3-5 linhas)
5. ⚠️ Riscos ou itens que precisam de atenção manual

---

## ROLLBACK — Se precisar desfazer

| Situação | Comando |
|----------|---------|
| Desfazer staging de um arquivo | `git restore --staged <arquivo>` |
| Desfazer último commit (local, mantém mudanças) | `git reset --soft HEAD~1` |
| Deletar branch local (antes do merge) | `git checkout [BRANCH_BASE] && git branch -d [NOME_DO_BRANCH]` |
| Desfazer push (cria revert commit) | `git revert HEAD && git push` |
| Verificar histórico de HEADs | `git reflog` |

> **NUNCA** use `git reset --hard` em branch compartilhado — use `git revert` para branches já pusheados.

---

## REGRAS INVIOLÁVEIS

1. Nunca force-push para `main` ou `master`
2. Nunca inclua secrets, chaves de API, ou credenciais
3. Sempre rode testes (ETAPA 3) antes de qualquer commit
4. Commits atômicos > commits monolíticos — um commit por mudança lógica
5. Nunca delete branch local antes do merge do PR
6. Se algo falhar: documente o erro e PEÇA instrução — nunca adivinhe nem "conserte" sem entender
7. PR body deve ser autocontido — alguém sem contexto deve entender o quê e por quê
8. Respeite TODAS as Cross-Cutting Rules do AGENTS.md (frozen_string_literal, 2-space indent, etc.)
9. Se a fase gerou decisão arquitetural, execute o Write-Back Protocol para docs/MEMORY.md
10. Nunca use `git add -A` — sempre staging explícito por arquivo
11. Nunca use `--no-verify` em commits — respeite todos os git hooks
12. Nunca use `git reset --hard` em branches já pusheados — use `git revert`
