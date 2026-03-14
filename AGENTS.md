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
docker-compose up -d          # Start services
bin/rails console             # Console
bin/rails jobs:work           # Workers
bin/rails test                # Tests
bin/rails routes              # List routes
```

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

---

## Non-Negotiable Rules

### 1. Null vs Zero - CRITICAL
- **NEVER** use `default: 0` on numeric columns (likes, views, followers)
- When API blocks/rate-limit: save as `nil`, **NEVER** as `0`
- **ALWAYS** use `.compact` in queries that calculate averages

### 2. LLM Prompts - Time Injection
- **REQUIRED** include timestamp in base prompts:
  ```erb
  <current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>
  ```
- Prompts in `config/prompts/` (YAML or ERB)

### 3. Ferrum + Docker Host Header Bypass
- Use `chromedp/headless-shell` container isolated
- **REQUIRED** bypass: request `/json/version` with `req["Host"] = "localhost"`
- Collect `webSocketDebuggerUrl`, replace internal IP for docker network

### 4. LLM Tool Calling
- **NEVER** use `.raise` - return `{success: false, message: "..."}`
- **REQUIRED** parameter clamping:
  ```ruby
  amount = [[argument_llm.to_i, 1].max, 50].min
  ```
- Return **only** pure JSON hashes/arrays (no string formatting)

### 5. Rate Limiting & Errors
- Identify HTTP `RateLimit` / `403` / Captcha
- **NEVER** immediate retry - silence, schedule job with 6-12h backoff

### 6. Idempotency
- Use `find_or_initialize_by(platform_post_id)` in jobs
- Snapshot dedup window: ignore metrics in windows < 1-2 hours

---

## Architecture Patterns

### Services
- **REQUIRED** domain logic in `app/services/`
- NEVER in controllers or models
- Naming: `NameService` (e.g., `InfluencerProfileService`)

### Background Jobs
- Solid Queue (Async)
- Naming: `NameJob` (e.g., `TwitterCollectJob`)
- Jobs must be idempotent

---

## Documentation

- [Requirements](Requisitos_Projeto_Data_Mining.md)
- [Implementation Plan](Plano_Prioridade_Implementacao.md)
- [AI Strategy](Documentations/estrategia_multi_model_ai.md)
- [Docker Chrome](Documentations/docker_chrome_setup.md)

---

## Code Conventions

- Ruby: snake_case variables/methods, CamelCase classes
- SQL: SQLite3 with migrations
- API: REST JSON-only (no HTML views)
- Testing: Minitest
