require 'test_helper'

class AiRouterTest < ActiveSupport::TestCase
  test 'should route background context to GeminiClient' do
    client = AiRouter.send(:select_client, :background, 100)
    assert_instance_of Llm::GeminiClient, client
  end

  test 'should route interactive short prompt to GemmaClient' do
    client = AiRouter.send(:select_client, :interactive, 1000)
    assert_instance_of Llm::GemmaClient, client
  end

  test 'should route interactive long prompt to OpenrouterClient' do
    client = AiRouter.send(:select_client, :interactive, 9000)
    assert_instance_of Llm::OpenrouterClient, client
  end

  test 'should raise ArgumentError for unknown context' do
    assert_raises(ArgumentError) do
      AiRouter.send(:select_client, :unknown, 100)
    end
  end

  test 'extract_messages should handle string prompt' do
    system_msg, user_msg = AiRouter.send(:extract_messages, 'hello world')

    assert_nil system_msg
    assert_equal 'hello world', user_msg
  end

  test 'extract_messages should handle hash prompt' do
    prompt = { system: 'you are helpful', user: 'hello' }
    system_msg, user_msg = AiRouter.send(:extract_messages, prompt)

    assert_equal 'you are helpful', system_msg
    assert_equal 'hello', user_msg
  end

  test 'estimate_tokens should return 0 for nil' do
    assert_equal 0, AiRouter.send(:estimate_tokens, nil)
  end

  test 'estimate_tokens should estimate based on character count' do
    # 4 chars ≈ 1 token
    tokens = AiRouter.send(:estimate_tokens, 'a' * 400)
    assert_equal 100, tokens
  end

  test 'gemma_tpm_threshold should be 8000' do
    assert_equal 8000, AiRouter.gemma_tpm_threshold
  end

  test 'GeminiClient model_id should be gemini flash lite' do
    assert_equal 'google/gemini-3.1-flash-lite', Llm::GeminiClient::MODEL_ID
  end

  test 'GemmaClient model_id should be gemma 3 27b' do
    assert_equal 'google/gemma-3-27b', Llm::GemmaClient::MODEL_ID
  end

  test 'OpenrouterClient model_id should be claude 3.5 sonnet' do
    assert_equal 'anthropic/claude-3.5-sonnet', Llm::OpenrouterClient::MODEL_ID
  end

  test 'GeminiClient daily quota should be 480' do
    assert_equal 480, Llm::GeminiClient::MAX_DAILY
  end

  test 'GemmaClient daily quota should be 14000' do
    assert_equal 14_000, Llm::GemmaClient::MAX_DAILY
  end

  test 'BaseClient should raise QuotaExceededError when quota exceeded' do
    client = Llm::GeminiClient.new

    # Mock SolidCache to return quota reached
    SolidCache.expects(:read).with(regexp_matches(/gemini_daily/)).returns(480)

    assert_raises Llm::BaseClient::QuotaExceededError do
      client.send(:check_quota!)
    end
  end
end
