# ERROS.md — Erros Críticos Identificados no Sistema de Deploy

> **Última atualização:** 2026-03-28
> **Analisados:** `deploy.sh`, `oracle-cloud-setup.sh`, `deploy.yml`, `oracle_vm_setup_guide.md`

---

## 🔴 CRÍTICO

### 1. Lógica do Rollback Invertida

**Arquivo:** `.github/scripts/deploy.sh`
**Linha:** 75-81

```bash
OLD_IDS=$(echo "${PREVIOUS_IMAGE_IDS}" | tr ',' '\n')
for OLD_ID in ${OLD_IDS}; do
  docker image tag "${OLD_ID}" "${OLD_ID}-rollback" 2>/dev/null || true
done
```

**Problema:** O código marca as imagens **atuais** com `-rollback` ao invés de restaurar as imagens **anteriores** como `latest`. No rollback, os containers sobem com a mesma imagem quebrada do deploy que falhou.

**Impacto:** Rollback ineficaz — a aplicação continua quebrada após falha.

---

### 2. Snapshot Tirado no Momento Errado

**Arquivo:** `.github/scripts/deploy.sh`
**Linha:** 104

```bash
snapshot_images
```

**Problema:** O snapshot é tirado **DEPOIS** do `git pull` (linha 102), não antes. Isso significa que captura as imagens do **novo código** que falhou, não do código anterior que estava funcionando.

**Impacto:** Rollback usa imagens quebradas ao invés das imagens funcionais anteriores.

---

### 3. Migration Falha Não Para o Deploy

**Arquivo:** `.github/scripts/deploy.sh`
**Linha:** 126-128

```bash
if ! ${DOCKER_COMPOSE} run --rm --entrypoint bin/rails app db:migrate >"${MIGRATE_LOG}" 2>&1; then
  echo "[deploy] WARNING: Migration failed — see ${MIGRATE_LOG} for details"
  cat "${MIGRATE_LOG}"
fi
# Script CONTINUA mesmo com falha!
```

**Problema:** Se a migration falhar, o script continua e os containers reiniciam com um banco de dados incompatível. A aplicação vai quebrar.

**Impacto:** Ambiente de produção com banco de dados quebrado.

---

### 4. usermod Sem Verificação de Usuário

**Arquivo:** `scripts/oracle-cloud-setup.sh`
**Linha:** 217

```bash
usermod -aG docker ubuntu
```

**Problema:** Se o usuário `ubuntu` não existir (ex: Oracle Linux usa `opc`, ou Ubuntu Minimal usa outro user pelo cloud-init), o script falha silenciosamente ou dá erro.

**Impacto:** Script falha em imagens Ubuntu que não criam usuário ubuntu por padrão.

---

### 5. GPG Key Sem Verificação de Fingerprint

**Arquivo:** `scripts/oracle-cloud-setup.sh`
**Linha:** 182

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

**Problema:** Baixa a chave GPG do Docker sem verificar a fingerprint — vulnerable a ataques MITM (Man-In-The-Middle).

**Impacto:** Potencial comprometimento do repositório apt.

---

## 🟡 MÉDIO

### 6. Prune Sem Filtro Seguro

**Arquivo:** `.github/scripts/deploy.sh`
**Linha:** 135

```bash
docker image prune -f
```

**Problema:** Pode remover imagens "dangling" que ainda são necessárias para rollback de deploys anteriores ou para outros containers.

**Impacto:** Perda acidental de imagens utilizáveis.

---

### 7. Referência a .env.example Inexistente

**Arquivo:** `docs/oracle_vm_setup_guide.md`
**Linha:** 214

```bash
sudo -u ubuntu cp .env.example .env
```

**Problema:** O arquivo `.env.example` **não existe** no projeto — existe apenas `.env` (que geralmente está no `.gitignore`).

**Impacto:** Guia de setup incorrect/confuso para novos desenvolvedores.

---

## 📋 Checklist de Correções

| # | Status | Descrição |
|---|--------|-----------|
| 1 | [ ] Corrigir lógica de rollback para restaurar imagens anteriores |
| 2 | [ ] Mover snapshot_images para ANTES do git pull |
| 3 | [ ] Fazer deploy PARAR quando migration falha |
| 4 | [ ] Verificar existência do usuário antes de usermod |
| 5 | [ ] Adicionar verificação de fingerprint GPG |
| 6 | [ ] Usar filtro seguro no docker image prune |
| 7 | [ ] Corrigir guia para usar .env correto |

---

## 🚀 Melhorias Futuras (Não Críticas)

| # | Descrição | Prioridade |
|---|-----------|------------|
| **A** | Healthcheck pós-rollback — adicionar verificação de saúde dos serviços após rollback para confirmar que os containers estão funcionando corretamente. | Média |
| **B** | Notificação Discord em caso de rollback — enviar alerta automático para o canal admin quando um rollback for executado, incluindo motivos e timestamp. | Média |
| **C** | Registro de métricas de deploy — criar log estruturado (JSON) com duração do deploy, tamanho das imagens, sucesso/falha para análise posterior. | Baixa |
| **D** | Timeout configurável para operações Docker — adicionar limites de tempo para build, migrate e restart, com cleanup automático em caso de deadlock. | Baixa |
| **E** | Rollback completo de imagens Docker — o script atual marca imagens antigas com `-rollback`, mas não as restaura como `latest`. Para rollback completo, seria necessário re-taggear as imagens antigas como `latest` antes do `docker compose up`. | Alta |

---

## Referências

-自带 Git reset for rollbacks: [Hoop.dev](https://hoop.dev/blog/git-reset-for-fast-deployment-rollbacks/)
- Docker rollback: [Kristof Kovacs](https://kkovacs.eu/docker-compose-rollback/)
- Git checkout vs reset: [Hoop.dev](https://hoop.dev/blog/git-checkout-vs-git-reset-understanding-the-key-differences/)