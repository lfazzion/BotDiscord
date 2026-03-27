# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/tools/tool_base'
require_relative '../../app/tools/social_profile_tools'
require_relative '../../app/tools/social_post_tools'
require_relative '../../app/tools/metrics_tools'
require_relative '../../app/tools/discovery_tools'
require_relative '../../app/tools/catalog_tools'
require_relative '../../app/tools/event_tools'
require_relative '../../app/tools/news_tools'
require_relative '../../app/services/chat_session_manager'
require_relative '../../app/services/discord_bot_service'

class DiscordBotServiceTest < ActiveSupport::TestCase
  test 'handle_message ignora content vazio' do
    event = mock('event')
    event.stubs(:user).returns(stub(id: 123))
    event.stubs(:channel).returns(stub(id: 456, private?: false))
    event.stubs(:message).returns(stub(content: '   '))

    event.expects(:respond).never
    DiscordBotService.handle_message(event)
  end

  test 'handle_message chama ChatSessionManager' do
    mock_chat = mock('chat')
    mock_response = stub(content: 'resposta do bot')
    mock_chat.stubs(:ask).returns(mock_response)

    ChatSessionManager.stubs(:get_or_create).returns(mock_chat)

    event = mock('event')
    event.stubs(:user).returns(stub(id: 123))
    event.stubs(:channel).returns(stub(id: 456, private?: false, start_typing: nil))
    event.stubs(:message).returns(stub(content: 'pergunta'))

    event.expects(:respond).with('resposta do bot')
    DiscordBotService.handle_message(event)
  end

  test 'handle_message trata RateLimitError com fallback' do
    mock_chat = mock('chat')
    mock_chat.stubs(:ask).raises(RubyLLM::RateLimitError, 'rate limit')

    mock_fallback_chat = mock('fallback_chat')
    mock_fallback_response = stub(content: 'resposta do fallback')
    mock_fallback_chat.stubs(:ask).returns(mock_fallback_response)

    ChatSessionManager.stubs(:get_or_create).returns(mock_chat)
    ChatSessionManager.stubs(:create_fallback_chat).returns(mock_fallback_chat)

    event = mock('event')
    event.stubs(:user).returns(stub(id: 123))
    event.stubs(:channel).returns(stub(id: 456, private?: false, start_typing: nil))
    event.stubs(:message).returns(stub(content: 'pergunta'))

    event.expects(:respond).with('resposta do fallback')
    DiscordBotService.handle_message(event)
  end

  test 'handle_message trata StandardError' do
    mock_chat = mock('chat')
    mock_chat.stubs(:ask).raises(StandardError, 'erro genérico')

    ChatSessionManager.stubs(:get_or_create).returns(mock_chat)

    event = mock('event')
    event.stubs(:user).returns(stub(id: 123))
    event.stubs(:channel).returns(stub(id: 456, private?: false, start_typing: nil))
    event.stubs(:message).returns(stub(content: 'pergunta'))

    event.expects(:respond).with('⚠️ Erro ao processar. Tente novamente.')
    DiscordBotService.handle_message(event)
  end
end
