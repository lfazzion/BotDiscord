# Documentação: AI com Gemini (Free Tier)

Para o "Cérebro" do bot, utilizaremos a API do Google Gemini no Tier Gratuito.

## 💎 Gemini 1.5 Flash (Free Tier)
- **Limites:** 15 RPM (Requisições por minuto), 1 milhão de TPM (Tokens por minuto).
- **Custo:** $0 (Totalmente gratuito).
- **Destaque:** Janela de contexto massiva (1M+ tokens), ideal para ler muitos logs de comentários.

## 🛠️ Configuração no Rails
Utilizaremos a gem `google-genai` ou chamadas REST diretas.

### Exemplo de Cliente
```ruby
# app/services/gemini_client.rb
class GeminiClient
  def self.complete(prompt)
    api_key = ENV["GEMINI_API_KEY"]
    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=#{api_key}"
    
    payload = {
      contents: [{ parts: [{ text: prompt }] }]
    }

    response = Faraday.post(url) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = payload.to_json
    end
    
    JSON.parse(response.body).dig("candidates", 0, "content", "parts", 0, "text")
  end
end
```

## 🧠 Estratégia de "Prompts Modulares"
Mesmo usando Gemini Free, manteremos os prompts em arquivos **YAML** no diretório `config/prompts/` para facilitar a troca de modelos no futuro.

> [!NOTE]
> No Tier Gratuito, o Google pode usar seus dados para treinamento. Certifique-se de não enviar informações sensíveis/pessoais da usuária.
