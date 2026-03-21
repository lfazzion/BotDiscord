# Contexto: app/services

Lógica de negócios e orquestração do BotDiscord.

## Services Existentes

| Service | Descrição |
|---------|-----------|
| `AiRouter` | Roteador de chamadas LLM (Gemini/Gemma/OpenRouter) |
| `Discovery::ProfileClassifier` | Classifica perfis descobertos por nicho/qualidade |
| `Discovery::SocialGraphAnalyzer` | Analisa conexões do grafo social |

## Regras Críticas para IA

1. **Lógica exclusiva aqui**: NUNCA colocar lógica de negócio em Controllers ou Models
2. **Sufixo Service**: `InfluencerProfileService`, `AiRouter`
3. **Orquestradores**: Services chamam models e outros services — não acessam banco diretamente com SQL cru
4. **Serviços stateless**: Usar `class << self` quando não precisam de estado de instância
5. **Early return**: Preferir guard clauses (`return if ...`, `next if ...`)
 6. **Null vs Zero**: Ver regra cross-cutting #3 no AGENTS.md
 7. **Métodos privados**: Depois da keyword `private`

## Cross-References

- Models: `app/models/CONTEXT.md` — dados que os services manipulam
- Jobs: `app/jobs/CONTEXT.md` — como os services são chamados
- LLM: `lib/llm/CONTEXT.md` — como o AiRouter integra com modelos
- Prompts: `config/prompts/CONTEXT.md` — templates usados pelo AiRouter
