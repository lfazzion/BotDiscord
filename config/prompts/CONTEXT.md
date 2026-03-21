# Contexto: config/prompts

Templates YAML de prompts para LLMs. Nunca hardcode strings de prompt — sempre carregar daqui.

## Estrutura

```
config/prompts/
  system/          — Prompts de sistema (completos)
    base.yml        — Prompt base para o AiRouter
    analysis.yml    — Prompt para análise de perfis
    discovery.yml   — Prompt para descoberta de perfis
  partials/        — Fragmentos reutilizáveis (injetados via ERB)
    _rules.yml      — Regras comuns
    _time_injection.yml — Injeção de timestamp
```

## Regras Críticas para IA

1. **Sempre ERB com timestamp**: Todo prompt principal deve injetar:
   ```erb
   <current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>>
   ```
2. **Partials com prefixo `_`**: Fragmentos reutilizáveis começam com `_` e são injetados via ERB render
3. **Carregamento**: Usar `PromptLoader.load('system/analysis')` — nunca ler arquivo diretamente
4. **Nomenclatura**: `snake_case.yml` — nome descreve o propósito
5. **Sem lógica Ruby nos YAML**: Apenas texto do prompt e ERB para interpolação de variáveis
 6. **Um prompt por tarefa**: Não criar prompts genéricos demais. Cada fluxo de LLM tem seu próprio prompt

## Cross-References

- LLM: `lib/llm/CONTEXT.md` — como o PromptLoader carrega estes templates
- Services: `app/services/CONTEXT.md` — AiRouter que consome os prompts
