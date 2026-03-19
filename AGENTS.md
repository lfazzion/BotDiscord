# BotDiscord - Data Mining System for Influencers

> Rails 8 Headless project for data collection, influencer analysis, and Discord chatbot with LLM.

## Stack

| Layer | Technology |
|-------|------------|
| Framework | Rails 8.1 (--minimal, no sprockets/ActionView) |
| Database | SQLite3 (WAL mode via bind mount) |
| Queue/Cache | Solid Queue + Solid Cache |
| Bot | discordrb |
| Scraping | Ferrum + chromedp/headless-shell + Python (Nodriver/Camoufox) |
| LLM | RubyLLM + OpenRouter/Gemini 3.1 Flash Lite/Gemma 3 27B |
| Docker | docker-compose (app, jobs, chrome) |
| Testing | Minitest |

---

## Commands

```bash
# Docker (run from project root)
docker-compose -f docker/docker-compose.yml up -d     # Start services
docker-compose -f docker/docker-compose.yml logs -f  # Watch logs
docker exec -it docker-app-1 bin/rails console        # Rails console
docker exec -it docker-app-1 bin/rails db:migrate     # Run migrations

# Local development
bin/rails jobs:work           # Workers
bin/rails test                # Tests
bin/rails routes              # List routes
```

---

## Docker Architecture

```
┌─────────────┐    ┌─────────────┐    ┌──────────────────┐
│  docker-app │    │ docker-jobs │    │  docker-chrome   │
│   Puma :3000│    │ Solid Queue │    │ headless-shell   │
│             │    │             │    │     :9222        │
└──────┬──────┘    └──────┬──────┘    └────────┬─────────┘
       │                  │                    │
       └──────────────────┴──────── storage/───┘
                     │
         ┌───────────┴───────────┐
         │  production.sqlite3   │
         │  (shared bind mount)   │
         └───────────────────────┘
```

### Container Entrypoints
- `bin/entrypoint` (app): Runs migrations → starts Puma
- `bin/entrypoint-jobs` (jobs): Starts Solid Queue supervisor
- `bin/jobs`: Solid Queue CLI (`start` command, NOT `supervisor`)

---

## Key Paths

- Models: `app/models/`
- Services: `app/services/` (REQUIRED - never in controllers/models)
- Jobs: `app/jobs/`
- Tools: `app/tools/` (40+ LLM Tool Calling classes)
- Scrapers: `lib/scraping/`
- LLM: `lib/llm/`
- Oracle: `lib/oracle/` (TMDB, IGDB, AniList)
- Prompts: `config/prompts/`
- Migrations: `db/migrate/`, `db/queue_migrate/`, `db/cache_migrate/`

---

## System Context & AI Routing (CRITICAL)

> **PROGRESSIVE DISCLOSURE**: To avoid flooding the AI context window, specific domain rules are distributed in `CONTEXT.md` files across the project.
> **YOU MUST** read the `CONTEXT.md` file in a directory before modifying or creating files within it!

### Directory Contexts (Read before modifying!)
- **`app/services/CONTEXT.md`** -> Rules for Business/Domain Logic.
- **`app/jobs/CONTEXT.md`** -> Rules for Async Queue, Idempotency, Rate Limits.
- **`app/tools/CONTEXT.md`** -> Rules for LLM Tool Calling and JSON returns.
- **`lib/scraping/CONTEXT.md`** -> Rules for Ferrum headless scraping and Docker bypass.
- **`lib/llm/CONTEXT.md`** -> Rules for Prompt Time Injection and OpenRouter.
- **`docker/CONTEXT.md`** -> Rules for Docker compose, shared volumes and Chrome Headless.

---

## Global Non-Negotiable Rules

### 1. Null vs Zero - CRITICAL
- **NEVER** use `default: 0` on numeric columns (likes, views, followers)
- When API blocks/rate-limit: save as `nil`, **NEVER** as `0`
- **ALWAYS** use `.compact` in queries that calculate averages

### 2. Database Configuration
- Production uses multi-database setup: `primary`, `queue`, `cache` connections
- All point to same SQLite file (`storage/production.sqlite3`) via bind mount
- Solid Queue tables in `db/queue_migrate/`, Solid Cache in `db/cache_migrate/`
- App container runs migrations on startup via `bin/entrypoint`
- Jobs container starts workers via `bin/entrypoint-jobs`

---

## Documentation

- [Requirements](Requisitos_Projeto_Data_Mining.md)
- [Implementation Plan](Plano_Prioridade_Implementacao.md)
- [AI Strategy](docs/estrategia_multi_model_ai.md)
- [Docker Chrome](docs/docker_chrome_setup.md)

---

## Code Conventions

- Ruby: snake_case variables/methods, CamelCase classes
- SQL: SQLite3 with migrations
- API: REST JSON-only (no HTML views)
- Testing: Minitest
