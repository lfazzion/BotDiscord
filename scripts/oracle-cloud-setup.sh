#!/usr/bin/env bash
# scripts/oracle-cloud-setup.sh
#
# Setup completo e otimizado para VM Oracle Cloud Always Free (Ampere A1 / Ubuntu 24.04 LTS)
# Execute como root ou com sudo após criar a instância.
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/seu-usuario/BotDiscord/main/scripts/oracle-cloud-setup.sh | sudo bash
#
# Ou copie para a VM e execute:
#   sudo bash oracle-cloud-setup.sh
#
set -euo pipefail

log() { echo -e "\n\033[1;36m[setup] $*\033[0m"; }
ok()  { echo -e "\033[1;32m  ✔ $*\033[0m"; }
err() { echo -e "\033[1;31m  ✘ $*\033[0m" >&2; }

# ─── Validar ambiente ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  err "Execute como root: sudo bash $0"
  exit 1
fi

ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
  log "AVISO: Arquitetura detectada: $ARCH (esperado: aarch64/ARM64)"
fi

log "=== Oracle Cloud VM Setup — BotDiscord ==="
log "Arquitetura: $ARCH"
log "RAM total: $(free -h | awk '/Mem:/{print $2}')"
log "CPUs: $(nproc)"

# ═══════════════════════════════════════════════════════════════════
# FASE 1: Sistema operacional
# ═══════════════════════════════════════════════════════════════════

log "FASE 1: Atualizando sistema operacional..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq -o Dpkg::Options::="--force-confold"
apt-get install -y -qq \
  curl wget git jq htop tmux unzip ca-certificates \
  gnupg lsb-release software-properties-common \
  apt-transport-https net-tools dnsutils \
  fail2ban iptables-persistent unattended-upgrades \
  build-essential

ok "Sistema atualizado e pacotes instalados"

# ═══════════════════════════════════════════════════════════════════
# FASE 2: Segurança — SSH hardening
# ═══════════════════════════════════════════════════════════════════

log "FASE 2: Hardening SSH (Drop-in config)..."

# Criar diretório drop-in caso não exista
mkdir -p /etc/ssh/sshd_config.d

# Criar arquivo de configuração em vez de alterar o original (melhor prática 2026)
cat > /etc/ssh/sshd_config.d/99-botdiscord-hardening.conf <<'SSH_EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
SSH_EOF

systemctl restart ssh
ok "SSH hardening aplicado via arquivo drop-in"

# ═══════════════════════════════════════════════════════════════════
# FASE 3: Segurança — Firewall iptables (OCI Seguro)
# ═══════════════════════════════════════════════════════════════════

log "FASE 3: Configurando regras seguras iptables..."

# Em OCI não podemos zerar iptables, senão mata a máquina com lockout de boot volume.
# Inserimos as permissões no topo da cadeia INPUT de forma não-destrutiva.
iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT -m comment --comment "SSH" || true
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT -m comment --comment "HTTP" || true
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT -m comment --comment "HTTPS" || true

# Salvar as regras inseridas para sobrevivência após reboot
netfilter-persistent save >/dev/null 2>&1

ok "Firewall assegurado via iptables-persistent (Sem UFW)"

# ═══════════════════════════════════════════════════════════════════
# FASE 4: Segurança — Fail2Ban
# ═══════════════════════════════════════════════════════════════════

log "FASE 4: Configurando Fail2Ban..."

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 86400

[sshd-ddos]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 6
bantime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban
ok "Fail2Ban configurado (SSH: 3 tentativas → ban 24h)"

# ═══════════════════════════════════════════════════════════════════
# FASE 5: Atualizações automáticas de segurança
# ═══════════════════════════════════════════════════════════════════

log "FASE 5: Atualizações automáticas de segurança..."

dpkg-reconfigure -plow unattended-upgrades -f noninteractive

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF

systemctl enable unattended-upgrades
ok "Atualizações automáticas de segurança habilitadas"

# ═══════════════════════════════════════════════════════════════════
# FASE 6: Swap (4GB para 24GB RAM — ratio conservador)
# ═══════════════════════════════════════════════════════════════════

log "FASE 6: Configurando swap..."

