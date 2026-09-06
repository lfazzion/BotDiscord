# frozen_string_literal: true

require 'test_helper'

# ── HOTFIX-GEMINI-PARAMS (06/09): normalização de params por provedor ─────────
# Bug de produção: Skills::Selector passa {max_tokens: 64} que BaseClient#complete
# repassa direto ao chat.with_params. A gem RubyLLM 1.16.0 deep_mergeia no topo do
# payload HTTP; Gemini espera generationConfig.maxOutputTokens, não max_tokens.
#
# Este teste verifica que BaseClient normaliza params ANTES do with_params:
#   - Gemini: max_tokens → generationConfig.maxOutputTokens, temperature → generationConfig.temperature
#   - Demais provedores: params intatos
class LlmBaseClientParamsTest < ActiveSupport::TestCase
  # Dummy chat que captura os args de with_params para inspeção.
  class CaptureChat
    attr_reader :with_params_args

    def with_instructions(_); self; end
    def with_tool(_); self; end
    def with_params(**kw)
      @with_params_args = kw
      self
    end
    def ask(_prompt)
      Struct.new(:content).new('resposta')
    end
  end

  # Cliente concreto mínimo que herda BaseClient e usa model_id Gemini.
  class TesteGeminiClient < Llm::BaseClient
    MODEL_ID = 'gemini-3.5-flash-lite'

    def model_id = MODEL_ID
    def daily_quota_key = 'teste_gemini_daily'
    def max_daily_requests = 999_999 # irrelevante para os testes de params
  end

  # Cliente concreto mínimo para provedor não-Gemini (openrouter).
  class TesteOpenrouterClient < Llm::BaseClient
    MODEL_ID = 'openrouter/free'

    def model_id = MODEL_ID
    def daily_quota_key = 'teste_openrouter_daily'
    def max_daily_requests = 999_999
  end

  setup do
    Rails.cache.clear
    @gemini_client = TesteGeminiClient.new
    @openrouter_client = TesteOpenrouterClient.new
  end

  # ── RED: comportamento atual (sem normalização) falha para Gemini ────────────

  test 'Gemini: max_tokens é normalizado para generationConfig.maxOutputTokens antes do with_params' do
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'gemini-3.5-flash-lite').returns(chat)

    @gemini_client.complete('foo', params: { max_tokens: 64 })

    # COMPORTAMENTO ATUAL (BUG): with_params recebe {max_tokens: 64} → Gemini rejeita.
    # Após o fix, deve receber {generationConfig: {maxOutputTokens: 64}}.
    assert_equal({ generationConfig: { maxOutputTokens: 64 } }, chat.with_params_args,
                 'Gemini deve receber generationConfig.maxOutputTokens, não max_tokens')
  end

  test 'Gemini: temperature é normalizado para generationConfig.temperature antes do with_params' do
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'gemini-3.5-flash-lite').returns(chat)

    @gemini_client.complete('foo', params: { temperature: 0.5 })

    assert_equal({ generationConfig: { temperature: 0.5 } }, chat.with_params_args,
                 'Gemini deve receber generationConfig.temperature, não temperature no topo')
  end

  test 'Gemini: params vazios não chama with_params' do
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'gemini-3.5-flash-lite').returns(chat)

    @gemini_client.complete('foo', params: nil)

    assert_nil chat.with_params_args, 'params nil não deve chamar with_params'
  end

  test 'Gemini: params vazios (hash vazio) não chama with_params' do
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'gemini-3.5-flash-lite').returns(chat)

    @gemini_client.complete('foo', params: {})

    assert_nil chat.with_params_args, 'params {} não deve chamar with_params'
  end

  test 'Gemini: outros params além de max_tokens/temperature são repassados intatos' do
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'gemini-3.5-flash-lite').returns(chat)

    # Se futuramente surgir outra key que Gemini aceite no topo, ela deve passar.
    @gemini_client.complete('foo', params: { max_tokens: 64, temperature: 0.5, extra_key: 'x' })

    # A chave extra_key (desconhecida) soma no with_params — o provider vai rejeitar
    # com erro nomeado (tratable), não silenciosamente.
    assert_equal 'x', chat.with_params_args[:extra_key]
  end

  # ── GREEN: comportamento para provedores não-Gemini (intato) ─────────────────

  test 'openrouter: max_tokens é repassado intato (formato OpenAI, correto para OpenRouter)' do
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'openrouter/free').returns(chat)

    @openrouter_client.complete('foo', params: { max_tokens: 64 })

    assert_equal({ max_tokens: 64 }, chat.with_params_args,
                 'OpenRouter deve receber max_tokens no topo (formato OpenAI)')
  end

  test 'openrouter: temperatura também repassada intata' do
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'openrouter/free').returns(chat)

    @openrouter_client.complete('foo', params: { temperature: 0.7 })

    assert_equal({ temperature: 0.7 }, chat.with_params_args)
  end

  # ── Model_id detection baseada em string (não enum) ──────────────────────────

  test 'qualquer model_id contendo gemini usa normalização Gemini' do
    # Verifica que a detecção é por `include?('gemini')`, não por enum exato.
    chat = CaptureChat.new
    RubyLLM.stubs(:chat).with(model: 'gemini-3.1-flash-lite').returns(chat)

    client = Class.new(Llm::BaseClient) do
      def model_id = 'gemini-3.1-flash-lite'
      def daily_quota_key = 'x'
      def max_daily_requests = 999_999
    end.new

    client.complete('foo', params: { max_tokens: 128 })

    assert_equal({ generationConfig: { maxOutputTokens: 128 } }, chat.with_params_args)
  end
end
