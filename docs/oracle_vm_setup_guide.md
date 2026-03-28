# Guia de Setup — VM Oracle Cloud (Ampere A1)

> **Última atualização:** 2026-03-28
> **Script:** `scripts/oracle-cloud-setup.sh`
> **Tempo estimado:** ~15 minutos (excluindo espera de provisionamento)

---

## Pré-requisitos

- [x] Conta Oracle Cloud criada em https://cloud.oracle.com/free
- [x] Chave SSH gerada localmente
- [x] Conexão com internet

---

## Parte 1: Criar a conta Oracle Cloud

### 1.1 Cadastro

1. Acesse https://cloud.oracle.com/free
2. Clique em **Start for free**
3. Preencha:
   - Country: **Brazil**
   - Email: seu email
   - Name: seu nome
4. **Verificação de email** — clique no link recebido
5. **Verificação de telefone** — código por SMS

### 1.2 Configurar pagamento

> **Importante:** O cartão de crédito é usado apenas para verificação de identidade. **Não é cobrado** enquanto você usar apenas recursos Always Free. Se ultrapassar os limites, a conta é **pausada**, não cobrada automaticamente.

- Insira um cartão de crédito (qualquer um)
- O sistema faz uma pré-autorização de ~$100 (devolvida em alguns dias)
- Após aprovação, você ganha $300 em créditos para usar em 30 dias

### 1.3 Definir região home

> **Crucial:** A região home define onde seus Always Free resources ficam. **Não pode ser alterada depois.**

- Ao fazer login pela primeira vez, será solicitado para escolher a região
- **Recomendado:** `sa-saopaulo-1` (São Paulo) — mais próxima, menor latência para usuários BR
- Alternativa: `us-ashburn-1` (Virginia) — mais opções de disponibilidade

---

## Parte 2: Gerar chaves SSH

### macOS / Linux

```bash
# Gerar par de chaves (Ed25519 — mais seguro que RSA)
ssh-keygen -t ed25519 -C "oracle-botdiscord" -f ~/.ssh/oracle_botdiscord

# Verificar chaves criadas
ls -la ~/.ssh/oracle_botdiscord*

# Visualizar chave pública (copiar para o console Oracle)
cat ~/.ssh/oracle_botdiscord.pub
```

### Windows (PowerShell)

```powershell
ssh-keygen -t ed25519 -C "oracle-botdiscord" -f "$env:USERPROFILE\.ssh\oracle_botdiscord"
```

---

## Parte 3: Criar a VM no Console OCI

### 3.1 Navegar até Compute

1. Login em https://cloud.oracle.com
2. Menu ☰ → **Compute** → **Instances**
3. Clique **Create Instance**

### 3.2 Configurar instância

| Campo | Valor | Observação |
|-------|-------|------------|
| **Name** | `botdiscord-prod` | Identificador legível |
| **Compartment** | root | Manter padrão |
| **Image** | Ubuntu 24.04 Minimal (aarch64) | Selecionar em "Change Image" |
| **Shape** | VM.Standard.A1.Flex | Shape ARM Always Free |
| **OCPUs** | 4 | Máximo gratuito |
| **Memory** | 24 GB | Máximo gratuito |
| **VCN** | Criar nova (padrão OK) | Ou selecionar existente |
| **Subnet** | Pública | Para acessar via SSH |
| **Assign public IP** | ✓ | Marcar |
| **SSH key** | Cole o conteúdo de `oracle_botdiscord.pub` | |

### 3.3 Boot Volume

| Campo | Valor |
|-------|-------|
| **Size** | 100 GB (ou 200 GB se quiser máximo) |
| **VPU** | 10 (padrão, balanced) |

> **Limite Always Free:** 200 GB total de block storage. Se usar 100 GB boot, sobram 100 GB para volumes adicionais.

### 3.4 Criar

Clique em **Create**. O provisionamento leva ~2-5 minutos.

---

## Parte 4: Anotar informações da instância

Após a VM ficar no status **Running**, anote:

