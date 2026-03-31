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

class ChatSessionManagerTest < ActiveSupport::TestCase
  setup do
    ChatSessionManager.instance_variable_set(:@sessions, {})
  end

  test 'get_or_create cria sessão nova' do
    mock_chat = mock('chat')
    mock_chat.stubs(:with_tool).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    RubyLLM.stubs(:chat).returns(mock_chat)

    chat = ChatSessionManager.get_or_create('user1', 'channel1')
    assert_not_nil chat
  end

  test 'get_or_create retorna sessão existente' do
    mock_chat = mock('chat')
    mock_chat.stubs(:with_tool).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    RubyLLM.stubs(:chat).returns(mock_chat)

    chat1 = ChatSessionManager.get_or_create('user1', 'channel1')
    chat2 = ChatSessionManager.get_or_create('user1', 'channel1')
    assert_equal chat1, chat2
  end

  test 'cleanup_expired remove sessões expiradas' do
    sessions = ChatSessionManager.instance_variable_get(:@sessions)
    sessions['expired:session'] = { chat: mock('chat'), expires_at: 1.hour.ago }
    sessions['active:session'] = { chat: mock('chat'), expires_at: 30.minutes.from_now }

    ChatSessionManager.cleanup_expired
    sessions = ChatSessionManager.instance_variable_get(:@sessions)
    assert_nil sessions['expired:session']
    assert_not_nil sessions['active:session']
  end

  test 'session_key formata corretamente' do
    key = ChatSessionManager.session_key('user1', 'channel1')
    assert_equal 'user1:channel1', key
  end
end
