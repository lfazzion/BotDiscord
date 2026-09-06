# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/discord/skill_entrypoint"
require_relative "../../app/services/discord/thread_event_proxy"

class DiscordBotServiceSkillEntrypointTest < ActiveSupport::TestCase
  setup do
    ChatSessionManager.stubs(:all_tool_classes).returns([])
  end

  def stub_chat(response_text = "resposta da IA")
    chat = mock("chat")
    chat.stubs(:with_thinking).returns(chat)
    chat.stubs(:with_params).returns(chat)
    chat.stubs(:with_tool).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:add_message).returns(chat)
    chat.stubs(:ask).returns(stub(content: response_text))
    RubyLLM.stubs(:chat).returns(chat)
    chat
  end

  def mock_event(channel_id: "456", parent_id: nil, thread: false, content: "oi", user_id: "123")
    user = stub(id: user_id, display_name: "joao", username: "joao", bot_account?: false)
    channel = stub(id: channel_id, private?: false, thread?: thread, parent_id: parent_id, start_typing: nil)
    message = stub(content: content, id: "msg_123")
    event = mock("event")
    event.stubs(:user).returns(user)
    event.stubs(:channel).returns(channel)
    event.stubs(:message).returns(message)
    event
  end

  test "handle_message com /grill ativa skill e passa requested_skill ao ChatSessionManager" do
    event = mock_event(content: "/grill tenho uma ideia")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    
    # Mock do ChatSessionManager para capturar o parâmetro requested_skill
    ChatSessionManager.expects(:ask)
      .with(
        has_entries(
          scope: scope,
          content: "/grill tenho uma ideia",
          user_id: "123",
          username: "joao",
          requested_skill: "grill-me"
        )
      )
      .returns("resposta do grill")
    
    event.expects(:respond).with("resposta do grill")
    
    DiscordBotService.handle_message(event)
  end

  test "handle_message com ideia vaga usa seletor autônomo" do
    event = mock_event(content: "tenho uma ideia vaga")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)

    # R5a: sem conversa previa, entrypoint cria conversa + oferta primeiro
    # (defeito c corrigido) — retorna resposta de oferta, não vai direto ao chat
    respond_args = []
    event.stubs(:respond).with do |arg|
      respond_args << arg
      true
    end

    DiscordBotService.handle_message(event)

    # Valida que oferta foi retornada (behavior change from R5a)
    assert_equal 1, respond_args.size, "deve chamar respond uma vez"
    response_text = respond_args.first.to_s
    assert_match(/criar.*thread|continuar/i, response_text,
                 "mensagem deve ser oferta de thread: #{response_text}")
  end

  test "handle_message sem skill mantém requested_skill nil" do
    event = mock_event(content: "oi bot")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    
    ChatSessionManager.expects(:ask)
      .with(
        has_entries(
          scope: scope,
          requested_skill: nil
        )
      )
      .returns("resposta normal")
    
    event.expects(:respond).with("resposta normal")
    
    DiscordBotService.handle_message(event)
  end

  test "falha de permissão na thread responde mensagem educada" do
    event = mock_event(content: "/grill")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    
    # Simula erro de permissão
    Discord::SkillEntrypoint.stubs(:evaluate).returns({
      skill_name: "grill-me",
      scope: scope,
      content: "/grill",
      response: "⚠️ Não consegui criar a thread. Tente novamente ou continue aqui."
    })
    
    event.expects(:respond).with("⚠️ Não consegui criar a thread. Tente novamente ou continue aqui.")
    ChatSessionManager.expects(:ask).never
    
    DiscordBotService.handle_message(event)
  end

  test "mensagem já em thread reutiliza o scope da thread" do
    event = mock_event(channel_id: "777", parent_id: "999", thread: true, content: "/grill")
    
    thread_scope = Discord::SessionScope.for(user_id: "123", channel_id: "777", open_channel_id: "999")
    
    Discord::SkillEntrypoint.stubs(:evaluate).returns({
      skill_name: "grill-me",
      scope: thread_scope,
      content: "/grill",
      thread_id: "777"
    })
    
    ChatSessionManager.expects(:ask)
      .with(has_entries(scope: thread_scope, requested_skill: "grill-me"))
      .returns("resposta na thread")
    
    event.expects(:respond).with("resposta na thread")
    
    DiscordBotService.handle_message(event)
  end

  # ===========================================================================
  # R7 Item 1: Prova fim a fim - ideia chega ao ask via bot
  # ===========================================================================

  test "R7-Item1: fluxo completo ideia -> oferta -> aceite -> ask recebe a ideia original" do
    # Cenario: usuario envia ideia vaga -> bot oferece thread -> usuario aceita ->
    # ChatSessionManager.ask recebe a IDEIA original, nao 'sim'
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    original_idea = "tenho uma ideia de app de entregas com drone"
    new_thread_id = "789"

    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    stub_chat("resposta")

    # Cria conversacao inicial (sem oferta)
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Simula primeiro evento: ideia vaga
    event1 = mock_event(channel_id: "456", content: original_idea)
    respond_args = []
    event1.stubs(:respond).with do |arg|
      respond_args << arg
      true
    end
    DiscordBotService.handle_message(event1)

    # Verifica que oferta foi enviada
    assert_equal 1, respond_args.size
    assert_match(/criar.*thread/i, respond_args.first.to_s)

    # Salva oferta na conversacao real
    conv.update!(offered_skill_name: "grill-me", offered_content: original_idea,
                 offered_at: Time.current)

    # Simula aceite: usuario diz "sim cria a thread"
    new_thread = stub(id: new_thread_id, thread?: true, parent_id: "456")
    new_thread.stubs(:send_message)
    event1.channel.stubs(:start_thread).returns(new_thread)
    # guild.channels precisa conter a thread recem-criada (o ThreadEventProxy
    # novo resolve a thread pelo guild e levanta erro nomeado se nao achar)
    event1.channel.stubs(:guild).returns(stub(id: "g1", channels: [new_thread]))

    ChatSessionManager.expects(:ask).with(
      has_entries(
        content: original_idea,  # A IDEIA original, nao "sim"
        user_id: "123",
        username: "joao",
        requested_skill: "grill-me"
      )
    ).returns("resposta do grill")

    event2 = mock_event(channel_id: "456", content: "sim, cria a thread")
    event2.stubs(:channel).returns(event1.channel)
    event2.stubs(:message).returns(stub(content: "sim, cria a thread", id: "msg_456"))
    event2.stubs(:guild).returns(stub(channels: []))
    event2.stubs(:respond)

    DiscordBotService.handle_message(event2)
  end
end
