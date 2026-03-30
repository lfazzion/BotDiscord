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
  build-essential chrony

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

# Validar config antes de restart — erro de sintaxe = lockout SSH
if ! sshd -t; then
  err "SSH config inválida — revertendo drop-in"
  rm -f /etc/ssh/sshd_config.d/99-botdiscord-hardening.conf
  exit 1
fi

systemctl reload ssh
ok "SSH hardening aplicado via arquivo drop-in (reload, não restart)"

# ═══════════════════════════════════════════════════════════════════
# FASE 3: Segurança — Firewall iptables (OCI Seguro)
# ═══════════════════════════════════════════════════════════════════

log "FASE 3: Configurando regras seguras iptables..."

# Em OCI não podemos zerar iptables, senão mata a máquina com lockout de boot volume.
# Inserimos as permissões no topo da cadeia INPUT de forma não-destrutiva.
# Idempotente: -C (check) falha se a regra não existe, então -I insere.
for PORT in 22 80 443; do
  case $PORT in
    22)  COMMENT="SSH" ;;
    80)  COMMENT="HTTP" ;;
    443) COMMENT="HTTPS" ;;
  esac
  iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT -m comment --comment "${COMMENT}" 2>/dev/null \
    || iptables -I INPUT 1 -p tcp --dport "${PORT}" -j ACCEPT -m comment --comment "${COMMENT}"
done

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

# Verificar espaço em disco (8GB mínimo: 4G swap + ~2G pacotes + headroom)
AVAILABLE_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
if [[ "${AVAILABLE_GB}" -lt 8 ]]; then
  err "Espaço insuficiente: ${AVAILABLE_GB}GB disponível, mínimo 8GB necessário"
  exit 1
fi
ok "Espaço em disco: ${AVAILABLE_GB}GB disponível"

if ! swapon --show | grep -q '/swapfile'; then
  fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  ok "Swap 4GB criado"
else
  ok "Swap já existe, pulando"
fi

# Idempotente: só adiciona ao fstab se não existir
if ! grep -qF '/swapfile' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Ajustar swappiness (baixo — preferir RAM)
cat > /etc/sysctl.d/99-swap.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl -p /etc/sysctl.d/99-swap.conf
ok "Swappiness ajustado para 10"

# ═══════════════════════════════════════════════════════════════════
# FASE 7: NTP — Chrony com OCI Managed NTP Service
# ═══════════════════════════════════════════════════════════════════
#
# OCI fornece NTP gerenciado via 169.254.169.254 (link-local metadata).
# Stratum 2, sincronizado contra Stratum 1 devices dedicados em cada AD.
# Ref: https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/configuringntpservice.htm
#
# Chrony é superior ao systemd-timesyncd em VMs:
# - Sincronização inicial mais rápida (segundos vs minutos)
# - Melhor performance com clock drift de VM (CPU scheduling)
# - Suporte a hardware timestamping
# - Acting como NTP server se necessário

log "FASE 7: Configurando NTP via Chrony (OCI)..."

# Desabilitar systemd-timesyncd — conflita com chrony
systemctl stop systemd-timesyncd 2>/dev/null || true
systemctl disable systemd-timesyncd 2>/dev/null || true

# Configurar chrony para OCI
cat > /etc/chrony/chrony.conf <<'CHRONY_EOF'
# ═══════════════════════════════════════════════════════════
# OCI Managed NTP Service — fonte primária
# 169.254.169.254 é o hypervisor metadata endpoint do OCI
# Stratum 2, baixa latência (< 1ms via VXLAN interno)
# ═══════════════════════════════════════════════════════════
server 169.254.169.254 iburst prefer

# Fallback: servidores públicos confiáveis caso OCI NTP fique indisponível
pool time.google.com iburst maxsources 2
pool time.cloudflare.com iburst maxsources 2

# Drift file — armazena offset de frequência para sync rápido após reboot
driftfile /var/lib/chrony/chrony.drift

# Para VMs: permitir step do clock sempre que offset > 1s
# VMs têm clock drift agressivo por CPU scheduling
makestep 1 -1

# RTC sync — mantém hardware clock preciso para boot correto
rtcsync

# Logs para diagnóstico
logdir /var/log/chrony
log tracking measurements statistics

# Leap second handling
leapsectz right/UTC

# Segurança: desabilitar command port (não gerenciado remotamente)
cmdport 0
CHRONY_EOF

# Garantir que o drift directory existe
mkdir -p /var/lib/chrony
chown _chrony:_chrony /var/lib/chrony 2>/dev/null || true

# Reiniciar e habilitar chrony
systemctl restart chrony
systemctl enable chrony
ok "Chrony configurado e habilitado (OCI NTP 169.254.169.254 + fallback público)"

# Aguardar sincronização inicial — waitsync é mais robusto que sleep fixo
# Ref: chronyc waitsync <max_loops> <max_error_seconds>
# - max_loops: número máximo de tentativas (1s entre cada)
# - max_error: offset máximo aceitável em segundos
if chronyc waitsync 30 0.1 2>/dev/null; then
  ok "NTP sincronizado (offset < 100ms)"
else
  log "AVISO: Sincronização inicial não atingiu 100ms em 30s — continuando"
  log "  Chrony continuará sincronizando em background"
  log "  Verificar com: chronyc tracking"
fi

# Mostrar status para o operador
chronyc sources -n 2>/dev/null || true
chronyc tracking 2>/dev/null | grep -E "Reference ID|Stratum|System time|Leap status" || true

