# Propostas de Melhoria: Deploy Script (`deploy.sh`)

Após pesquisa de validação contra o atual Estado da Arte (2025/2026), ajustamos as recomendações levando em conta o **nível de Pragmatismo vs. Overengineering** aplicável a um setup em **Single VM** (Oracle Cloud Free Tier).

Abaixo estão listadas apenas as propostas sensatas e de alto valor, separadas por grau de prioridade e risco de complexidade exagerada.

---

## 🟢 Prioridade Alta: Pragmatismo Puro (Custo Zero, Sem Overengineering)

Estas alterações exigem apenas algumas linhas de código bash/docker ou ajustes simples de configuração, sem adicionar dependências externas complexas, mas aumentam enormemente a resiliência e a segurança.

### 1. Robustez no Bash Strict Mode (`set -E`)
* **Problema atual:** O script usa `set -euo pipefail`, mas omite o `-E`. O comportamento padrão do Bash não herda o `trap ERR` (que engatilha o rollback) quando os erros acontecem no escopo de funções internas ou subshells.
* **Proposta:** Adicionar `set -Eeuo pipefail`.
* **Proposta:** Utilizar o designador `local` nas variáveis criadas dentro de funções em Bash (ex: `local _ROLLBACK_IN_PROGRESS`) para blindar o escopo global de poluição ou concorrências sutis.

### 2. Rollback Determinístico (Evitar Rebuild durante Crises)
* **Problema atual:** Se houver falha na migration, o `rollback()` atual executa um checkout git e refaz o comando de build (`docker compose build`). Fazer um *build* sob tensão aumenta muito o Risco de Falência (ex: falhas transitórias de conexão apt, rubygems).
* **Proposta:** Passar o hash do commit atual como *Tag* exclusiva da imagem durante o build (ex: `IMAGE_TAG=$LOCAL docker compose build`). Em um fluxo de rollback, o script nunca tenta dar "build" novamente; ele apenas altera o compose para usar a versão da tag `$LOCAL` (ou tag prévia conhecida), realizando o restabelecimento instantâneo através do que já foi testado e cacheado localmente.

### 3. Substituição de Healthchecks Interativos (Fim do Sleep)
* **Problema atual:** O script testa a saúde manualmente usando um laço `for` com `curl` e `sleep` de 5 segundos.
* **Proposta:** Integrar o bloco unificado de `healthcheck:` no contexto do `docker-compose.yml` para a aplicação e usar o comando nativo **`docker compose wait app`** (introduzido nativamente no Compose V2.x). O compose processa a rechecagem repetitiva de forma transparente e só libera o script ou gera exception (`exit 1`) quando as regras são atingidas, simplificando radicalmente o código shell.

### 4. Autenticação Segura (GitHub Self-Hosted Runner)
* **Problema atual:** O fluxo "Push" atual usa a variável estática `SSH_PRIVATE_KEY` para entrar na VM de fora para dentro, exigindo que a porta 22 (SSH) da sua Oracle Cloud fique indefinidamente exposta à internet para o `ubuntu-latest` poder conectar.
* **Proposta (O Novo Padrão de Infraestrutura):** Adotar o **GitHub Self-Hosted Runner** direto dentro dessa VM. 
  * O agente já vai estar instalado no host alvo; conectando com HTTPS "outgoing" pro GitHub de forma 100% isolada e reativa ("Pull").
  * Com o `runs-on: self-hosted`, abolimos do Github Secrets as chaves criptográficas (Zero Keys), trancamos a porta 22 por completo num firewall hermético, e evitamos a enorme complexidade técnica ("overengineering") de tentar acoplar a IAM da Oracle via Trust-Policies OIDC. Isso atinge o **estado da arte de segurança local** com esforço quase zero.

---

## 🟡 Prioridade Média/Opcional: Limite do "Zero-Downtime"

Pode ser *overengineering* dependendo da sua banda de SLA:

### 5. Zero Downtime Deployments (ZDD) Standalone
* **O Contexto:** Com `docker compose up -d --force-recreate` numa VM única, os contêineres velhos descem primeiro para depois os novos subirem. Existe uma brecha inevitável de queda da API de alguns segundos.
* **Proposta Pragmática:** Se ZDD for um requisito de negócio indispensável, a recomendação mais simples (livre de swarm kubernetes) é subir uma infra de reversão via proxy (ex: plugin `docker-rollout` ou script de Nginx proxy reload).  
* **Porém:** Para Bots do Discord e tarefas de background jobs processadas no Solid Queue, se alguns segundos de instabilidade no deploy não prejudicarem as regras de concorrência ou features vitais, aceitar o `force-recreate` com downtime em torno de ~5 segundos costuma ser o limite saudável antes de incorrer em *Overengineering*.

---

## 🔴 Rejeitados na Fase Pragmática (Overengineering Comprovado)

* **OIDC na Oracle Free Tier:** Instaurar OpenID Connect só para fazer um simples Push de Git via SSH. Resolvemos isso mais rápido com a adoção do **Self-Hosted Runner** no item 4.
* **Standalone Docker Swarm / Kubernetes:** Levantar todo o *overhead* de orquestração de Data Center num nó (node) unitário só para fazer implementações sem micro-downtime num servidor de 24GB. Não vale o custo transacional.
