# Contexto: lib/llm

Integração pura com LLMs via OpenRouter, Gemini, Gemma.

## Arquivos

| Arquivo | Descrição |
|---------|-----------|
| `base_client.rb` | Classe base com error handling e retry |
| `gemini_client.rb` | Cliente Gemini 3.1 Flash (tier: background) |
| `gemma_client.rb` | Cliente Gemma 3 27B/12B (tier: interactive short) |
| `openrouter_client.rb` | Cliente OpenRouter (tier: interactive long) |
| `prompt_loader.rb` | Carrega templates YAML de `config/prompts/` |

## Regras Críticas para IA

 1. **Time Injection**: Ver regra cross-cutting #8 no AGENTS.md
 2. **Usar PromptLoader**: `PromptLoader.load('system/analysis')` — nunca ler YAML diretamente
 3. **Roteamento**: `AiRouter.complete(prompt, context: :interactive|:background)` — ver `app/services/CONTEXT.md`
 4. **Error handling**: `QuotaExceededError`, `RateLimitError` — classes aninhadas no módulo

## Cross-References

- Services: `app/services/CONTEXT.md` — AiRouter orquestra chamadas
- Prompts: `config/prompts/CONTEXT.md` — templates carregados pelo PromptLoader
