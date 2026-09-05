# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/discord/skill_entrypoint"

class SkillModeFlowIntegrationTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    ChatSessionManager.instance_variable_set(:@sessions, {})
    ChatSessionManager.instance_variable_set(:@mutexes, {})
    ChatSessionManager.stubs(:all_tool_classes).returns([])
    @link = Llm::ModelChain::Link.new(label: "openrouter", provider: :openrouter, model: "openrouter/free")
    Llm::ModelChain.stubs(:links).returns([@link])
    Llm::ModelChain.stubs(:primary).returns(@link)
  end

  teardown do
    Thread.current[:cleitin_origin] = nil
    Thread.current[:cleitin_conversation_scope_key] = nil
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

  # 1. ideia vaga -> seletor escolhe grill -> oferta salva (ask-first), SEM thread
  test "ideia vaga: seletor escolhe grill e oferta é salva em vez de thread" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    user = stub(id: "101", display_name: "joao", username: "joao")
    event = mock("event")
    event.stubs(:user).returns(user)
    event.stubs(:channel).returns(stub(id: "202", thread?: false, start_thread: nil))
    event.stubs(:message).returns(stub(content: "tenho uma ideia vaga"))

    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    stub_chat("ok")

    result = Discord::SkillEntrypoint.evaluate(event, scope, "tenho uma ideia vaga")

    assert_equal "grill-me", result[:skill_name]
    assert_nil result[:thread_id], "R5a: thread NÃO criada no primeiro uso (ask-first)"
    refute_nil result[:response], "R5a: resposta de oferta retornada"
    assert_match(/criar.*thread|continuar/i, result[:response], "R5a: mensagem pede decisão do usuário")
  end

  # 2. fluxo ask-first: oferta primeiro, aceite depois cria thread + modo
  test "thread criada: fluxo ask-first com oferta e aceite posterior" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    user = stub(id: "101", display_name: "joao", username: "joao")
    event = mock("event")
    event.stubs(:user).returns(user)
    event.stubs(:channel).returns(stub(id: "202", thread?: false, start_thread: nil))
    event.stubs(:message).returns(stub(content: "tenho uma ideia"))

    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    stub_chat("primeira pergunta grill")

    # Primeiro turno: oferta salva (sem thread)
    result1 = Discord::SkillEntrypoint.evaluate(event, scope, "tenho uma ideia")
    assert_equal "grill-me", result1[:skill_name]
    assert_nil result1[:thread_id], "R5a: primeiro turno não cria thread"
    assert_not_nil result1[:response], "R5a: resposta de oferta presente"

    # Simula conversa com oferta pendente para o segundo turno
    conv = Conversation.open_for(scope: scope.key, channel_id: "202", user_id: "101")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current)
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Segundo turno: usuário aceita, thread é criada
    new_thread = stub(id: "303", thread?: true, parent_id: "202")
    event.channel.stubs(:start_thread).returns(new_thread)

    result2 = Discord::SkillEntrypoint.evaluate(event, scope, "sim, cria a thread")
    assert_equal "grill-me", result2[:skill_name]
    assert_equal "303", result2[:thread_id], "R5a: thread criada após aceite"
    assert_equal "303", result2[:scope].channel_id, "R5a: scope aponta para thread"

    # Verifica persistência da conversa
    # R11 Bug 2: conversa pai não deve ter active_skill_name após aceite com thread
    assert_nil conv.reload.active_skill_name, "R11: canal pai sem active_skill_name após aceite"
    assert_nil conv.reload.offered_skill_name, "R5a: oferta limpa após aceite"
  end

  # 3. prompt contém protocolo
  test "prompt contém o protocolo da skill" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    grill = Skills::Definition.new(
      name: "grill-me",
      description: "grill",
      system_prompt: "PROTOCOLO_GRILL_FRAGMENT",
      explicit_triggers: {},
      autonomous: {},
      tools: { allow: [], deny: ["*"] },
      context: { max_rehydrated_messages: 100, prompt_fragment_max_chars: 6000, compaction_instructions: "PRESERVA_GRILL" },
      cost: {},
      discord: {}
    )
    Skills::Registry.stubs(:fetch?).with(anything).returns(nil)
    Skills::Registry.stubs(:fetch?).with("grill-me").returns(grill)
    ChatSessionManager.stubs(:build_tool_policy).returns(stub("p", allowed_tools: []))
    stub_chat("ok")

    capturado = nil
    chat = stub_chat("ok")
    chat.stubs(:with_instructions).with do |instrucoes, **_kw|
      capturado = instrucoes
      true
    end.returns(chat)

    ChatSessionManager.ask(
      scope: scope,
      content: "ideia",
      user_id: "101",
      username: "joao",
      requested_skill: "grill-me"
    )

    refute_nil capturado
    assert_includes capturado, "PROTOCOLO_GRILL_FRAGMENT"
  end

  # 4. nenhuma tool é anexada (deny: ["*"])
  test "nenhuma tool é anexada quando deny: ['*']" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    grill = Skills::Definition.new(
      name: "grill-me",
      description: "grill",
      system_prompt: "PROTOCOLO",
      explicit_triggers: {},
      autonomous: {},
      tools: { allow: [], deny: ["*"] },
      context: {},
      cost: {},
      discord: {}
    )
    Skills::Registry.stubs(:fetch?).with(anything).returns(nil)
    Skills::Registry.stubs(:fetch?).with("grill-me").returns(grill)
    ChatSessionManager.stubs(:build_tool_policy).returns(stub("p", allowed_tools: []))
    
    chat = stub_chat("ok")
    chat.expects(:with_tool).never

    ChatSessionManager.ask(
      scope: scope,
      content: "ideia",
      user_id: "101",
      username: "joao",
      requested_skill: "grill-me"
    )
  end

  # 5. turno seguinte permanece no modo sem nova classificação
  test "turno seguinte permanece no modo sem nova classificação" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    grill = Skills::Definition.new(
      name: "grill-me",
      description: "grill",
      system_prompt: "PROTOCOLO",
      explicit_triggers: {},
      autonomous: {},
      tools: { allow: [], deny: ["*"] },
      context: {},
      cost: {},
      discord: {}
    )
    Skills::Registry.stubs(:fetch?).with(anything).returns(nil)
    Skills::Registry.stubs(:fetch?).with("grill-me").returns(grill)
    ChatSessionManager.stubs(:build_tool_policy).returns(stub("p", allowed_tools: []))
    stub_chat("ok")

    # Primeiro turno com skill
    ChatSessionManager.ask(
      scope: scope,
      content: "ideia",
      user_id: "101",
      username: "joao",
      requested_skill: "grill-me"
    )

    # Segundo turno SEM requested_skill (deveria manter o modo)
    AiRouter.expects(:complete).never
    
    ChatSessionManager.ask(
      scope: scope,
      content: "continua",
      user_id: "101",
      username: "joao"
    )

    conv = Conversation.active_for(scope.key)
    assert_equal "grill-me", conv.active_skill_name
  end

  # 6. evicção do cache não perde modo
  test "evicção do cache não perde modo" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    grill = Skills::Definition.new(
      name: "grill-me",
      description: "grill",
      system_prompt: "PROTOCOLO",
      explicit_triggers: {},
      autonomous: {},
      tools: { allow: [], deny: ["*"] },
      context: {},
      cost: {},
      discord: {}
    )
    Skills::Registry.stubs(:fetch?).with(anything).returns(nil)
    Skills::Registry.stubs(:fetch?).with("grill-me").returns(grill)
    ChatSessionManager.stubs(:build_tool_policy).returns(stub("p", allowed_tools: []))
    stub_chat("ok")

    # Turno inicial
    ChatSessionManager.ask(
      scope: scope,
      content: "ideia",
      user_id: "101",
      username: "joao",
      requested_skill: "grill-me"
    )

    # Evict cache
    ChatSessionManager.evict(scope.key)

    # Próximo turno deve reidratar com skill persistida
    ChatSessionManager.ask(
      scope: scope,
      content: "depois do evict",
      user_id: "101",
      username: "joao"
    )

    conv = Conversation.active_for(scope.key)
    assert_equal "grill-me", conv.active_skill_name
  end

  # 7. /new encerra o modo
  test "/new encerra o modo" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    grill = Skills::Definition.new(
      name: "grill-me",
      description: "grill",
      system_prompt: "PROTOCOLO",
      explicit_triggers: {},
      autonomous: {},
      tools: { allow: [], deny: ["*"] },
      context: {},
      cost: {},
      discord: {}
    )
    Skills::Registry.stubs(:fetch?).with(anything).returns(nil)
    Skills::Registry.stubs(:fetch?).with("grill-me").returns(grill)
    stub_chat("ok")

    # Ativa modo
    ChatSessionManager.ask(
      scope: scope,
      content: "ideia",
      user_id: "101",
      username: "joao",
      requested_skill: "grill-me"
    )

    # /new (reset)
    ChatSessionManager.reset!(scope)

    # Novo turno sem skill
    ChatSessionManager.ask(
      scope: scope,
      content: "nova conversa",
      user_id: "101",
      username: "joao"
    )

    conv = Conversation.active_for(scope.key)
    assert_nil conv.active_skill_name
  end

  # 8. segunda skill de fixture percorre mesmo fluxo
  test "segunda skill de fixture percorre o mesmo fluxo sem mudança no router" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    second = Skills::Definition.new(
      name: "second-skill",
      description: "second",
      system_prompt: "PROTOCOLO_SECOND",
      explicit_triggers: {},
      autonomous: {},
      tools: { allow: [], deny: ["*"] },
      context: {},
      cost: {},
      discord: {}
    )
    Skills::Registry.stubs(:fetch?).with(anything).returns(nil)
    Skills::Registry.stubs(:fetch?).with("second-skill").returns(second)
    ChatSessionManager.stubs(:build_tool_policy).returns(stub("p", allowed_tools: []))
    stub_chat("ok")

    # Usa segunda skill
    ChatSessionManager.ask(
      scope: scope,
      content: "test",
      user_id: "101",
      username: "joao",
      requested_skill: "second-skill"
    )

    conv = Conversation.active_for(scope.key)
    assert_equal "second-skill", conv.active_skill_name
  end

  # Parallel test: /grill pula classificador e chega ao mesmo estado final
  test "/grill pula classificador e chega ao mesmo estado final" do
    scope = Discord::SessionScope.for(user_id: "101", channel_id: "202")
    grill = Skills::Definition.new(
      name: "grill-me",
      description: "grill",
      system_prompt: "PROTOCOLO_GRILL",
      explicit_triggers: { slash: { name: "grill", description: "grill", input: {} } },
      autonomous: {},
      tools: { allow: [], deny: ["*"] },
      context: {},
      cost: {},
      discord: {}
    )
    Skills::Registry.stubs(:fetch?).with(anything).returns(nil)
    Skills::Registry.stubs(:fetch?).with("grill-me").returns(grill)
    ChatSessionManager.stubs(:build_tool_policy).returns(stub("p", allowed_tools: []))
    stub_chat("ok")

    # /grill deve pular classificador
    AiRouter.expects(:complete).never

    ChatSessionManager.ask(
      scope: scope,
      content: "/grill tema",
      user_id: "101",
      username: "joao",
      requested_skill: "grill-me"
    )

    conv = Conversation.active_for(scope.key)
    assert_equal "grill-me", conv.active_skill_name
  end
end
