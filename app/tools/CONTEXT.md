# Contexto: app/tools

Este diretório contém classes responsáveis pelas Tool Calls feitas via LLM, integradas à lógica do projeto BotDiscord.

## Regras Críticas para IA e Ferramentas LLM
1. **Tratamento de Exceções**: **NUNCA** use `.raise` em ferramentas. Todos os erros previsíveis e comportamentos inesperados devem retornar um hash de resposta indicando erro. Por exemplo: `{success: false, message: "Razão do erro..."}`.
2. **Limitação e Clamping de Parâmetros**: Parâmetros passados pelo LLM não são totalmente confiáveis. Você é **OBRIGADO** a fazer clamp ou sanitizar valores numéricos.
   - Exemplo obrigatório de clamping: `amount = [[argument_llm.to_i, 1].max, 50].min`
3. **Formatação de Retorno**: O retorno do método da ferramenta deve ser **apenas** Arrays ou Hashes JSON puros. **NUNCA** retorne strings formatadas para "leitura humana" a partir das tools. O LLM cuida da formatação na camada superior de geração, mas a tool deve retornar puro dado estruturado.
4. **Números (Null vs Zero)**: Valores numéricos de métricas (resgatados via API, etc.) que não foram encontrados devem ser retornados/salvos como `nil`, e nunca `0`! O `0` falseia as médias. Apenas use `0` se tiver certeza de que a métrica é de fato 0.
