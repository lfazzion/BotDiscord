# frozen_string_literal: true

module Llm
  class BaseClient
    class QuotaExceededError < StandardError; end

    def model_id
      raise NotImplementedError, "#{self.class}#model_id não implementado"
    end

    def daily_quota_key
      raise NotImplementedError, "#{self.class}#daily_quota_key não implementado"
    end

    def max_daily_requests
      raise NotImplementedError, "#{self.class}#max_daily_requests não implementado"
    end

    def complete(prompt, system: nil, tools: [], params: nil)
      reserve_quota!

      # HOTFIX-GEMINI-PARAMS (06/09): normalizar params por provedor ANTES do
      # with_params. A gem RubyLLM 1.16.0 deep_mergeia params NO TOPO do payload
      # HTTP (provider.rb:57); Gemini espera generationConfig.maxOutputTokens /
      # generationConfig.temperature, não max_tokens / temperature no topo.
      # OpenAI/OpenRouter aceitam max_tokens no topo — params intatos para eles.
      normalized_params = normalize_params_for_provider(params) if params.is_a?(Hash) && params.any?

      begin
        chat = RubyLLM.chat(model: model_id)
        chat.with_instructions(system) if system
        tools.each { |t| chat.with_tool(t) }
        chat.with_params(**normalized_params) if normalized_params.is_a?(Hash) && normalized_params.any?
      rescue QuotaExceededError
        # levantada dentro de reserve_quota! antes de qualquer chat — nada a reverter
        raise
      rescue StandardError
        # Falha na PREPARAÇÃO (antes do envio ao provedor): a quota externa não
        # foi tocada, reverte a reserva local (P1 do sol, 13/08).
        rollback_quota!
        raise
      end

      # A partir daqui a requisição SAI para o provedor: timeout, parse error e
      # qualquer falha do chat.ask NÃO revertem a quota — o provedor já contou
      # a chamada mesmo sem resposta útil.
      Rails.logger.info "[#{self.class.name}] Requisição enviada (model: #{model_id})"
      chat.ask(prompt)
    rescue QuotaExceededError
      raise
    end

    private

    # Normaliza params de acordo com o provedor antes de repassar ao chat.with_params.
    #
    # Regra (apenas as 2 keys conhecidas — não inventar traduções para keys desconhecidas):
    #   - Modelo Gemini (model_id.include?('gemini')):
    #       :max_tokens      → {generationConfig: {maxOutputTokens: valor}}
    #       :temperature     → {generationConfig: {temperature: valor}}
    #       outras keys      → repassadas intatas (o provedor vai rejeitar com erro
    #                           nomeado, tratável — não silencioso).
    #   - Demais provedores (OpenRouter, OpenAI, etc.): params intatos.
    def normalize_params_for_provider(params)
      return params unless model_id.include?('gemini')

      gemini_params = {}
      generation_config = {}

      params.each do |key, value|
        case key
        when :max_tokens
          generation_config[:maxOutputTokens] = value
        when :temperature
          generation_config[:temperature] = value
        else
          gemini_params[key] = value
        end
      end

      gemini_params[:generationConfig] = generation_config if generation_config.any?

      gemini_params
    end

    # Atômico: usa Rails.cache.increment como única operação de reserva.
    # Nenhum read-modify-write — o incremento é uma operação CAS do backend.
    def reserve_quota!
      cache_key = daily_cache_key
      max = max_daily_requests

      # Primeira tentativa: criação atômica da chave (unless_exist) + incremento.
      # Se a chave já existia, increment retorna nil e fazemos uma nova tentativa
      # sem unless_exist — ainda assim atômica.
      count = Rails.cache.increment(cache_key, 1, expires_in: 26.hours, unless_exist: true)
      count = Rails.cache.increment(cache_key, 1, expires_in: 26.hours) if count.nil?

      # ACHADO B (P1, sol 13/08): se AMBAS as tentativas de increment retornarem
      # nil (backend de cache sem suporte a increment/CAS), `count` fica nil e o
      # método retornaria nil, fazendo com que o provedor fosse chamado SEM
      # qualquer reserva de quota — um bypass silencioso. Levantamos erro
      # explícito ANTES de criar o chat (complete() chama reserve_quota! antes de
      # RubyLLM.chat). Não há fallback seguro: sem increment atômico não podemos
      # garantir a contagem, então recusamos a chamada em vez de contorná-la.
      raise RuntimeError, "#{self.class.name}: não foi possível reservar quota — Rails.cache.increment retornou nil nas duas tentativas (backend sem suporte a increment atômico?)" if count.nil?

      if count && count > max
        rollback_quota!
        Rails.logger.warn "[#{self.class.name}] Quota diária atingida: #{count}/#{max}"
        raise QuotaExceededError, "#{self.class.name} excedeu #{max} requests/dia"
      end

      count
    end

    # Reverte atomicamente o incremento feito por reserve_quota! quando a
    # requisição falha antes de completar. Garante que a quota só seja
    # consumida por requisições que realmente atingiram o provedor.
    def rollback_quota!
      cache_key = daily_cache_key
      Rails.cache.decrement(cache_key, 1, expires_in: 26.hours)
    end

    def daily_cache_key
      "#{daily_quota_key}:#{Date.current.iso8601}"
    end
  end
end
