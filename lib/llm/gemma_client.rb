# frozen_string_literal: true

module Llm
  class GemmaClient < BaseClient
    # Gemma 3 27B: 15K TPM, 30 RPM, 14.400 RPD
    MODEL_ID = 'google/gemma-3-27b'
    MAX_DAILY = 14_000 # margem de segurança dos 14.400 RPD
    TPM_SAFE_THRESHOLD = 8_000 # acima disso, escalar para OpenRouter

    def model_id = MODEL_ID
    def daily_quota_key = 'gemma_daily'
    def max_daily_requests = MAX_DAILY

    def self.tpm_safe_threshold
      TPM_SAFE_THRESHOLD
    end
  end
end
