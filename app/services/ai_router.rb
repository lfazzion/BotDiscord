# frozen_string_literal: true

class AiRouter
  ESTIMATED_TOKENS_PER_CHAR = 0.25

  class << self
    def gemma_tpm_threshold
      @gemma_tpm_threshold ||= defined?(Llm::GemmaClient) ? Llm::GemmaClient.tpm_safe_threshold : 8000
    end

    def complete(prompt, context: :interactive, tools: [])
      system_msg, user_msg = extract_messages(prompt)
      estimated_tokens = estimate_tokens(user_msg)

      client = select_client(context, estimated_tokens)
      Rails.logger.info "[AiRouter] Roteando para #{client.class.name} " \
                        "(ctx: #{context}, ~#{estimated_tokens} tokens)"

      client.complete(user_msg, system: system_msg, tools: tools)
    rescue Llm::BaseClient::QuotaExceededError => e
      handle_quota_exceeded(e, context, estimated_tokens)
    end

    private

    def extract_messages(prompt)
      if prompt.is_a?(Hash)
        [prompt[:system], prompt[:user]]
      else
        [nil, prompt.to_s]
      end
    end

    def select_client(context, estimated_tokens)
      case context
      when :background
        Llm::GeminiClient.new
      when :interactive
        if estimated_tokens > gemma_tpm_threshold
          Llm::OpenrouterClient.new
        else
          Llm::GemmaClient.new
        end
      else
        raise ArgumentError, "Contexto desconhecido: #{context}. Use :background ou :interactive"
      end
    end

    def estimate_tokens(text)
      return 0 if text.nil?

      (text.length * ESTIMATED_TOKENS_PER_CHAR).ceil
    end

    def handle_quota_exceeded(error, context, _estimated_tokens)
      Rails.logger.warn "[AiRouter] #{error.message}. Tentando fallback..."
      raise error unless context == :background

      Rails.logger.warn '[AiRouter] Gemini esgotado. Fallback para OpenRouter (background).'
      raise error
    end
  end
end