| Informação | Onde encontrar |
|------------|----------------|
| **Public IP** | Instance Details → Primary VNIC → Public IP |
| **OCID** | Instance Details → OCID (copiar) |
| **VNIC OCID** | Attached VNICs → VNIC OCID |
| **VCN OCID** | Instance Details → Attached VNIC → VCN |
| **Subnet OCID** | Instance Details → Attached VNIC → Subnet |

---

## Parte 5: Configurar Security List (Firewall OCI)

> **IMPORTANTE:** Nunca instale ou use o UFW na Oracle Cloud, pois ele apaga regras vitais (iSCSI e metadados) causando o travamento (lockout) da máquina. A segurança principal no OCI é feita através das Security Lists. **Você precisa abrir as portas primariamente por ali.**

### 5.1 Navegar até Security Lists

1. Menu ☰ → **Networking** → **Virtual Cloud Networks**
2. Clique na VCN criada automaticamente
3. Clique em **Security Lists** → **Default Security List**

### 5.2 Adicionar regras de Ingress

| Source | Protocol | Dest Port | Description |
|--------|----------|-----------|-------------|
| 0.0.0.0/0 | TCP | 22 | SSH |
| 0.0.0.0/0 | TCP | 80 | HTTP |
| 0.0.0.0/0 | TCP | 443 | HTTPS |

> **Nota:** A regra de SSH (porta 22) já existe por padrão no OCI.

### 5.3 (Opcional) Adicionar regra para Chrome headless

Se precisar acessar o Chrome remote debugging externamente:

| Source | Protocol | Dest Port | Description |
|--------|----------|-----------|-------------|
| SEU_IP/32 | TCP | 9222 | Chrome DevTools (apenas seu IP) |

---

## Parte 6: Executar o script de setup

### 6.1 Conectar via SSH

```bash
# Conectar ao servidor
ssh -i ~/.ssh/oracle_botdiscord ubuntu@<PUBLIC_IP>

# Testar conexão
uname -a
```

### 6.2 Copiar e executar o script

Opção A — Clonar o repo e executar:
```bash
# Instalar git (pode não estar no Ubuntu minimal)
sudo apt update && sudo apt install -y git

# Clonar o projeto
sudo git clone <SEU_REPO> /opt/botdiscord
sudo bash /opt/botdiscord/scripts/oracle-cloud-setup.sh
```

Opção B — Copiar o script manualmente:
```bash
# No seu computador local:
scp -i ~/.ssh/oracle_botdiscord \
  scripts/oracle-cloud-setup.sh \
  ubuntu@<PUBLIC_IP>:/tmp/setup.sh

# Na VM:
sudo bash /tmp/setup.sh
```

### 6.3 O que o script faz

| Fase | Ação |
|------|------|
| **1** | Atualiza SO, instala pacotes essenciais |
| **2** | Hardening SSH drop-in (desabilita root, senha, fixa KbdInteractiveAuthentication) |
| **3** | Configura segurança nativa de rede OCI (iptables persistente sem UFW) |
| **4** | Configura Fail2Ban (3 falhas → ban 24h) |
| **5** | Atualizações automáticas de segurança |
| **6** | Cria swap 4GB com swappiness=10 |
| **7** | Instala Docker + Compose + configura daemon |
| **8** | Otimiza kernel (network, file descriptors, OOM) |
| **9** | Prepara diretório `/opt/botdiscord` |

---

## Parte 7: Deploy do BotDiscord

### 7.1 Clonar e configurar

```bash
# Clonar o projeto
sudo -u ubuntu git clone <SEU_REPO> /opt/botdiscord

# Copiar e editar variáveis de ambiente
cd /opt/botdiscord
sudo -u ubuntu cp .env.example .env
sudo -u ubuntu nano .env

# Preencher as variáveis obrigatórias:
#   DISCORD_BOT_TOKEN=
#   DISCORD_CLIENT_ID=
#   DISCORD_GUILD_ID=
#   GOOGLE_API_KEY=         (Gemini)
#   OPENROUTER_API_KEY=     (Gemma/OpenRouter)
```

### 7.2 Subir os containers

```bash
cd /opt/botdiscord

# Build e start
docker compose -f docker/docker-compose.yml up -d --build

# Verificar status
docker compose -f docker/docker-compose.yml ps

# Ver logs
docker compose -f docker/docker-compose.yml logs -f --tail=100
```

