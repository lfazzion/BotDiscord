# Audit de Segurança — deploy.sh + oracle-cloud-setup.sh

> **Data:** 2026-03-28
> **Escopo:** `.github/scripts/deploy.sh`, `scripts/oracle-cloud-setup.sh`
> **Objetivo:** Identificar brechas e fragilidades que impedem uso seguro em produção

---

## deploy.sh

### 🔴 Crítico

**A1. `StrictHostKeyChecking=no` permite MITM**
- Linha 28: `-o StrictHostKeyChecking=no`
- O SSH não verifica a identidade do host. Qualquer atacante na rede entre o
  runner do GitHub Actions e a VM pode interceptar a conexão.
- **Correção:** Remover a flag. Na primeira execução, fazer `ssh-keyscan` e
  registrar o host key no `known_hosts`. Nas execuções subsequentes, o SSH
  valida automaticamente.

**A2. Diff entre commits já avançados (git diff quebrado)**
- Linhas 80-81: `LOCAL=$(git rev-parse HEAD)` é capturado ANTES do pull.
- Linha 93: `git diff --name-only "${LOCAL}" "${REMOTE}"` — mas depois do
  `git pull` (linha 90), o HEAD já aponta para REMOTE. O diff compara o
  commit antigo com o novo — isso está correto, mas `CHANGED` lista arquivos
  que foram modificados. Se o pull trouxer merge commits, o diff pode não
  refletir corretamente o que mudou.
- **Correção:** Usar `git diff --name-only "${LOCAL}..HEAD"` após o pull,
  ou capturar `REMOTE` como commit hash em vez de `origin/main`.

**A3. Sem deploy lock — dois deploys simultâneos corrompem tudo**
- Não existe nenhum mecanismo de lock. Se dois workflows do GitHub Actions
  rodarem ao mesmo tempo (ex: push rápido em sequência), ambos fazem
  `git pull` + `build` + `migrate` concorrentemente.
- **Correção:** Usar `flock` na VM ou criar um lock file antes de iniciar.

**A4. Rollback não reverte migrations**
- Se a migration rodou com sucesso mas o health check falhou depois, o
  rollback faz `git reset` + `build`, mas o banco já tem a migration
  aplicada. O código antigo pode ser incompatível com o schema novo.
- **Correção:** Guardar o version de migration antes do deploy. No rollback,
  rodar `db:migrate:down` ou `db:rollback` para a versão anterior.

**A5. `|| true` no rollback mascara falhas reais**
- Linhas 68-71: todos os comandos do rollback terminam com `|| true`.
  Se o `git reset` falhar, o deploy "sucede" do ponto de vista do
  GitHub Actions (exit code 0 do heredoc).
- **Correção:** O rollback deve logar cada falha e retornar exit code
  não-zero se qualquer passo falhar. O `trap rollback ERR` não ajuda
  porque o rollback já é chamado pelo trap — o `|| true` impede que
  o trap propague o erro original.

### 🟡 Médio

**A6. Health check falso — `docker compose ps` não testa o serviço**
- Linha 127: `${DOCKER_COMPOSE} ps` apenas mostra se os containers estão
  rodando, não se o serviço responde. Um Puma com erro de boot aparece
  como "running" mas não serve requests.
- **Correção:** Fazer `curl -f http://localhost:3000/up` (Rails health
  endpoint) ou usar `docker compose exec app bin/rails runner "puts :ok"`.

**A7. Migrate log em /tmp pode sumir**
- Linha 58: `mktemp /tmp/deploy-migrate-XXXXXX.log` — logs temporários
  podem ser limpados por `systemd-tmpfiles` antes da investigação.
- **Correção:** Salvar em `${PROJECT_PATH}/log/deploy-migrate.log`.

**A8. Sem verificação de integridade do código deployado**
- Após `git pull`, não há verificação de assinatura GPG de commits nem
  checksums. Se o GitHub Actions runner for comprometido, código malicioso
  é deployado sem detecção.
- **Correção (opcional):** `git verify-commit HEAD` se commits assinados
  estiverem habilitados no repositório.

---

## oracle-cloud-setup.sh

### 🔴 Crítico

**B1. Script inteiro roda como root — sem drop de privilégios**
- O script precisa de root para muitas operações, mas algumas (como
  `git clone`, configuração de `.env`) poderiam rodar como usuário normal.
  Se o curl de download for comprometido, execução como root = comprometimento total.
- **Correção:** Executar apenas os comandos que precisam de root com `sudo`.
  Usar `sudo` pontualmente em vez de rodar tudo como root.

**B2. curl sem verificação de integridade dos pacotes Docker**
- Linha 203: `apt-get install docker-ce` instala sem verificar checksum.
  Se o repositório Docker for comprometido (supply chain attack), pacotes
  maliciosos são instalados.
