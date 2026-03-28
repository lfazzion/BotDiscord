# Oracle Cloud Always Free Tier — Guia Completo para BotDiscord

> **Última atualização:** 2026-03-27
> **Fonte:** Documentação oficial Oracle + blogs técnicos da Oracle e Ampere Computing
> **Objetivo:** Documentar todos os limites do plano Always Free, capacidades reais de processamento e viabilidade de rodar IAs localmente na VM.

---

## 1. Visão Geral

A Oracle Cloud Infrastructure (OCI) oferece um dos free tiers mais generosos do mercado:

- **$300 USD em créditos** para usar em qualquer serviço por 30 dias (Free Trial)
- **Always Free** — recursos que nunca expiram, para sempre, sem cartão de crédito adicional após trial

Os recursos Always Free estão disponíveis para **todas as contas** (inclusive após expiração do trial) e nunca geram cobrança automática.

---

## 2. Compute — VM Ampere A1 Flex (ARM)

### 2.1 Specs do Processador

| Especificação | Valor |
|----------------|-------|
| **Fabricante** | Ampere Computing |
| **Modelo** | Ampere Altra |
| **Arquitetura** | ARM64 (Arm v8.2+) |
| **Cores por CPU** | Até 80 cores (no datacenter completo) |
| **Clock máximo** | Até 3.30 GHz |
| **L1 Cache** | 64KB I-cache + 64KB D-cache **por core** |
| **L2 Cache** | 1 MB **por core** |
| **SLC (System Level Cache)** | 32 MB |
| **SIMD** | 2x full-width (128-bit NEON) |
| **Design** | Single-threaded por core (cada core tem thread dedicada) |
| **Interconexão** | Coherent Mesh Interconnect (CMI) com snoop filtering distribuído |

### 2.2 Limites Always Free — VM Standard A1.Flex

| Recurso | Limite Free | Observação |
|---------|-------------|------------|
| **OCPUs** | 4 total | Alocável entre 1 e 4 VMs |
| **Memória** | 24 GB total | Distribuível entre as VMs |
| **OCPU-hours/mês** | 3.000 | Suficiente para 4 OCPUs rodando 24/7 (4 × 24h × 31d = 2.976) |
| **GB-hours/mês** | 18.000 | Suficiente para 24GB rodando 24/7 (744h × 24GB = 17.856) |
| **VMs máximas** | 4 instâncias | Combinando com boot volumes de 47GB mínimo |
| **Imagens disponíveis** | Ubuntu, Oracle Linux, Oracle Linux Cloud Developer | Linux Cloud Developer requer mínimo 8GB de RAM |

### 2.3 Cálculo Real — Adequação para o BotDiscord

```
Necessário (4 containers):
  app:          ~512MB RAM, ~0.25 vCPU
  jobs:         ~512MB RAM, ~0.25 vCPU
  discord-bot:  ~256MB RAM, ~0.1 vCPU
  chrome:       ~2GB shm + ~512MB RAM
  ─────────────────────────────
  Total:        ~3.5GB RAM, ~1 vCPU contínuo

Disponível (Always Free):
  24GB RAM, 4 OCPUs
  ─────────────────────────────
  Margem:       20.5GB sobrando (85% ocioso)
```

**Veredicto:** A VM é **sobradamente suficiente** para rodar o BotDiscord 24/7 com margem de sobra para outros serviços.

---

## 3. Compute — VM Standard E2.1.Micro (AMD)

| Recurso | Limite Always Free |
|---------|-------------------|
| **Instâncias** | 2 VMs |
| **OCPU** | 1/8 de OCPU por instância (burstable até 100% em spikes) |
| **RAM** | 1 GB por instância |
| **Rede** | 50 Mbps via internet, 480 Mbps interno |
| **Imagens** | Oracle Linux, Ubuntu, CentOS, Oracle Linux Cloud Developer |

> **Nota:** As VMs Micro AMD são pouco úteis para o BotDiscord. Focar na VM Ampere A1.

---

