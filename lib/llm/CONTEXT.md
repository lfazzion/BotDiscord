# Contexto: lib/llm e Prompts

Este diretório contém a lógica pura de integração com LLMs via OpenRouter, RubyLLM (por exemplo Gemini ou Gemma), bem como chamadas base à IA.
*(Para arquivos de prompts escritos puramente, confira `config/prompts/`)*

## Regras Críticas para IA
1. **Time Injection (Injeção de Tempo) - CRÍTICO**: Todo e qualquer prompt principal mandado para o LLM deve receber hard-coded o timestamp atual num trecho de injeção.
   - Isso é **OBRIGATÓRIO**: `<current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>`
2. **Formatação de JSON**: Certifique-se que o parser exija retornos consistentes, caso aplicável.
3. **Model Selection**: Observe o tier correto (Gemini 3.1 Flash / Gemma 3, etc.).
