# Documentação: Estratégia Multi-Model (Gemini & Gemma)

Para máxima eficiência no Tier Gratuito, o bot alternará entre **Gemini 3.1 Flash Lite** e **Gemma 3 27B**.

## 🏦 Alocação de Recursos

| Tarefa | Modelo Primário | Motivo |
| :--- | :--- | :--- |
| **Mineração de Posts (Lote)** | Gemini 3.1 Flash Lite | Janela de 1M tokens e 250K TPM. |
| **Interação Discord (Chat)** | Gemma 3 27B | Alto limite diário (14.4K RPD). |
| **Classificação Simples** | Gemma 3 27B | Economiza as 500 requests do Gemini. |
| **Fallback (Limite atingido)** | Gemma 3 27B | Assume todas as tarefas se o Gemini travar. |

## 🛠️ Implementação do Router IA (Conceito)

```ruby
# app/services/ai_router.rb
class AiRouter
  def self.complete(prompt, type: :chat)
    if type == :mining && !gemini_limit_reached?
      GeminiClient.complete(prompt)
    else
      GemmaClient.complete(prompt)
    end
  end

  def self.gemini_limit_reached?
    # Lógica baseada em Redis/DB para contar as 500 requisições diárias
    CurrentDayUsage.gemini_requests >= 490
  end
end
```

## ❄️ Especificações Gemma 3 27B
- **TPM (15.000):** Suficiente para prompts de até ~10.000 palavras por minuto.
- **RPD (14.400):** Permite o bot responder 10 vezes por minuto, 24h por dia.

> [!IMPORTANT]
> O Gemma 3 27B é um modelo de 27 bilhões de parâmetros, excelente em raciocínio, mas o limite baixo de TPM obriga a fragmentar tarefas grandes caso o Gemini não esteja disponível.
