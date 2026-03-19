# Contexto: lib/llm e Prompts

Este diretório contém a lógica pura de integração com LLMs via OpenRouter, RubyLLM (Gemini, Gemma), bem como chamadas base à IA.
*(Arquivos de prompts em `config/prompts/`)*

## Regras Críticas para IA
1. **Time Injection (Injeção de Tempo) - CRÍTICO**: Todo prompt principal deve receber timestamp atual:
   ```erb
   <current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>
   ```
2. **Formatação de JSON**: Parser deve exigir retornos consistentes do LLM.
3. **Model Selection**: Observar tier correto (Gemini 3.1 Flash / Gemma 3 27B / Gemma 3 12B).
