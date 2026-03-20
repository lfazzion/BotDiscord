# frozen_string_literal: true

module Llm
  class OpenrouterClient < BaseClient
    # Claude 3.5 Sonnet via OpenRouter — fallback pesado para chat
    MODEL_ID = 'anthropic/claude-3.5-sonnet'
    MAX_DAILY = 400 # conservador para tier gratuito/pago básico

    def model_id = MODEL_ID
    def daily_quota_key = 'openrouter_daily'
    def max_daily_requests = MAX_DAILY
  end
end
