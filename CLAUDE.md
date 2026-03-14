# BotDiscord

> Rails 8 Headless project for data collection, influencer analysis, and Discord chatbot with LLM.

**See [AGENTS.md](./AGENTS.md) for full documentation.**

## Quick Reference

| Layer | Technology |
|-------|------------|
| Framework | Rails 8.1 (--minimal) |
| Database | SQLite3 (WAL mode) |
| Queue | Solid Queue |
| Bot | discordrb |
| Scraping | Ferrum + chromedp/headless-shell |
| LLM | RubyLLM + OpenRouter/Gemini |

## Commands

```bash
docker-compose up -d          # Start services
bin/rails console             # Console
bin/rails jobs:work           # Workers
bin/rails test                # Tests
```

## System Context & AI Routing (CRITICAL)

> **PROGRESSIVE DISCLOSURE**: To avoid flooding the AI context window, specific domain rules are distributed in `CONTEXT.md` files across the project.
> **YOU MUST** read the `CONTEXT.md` file in a directory before modifying or creating files within it!

### Directory Contexts (Read before modifying!)
- **`app/services/CONTEXT.md`** -> Rules for Business/Domain Logic.
- **`app/jobs/CONTEXT.md`** -> Rules for Async Queue, Idempotency, Rate Limits.
- **`app/tools/CONTEXT.md`** -> Rules for LLM Tool Calling and JSON returns.
- **`lib/scraping/CONTEXT.md`** -> Rules for Ferrum headless scraping and Docker bypass.
- **`lib/llm/CONTEXT.md`** -> Rules for Prompt Time Injection and OpenRouter.

## Global Rule

1. **Null vs Zero**: NEVER `default: 0` on likes/views/followers. Use `nil` when API blocks. Always `.compact` averages.

## Structure

```
app/services/     # Business logic (read CONTEXT.md)
app/jobs/        # Solid Queue jobs (read CONTEXT.md)
app/tools/       # 40+ LLM Tool Calling classes (read CONTEXT.md)
lib/scraping/    # Ferrum scrapers (read CONTEXT.md)
lib/llm/         # LLM orchestrator (read CONTEXT.md)
config/prompts/  # YAML/ERB prompts
test/            # Minitest
```

## Docs

- [Requirements](./Requisitos_Projeto_Data_Mining.md)
- [Implementation Plan](./Plano_Prioridade_Implementacao.md)
