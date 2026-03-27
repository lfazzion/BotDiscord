# frozen_string_literal: true

# config/initializers/ruby_llm.rb
#
# Configuração global do RubyLLM. Suporta Gemini nativamente e OpenRouter
# via openrouter_api_key. O provider é escolhido automaticamente pelo
# prefixo do model_id (ex: 'google/gemini-*' → Gemini, 'anthropic/*' → OpenRouter).

begin
  require 'ruby_llm'

  RubyLLM.configure do |config|
    config.gemini_api_key = ENV.fetch('GOOGLE_AI_API_KEY', nil)
    config.openrouter_api_key = ENV.fetch('OPENROUTER_API_KEY', nil)
    config.default_model = 'stepfun/step-3.5-flash:free'
    config.logger = Rails.logger
    config.log_level = Rails.env.production? ? :info : :debug
    config.request_timeout = 120
  end
rescue LoadError => e
  Rails.logger.warn "[RubyLLM] Gem não disponível: #{e.message}. Funcionalidade LLM desabilitada."
end
