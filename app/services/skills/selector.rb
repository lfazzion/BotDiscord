# frozen_string_literal: true

module Skills
  # Seletor autônomo de skills: decide se uma mensagem deve ativar uma skill.
  #
  # Prioridade:
  # 1. Trigger explícito (slash/texto) -> escolhe sem chamar classificador
  # 2. Modo já ativo -> mantém
  # 3. Hints candidatos -> chama classificador uma vez
  # 4. Nada -> nil
  #
  # Fail-closed: baixa confiança, timeout, quota ou erro => nil (sem classificação)
  class Selector
    CONFIDENCE_THRESHOLD = 0.7
    SELECTOR_CONTEXT = :interactive

    attr_reader :registry

    def initialize(registry:)
      @registry = registry
    end

    # Chama o seletor com a mensagem do usuário.
    #
    # Args:
    #   message: String com o conteúdo da mensagem
    #   conversation_id: String/NIL - ID da conversa ativa (para fail-closed)
    #   active_skill: String/NIL - skill já ativa (se houver)
    #
    # Returns:
    #   String com o nome da skill selecionada, ou nil se nenhuma for adequada
    def call(message, conversation_id: nil, active_skill: nil)
      # 1. Se já há skill ativa, mantém
      return active_skill if active_skill.present?

      # 2. Trigger explícito?
      explicit_match = registry.explicit_match?(message)
      return explicit_match if explicit_match

      # 3. Hint candidato?
      return nil unless registry.candidate_hints?(message)

      # 4. Fail-closed: se já houve negativa nesta conversa, não tenta novamente
      if conversation_id.present? && negated_in_conversation?(conversation_id)
        Rails.logger.info "[Skills::Selector] Fail-closed: classificação negada anteriormente em #{conversation_id}"
        return nil
      end

      # 5. Chama classificador (no máximo 1x por turno)
      select_with_classifier(message, conversation_id)
    end

    private

    def negated_in_conversation?(conversation_id)
      Rails.cache.fetch("selector_negated_#{conversation_id}") { false }
    end

    def select_with_classifier(message, conversation_id)
      catalog = build_compact_catalog
      prompt_text = load_selector_prompt

      # Trunca input conforme limite
      max_input = registry.selector_max_input_chars
      truncated_message = message.to_s[0...max_input]

      # Combina o prompt do sistema com o catálogo
      full_prompt = "#{prompt_text}\n\nCatálogo de skills:\n#{catalog}\n\nMensagem do usuário: #{truncated_message}"

      # Parâmetros limitadores da classificação
      params = {
        max_tokens: registry.selector_max_output_tokens
      }

      begin
        response = AiRouter.complete(
          full_prompt,
          context: SELECTOR_CONTEXT,
          tools: [],
          params: params
        )

        parse_classification(response, conversation_id)
      rescue Timeout::Error, RubyLLM::RateLimitError, RubyLLM::ServiceUnavailableError,
             RubyLLM::OverloadedError, RubyLLM::PaymentRequiredError, Llm::BaseClient::QuotaExceededError => e
        Rails.logger.warn "[Skills::Selector] Erro no classificador: #{e.class.name}: #{e.message}"
        mark_negative(conversation_id) if conversation_id.present?
        nil
      end
    end

    def build_compact_catalog
      @catalog ||= begin
        skills = registry.all.map do |skill|
          {
            name: skill[:name],
            description: skill[:description][0..200] # Compacta: máx 200 chars
          }
        end
        "{\n" + skills.map { |s| "  \"#{s[:name]}\": \"#{s[:description]}\"" }.join(",\n") + "\n}"
      end
    end

    def load_selector_prompt
      prompt_path = Rails.root.join('config/prompts/system/skill_selector.yml')
      return '' unless prompt_path.exist?

      raw = prompt_path.read
      yaml = YAML.safe_load(raw, permitted_classes: [Symbol])
      yaml['system'].to_s.strip
    end

    def parse_classification(response, conversation_id)
      text = response.respond_to?(:content) ? response.content.to_s : response.to_s
      return nil if text.blank?

      begin
        result = JSON.parse(text)
        skill = result['skill']
        confidence = result['confidence'].to_f

        # Valida confidence
        return nil if confidence < CONFIDENCE_THRESHOLD

        # Valida skill
        unless valid_skill?(skill)
          Rails.logger.warn "[Skills::Selector] skill '#{skill}' retornada pelo classificador não existe no registry"
          mark_negative(conversation_id) if conversation_id.present?
          return nil
        end

        # Sucesso: marca como positiva (remove flag de negativa se existir)
        clear_negative(conversation_id) if conversation_id.present?

        skill
      rescue JSON::ParserError
        Rails.logger.warn "[Skills::Selector] Resposta não-JSON do classificador: #{response.inspect}"
        mark_negative(conversation_id) if conversation_id.present?
        nil
      end
    end

    def valid_skill?(skill_name)
      return false if skill_name.nil? || skill_name.to_s.strip.empty?
      registry.fetch(skill_name.to_s).present?
    end

    def mark_negative(conversation_id)
      Rails.cache.write("selector_negated_#{conversation_id}", true, expires_in: 1.hour)
    end

    def clear_negative(conversation_id)
      Rails.cache.delete("selector_negated_#{conversation_id}")
    end
  end
end
