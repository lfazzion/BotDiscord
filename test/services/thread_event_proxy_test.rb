# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/discord/thread_event_proxy"

class ThreadEventProxyTest < ActiveSupport::TestCase
  test "edit_response envia para a thread quando canal e encontrado" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")
    thread_channel = stub(id: "789", respond_to?: true)
    
    # A implementacao usa channel.guild.channels.find
    guild = stub(channels: [thread_channel])
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)
    
    # Espera que edit_response seja chamado no canal da thread
    thread_channel.expects(:edit_response).with(content: "resposta", ephemeral: false)
    
    proxy = Discord::ThreadEventProxy.new(original_event, "789")
    proxy.edit_response(content: "resposta")
  end

  test "edit_response nao faz fallback silencioso quando thread nao encontrada" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")
    
    # Nao encontra thread (canais vazios)
    guild = stub(channels: [])
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)
    
    # O original_event NAO deve receber edit_response
    original_event.expects(:edit_response).never
    
    proxy = Discord::ThreadEventProxy.new(original_event, "789")
    
    # Deve levantar StandardError, nao voltar silenciosamente para o original
    assert_raises(StandardError) do
      proxy.edit_response(content: "resposta")
    end
  end

  test "send_message envia para a thread quando canal e encontrado" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")
    thread_channel = stub(id: "789", respond_to?: true)
    
    guild = stub(channels: [thread_channel])
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)
    
    # Espera que send_message seja chamado no canal da thread
    thread_channel.expects(:send_message).with(content: "msg2", ephemeral: false)
    
    proxy = Discord::ThreadEventProxy.new(original_event, "789")
    proxy.send_message(content: "msg2")
  end
end
