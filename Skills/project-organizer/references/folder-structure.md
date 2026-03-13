# Estrutura de Pastas — BotDiscord Data Mining System

Estrutura recomendada mapeando cada diretório para sua camada na hierarquia de contexto e fase do plano de implementação.

## Árvore Completa

```
BotDiscord/
│
├── CLAUDE.md                          # 🧠 IDENTITY — Memória central do projeto
├── README.md                          # Descrição pública do repositório
├── LICENSE
│
├── PRDs/                              # 📋 STAGE CONTRACTS — Requirements por feature
│   ├── PRD_Infra_Docker.md            #   Ex: Feature de infraestrutura
│   ├── PRD_Discovery_Pipeline.md      #   Ex: Pipeline de descoberta
│   └── archive/                       #   PRDs concluídos (referência histórica)
│
├── Specs/                             # 📐 STAGE CONTRACTS — Especificações táticas
│   ├── SPEC_Docker_Chrome_Setup.md    #   Ex: Setup técnico detalhado
│   └── archive/
│
├── Tasks/                             # ✅ STAGE CONTRACTS — Backlog granular
│   ├── P0_fundacao/                   #   Agrupado por fase de prioridade
│   │   ├── TASK-001_setup_rails.json
│   │   ├── TASK-002_docker_compose.json
│   │   └── TASK-003_core_domain.json
│   ├── P1_coleta/
│   ├── P1_cerebro_llm/
│   ├── P2_oracle/
│   ├── P2_chatbot/
│   └── P3_operacao/
│
├── Documentations/                    # 📚 REFERENCE MATERIAL — Docs técnicos
│   ├── comparativo_IA_gemini_gemma.md
│   ├── docker_chrome_setup.md
│   ├── estrategia_multi_model_ai.md
│   ├── ferramentas_scraping_gratuito.md
│   ├── rails_8_1_solid_stack.md
│   └── sqlite_production_wal.md
│
├── Skills/                            # 🛠️ REFERENCE MATERIAL — Skills da IA
│   ├── project-organizer/
│   └── skill-creator/
│
├── config/                            # ⚙️ WORKING ARTIFACTS — Configurações Rails
│   └── prompts/                       #   Prompts YAML com macros ERB
│       ├── system_base.yml
│       ├── classificador_discovery.yml
│       └── digest_semanal.yml
│
├── app/                               # 💎 WORKING ARTIFACTS — Código Rails
│   ├── models/
│   │   ├── social_profile.rb
│   │   ├── social_post.rb
│   │   └── profile_snapshot.rb
│   ├── services/
│   │   ├── ai_router.rb
│   │   └── scrapers/
│   │       ├── rss_collector.rb
│   │       ├── youtube_collector.rb
│   │       └── stealth_scraper.rb
│   ├── jobs/
│   │   ├── scraping_job.rb
│   │   ├── discovery_job.rb
│   │   └── digest_job.rb
│   └── tools/                         #   40+ Tool Calling classes
│       ├── base_tool.rb
│       ├── query_posts_tool.rb
│       └── compare_profiles_tool.rb
│
├── db/                                # 💾 WORKING ARTIFACTS — Database
│   ├── migrate/
│   └── schema.rb
│
├── docker/                            # 🐳 WORKING ARTIFACTS — Infra Docker
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── scripts/
│       └── chrome_ws_connector.rb
│
└── test/                              # 🧪 WORKING ARTIFACTS — Testes
    ├── models/
    ├── services/
    └── tools/
```

## Mapeamento: Pastas ↔ Fases do Plano

| Pasta | Fase(s) | Descrição |
|-------|---------|-----------|
| `config/`, `docker/`, `db/migrate/` | P0 — Fundação | Setup Rails, Docker, Core Domain |
| `app/services/scrapers/` | P1 — Coleta | Motor de coleta híbrida |
| `app/services/ai_router.rb`, `config/prompts/` | P1 — Cérebro LLM | Orquestrador Multi-Model |
| `app/jobs/` (parte oracle) | P2 — Oracle | Contexto externo (TMDB, IGDB, RSS) |
| `app/tools/`, `app/jobs/` (digest) | P2 — Chatbot | Discord Bot + Tool Calling |
| `docker/`, `test/` | P3 — Operação | Monitoramento e auto-healing |

## Regras de Navegação

1. **Precisa entender o projeto?** → Leia `CLAUDE.md` (Identity)
2. **Precisa de contexto técnico?** → Navegue `Documentations/` (Reference)
3. **Quer saber o que fazer?** → Consulte `Tasks/` e `PRDs/` (Contracts)
4. **Vai começar a codar?** → Gere SPEC primeiro, depois implemente em `app/` (Artifacts)