# ═══════════════════════════════════════════════════════════════════
# FASE 8: Docker + Docker Compose
# ═══════════════════════════════════════════════════════════════════

log "FASE 8: Instalando Docker..."

# Remover versões antigas (se houver)
apt-get remove -y -qq docker docker-engine docker.io containerd runc 2>/dev/null || true

# Adicionar repositório oficial Docker
mkdir -p /etc/apt/keyrings
DOCKER_GPG_TMP=$(mktemp)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$DOCKER_GPG_TMP"
DOCKER_FP=$(gpg --with-colons --import-options show-only --import "$DOCKER_GPG_TMP" 2>/dev/null \
  | awk -F: '/^fpr:/{print $10; exit}')
EXPECTED_DOCKER_FP="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
if [[ "$DOCKER_FP" != "$EXPECTED_DOCKER_FP" ]]; then
  rm -f "$DOCKER_GPG_TMP"
  err "Docker GPG key fingerprint mismatch!"
  err "Got:      ${DOCKER_FP:-<empty>}"
  err "Expected: ${EXPECTED_DOCKER_FP}"
  exit 1
fi
gpg --dearmor -o /etc/apt/keyrings/docker.gpg < "$DOCKER_GPG_TMP"
rm -f "$DOCKER_GPG_TMP"
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
  "mtu": 1400,
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

# Adicionar usuário ao grupo docker
DOCKER_USER="${SUDO_USER:-$(logname 2>/dev/null || echo ubuntu)}"
if id "${DOCKER_USER}" &>/dev/null; then
  usermod -aG docker "${DOCKER_USER}"
  ok "Usuário ${DOCKER_USER} adicionado ao grupo docker"
else
  err "Usuário ${DOCKER_USER} não existe — adicione manualmente: usermod -aG docker <usuario>"
fi

# Plataforma Docker padrão ARM64 (evita QEMU x86→ARM em builds)
DOCKER_PROFILE="/home/${DOCKER_USER}/.profile"
touch "${DOCKER_PROFILE}"
if ! grep -q 'DOCKER_DEFAULT_PLATFORM' "${DOCKER_PROFILE}"; then
  echo 'export DOCKER_DEFAULT_PLATFORM=linux/arm64' >> "${DOCKER_PROFILE}"
  ok "DOCKER_DEFAULT_PLATFORM=linux/arm64 adicionado ao ~/.profile"
fi

# ═══════════════════════════════════════════════════════════════════
# FASE 9: Otimizações de kernel
# ═══════════════════════════════════════════════════════════════════

log "FASE 9: Otimizações de kernel..."

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

# Memory — heurístico padrão, evita OOM kills agressivos
vm.overcommit_memory = 0
vm.panic_on_oom = 0

# Chromium/Chrome headless
kernel.core_pattern = /tmp/core.%e.%p.%t
EOF

sysctl -p /etc/sysctl.d/99-botdiscord.conf
ok "Kernel tunado (network, file descriptors, OOM)"

# Aumentar limites de arquivo para o usuário detectado
cat > /etc/security/limits.d/99-botdiscord.conf <<EOF
${DOCKER_USER} soft nofile 65536
${DOCKER_USER} hard nofile 65536
${DOCKER_USER} soft nproc 16384
${DOCKER_USER} hard nproc 16384
EOF
ok "Limites de arquivo aumentados para ${DOCKER_USER} (65536)"

# ═══════════════════════════════════════════════════════════════════
# FASE 10: Deploy do BotDiscord
# ═══════════════════════════════════════════════════════════════════

log "FASE 10: Preparando diretório do projeto..."

PROJECT_DIR="/opt/botdiscord"
mkdir -p "$PROJECT_DIR"
chown "${DOCKER_USER}:${DOCKER_USER}" "$PROJECT_DIR"
ok "Diretório $PROJECT_DIR criado"

cat <<DEPLOY_MSG

═══════════════════════════════════════════════════════════════
  PRÓXIMOS PASSOS — Como deployar o BotDiscord:
═══════════════════════════════════════════════════════════════

  1. Clonar o repositório:

     sudo -u ${DOCKER_USER} git clone <SEU_REPO_URL> /opt/botdiscord

  2. Configurar variáveis de ambiente:

     sudo -u ${DOCKER_USER} cp /opt/botdiscord/.env.example /opt/botdiscord/.env
     sudo -u ${DOCKER_USER} nano /opt/botdiscord/.env

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
  ✔ NTP: Chrony via OCI Managed NTP (169.254.169.254) + fallback público
  ✔ Docker: live-restore, logs rotativos, MTU 1400, metrics
  ✔ Docker platform: linux/arm64 (sem QEMU)
  ✔ Kernel: network tuning, file descriptors 65536

═══════════════════════════════════════════════════════════════
  HARDENING OPCIONAL (não aplicado automaticamente):
═══════════════════════════════════════════════════════════════

  ⚠ Docker userns-remap: protege contra container→host escape,
    mas QUEBRA bind mounts (storage/). Para aplicar:

    1. Pare todos os containers
    2. Adicione "userns-remap": "default" ao daemon.json
    3. REFAÇA o chown: chown -R 100000:100000 /opt/botdiscord/storage
    4. Reinicie Docker: systemctl restart docker
    5. Reconstrua: docker compose -f docker/docker-compose.yml build --no-cache

═══════════════════════════════════════════════════════════════

═══════════════════════════════════════════════════════════════

DEPLOY_MSG

log "=== Setup concluído com sucesso ==="
