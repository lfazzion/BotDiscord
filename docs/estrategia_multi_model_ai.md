# Documentação: Estratégia Multi-Model e Tratamento de Rate Limits (2026)

A arquitetura Multi-Model orquestra o roteamento da lógica não apenas pela propensão de modelo, mas **estritamente para desviar das colisões lógicas de limites** de TPM (Tokens Per Minute) e RPD (Requests Per Day) exigidos pelas cotas do Google AI Studio.

## 🏦 Alocação Dinâmica Baseada na Matriz de Cota

| Tarefa | Modelo Acionado | Justificativa Baseada nos Limites (Ruleset) |
| :--- | :--- | :--- |
| **Pipes de Scraping & Processamento de Dados** | Gemini 3.1 Flash Lite | Devido ao TPM de 250K, aguenta payloads pesados. Como tem apenas 500 RPD, os jobs devem agrupar tarefas (batching) e realizar poucos chamados ultra densos por dia. |
| **Chatbot Interativo (Discord)** | Gemma 3 27B | Com 14.400 RPD, pode conversar à vontade. Graças ao limite de 15K TPM, as interações não devem possuir grandes anexos contextuais em uma mesma janela curta. |
| **Tool Calling / Database Queries**| Gemma 3 27B | Os prompts contendo injeções analíticas DEVEM ser micro-otimizados (< 7K tokens de ida), respeitando a via dupla restrita do teto de 15K TPM. |

## 🛠️ O "AI Router" e Rate Limit Guardian (Pseudo-Implementação Ruby)

O roteador de IA atua como um "Guardião de Transações". Cargas contextuais devem ser rigorosamente medidas antes do envio.

```ruby
# app/services/ai_router.rb
class AiRouter
  # Limiar defensivo baseando-se no limite estrito de 15.000 TPM do Gemma
  # Se o prompt superar isso, a API retornará falha imediata na taxa (429)
  GEMMA_TPM_SAFE_THRESHOLD = 8_000

  def self.complete(prompt, tools: [], expected_tokens: 0)
    if expected_tokens > GEMMA_TPM_SAFE_THRESHOLD
      Rails.logger.warn "[AiRouter] Limite seguro do Gemma(15K) excedido. Escalando p/ Gemini 3.1 Flash Lite."
      # Falback pesado: Aproveita o TPM de 250K do Flash Lite sacrificando 1 das 500 requisições diárias.
      GeminiClient.complete(prompt, tools: tools)
    else
      # Operação Padrão: Alta agilidade (30 RPM) e quase infinito uso diário (14.4K RPD)
      Rails.logger.info "[AiRouter] Requisição leve. Entregando para Gemma 3 27B."
      GemmaClient.complete(prompt, tools: tools)
    end
  end
end
```

## ❄️ Estratégias Definitivas de Proteção de Cotas no Rails 8

1. **Batching Compulsório (Solid Queue):**
   Como o Gemini 3.1 Flash Lite foi severamente restrito a meros **500 Requests/Dia**, o seu Scraping Worker NUNCA deve requisitar IA para classificar uma postagem de cada vez. O Solid Queue deve preencher uma tabela de `pending_analyses`, e um Cron Job roda de hora em hora pegando blocos gigantes de dados e processando tudo em um único prompt de `150.000` tokens, poupando imensamente as preciosas quotas diárias.
   
2. **Context Shrinking (Memória do Discord via Gemma):**
   Gemma no limite de **15.000 TPM** obriga o Bot a sofrer de certa "amnésia controlada". O método controlador do Evento do Discord deve injetar no máximo o contexto da conversa dos últimos **5 balõezinhos** de mensagens na API, com extrema parcimônia e regras que cortem a string se a soma arriscar bater o teto de 15K por minuto.