if ! swapon --show | grep -q '/swapfile'; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "Swap 4GB criado"
else
  ok "Swap já existe, pulando"
fi

# Ajustar swappiness (baixo — preferir RAM)
cat > /etc/sysctl.d/99-swap.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl -p /etc/sysctl.d/99-swap.conf
ok "Swappiness ajustado para 10"

# ═══════════════════════════════════════════════════════════════════
# FASE 7: Docker + Docker Compose
# ═══════════════════════════════════════════════════════════════════

log "FASE 7: Instalando Docker..."

# Remover versões antigas (se houver)
apt-get remove -y -qq docker docker-engine docker.io containerd runc 2>/dev/null || true

# Adicionar repositório oficial Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
ok "Docker instalado"

# Configurar daemon Docker
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 65536, "Soft": 65536 }
  },
  "metrics-addr": "127.0.0.1:9323",
  "experimental": false
}
EOF

systemctl restart docker
systemctl enable docker
ok "Docker daemon configurado (live-restore, logs limitados, metrics)"

# Adicionar usuário ubuntu ao grupo docker
usermod -aG docker ubuntu
ok "Usuário ubuntu adicionado ao grupo docker"

# ═══════════════════════════════════════════════════════════════════
# FASE 8: Otimizações de kernel
# ═══════════════════════════════════════════════════════════════════

log "FASE 8: Otimizações de kernel..."

cat > /etc/sysctl.d/99-botdiscord.conf <<'EOF'
# Network performance
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# File descriptors
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# Memory — OOM killer mais agressivo com processos runaway
vm.overcommit_memory = 1
vm.panic_on_oom = 0

# Chromium/Chrome headless
kernel.core_pattern = /tmp/core.%e.%p.%t
EOF

sysctl -p /etc/sysctl.d/99-botdiscord.conf
ok "Kernel tunado (network, file descriptors, OOM)"

# Aumentar limites de arquivo para o usuário ubuntu
cat > /etc/security/limits.d/99-botdiscord.conf <<'EOF'
ubuntu soft nofile 65536
ubuntu hard nofile 65536
ubuntu soft nproc 16384
ubuntu hard nproc 16384
EOF
ok "Limites de arquivo aumentados (65536)"

# ═══════════════════════════════════════════════════════════════════
# FASE 9: Deploy do BotDiscord
# ═══════════════════════════════════════════════════════════════════

log "FASE 9: Preparando diretório do projeto..."

PROJECT_DIR="/opt/botdiscord"
mkdir -p "$PROJECT_DIR"
chown ubuntu:ubuntu "$PROJECT_DIR"
ok "Diretório $PROJECT_DIR criado"

cat <<'DEPLOY_MSG'

═══════════════════════════════════════════════════════════════
  PRÓXIMOS PASSOS — Como deployar o BotDiscord:
═══════════════════════════════════════════════════════════════

  1. Clonar o repositório:

     sudo -u ubuntu git clone <SEU_REPO_URL> /opt/botdiscord

  2. Configurar variáveis de ambiente:

     sudo -u ubuntu cp /opt/botdiscord/.env.example /opt/botdiscord/.env
     sudo -u ubuntu nano /opt/botdiscord/.env

  3. Subir os containers:

     cd /opt/botdiscord
     docker compose -f docker/docker-compose.yml up -d

  4. Verificar status:

     docker compose -f docker/docker-compose.yml ps
     docker compose -f docker/docker-compose.yml logs -f --tail=50

═══════════════════════════════════════════════════════════════
  SEGURANÇA APLICADA:
═══════════════════════════════════════════════════════════════

  ✔ SSH: root desabilitado, drop-in conf, KbdInteractiveAuthentication no
  ✔ Firewall Seguro: OCI Security Lists combinadas com iptables, sem UFW
  ✔ Fail2Ban: ban de 24h após 3 falhas SSH
  ✔ Atualizações automáticas de segurança
  ✔ Swap 4GB com swappiness=10
  ✔ Docker: live-restore, logs rotativos, metrics
  ✔ Kernel: network tuning, file descriptors 65536

═══════════════════════════════════════════════════════════════

DEPLOY_MSG

log "=== Setup concluído com sucesso ==="