## 4. Block Volume (Armazenamento de Bloco)

| Recurso | Limite Always Free |
|---------|-------------------|
| **Total combinado** | 200 GB (boot + block volumes) |
| **Backups** | 5 backups totais |
| **Boot volume padrão** | 50 GB por instância |
| **Boot volume máximo** | 200 GB (consome todo o limite free) |

**Configuração recomendada para BotDiscord:**
- 1 instância Ampere A1 com boot volume de 100 GB
- Sobram 100 GB para block volume adicional (SQLite + dados)

---

## 5. Object & Archive Storage

| Recurso | Limite Always Free |
|---------|-------------------|
| **Storage total** | 20 GB (Standard + Infrequent Access + Archive combinados) |
| **API requests/mês** | 50.000 |
| **Tier padrão** | Standard (sem taxa de retrieval) |

> **Nota:** Útil para backups do SQLite e armazenamento de imagens geradas.

---

## 6. Networking

| Recurso | Limite Always Free |
|---------|-------------------|
| **VCNs** | 2 |
| **Egress (saída)** | **10 TB/mês** |
| **Ingress (entrada)** | Ilimitado e gratuito |
| **Load Balancer** | 1 Flexible LB (10 Mbps) |
| **Network Load Balancer** | 1 |
| **IPv4/IPv6** | Suportado |
| **Site-to-Site VPN** | 50 conexões IPSec |
| **Porta 25 (SMTP)** | Bloqueada por padrão — requer solicitação |

---

## 7. Database (Serviços Gerenciados — não o SQLite do BotDiscord)

| Serviço | Limite Always Free |
|---------|-------------------|
| **Autonomous Database** | 2 instâncias (1 OCPU + 20 GB cada) |
| **MySQL HeatWave** | 1 instância (50 GB storage + 50 GB backup) |
| **NoSQL Database** | 133M reads/mês, 133M writes/mês, 3 tabelas (25 GB/tabela) |

---

## 8. Outros Serviços Always Free

| Serviço | Limite |
|---------|--------|
| **Email Delivery** | 3.000 emails/mês |
| **Monitoring** | 500M datapoints ingestion, 1B retrieval |
| **Logging** | 10 GB/mês |
| **Notifications** | 1M HTTPS + 1.000 email/mês |
| **Vault** | 20 HSM keys, 150 secrets |
| **Bastion** | 5 bastions |
| **Certificates** | 5 CAs + 150 certificados |
| **Console Dashboards** | 100 |
| **VCN Flow Logs** | 10 GB/mês (compartilhado com Logging) |

---

## 9. IA Local na VM Ampere A1 — Viabilidade e Limites

### 9.1 É permitido?

**Sim.** A Oracle e a Ampere Computing **incentivam ativamente** o uso de LLMs nas instâncias Ampere A1:

- A Oracle publica imagens de marketplace otimizadas para IA ([OCI Ampere A1 LLM Inference](https://cloudmarketplace.oracle.com/marketplace/en_US/listing/165367725))
- A Ampere mantém containers Docker otimizados de `llama.cpp` no Docker Hub ([amperecomputingai/llama.cpp](https://hub.docker.com/r/amperecomputingai/llama.cpp))
- A Oracle blog publica benchmarks oficiais de LLM inference no Ampere A1
- Não há nenhuma restrição na Acceptable Use Policy que proíba workload de IA/ML

### 9.2 Não há GPU — e daí?

A VM Ampere A1 **não possui GPU**. Toda inferência de IA é feita em CPU ARM. O Ampere Altra é otimizado para isso:

| Benchmark (Llama 3 8B, llama.cpp otimizado) | OCPUs | Throughput (TPS) |
|----------------------------------------------|-------|------------------|
| Batch 1 (single user) | 64 | 30 TPS |
| Batch 4 | 64 | 72 TPS |
| Batch 8 | 64 | 94 TPS |
| Batch 16 | 64 | 115 TPS |

> **Fonte:** [Oracle AI Blog — "Introducing Meta Llama 3 on OCI Ampere A1"](https://blogs.oracle.com/ai-and-datascience/post/introducing-meta-llama-3-on-oci-ampere-a1) (abril 2024)

### 9.3 O que cabe na VM Always Free (4 OCPUs, 24GB RAM)?

| Modelo | Params | RAM (Q4) | Viável? | Nota |
|--------|--------|----------|---------|------|
| Gemma 3 1B IT | 1B | ~0.8 GB | Sim | Ultra-leve |
| Llama 3.2 3B | 3B | ~2 GB | Sim | Tool calling |
| Phi-4-mini | 3.8B | ~2.5 GB | Sim | ARC-C 83.7% |
| Gemma 3 4B IT | 4B | ~3 GB | Sim | Multimodal, código |
| Qwen3.5-4B | 4B | ~3 GB | Sim | MMLU-Pro 79.1 |
| Qwen3.5-9B | 9B | ~6 GB | Sim | #1 SLM leaderboard |
| DeepSeek-R1-Distill-14B | 14B | ~10 GB | Sim | Chain-of-thought |
| Phi-4 | 14B | ~10 GB | Sim | GSM8K 89.8% |
| Qwen3-30B-A3B (MoE) | 30B (3B ativos) | ~18 GB | Apertado | 2.5GB margem |
| Gemma 3 27B | 27B | ~16 GB | Apertado | 4.5GB margem |
| Llama 4 Scout (MoE) | 109B (17B ativos) | ~70 GB | Não | |

### 9.4 Velocidade esperada com 4 OCPUs (Always Free)

Projetando a partir dos benchmarks oficiais (64 OCPUs → ~30 TPS single user):
- **4 OCPUs:** ~2-4 TPS single user (suficiente para chat async, não streaming realtime)
- Para comparação: leitura humana média = ~5 tokens/segundo

### 9.5 Como rodar Ollama na VM (exemplo)

```bash
# Ollama suporta ARM64 nativamente
curl -fsSL https://ollama.ai/install.sh | sh
ollama pull llama3.2:3b
ollama run llama3.2:3b
```

### 9.6 LLMs Mais Potentes para 4 OCPUs / 24GB RAM (Março 2026)

> **Filtro:** apenas modelos pós-julho 2025.
> **Benchmarks:** AwesomeAgents SLM Leaderboard (mar 2026), BenchLM.ai, LMArena Elo, LiveBench.
> **Velocidade:** projetada dos benchmarks oficiais Oracle (64 OCPUs = 30 TPS Llama 8B Q4) para 4 OCPUs.

---

#### FOCO: RACIOCINIO — Qualidade máxima

| Modelo | Params | RAM Q4 | MMLU-Pro | GPQA Dia | ARC-C | GSM8K | Elo | Veloc 4OCPUs | Data |
|--------|--------|--------|----------|----------|-------|-------|-----|-------------|------|
| **Qwen3.5-9B** | 9B | 6 GB | **82.5** | **81.7** | — | — | ~1150 | ~3-5 tps | Mar 26 |
| **Qwen3-30B-A3B** MoE | 30B (3B ativos) | 18 GB | ~80 | ~78 | — | — | ~1180 | ~2-4 tps | Jun 25 |
| **DeepSeek-R1-Distill-14B** | 14B | 10 GB | ~78 | ~75 | — | 88% | ~1120 | ~2-4 tps | Jan 25 |
| **Phi-4** | 14B | 10 GB | ~78 | — | — | 89.8% | ~1100 | ~2-4 tps | Jun 25 |
| **Phi-4-mini** | 3.8B | 2.5 GB | 52.8 | — | **83.7** | 88.6% | ~1000 | ~6-10 tps | Jun 25 |
| **Gemma 3n E4B** | 8B (eff 4B) | 3 GB | — | — | — | — | **1300+** | ~5-8 tps | Nov 25 |

**Melhor pick raciocínio com BotDiscord rodando:** Qwen3.5-9B (6GB + 3.5GB = 9.5GB / 24GB = margem boa)

---

#### FOCO: VELOCIDADE — Tokens/s máximos em CPU

| Modelo | Params | RAM Q4 | MMLU-Pro | HumanEval | GSM8K | Elo | Veloc 4OCPUs | Data | Destaque |
|--------|--------|--------|----------|-----------|-------|-----|-------------|------|----------|
| **Gemma 3 4B IT** | 4B | 3 GB | 43.6 | **71.3%** | **89.2%** | — | **~7-10 tps** | Mar 25 | Codigo + matematica |
| **Qwen3.5-4B** | 4B | 3 GB | **79.1** | — | — | ~1050 | ~6-9 tps | Mar 26 | Melhor raciocinio 4B |
| **Phi-4-mini** | 3.8B | 2.5 GB | 52.8 | 74.4% | 88.6% | ~1000 | ~6-10 tps | Jun 25 | ARC-C 83.7%, 128K ctx |
| **Gemma 3n E4B** | 8B (eff 4B) | 3 GB | — | — | — | 1300+ | ~5-8 tps | Nov 25 | Phone-ready |
| **Llama 3.2 3B** | 3B | 2 GB | — | — | 77.7% | — | ~8-12 tps | Set 24 | Tool calling BFCL 67% |
| **Gemma 3 1B IT** | 1B | 0.8 GB | 14.7 | 41.5% | 62.8% | — | ~12-18 tps | Mar 25 | Ultra-rapido |

**Melhor pick velocidade com BotDiscord rodando:** Qwen3.5-4B ou Gemma 3 4B (3GB + 3.5GB = 6.5GB / 24GB = sobra enorme)

---

#### Resumo: Melhor escolha por cenário

| Cenário | Modelo | RAM | Veloc | Por quê |
|---------|--------|-----|-------|---------|
| Melhor qualidade geral | **Qwen3.5-9B** | 6 GB | 3-5 tps | MMLU-Pro 82.5, GPQA 81.7, #1 SLM |
| Melhor qualidade MoE | **Qwen3-30B-A3B** | 18 GB | 2-4 tps | 30B conhec, 3B ativos/token |
| Melhor veloc+qualidade | **Qwen3.5-4B** | 3 GB | 6-9 tps | MMLU-Pro 79.1 em 4B, 262K ctx |
| Melhor codigo | **Gemma 3 4B IT** | 3 GB | 7-10 tps | HumanEval 71.3%, GSM8K 89.2% |
| Melhor raciocinio logico | **Phi-4-mini** | 2.5 GB | 6-10 tps | ARC-C 83.7%, GSM8K 88.6% |
| Melhor para tool calling | **Llama 3.2 3B** | 2 GB | 8-12 tps | BFCL V2 67% |
| Melhor mobile/edge | **Gemma 3n E4B** | 3 GB | 5-8 tps | LMArena 1300+ |
| Melhor custo-zero minimo | **Gemma 3 1B IT** | 0.8 GB | 12-18 tps | 125MB, roda em qualquer coisa |

---

#### Instalacao Ollama

```bash
curl -fsSL https://ollama.ai/install.sh | sh
ollama pull qwen3.5:9b           # #1 qualidade geral
ollama pull qwen3:30b-a3b        # #1 qualidade MoE (18GB!)
ollama pull qwen3.5:4b           # #1 velocidade+qualidade
ollama pull phi:14b              # raciocínio avançado
ollama pull phi:3.8b             # raciocínio rápido
ollama pull gemma3:4b            # código + multimodal
ollama pull gemma3n:e4b          # phone-ready
ollama pull llama3.2:3b          # tool calling
```

#### Instalacao llama.cpp otimizado Ampere

```bash
docker run -d \
  --name llama-server \
  -p 8080:8080 \
  -v ~/.ollama/models:/models \
  amperecomputingai/llama.cpp:latest \
  -m /models/model.gguf \
  --host 0.0.0.0 --port 8080 \
  -t 4 -c 4096
```

---

## 10. Políticas de Uso — O que NÃO fazer

### 10.1 Reivindicação de VMs Ociosas

> **Regra oficial da Oracle:** VMs Always Free que estiverem ociosas podem ser **reivindicadas** pela Oracle após 7 dias se TODOS os critérios abaixo forem verdadeiros simultaneamente:
> - CPU utilization (percentil 95) < 20%
> - Network utilization < 20%
> - Memory utilization < 20% (apenas para A1)

**Para o BotDiscord:** o workload de scraping + jobs Solid Queue + Chrome headless já garante uso mínimo acima de 20%. Recomenda-se também um cron job de health check.

### 10.2 Upgrade para Pay As You Go (PAYG)

- **Melhora a disponibilidade** de instâncias Ampere (elimina erros "out of capacity")
- **NÃO elimina** os recursos Always Free — continua sem cobrança
- **Atenção:** qualquer uso acima dos limites free gera cobrança
- Temporariamente pode haver verificação de $100 no cartão (devolvida)

### 10.3 Atividades Proibidas pela Oracle

A Oracle Cloud CSA (Cloud Services Agreement) não lista restrições específicas para IA/ML, criptomoedas ou scraping dentro do escopo de uso legítimo. Contudo:

- **Cryptomining:** Não explicitamente proibido no free tier, mas instâncias ociosas por CPU baixa são reivindicadas
- **Atividades ilegais:** Proibidas (como em qualquer cloud)
- **Violação de ToS de terceiros:** O scraping viola ToS de redes sociais (problema jurídico, não da Oracle)
- **Resale/repackaging:** Não é permitido revender os serviços OCI

---

## 11. Regiões e Disponibilidade

| Aspecto | Detalhe |
|---------|---------|
| **Home region** | Escolhida no momento do cadastro (imutável para Always Free) |
| **Ampere A1 em múltiplos ADs** | Sim, pode criar em qualquer Availability Domain |
| **E2 Micro** | Apenas em 1 AD específico |
| **Erro "out of capacity"** | Comum em free tier — tente outro AD ou aguarde |
| **Solução definitiva** | Upgrade para PAYG remove o guardrail de capacidade |

---

## 12. Resumo Comparativo — BotDiscord vs Always Free

| Requisito do BotDiscord | Disponível (Always Free) | Status |
|-------------------------|--------------------------|--------|
| 4 containers Docker | VM completa com Docker Compose | OK |
| ~3.5 GB RAM total | 24 GB RAM | OK (14% uso) |
| ~1 vCPU contínuo | 4 OCPUs | OK (25% uso) |
| Chrome headless (2GB shm) | Sem restrição de shm em VM | OK |
| SQLite persistente | 200 GB block volume | OK |
| Python + yt-dlp | Ubuntu nativo | OK |
| Deploy via GitHub Actions | SSH + git pull | OK |
| IA local (opcional) | Suportado e incentivado | OK (até 30B MoE params) |

**Veredicto final:** O Oracle Cloud Always Free é **viável e recomendado** para hospedar o BotDiscord 24/7, com capacidade de sobra para rodar LLMs locais de até 14B params (ou 30B MoE apertado).

---

## Referências

- [Oracle Always Free Resources (documentação oficial)](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Ampere Altra Datasheet](https://amperecomputing.com/assets/Altra_Rev_A1_DS_v1_50_20240130_3375c3dec5_1c5d4604fa.pdf)
- [Oracle AI Blog — Llama 3 on Ampere A1](https://blogs.oracle.com/ai-and-datascience/post/introducing-meta-llama-3-on-oci-ampere-a1)
- [Oracle AI Blog — Cost-efficient LLM serving with Ampere CPUs](https://blogs.oracle.com/ai-and-datascience/smaller-llama-llm-models-cost-efficient-ampere-cpus)
- [Ampere Computing — LLM Inference on OCI](https://amperecomputing.com/solutions/llm-oci)
- [FullmetalBrackets — OCI Free Tier Breakdown](https://fullmetalbrackets.com/blog/oci-free-tier-breakdown/)