### 7.3 Verificar saúde

```bash
# Verificar todos os containers rodando
docker compose -f docker/docker-compose.yml ps

# Deve mostrar:
# NAME                  STATUS
# app                   Up
# jobs                  Up
# discord-bot           Up
# chrome                Up

# Verificar uso de recursos
docker stats --no-stream

# Verificar portas abertas
ss -tlnp | grep -E '3000|9222|3333'
```

---

## Parte 8: Configurar GitHub Actions Deploy

### 8.1 Adicionar secrets no GitHub

Vá para o repositório → **Settings** → **Secrets and variables** → **Actions**:

| Secret | Valor | Como obter |
|--------|-------|------------|
| `DEPLOY_SSH_PRIVATE_KEY` | Conteúdo completo de `~/.ssh/oracle_botdiscord` | `cat ~/.ssh/oracle_botdiscord` |
| `DEPLOY_SSH_HOST` | IP público da VM | Instance Details do OCI |
| `DEPLOY_SSH_USER` | `ubuntu` | Padrão da imagem Ubuntu |
| `DEPLOY_PROJECT_PATH` | `/opt/botdiscord` | Onde o projeto está na VM |

### 8.2 Testar deploy

```bash
# Fazer um commit no branch main
git add -A && git commit -m "test: deploy automation" && git push

# Monitorar o workflow no GitHub
# Actions → Deploy → Verificar se passou
```

---

## Parte 9: Manter a VM Always Free ativa

### 9.1 Regra de reivindicação da Oracle

A Oracle pode reivindicar VMs Always Free que estiverem **ociosas por 7 dias**. Os critérios (TODOS devem ser verdadeiros simultaneamente):

| Métrica | Threshold |
|---------|-----------|
| CPU utilization (P95) | < 20% |
| Network utilization | < 20% |
| Memory utilization | < 20% |

### 9.2 Como prevenir

O workload do BotDiscord (jobs Solid Queue + Chrome + scraping) já garante uso acima de 20%. Para reforçar:

```bash
# Adicionar cron job de health check a cada 6 horas
sudo -u ubuntu crontab -e

# Adicionar esta linha:
0 */6 * * * curl -s http://localhost:3000/health > /dev/null 2>&1 || true
```

### 9.3 Monitorar uso

```bash
# Verificar uso de CPU
mpstat 1 5

# Verificar uso de memória
free -h

# Dashboard OCI (browser)
# Menu ☰ → Observability → Monitoring → Service Metrics
```

---

## Troubleshooting

### "Out of capacity" ao criar instância

Solução:
1. Tente outro Availability Domain (AD-1, AD-2, AD-3)
2. Tente novamente em horários diferentes (menor movimento)
3. Upgrade para PAYG (não cobra nada se ficar dentro do Always Free):
   - Menu ☰ → **Billing & Cost Management** → **Upgrade and Manage Payment**

### Não consegue SSH após criar

1. Verificar Security List do OCI (porta 22 aberta)
2. Verificar IP público atribuído
3. Verificar caminho da chave SSH
4. Verificar se a imagem é Ubuntu (user: `ubuntu`) ou Oracle Linux (user: `opc`)

### Containers não sobem

```bash
# Verificar logs
docker compose -f docker/docker-compose.yml logs

# Verificar espaço em disco
df -h

# Verificar se Docker está rodando
systemctl status docker

# Reiniciar Docker
sudo systemctl restart docker
```

### Memória insuficiente

```bash
# Verificar uso de swap
swapon --show

# Verificar OOM kills
dmesg | grep -i oom

# Aumentar swap temporariamente
sudo swapoff /swapfile
sudo fallocate -l 8G /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## Referências

- [Oracle Cloud — Always Free Resources](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Oracle Cloud — Security Best Practices](https://docs.oracle.com/iaas/Content/Security/Reference/configuration_security.htm)
- [Docker — Oracle Linux / Ubuntu install](https://docs.docker.com/engine/install/)
- [Ubuntu 24.04 LTS on OCI — Canonical](https://canonical-oracle.readthedocs-hosted.com/en/latest/)