- **Correção:** Adicionar `apt-get install --allow-change-held-packages`
  apenas se necessário. Validar checksums dos pacotes após instalação.

**B3. Reinício do SSH pode travar sessão**
- Linha 73: `systemctl restart ssh` — se a configuração drop-in tiver
  erro, o SSH pode não subir e você perde acesso à VM.
- **Correção:** Usar `sshd -t` (test config) antes de restart. Ou usar
  `systemctl reload ssh` em vez de `restart` (reload não mata conexões
  ativas).

**B4. `chown` hardcoded para `ubuntu` ignora `$DOCKER_USER`**
- Linha 284: `chown ubuntu:ubuntu "$PROJECT_DIR"` — mas o script detecta
  o usuário dinamicamente em `$DOCKER_USER` (linha 230). Inconsistência.
- **Correção:** `chown "${DOCKER_USER}:${DOCKER_USER}" "$PROJECT_DIR"`

**B5. `limits.d` hardcoded para `ubuntu`**
- Linha 269-272: `ubuntu soft nofile 65536` — mesmo problema do B4.
  Se a VM tem outro nome de usuário, os limites não se aplicam.
- **Correção:** Usar `${DOCKER_USER}` ou `*` wildcard.

**B6. Não idempotente — executar duas vezes causa problemas**
- Linha 157: `echo '/swapfile ...' >> /etc/fstab` — append duplicado
  se rodar duas vezes.
- Linhas 84-86: `iptables -I INPUT 1` — insere regras duplicadas no topo
  a cada execução.
- **Correção:** Verificar se a regra já existe antes de inserir.
  Para fstab: `grep -q` antes de append. Para iptables:
  `iptables -C` (check) antes de `-I`.

### 🟡 Médio

**B7. `fallocate` pode falhar silenciosamente em alguns filesystems**
- Linha 153: `fallocate -l 4G /swapfile` — em ext4 com `fallocate`
  não suportado (ex: alguns volumes OCI), falha silenciosamente.
- **Correção:** Usar `dd if=/dev/zero of=/swapfile bs=1M count=4096`
  como fallback, ou verificar exit code de `fallocate`.

**B8. Sem rollback do SSH se restart falhar**
- Se `systemctl restart ssh` (linha 73) falhar, não há mecanismo de
  recovery. O script continua (`set -e` ajuda, mas depende do exit code).
- **Correção:** Copiar config original antes de modificar. Restaurar
  se restart falhar: `cp /etc/ssh/sshd_config.d/99-botdiscord.conf.bak ...`

**B9. Sem verificação de espaço em disco antes de swap e Docker**
- Não verifica se há espaço suficiente antes de `fallocate 4G` nem
  antes de instalar Docker (~2GB).
- **Correção:** Verificar `df -BG / | awk 'NR==2{print $4}'` antes de
  alocar.

**B10. firewall sem default DROP**
- Linhas 84-86: apenas insere ACCEPT para 22/80/443. Não há regra
  default DROP ou REJECT. Se as OCI Security Lists não estiverem
  configuradas, todas as portas ficam abertas.
- **Correção:** Adicionar `iptables -P INPUT DROP` após as regras ACCEPT
  (com cuidado de não bloquear a sessão SSH atual).

---

## Resumo

| # | Severidade | Arquivo | Problema |
|---|-----------|---------|----------|
| A1 | 🔴 | deploy.sh | StrictHostKeyChecking=no — MITM |
| A2 | 🟡 | deploy.sh | git diff pode não refletir mudanças reais |
| A3 | 🔴 | deploy.sh | Sem deploy lock — concorrência |
| A4 | 🔴 | deploy.sh | Rollback não reverte migrations |
| A5 | 🔴 | deploy.sh | `\|\| true` mascara falhas |
| A6 | 🟡 | deploy.sh | Health check falso (só ps) |
| A7 | 🟡 | deploy.sh | Migrate log em /tmp pode sumir |
| A8 | 🟡 | deploy.sh | Sem verificação de integridade do código |
| B1 | 🔴 | setup.sh | Tudo roda como root |
| B2 | 🟡 | setup.sh | Sem checksum dos pacotes Docker |
| B3 | 🔴 | setup.sh | restart SSH pode travar sessão |
| B4 | 🟡 | setup.sh | chown hardcoded ubuntu |
| B5 | 🟡 | setup.sh | limits.d hardcoded ubuntu |
| B6 | 🔴 | setup.sh | Não idempotente |
| B7 | 🟡 | setup.sh | fallocate pode falhar silenciosamente |
| B8 | 🟡 | setup.sh | Sem rollback do SSH config |
| B9 | 🟡 | setup.sh | Sem verificação de espaço em disco |
| B10 | 🔴 | setup.sh | Firewall sem default DROP |

**Totais:** 6 críticos, 10 médios
