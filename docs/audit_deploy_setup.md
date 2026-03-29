# Audit de Segurança — deploy.sh + oracle-cloud-setup.sh

> **Data:** 2026-03-29
> **Escopo:** `.github/scripts/deploy.sh`, `scripts/oracle-cloud-setup.sh`
> **Objetivo:** Identificar brechas e fragilidades que impedem uso seguro em produção, com contexto de recomendações do Estado da Arte.

---

## deploy.sh

### 🔴 Crítico

**A1. `StrictHostKeyChecking=no` permite MITM**
- Linha 28: `-o StrictHostKeyChecking=no`
- Qualquer atacante na rede entre o runner do GitHub Actions e a VM pode interceptar a conexão (MITM).
- **Correção (Estado da Arte):** Apenas usar `ssh-keyscan` no runtime diminui, mas não encerra o risco (TOFU). O padrão da indústria em CI/CD é salvar e validar firmemente a public key real via secret no GitHub (`SSH_KNOWN_HOSTS`) e injetá-la no runner em runtime, ou alternativamente abrandar com o parametro menos agressivo `StrictHostKeyChecking=accept-new` (SSH versão >= 7.6).

**A3. Sem deploy lock — concorrência e race condition**
- Duplos disparos simultâneos desencadeiam `docker build` concorrentes.
- **Correção (Estado da Arte / Evitar Overengineering):** Criar subistemas de `flock` bashológicos é obsoleto e complexo. Simplesmente adicione a chave `concurrency: production_deploy` (ou similar) no arquivo YAML do workflow do próprio GitHub Actions.

**A5. `|| true` no rollback anula visibilidade de falhas**
- Linhas 68-71: Os atenuantes como `|| true` disfarçam erros no fallback. O `trap rollback ERR` absorve as falhas, encerra o container antigo no ar e mesmo assim emite Exit Code 0 para o GitHub.
- **Correção:** Garantir rigorosamente que a rotina `rollback() {...}` remova o silenciamento passivo das instruções e finalize sua scope com um claro e direto `exit 1` ao notificar o alerta pra manter o job na cor vermelha.

### 🟡 Médio

**A2. Diff frágil na identificação de alterações (git diff quebradiço)**
- Linhas 80-81 e 93: O pareamento via hashes extraídas com antecedência `"$LOCAL"` ao invés da pointer reference pós-pull sofre desvios se o merge não constar como fast-forward.
- **Correção:** Adotar abordagens nativas unificadas após o git fetch/pull, como `git diff --name-only ORIG_HEAD HEAD` para varrer rigorosamente as mutações atuais.

**A6. Health check cego — Puma silenciado sob `docker compose ps`**
- Linha 127: O status de "Up" dos containers não reflete a saúde interna do Puma e do ActiveRecord.
- **Correção:** Utilizar sonda HTTP pura via `curl -f http://localhost:3000/up` (Endpoint Heath default gerado no scaffold Rails 8) aliada a um simples loop de sleep.

**A7. Migrate log volátil (`/tmp`)**
- Persistir artefatos vitais em `/tmp` resulta usualmente em sumiços orquestrados pelo daemon daemon `systemd-tmpfiles`.
- **Correção:** Redirecionar os rastros logísticos à stack do app via `${PROJECT_PATH}/log/deploy-migrate.log`.

### ⚪ Informativo / Fix-Forward

**A4. Rollback de DB manual esquivado corretamente**
- A omissão de comandos automáticos de `db:rollback` é altamente encorajada pelo Estado da Arte e Cloud-Native (Expand/Contract pattern e Fix-Forward model). Nunca reverter banco via esteira.

**A8. Validação rigorosa de commit-hash (Overengineering)**
- Verificações criptográficas de GPG no checkout devem ser gerenciadas em camadas superiores (Branch Protection Rules no repositório) e não via Shell verification pass. O script acerta em não poluir o arquivo com validações deste tipo.

---

## oracle-cloud-setup.sh

*Nota de Atualização: O script `oracle-cloud-setup.sh` atual já absorve e aplica práticas avançadas de infra. Grande parte das críticas históricas levantadas contra ele hoje consistem em pontos neutralizados pelo próprio código ou Falsos Positivos frente à padrões de Cloud Native.*

### 🟡 Médio

**B7. Inflexibilidade de sistema perante alocação do Swap (`fallocate`)**
- Linha 163: Apesar de veloz, o comando `fallocate` tende a abortar silenciosamente e retornar error traces caso seja disparado contra Volumes Block Storage específicos alocados em filesystems da Nuvem sem permissão de contiguidade direta (ex: XFS cloud blocks).
- **Correção:** Engatilhar um fallback elementar para provisionamento de bits binários no swap via utilitário standard garantido: `|| dd if=/dev/zero of=/swapfile bs=1M count=4096`.

**B9. Capacidade de disco não sanitizada**
- Gerar rombo estático (4GB pro Swap + 2GB apt/Docker) em root devices pode consumir toda margem e causar congelamentos fatais no OOM de sistema.
- **Correção:** Condicionar e antecipar bloqueios checando armazenamento inicial via readouts de `df -BG /`.

