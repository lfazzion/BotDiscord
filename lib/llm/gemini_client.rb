# frozen_string_literal: true

module Llm
  class GeminiClient < BaseClient
    # Gemini 3.1 Flash Lite: 250K TPM, 15 RPM, 500 RPD
    MODEL_ID = 'google/gemini-3.1-flash-lite'
    MAX_DAILY = 480 # margem de segurança dos 500 RPD

    def model_id = MODEL_ID
    def daily_quota_key = 'gemini_daily'
    def max_daily_requests = MAX_DAILY
  end
end
