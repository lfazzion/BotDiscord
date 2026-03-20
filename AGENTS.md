# AGENTS.md — BotDiscord

Headless Rails 8.1 app for influencer data mining, scraping, and Discord bot integration. Ruby ~> 4.0, SQLite3 (WAL), Solid Queue/Cache, Minitest.

## Build / Test / Lint Commands

All commands run inside Docker. Execute from project root.

```bash
# ── Docker services ──────────────────────────────────────────────────────
docker-compose -f docker/docker-compose.yml up -d          # start app + jobs + chrome
docker-compose -f docker/docker-compose.yml logs -f        # tail logs
docker-compose -f docker/docker-compose.yml down           # stop everything
docker-compose -f docker/docker-compose.yml build          # rebuild after code changes

# ── Tests (always dockerized) ────────────────────────────────────────────
# Run all tests
docker-compose -f docker/docker-compose.yml run --rm test

# Run a single test file
docker-compose -f docker/docker-compose.yml run --rm test test test/models/social_profile_test.rb

# Run a single test by name (Minitest filter)
docker-compose -f docker/docker-compose.yml run --rm test test test/models/social_profile_test.rb -n "/test_name_pattern/"

# Run tests in a directory
docker-compose -f docker/docker-compose.yml run --rm test test test/services/

# ── Database (inside running app container) ──────────────────────────────
docker-compose -f docker/docker-compose.yml exec app bin/rails db:migrate

# ── Rails console (inside running app container) ─────────────────────────
docker-compose -f docker/docker-compose.yml exec app bin/rails console

# ── Job workers ──────────────────────────────────────────────────────────
# Already started by docker-compose up via the 'jobs' service.
# Manual restart:
docker-compose -f docker/docker-compose.yml restart jobs

# No Rubocop or linting configured — follow conventions below
```

## Project Structure

```
app/
  jobs/        — ActiveJob classes (Solid Queue). Suffix: *Job
  models/      — ActiveRecord models. Inherit ApplicationRecord
  services/    — Business logic. Suffix: *Service. Orchestrators only
  tools/       — LLM tool definitions
lib/
  llm/         — LLM clients (Gemini, Gemma, OpenRouter). Module: Llm::
  scraping/    — Scraping services, Python bridge. Module: ScrapingServices::
  chrome_ws_connector.rb — Chrome DevTools WebSocket connector
config/
  prompts/     — YAML prompt templates (system/, partials/)
test/
  factories/   — FactoryBot factories
  mirrors app/ structure for test organization
```

## Code Style

### General
- Use `# frozen_string_literal: true` at top of every Ruby file
- 2-space indentation, no tabs
- Double quotes for strings (mixed in existing code, but prefer `"` for new code)
- Max line length ~120 chars (soft limit)
- No trailing whitespace

### Naming Conventions
- Classes: `PascalCase`. Jobs end in `Job`, services end in `Service`
- Methods/variables: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`
- Database columns: `snake_case`
- Files: `snake_case.rb` matching class name

### Modules and Namespacing
- Services in `app/services/` use plain classes (e.g., `AiRouter`)
- Services in subdirectories use modules (e.g., `Discovery::ProfileClassifier`)
- Lib classes use modules: `Llm::BaseClient`, `ScrapingServices::RateLimitHandler`

### Models
- Inherit from `ApplicationRecord`
- Define constants with `.freeze` (e.g., `PLATFORMS = %w[twitter instagram].freeze`)
- Use scopes for reusable queries, prefer `lambda` syntax
- Validations at top, then associations, then scopes, then instance methods

### Services
- Business logic lives in `app/services/`, never in controllers or models
- Stateless services use `class << self` pattern
- Private methods go after `private` keyword
- Return early with guard clauses (`return if ...`, `next if ...`)

### Jobs
- Inherit from `ApplicationJob`
- Always use `queue_as :default` (or named queue)
- Must be idempotent — use `find_or_initialize_by` / `find_or_create_by`
- Rate-limit errors: rescue `ScrapingServices::RateLimitError`, call `retry_job wait:`
- Never retry immediately on 403/429/captcha — backoff 6-12 hours

### Error Handling
- Custom errors nested in their module (e.g., `Llm::BaseClient::QuotaExceededError`)
- Use `StandardError` as base, not `Exception`
- Rescue specific errors before `StandardError`
- Log with `[ClassName]` prefix: `Rails.logger.error "[MyClass] message"`
- Use `ensure` for cleanup (closing browser connections, etc.)

### Null vs Zero
- Social metrics (likes, views, followers): save `nil` on failure, never `0`
- Zero is a valid value; nil means "unknown/failed collection"
- Use `.compact` when computing averages to exclude nils

### Testing
- Framework: Minitest with `ActiveSupport::TestCase`
- Factories: FactoryBot (use `build`, `create`, `build_list`, `create_list`)
- Mocks: Mocha (`.expects`, `.stubs`)
- HTTP stubs: WebMock (`stub_request`)
- Test class names: `ClassNameTest` in file `test/path/class_name_test.rb`
- Use `test "description do ... end` block syntax (not `def test_...`)
- Use `setup` blocks for shared test data
- Include `require 'test_helper'` at top of every test file

### LLM / Prompt Patterns
- Prompts live in YAML files under `config/prompts/`, not hardcoded strings
- Always inject current timestamp in prompts: `<current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>`
- Use `AiRouter.complete(prompt, context: :interactive|:background)` for LLM calls
- Context `:background` routes to Gemini; `:interactive` routes to Gemma (short) or OpenRouter (long)

### Scraping Patterns
- Chrome headless via Ferrum, connecting to `docker-chrome` on port 9222
- Host Header Bypass: set `Host: localhost` on `/json/version` requests (Chrome 120+ requirement)
- Always close browser connections in `ensure` blocks
- Detect blocks (DataDome, Cloudflare, captchas) → return nil, reschedule with backoff

## Key Design Decisions
- Headless Rails: no ActionView, no Sprockets, JSON API only
- SQLite in WAL mode for all environments; single file, 3 connections (primary, queue, cache)
- Solid Queue replaces Redis/Sidekiq; Solid Cache replaces Redis cache
- Idempotent collection jobs — safe to re-run without duplicates
- Dedup window for snapshots: 2 hours (`SNAPSHOT_DEDUP_WINDOW = 2.hours`)
