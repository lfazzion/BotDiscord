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
| Testing | Minitest + FactoryBot + Mocha + WebMock |

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
bin/rails routes              # List routes

# Testing
bin/rails test                          # Run all tests
bin/rails test test/models/             # Run all model tests
bin/rails test test/models/social_profile_test.rb       # Single test file
bin/rails test test/models/social_profile_test.rb:10    # Single test by line number
bin/rails test test/jobs/discovery_job_test.rb -n test_should_enqueue_in_default_queue  # By test name
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
- `bin/entrypoint-jobs` (jobs): Starts Solid Queue supervisor via `bin/jobs start`
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
- Test fixtures: `test/factories/`
- Test files mirror `app/` structure under `test/`

---

## Code Style

### General
- Ruby: `snake_case` for variables/methods, `CamelCase` for classes/modules
- Constants: `SCREAMING_SNAKE_CASE` (e.g., `SNAPSHOT_DEDUP_WINDOW = 2.hours`)
- Add `# frozen_string_literal: true` at top of all `.rb` files
- API: REST JSON-only (no HTML views - this is a headless Rails app)

### Naming Conventions
- Services: `XxxService` suffix (e.g., `AiRouter`, `Discovery::SocialGraphAnalyzer`)
- Jobs: `XxxJob` suffix (e.g., `ScrapeTwitterJob`, `DiscoveryJob`)
- Tools (LLM): descriptive names, return JSON hashes only
- Models: singular noun (e.g., `SocialProfile`, `DiscoveredProfile`)

### Imports/Requires
- Test files: `require "test_helper"` (relative to `test/`)
- Lib files are autoloaded via `config.autoload_lib(ignore: %w[assets tasks scraping llm])`
- `lib/scraping/` and `lib/llm/` are NOT autoloaded — require them explicitly when needed

### Error Handling
- Services/Jobs: rescue `StandardError` with logging, never swallow silently
- Rate limits: never retry immediately; reschedule with 6-12 hour backoff
- Tools (LLM): return `{success: false, message: "..."}` — **never** raise exceptions
- Quota errors: rescue `Llm::BaseClient::QuotaExceededError` separately from generic errors

### Null vs Zero (CRITICAL)
- **NEVER** use `default: 0` on numeric columns (likes, views, followers)
- When API blocks/rate-limits: save as `nil`, **never** as `0`
- **ALWAYS** use `.compact` in queries that calculate averages

### Testing (Minitest)
- Test class inherits from `ActiveSupport::TestCase` or `ActiveJob::TestCase`
- Use FactoryBot methods via `include FactoryBot::Syntax::Methods` (in test_helper)
- Use Mocha for stubs/mocks: `.stubs()`, `.expects()`, `.never`
- Use WebMock for HTTP stubbing; `WebMock.disable_net_connect!(allow_localhost: true)` is on
- Test names: `test "should do something descriptive" do ... end`
- Use `assert_difference` / `assert_no_difference` for count changes

---

## System Context & AI Routing (CRITICAL)

> **PROGRESSIVE DISCLOSURE**: To avoid flooding the AI context window, specific domain rules are distributed in `CONTEXT.md` files across the project.
> **YOU MUST** read the `CONTEXT.md` file in a directory before modifying or creating files within it!

### Directory Contexts (Read before modifying!)
- **`app/services/CONTEXT.md`** -> Business/Domain Logic rules
- **`app/jobs/CONTEXT.md`** -> Async Queue, Idempotency, Rate Limits
- **`app/tools/CONTEXT.md`** -> LLM Tool Calling, JSON returns, parameter clamping
- **`lib/scraping/CONTEXT.md`** -> Ferrum headless scraping, Chrome Docker bypass
- **`lib/llm/CONTEXT.md`** -> Prompt Time Injection, OpenRouter integration
- **`docker/CONTEXT.md`** -> Docker compose, shared volumes, Chrome Headless

### Global Non-Negotiable Rules

1. **Null vs Zero**: Never `default: 0` on metrics; save `nil` on failure, use `.compact` for averages
2. **Database**: Multi-database setup (`primary`, `queue`, `cache`) pointing to single SQLite file via bind mount
3. **Jobs**: Must be idempotent (`find_or_initialize_by`). No immediate retries on rate limits
4. **Services**: Business logic lives in `app/services/`, never in controllers or models
5. **Tools**: Return structured hashes only. Clamp LLM parameters. Never raise

### LLM Prompt Requirement
- All prompts must include current timestamp via ERB:
  ```erb
  <current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>
  ```

---

## Documentation

- [Requirements](Requisitos_Projeto_Data_Mining.md)
- [Implementation Plan](Plano_Prioridade_Implementacao.md)
- [AI Strategy](docs/estrategia_multi_model_ai.md)
- [Docker Chrome](docs/docker_chrome_setup.md)
