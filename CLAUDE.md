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

## Key Rules (CRITICAL)

1. **Null vs Zero**: NEVER `default: 0` on likes/views/followers. Use `nil` when API blocks.
2. **Prompts**: Include `<current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>` in all LLM prompts.
3. **Tool Calling**: NEVER use `.raise` - return `{success: false, message: "..."}` instead.
4. **Tool Returns**: Return pure Hash/Array JSON, never formatted strings.
5. **Clamping**: Always clamp LLM parameters: `amount = [[arg.to_i, 1].max, 50].min`
6. **Rate Limits**: NEVER retry immediately - schedule job with 6-12h backoff.

## Structure

```
app/services/     # Business logic (REQUIRED)
app/jobs/        # Solid Queue jobs
app/tools/       # 40+ LLM Tool Calling classes
lib/scraping/    # Ferrum scrapers
lib/llm/         # LLM orchestrator
config/prompts/  # YAML/ERB prompts
test/            # Minitest
```

## Docs

- [Requirements](./Requisitos_Projeto_Data_Mining.md)
- [Implementation Plan](./Plano_Prioridade_Implementacao.md)