### 🟢 Resolvidos / Removidos do Risco (Falso Positivos)

**B1. Contexto Monolítico Root (Falso Positivo)**
- Alertava periculosidade pelo script não suprimir elevação de privilégio. Porém, workflows de bootstrapping de Infraestrutura baseada em nuvem requerem ativamente context execution root completo para tuning de kernel e injeções de Systemd. Privilégios contidos sob `sudo -u user` unicamente onde necessário. Prática ratificada como segura.

**B2. Download do apt sem hash GPG manual (Falso Positivo)**
- Validar chaves em package managers (`apt`) é overengineering desnecessário pois o processo já desfruta dos sub-módulos Dpkg internos contra adulteração.

**B3. SSH restart bloqueante com risco lockout (Resolvido)*
- O script mitigou eficientemente este vetor injetando um sanity check test parser com o `sshd -t` associado a execuções non-lethal com `systemctl reload ssh`, poupando a deleção completa de sessions operacionais.

**B4, B5. Parâmetros hardcoded ao usuário Ubuntu (Resolvido)**
- Chown strings unificadas via discovery de runtime na váriavel dinâmica `$DOCKER_USER`, validando portabilidade agnóstica a AMIs e distros.

**B6. Impossibilidade operacional por falta de Idempotência (Resolvido)**
- Comandos destrutivos de appending no fstab e de Network tables ganharam wrappers lógicos `grep -qF` e `-C INPUT`, blindando contra dual calls.

**B8. Drop in SSH sem fallback backup (Resolvido)**
- As confs parciais depositadas em `sshd_config.d` detêm tratativas exclusivas de deleção reativa (rm) atrelada diretamente as falhas pre-check.

**B10. Política Local Dropped iptables ausente (Abordagem de Segurança via OCI/NSG)**
- Abster a instância de Lockouts pesados `DROP` locais e relegar firewalls periféricos as "Security Lists" nativas OCI caracteriza as novas tendências de Segurança Descentralizada e evita auto-exclusões letais geradas por scripts automáticos. Plenamente alinhado.

---

### 🔵 Otimizações Avançadas (Cloud Native / OCI ARM Specific)

*As validações focadas no uso de Ampere A1 (ARM64) no Oracle Cloud trazem algumas descobertas críticas de Estado da Arte (Performance e Segurança) elegíveis e recomendadas para a instância:*

**B11. OCI MTU "Black Holes" (Crítico de Rede e Estabilidade Doutrinária)**
- **Situação:** As instâncias Oracle em VCNs frequentemente herdam "Jumbo Frames" com MTU elevado (9000), contrastando agressivamente com a ponte nativa do Docker (`docker0` base em 1500). Isso induz fragmentação pesada ou interrupções silenciosas em rotas web/HTTPS, fazendo requests "pendurarem" na rede externa (conhecido como *MTU Black hole*).
- **Correção:** Inserir explicitamente no escopo da FASE 7 a chave `"mtu": 1400` no payload injetado para `/etc/docker/daemon.json`, harmonizando fluxos entre as VNICs da nuvem e pacotes do Docker.

**B12. Cloud Sync de Relógio via Oracle PTP (Segurança de Handshakes/OAuth)**
- **Situação:** Desvios progressivos no clock do node físico Linux (*Time Drift*) degradam as negociações SSL/TLS das requisições, comprometem tokens temporizados via OAuth no Discord Bot, e avariam snapshots idempotentes de jobs lógicos.
- **Correção:** Certificar que o pacote `chrony` esteja sendo adicionado à call do apt-get, forçando sync hard-coded com o *Hardware Timestamping* de precisão direto do Hypervisor via IP metadado do serviço Oracle (`server 169.254.169.254 prefer`).

**B13. Otimização Nativa de Compilação ARM64**
- **Situação:** Os processos rubygems (Nokogiri etc.) e compilações Node/Assets devem maximizar o uso da arquitetura Neoverse-N1 da Ampere A1. Dependências não pinadas podem recorrer ao emulador `QEMU` (x86_to_ARM) nos bastidores.
- **Correção:** Instituir forçadamente a flag/env variável `export DOCKER_DEFAULT_PLATFORM=linux/arm64` como recomendação de Setup do servidor e instruir buildx explicitly focado em não recorrer a polyfills instáveis/lentos.

**B14. Docker Root-Escape Vector prevention (Segurança Local Restritiva)**
- **Situação:** O engine instalado adiciona seu User diretamente as chaves irrestritas (DockerGroup) repassando `root-capabilities` indiretamente. Um script Scraper hostil dentro do container pode quebrar a sandbox e ganhar controle total.
- **Correção:** Como Estado da Arte na nuvem sem clusters K8s (onde ferramentas como Cilium fariam barreira), o recomendável em Bare-Metal Docker é habilitar os `User Namespaces (userns-remap=default)` diretamente no setup do `/etc/docker/daemon.json`, bloqueando de vez qualquer escalonamento do ID do container para permissões `root` efetivas do host.
