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

    def complete(prompt, system: nil, tools: [])
      check_quota!
      track_request!

      chat = RubyLLM.chat(model: model_id)
      chat.with_instructions(system) if system
      tools.each { |t| chat.with_tool(t) }

      Rails.logger.info "[#{self.class.name}] Requisição enviada (model: #{model_id})"
      chat.ask(prompt)
    end

    private

    def check_quota!
      count = daily_request_count
      return unless count >= max_daily_requests

      Rails.logger.warn "[#{self.class.name}] Quota diária atingida: #{count}/#{max_daily_requests}"
      raise QuotaExceededError, "#{self.class.name} excedeu #{max_daily_requests} requests/dia"
    end

    def track_request!
      cache_key = daily_cache_key
      current = SolidCache.read(cache_key).to_i
      SolidCache.write(cache_key, current + 1, expires_in: 26.hours)
    end

    def daily_request_count
      SolidCache.read(daily_cache_key).to_i
    end

    def daily_cache_key
      "#{daily_quota_key}:#{Date.current.iso8601}"
    end
  end
end
