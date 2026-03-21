# AGENTS.md — BotDiscord (Router)

Headless Rails 8.1 app for influencer data mining, scraping, and Discord bot integration. Ruby ~> 4.0, SQLite3 (WAL), Solid Queue/Cache, Minitest. All commands run inside Docker.

## Folder Map

```
app/
  jobs/              — ActiveJob classes (Solid Queue)
  models/            — ActiveRecord models
  services/          — Business logic orchestrators
    discovery/       — Profile classification & graph analysis
  tools/             — LLM tool definitions
lib/
  llm/               — LLM clients (Gemini, Gemma, OpenRouter)
  scraping/          — Scraping services, Python bridge
  chrome_ws_connector.rb
config/
  prompts/           — YAML prompt templates (system/, partials/)
db/
  migrate/           — App migrations
  queue_migrate/     — Solid Queue migrations
  cache_migrate/     — Solid Cache migrations
docker/              — Dockerfile, docker-compose.yml
scripts/python/      — Python scraping scripts (nodriver, camoufox)
test/                — Mirrors app/ structure
  factories/         — FactoryBot factories
docs/                — Architecture docs, comparisons, strategies
```

## Routing Table

What are you doing? Go read the CONTEXT.md for that workspace.

| Tarefa | Ler | Pular | Notas |
|--------|-----|-------|-------|
| Novo model, schema, migration | `app/models/CONTEXT.md`, `db/CONTEXT.md` | `lib/`, `scripts/` | |
| Novo job, coleta de dados | `app/jobs/CONTEXT.md`, `lib/scraping/CONTEXT.md` | `config/prompts/` | Jobs devem ser idempotentes |
| Serviço de negócio, orquestração | `app/services/CONTEXT.md` | `lib/`, `scripts/` | |
| Tool LLM, tool call | `lib/llm/CONTEXT.md` | `lib/scraping/` | Regras no próprio AGENTS.md (seção futura) |
| Integração LLM, prompt | `lib/llm/CONTEXT.md`, `config/prompts/CONTEXT.md` | `lib/scraping/`, `app/jobs/` | |
| Scraper Ferrum, Chrome, Python | `lib/scraping/CONTEXT.md`, `scripts/python/CONTEXT.md` | `config/prompts/`, `app/tools/` | |
| Escrever testes | `test/CONTEXT.md` | — | Sempre dockerizado |
| Configurar Docker | `docker/CONTEXT.md` | `app/`, `lib/` | |
| Consultar docs / estratégia | `docs/CONTEXT.md` | — | Apenas leitura |

## Commands

All commands from project root, always dockerized:

```bash
# Docker
docker-compose -f docker/docker-compose.yml up -d
docker-compose -f docker/docker-compose.yml down
docker-compose -f docker/docker-compose.yml build

# Tests
docker-compose -f docker/docker-compose.yml run --rm test
docker-compose -f docker/docker-compose.yml run --rm test test test/models/social_profile_test.rb
docker-compose -f docker/docker-compose.yml run --rm test test test/models/social_profile_test.rb -n "/test_name_pattern/"

# DB & Console
docker-compose -f docker/docker-compose.yml exec app bin/rails db:migrate
docker-compose -f docker/docker-compose.yml exec app bin/rails console
```

## Cross-Cutting Rules

These apply everywhere. Domain-specific rules live in each CONTEXT.md.

1. `# frozen_string_literal: true` on every Ruby file
2. 2-space indentation, double quotes, ~120 char lines
3. Metrics (likes, views, followers): `nil` on failure, never `0`
4. Never retry scraping on 403/429/captcha — backoff 6-12 hours
5. Always close browser connections in `ensure` blocks
6. Log with `[ClassName]` prefix: `Rails.logger.error "[MyClass] message"`
7. Prompts in YAML (`config/prompts/`), never hardcoded strings
8. Inject timestamp in every prompt: `<current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>>`

## Naming Conventions

| Tipo | Convenção | Exemplo |
|------|-----------|---------|
| Class | PascalCase | `TwitterCollectJob` |
| Job file | `snake_case_job.rb` | `scrape_twitter_job.rb` |
| Service file | `snake_case_service.rb` | `ai_router.rb` |
| Model file | `snake_case.rb` | `social_profile.rb` |
| Test file | `*_test.rb` mirroring app | `test/models/social_profile_test.rb` |
| Migration | `TIMESTAMP_description.rb` | `20260314000001_create_social_profiles.rb` |
| Prompt | `snake_case.yml` | `config/prompts/system/analysis.yml` |
| Python script | `snake_case.py` | `scripts/python/nodriver_twitter.py` |

## Key Design Decisions

- Headless Rails: no ActionView, no Sprockets, JSON API only
- SQLite WAL, 3 connections (primary, queue, cache) in single file
- Solid Queue replaces Redis/Sidekiq; Solid Cache replaces Redis cache
- Idempotent collection jobs — safe to re-run without duplicates
- Snapshot dedup window: 2 hours
