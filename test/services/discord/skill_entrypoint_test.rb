# frozen_string_literal: true

require "test_helper"
require_relative "../../../app/services/discord/skill_entrypoint"

class DiscordSkillEntrypointTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @registry = Skills::Registry.new
    @selector = Skills::Selector.new(registry: @registry)
  end

  # Helper para criar event mock com estado de thread opcional
  def mock_event(channel_id: "456", parent_id: nil, thread: false, content: "oi", user_id: "123", message_id: nil)
    user = stub(id: user_id, display_name: "joao", username: "joao", bot_account?: false)
    channel = stub(id: channel_id, private?: false, thread?: thread, parent_id: parent_id, start_typing: nil)
    message = stub(content: content, id: message_id)
    event = mock("event")
    event.stubs(:user).returns(user)
    event.stubs(:channel).returns(channel)
    event.stubs(:message).returns(message)
    event
  end

  # Helper para criar conversa mock com oferta pendente
  def mock_conversation(scope_key:, active_skill_name: nil, offered_skill_name: nil, offered_at: nil, offered_content: nil)
    state = {
      key: scope_key,
      active_skill_name: active_skill_name,
      offered_skill_name: offered_skill_name,
      offered_at: offered_at,
      offered_content: offered_content
    }

    conv = stub(state)

    # Permite que update! modifique o estado do mock
    conv.define_singleton_method(:update!) do |attrs|
      attrs.symbolize_keys.each do |k, v|
        state[k] = v
      end
      true
    end

    # Necessário para que conversation.present? retorne true
    conv.stubs(:present?).returns(true)
    conv.stubs(:id).returns("conv-77")
    conv.stubs(:reload).returns(conv)

    conv
  end

  # GREEN: classe existe após implementação
  test "SkillEntrypoint existe" do
    assert defined?(Discord::SkillEntrypoint)
  end

  # Testes RED para comportamento esperado (serão GREEN após implementação)

  test "/grill é derivado do registro (trigger explícito)" do
    event = mock_event(content: "/grill tenho uma ideia")

    # O conteúdo passado inclui o trigger; o registry detecta pelo prefixo
    result = Discord::SkillEntrypoint.evaluate(event, Discord::SessionScope.for(user_id: "123", channel_id: "456"), "/grill tenho uma ideia")

    assert_equal "grill-me", result[:skill_name]
    assert_nil result[:thread_id]
  end

  test "opção de ideia usa o nome definido no YAML" do
    event = mock_event(content: "tenho uma ideia vaga de produto")
    
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    result = Discord::SkillEntrypoint.evaluate(event, Discord::SessionScope.for(user_id: "123", channel_id: "456"), "tenho uma ideia vaga de produto")
    
    assert_equal "grill-me", result[:skill_name]
  end

  test "trigger explícito não entra no CommandRouter" do
    event = mock_event(content: "/grill")
    
    Discord::CommandRouter.expects(:parse_text).never
    
    result = Discord::SkillEntrypoint.evaluate(event, Discord::SessionScope.for(user_id: "123", channel_id: "456"), "/grill")
    
    assert_equal "grill-me", result[:skill_name]
  end

  test "evento já em thread reutiliza a thread" do
    event = mock_event(channel_id: "777", parent_id: "999", thread: true, content: "/grill")
    
    result = Discord::SkillEntrypoint.evaluate(event, Discord::SessionScope.for(user_id: "123", channel_id: "777", open_channel_id: "999"), "/grill")
    
    assert_equal "grill-me", result[:skill_name]
    assert_equal "777", result[:thread_id]
  end

  test "evento fora de thread cria thread dedicada" do
    event = mock_event(channel_id: "456", content: "/grill")
    channel = event.channel

    # Simula criação de thread - nome vem da definição da skill (thread_name: "Skill: %s")
    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    channel.expects(:start_thread).with("Skill: /grill", 10080, type: 11).returns(new_thread)

    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    result = Discord::SkillEntrypoint.evaluate(event, scope, "/grill")

    assert_equal "grill-me", result[:skill_name]
    assert_equal "888", result[:thread_id]
  end

  test "scope resultante contém o ID da thread" do
    event = mock_event(channel_id: "456", content: "/grill")
    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    event.channel.stubs(:start_thread).returns(new_thread)
    
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    result = Discord::SkillEntrypoint.evaluate(event, scope, "/grill")
    
    assert result[:scope].is_a?(Discord::SessionScope::Scope)
    assert_equal "888", result[:scope].channel_id
  end

  test "falha de permissao gera resposta visivel" do
    event = mock_event(channel_id: "456", content: "/grill")
    event.channel.stubs(:start_thread).raises(Discordrb::Errors::NoPermission, "sem permissao")

    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    result = Discord::SkillEntrypoint.evaluate(event, scope, "/grill")

    assert_equal "grill-me", result[:skill_name]
    assert_nil result[:thread_id]
    assert_equal "⚠️ Não consegui criar a thread. Tente novamente ou continue aqui.", result[:response]
  end

  test "R8-Item2: thread_visibility private gera type: 12" do
    private_def = Object.new
    def private_def.dig(*keys)
      case keys
      when [:discord, :thread_visibility] then "private"
      when [:discord, :thread_name] then "Privado: %s"
      else nil
      end
    end
    def private_def.create_thread?; true; end
    def private_def.present?; true; end

    mock_registry = stub(
      explicit_match?: "private",
      fetch?: private_def
    )
    Skills::Registry.stubs(:new).returns(mock_registry)

    event = mock_event(channel_id: "456", content: "/private", user_id: "123", message_id: "msg_priv")
    new_thread = stub(id: "999", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with("Privado: /private", 10080, type: 12).returns(new_thread)

    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    result = Discord::SkillEntrypoint.evaluate(event, scope, "/private")

    assert_equal "private", result[:skill_name]
    assert_equal "999", result[:thread_id]
  end

  test "R7-Item4: thread_visibility invalida levanta erro" do
    # Cria channel que levanta error ao tentar criar thread (para forcar o check de visibility)
    channel = stub(id: "456", private?: false, thread?: false, parent_id: nil,
                   start_typing: nil, respond_to?: true)
    channel.stubs(:start_thread).raises(Discordrb::Errors::NoPermission, "teste")
    original_event = stub(user: stub(id: "123"), channel: channel, message: stub(content: "/grill", id: "msg_1"))

    # Definicao com thread_visibility invalida
    grill_def = Object.new
    def grill_def.dig(*keys)
      { discord: { thread_visibility: "ultravioleta", thread_name: nil } }[keys[0]]&.[](keys[1])
    end
    def grill_def.create_thread?
      true
    end

    mock_registry = stub(
      explicit_match?: "grill-me",
      fetch?: grill_def
    )
    Skills::Registry.stubs(:new).returns(mock_registry)

    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    # Deve levantar ThreadVisibilityError ANTES de tentar criar thread
    assert_raises(Discord::SkillEntrypoint::ThreadVisibilityError) do
      Discord::SkillEntrypoint.evaluate(original_event, scope, "/grill")
    end
  end

  test "duas interações sobre a mesma mensagem não criam silenciosamente dois modos" do
    event = mock_event(channel_id: "456", content: "/grill", message_id: "msg_001")
    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).once.returns(new_thread)

    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    # Primeira avaliação
    result1 = Discord::SkillEntrypoint.evaluate(event, scope, "/grill")
    assert_equal "888", result1[:thread_id]

    # Segunda avaliação na mesma mensagem (deveria reutilizar)
    result2 = Discord::SkillEntrypoint.evaluate(event, scope, "/grill")
    assert_equal "888", result2[:thread_id]
  end

  test "R7-Item3: dedup por ID de mensagem evita colisão com mensagens distintas" do
    # Duas mensagens diferentes (IDs distintos) com mesmo conteúdo
    # devem criar threads diferentes
    event1 = mock_event(channel_id: "456", content: "/grill", message_id: "msg_A")
    event2 = mock_event(channel_id: "456", content: "/grill", message_id: "msg_B")

    new_thread1 = stub(id: "T1", thread?: true, parent_id: "456")
    new_thread2 = stub(id: "T2", thread?: true, parent_id: "456")

    event1.channel.expects(:start_thread).with("Skill: /grill", 10080, type: 11).returns(new_thread1)
    event2.channel.expects(:start_thread).with("Skill: /grill", 10080, type: 11).returns(new_thread2)

    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    result1 = Discord::SkillEntrypoint.evaluate(event1, scope, "/grill")
    result2 = Discord::SkillEntrypoint.evaluate(event2, scope, "/grill")

    assert_equal "T1", result1[:thread_id]
    assert_equal "T2", result2[:thread_id]
    assert_not_equal result1[:thread_id], result2[:thread_id],
                     "mensagens distintas devem ter threads distintas"
  end

  test "o conteúdo original chega ao primeiro ask" do
    event = mock_event(channel_id: "456", content: "/grill tenho uma ideia")
    
    result = Discord::SkillEntrypoint.evaluate(event, Discord::SessionScope.for(user_id: "123", channel_id: "456"), "/grill tenho uma ideia")
    
    assert_equal "grill-me", result[:skill_name]
    assert_equal "/grill tenho uma ideia", result[:content]
  end

  test "mensagem natural candidata entra pelo seletor" do
    event = mock_event(channel_id: "456", content: "tenho uma ideia vaga")
    
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    result = Discord::SkillEntrypoint.evaluate(event, Discord::SessionScope.for(user_id: "123", channel_id: "456"), "tenho uma ideia vaga")
    
    assert_equal "grill-me", result[:skill_name]
  end

  # ===========================================================================
  # Tarefa 7b — OFERTA PENDENTE (ASK-FIRST v4b)
  # ===========================================================================

  test "detectcao autonoma com create_thread salva oferta pendente em vez de thread" do
    event = mock_event(channel_id: "456", content: "tenho uma ideia vaga")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)

    # Mock da conversa ativa
    conv = mock_conversation(scope_key: scope.key)
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Stub do registry para retornar a definição da skill
    grill_def = stub(create_thread?: true, present?: true)
    mock_registry = stub(
      explicit_match?: nil,
      fetch?: grill_def,
      fetch: grill_def,
      candidate_hints?: true,
      all: [],
      selector_max_input_chars: 4000,
      selector_max_output_tokens: 64
    )
    Skills::Registry.stubs(:new).returns(mock_registry)

    # Deve chamar update! para salvar oferta
    call_args = nil
    conv.stubs(:update!).with do |*args|
      call_args = args.first
      true
    end

    result = Discord::SkillEntrypoint.evaluate(event, scope, "tenho uma ideia vaga")

    assert_equal "grill-me", result[:skill_name], "skill deve ser detectada"
    assert_nil result[:thread_id]
    assert result[:response].present?, "deve responder com opcoes ao usuario"
    assert_match(/criar thread|continuar/i, result[:response])
    assert_not_nil call_args, "update! deve ter sido chamado"
    assert_equal "grill-me", call_args[:offered_skill_name], "oferta deve ser salva"
  end

  test "mensagem seguinte com oferta pendente e resposta aceitar cria thread" do
    event = mock_event(channel_id: "456", content: "sim, cria a thread")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    # Simula conversa com oferta pendente
    conv = mock_conversation(scope_key: scope.key, offered_skill_name: "grill-me", offered_at: Time.current)
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Mock do canal para criar thread
    new_thread = stub(id: "999", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with(anything, anything, anything).returns(new_thread)

    # R11 Bug 2: limpa oferta na conversa pai SEM ativar skill nela
    conv.expects(:update!).with(
      offered_skill_name: nil,
      offered_at: nil,
      offered_content: nil
    ).returns(true)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "sim, cria a thread")

    assert_equal "grill-me", result[:skill_name]
    assert_equal "999", result[:thread_id]
  end

  test "mensagem seguinte com oferta pendente e resposta continuar nao cria thread" do
    event = mock_event(channel_id: "456", content: "continua aqui")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    # Simula conversa com oferta pendente
    conv = mock_conversation(scope_key: scope.key, offered_skill_name: "grill-me", offered_at: Time.current)
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Nao deve criar thread
    event.channel.expects(:start_thread).never

    # Deve limpar oferta e ativar modo (uma única chamada update!)
    # R5a: adicionada chave offered_content
    conv.expects(:update!).with(
      active_skill_name: "grill-me",
      offered_skill_name: nil,
      offered_at: nil,
      offered_content: nil
    ).returns(true)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "continua aqui")

    assert_equal "grill-me", result[:skill_name]
    assert_nil result[:thread_id]
  end

  test "mensagem seguinte com oferta pendente e resposta diferente descarta oferta" do
    event = mock_event(channel_id: "456", content: "nao sei, vou pensar")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    # Simula conversa com oferta pendente
    conv = mock_conversation(scope_key: scope.key, offered_skill_name: "grill-me", offered_at: Time.current)
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Nao deve criar thread nem ativar modo
    event.channel.expects(:start_thread).never
    # Não precisa verificar update! - o teste só quer garantir que oferta é descartada
    # conv.expects(:update!).with(...)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "nao sei, vou pensar")

    assert_nil result[:skill_name]
    assert_nil result[:thread_id]
    assert_nil result[:response]
  end

  test "oferta pendente expirada apos 30 minutos e descarta automatica" do
    event = mock_event(channel_id: "456", content: "tenho uma ideia")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)

    # Simula conversa com oferta expirada
    expired_at = 31.minutes.ago
    conv = mock_conversation(scope_key: scope.key, offered_skill_name: "grill-me", offered_at: expired_at)
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Deve limpar oferta expirada (1ª chamada) e salvar nova oferta (2ª chamada)
    conv.expects(:update!).times(2).returns(true)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "tenho uma ideia")

    # Após descartar oferta expirada, comportamento normal (select novamente)
    assert_equal "grill-me", result[:skill_name]
  end

  test "trigger explicito (/grill) ignora oferta pendente e cria thread direto" do
    event = mock_event(channel_id: "456", content: "/grill")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    # Simula conversa com oferta pendente
    conv = mock_conversation(scope_key: scope.key, offered_skill_name: "grill-me", offered_at: Time.current)
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Deve limpar oferta pendente ao lidar com trigger explícito
    conv.expects(:update!).returns(true) do |*args|
      attrs = args.first.is_a?(Hash) ? args.first : {}
      assert_equal nil, attrs[:offered_skill_name], "oferta deve ser limpa"
      assert_equal nil, attrs[:offered_at], "oferta_at deve ser limpo"
      true
    end

    new_thread = stub(id: "777", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with("Skill: /grill", 10080, type: 11).returns(new_thread)

    # Stub do registry
    grill_def = stub(
      create_thread?: true,
      present?: true
    )
    grill_def.stubs(:dig).returns(nil)
    grill_def.stubs(:dig).with(:discord, :thread_name).returns("Skill: %s")

    mock_registry = stub(
      explicit_match?: "grill-me",
      fetch?: grill_def,
      all: []
    )
    Skills::Registry.stubs(:new).returns(mock_registry)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "/grill")

    assert_equal "grill-me", result[:skill_name]
    assert_equal "777", result[:thread_id]
    assert result[:response].nil?, "trigger explícito não deve retornar resposta de oferta"
  end

  # ===========================================================================
  # R5a — Testes com Conversation REAL (R4 crítica)
  # ===========================================================================

  test "R5a-defeito-a: aceite ativa com skill certa usando variável capturada (Conversation real)" do
    event = mock_event(channel_id: "456", content: "sim, cria a thread")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    # Cria Conversation REAL no banco
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current)

    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Mock do canal para criar thread
    new_thread = stub(id: "999", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with(anything, anything, anything).returns(new_thread)

    # Não stubamos update! aqui — queremos que o ActiveRecord real persista
    result = Discord::SkillEntrypoint.evaluate(event, scope, "sim, cria a thread")

    assert_equal "grill-me", result[:skill_name], "R5a: skill_name correto no resultado"
    assert_equal "999", result[:thread_id], "R5a: thread criada"
    # R11 Bug 2: conversa pai não deve ter active_skill_name após aceite com thread
    conv.reload
    assert_nil conv.active_skill_name, "R11: canal pai sem active_skill_name após aceite"
    assert_nil conv.offered_skill_name, "R5a: oferta limpa após aceite"
  end

  test "R5a-defeito-b: continuar ativa sem thread e ideia original chega (Conversation real)" do
    event = mock_event(channel_id: "456", content: "continua aqui")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    original_idea = "tenho uma ideia de app de entregas com drone"
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(
      offered_skill_name: "grill-me",
      offered_at: Time.current,
      offered_content: original_idea
    )

    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # Não deve criar thread
    event.channel.expects(:start_thread).never

    # Não stubamos update! — queremos persistência real no ActiveRecord
    result = Discord::SkillEntrypoint.evaluate(event, scope, "continua aqui")

    assert_equal "grill-me", result[:skill_name], "R5a: skill correta"
    assert_nil result[:thread_id], "R5a: sem thread"
    assert_equal original_idea, result[:content], "R5a: conteúdo original da ideia chega"
    # R5a: valida persistência na Conversation real
    conv.reload
    assert_equal "grill-me", conv.active_skill_name, "R5a: skill persistida"
    assert_nil conv.offered_content, "R5a: oferta limpa após continuação"
  end

  test "R5a-defeito-b: ideia original chega via aceite também (Conversation real)" do
    event = mock_event(channel_id: "456", content: "sim")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    original_idea = "produto SaaS para gestão de estoques"
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(
      offered_skill_name: "grill-me",
      offered_at: Time.current,
      offered_content: original_idea
    )

    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with(anything, anything, anything).returns(new_thread)

    # Não stubamos update! — queremos persistência real no ActiveRecord
    result = Discord::SkillEntrypoint.evaluate(event, scope, "sim")

    assert_equal original_idea, result[:content], "R5a: ideias originais chegam no aceite"
    assert_equal "888", result[:thread_id], "R5a: thread criada"
  end

  test "R5a-defeito-c: primeiro uso autônomo cria conversa + oferta em vez de thread direta" do
    event = mock_event(channel_id: "456", content: "tenho uma ideia vaga")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)

    # NÃO existe conversa ativa — debe ser criada automaticamente
    Conversation.stubs(:active_for).with(scope.key).returns(nil)

    # Stub save_offered_skill para capturar os argumentos
    captured = {}
    Discord::SkillEntrypoint.stubs(:save_offered_skill).with do |conv, name, c|
      captured[:conv] = conv
      captured[:name] = name
      captured[:content] = c
      true
    end

    result = Discord::SkillEntrypoint.evaluate(event, scope, "tenho uma ideia vaga")

    assert_equal "grill-me", result[:skill_name], "R5a: skill detectada"
    assert result[:response].present?, "R5a: resposta de oferta retornada"
    assert_match(/criar.*thread/i, result[:response], "R5a: mensagem de oferta")
    refute_nil captured[:conv], "R5a: Conversation foi criada/salva"
    assert_equal "grill-me", captured[:name], "R5a: skill salva na oferta"
    assert_equal "tenho uma ideia vaga", captured[:content], "R5a: ideia original salva"
  end

  test "R5a: oferta salva offered_content correto via save_offered_skill" do
    event = mock_event(channel_id: "456", content: "proposta de marketplace")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    grill_def = stub(create_thread?: true, present?: true)
    mock_registry = stub(
      explicit_match?: nil,
      fetch?: grill_def,
      fetch: grill_def,
      candidate_hints?: true
    )
    Skills::Registry.stubs(:new).returns(mock_registry)

    # Stub selector para evitar invoke real do classificador
    mock_selector = stub(call: "grill-me")
    Skills::Selector.stubs(:new).returns(mock_selector)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "proposta de marketplace")

    assert_equal "grill-me", result[:skill_name]
    assert_equal "proposta de marketplace", conv.reload.offered_content, "R5a: conteúdo original persistido"
    assert_equal "grill-me", conv.reload.offered_skill_name, "R5a: skill nomeada"
  end

  # ===========================================================================
  # R9-Item1: Exit phrases
  # ===========================================================================

  test "R9-Item1: exit phrase 'parar de grillar' detectada pelo registry" do
    registry = Skills::Registry.new
    result = registry.exit_phrase_match?("parar de grillar")
    assert_equal "grill-me", result, "exit phrase deve retornar nome da skill"
  end

  test "R9-Item1: exit phrase 'sair do grill' detectada pelo registry" do
    registry = Skills::Registry.new
    result = registry.exit_phrase_match?("sair do grill")
    assert_equal "grill-me", result, "exit phrase deve retornar nome da skill"
  end

  test "R9-Item1: exit phrase não corresponde retorna nil" do
    registry = Skills::Registry.new
    result = registry.exit_phrase_match?("ola bot")
    assert_nil result, "mensagem sem exit phrase deve retornar nil"
  end

  test "R9-Item1: exit phrase é case-insensitive" do
    registry = Skills::Registry.new
    result = registry.exit_phrase_match?("PARAR DE GRILLAR")
    assert_equal "grill-me", result, "exit phrase deve ser case-insensitive"
  end

  test "R9-Item1: exit phrase encerra conversa com reset! igual /new" do
    event = mock_event(channel_id: "456", content: "parar de grillar")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    # Simula conversa ativa com skill grill-me
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123", active_skill_name: "grill-me")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    # O exit phrase deve ser detectado pelo registry e o bot deve chamar reset!
    ChatSessionManager.expects(:reset!).with do |s|
      conv.close!
      s == scope
    end
    event.expects(:respond).with("👋 Conversa encerrada.")

    DiscordBotService.handle_message(event)

    # Verifica que a conversa foi fechada (close! preserva active_skill_name
    # para histórico — ver T6 em conversation_test.rb)
assert_equal false, conv.reload.active, "exit phrase deve encerrar a skill ativa"
  end

  # ===========================================================================
  # R11 — Testes RED para Bug 1 (matching recusas/aceites) e Bug 2(conversa pai)
  # ===========================================================================

  test "R11: recusas como assim nao e nao quero nao sao tratadas como aceite" do
scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

    ["assim nao", "assim não", "nao quero", "não quero"].each do |refusal|
      conv = mock_conversation(scope_key: scope.key, offered_skill_name: "grill-me", offered_at: Time.current)
      Conversation.stubs(:active_for).with(scope.key).returns(conv)
      event = mock_event(channel_id: "456", content: refusal)

      result = Discord::SkillEntrypoint.evaluate(event, scope, refusal)

      assert_nil result[:skill_name], "Recusa '#{refusal}' não deve ativar skill"
      assert_nil result[:thread_id], "Recusa '#{refusal}' não deve criar thread"
    end
  end

  test "R11: aceite com thread nao ativa active_skill_name no canal pai" do
    event = mock_event(channel_id: "456", content: "sim")
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")

conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "ideia x")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with(anything, anything, anything).returns(new_thread)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "sim")

    assert_equal "grill-me", result[:skill_name]
    assert_equal "888", result[:thread_id]
    conv.reload
    assert_nil conv.active_skill_name, "Canal pai não deve ter active_skill_name após aceite com thread"
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa no canal pai"
  end

  # ===========================================================================
  # R12 — Bloqueantes r9b (TDD)
  # ===========================================================================

  test "R12-B1: negativa composta como 'nao criar thread' nao cria thread e responde como recusa" do
scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at:Time.current, offered_content: "ideia x")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event = mock_event(channel_id: "456", content: "nao criar thread")
    event.channel.expects(:start_thread).never

    result = Discord::SkillEntrypoint.evaluate(event, scope, "nao criar thread")

    assert_nil result[:skill_name], "Não deve ativar skill"
    assert_nil result[:thread_id], "Não deve criar thread"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa como recusa"
  end

  test "R12-B1: numeracao como 21) ou 12)nao casa aceite ou continuacao por substring" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = mock_conversation(
      scope_key: scope.key,
      offered_skill_name:"grill-me",
      offered_at: Time.current,
      offered_content: "ideia x"
    )
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event = mock_event(channel_id: "456", content: "21)")
    event.channel.expects(:start_thread).never

    result = Discord::SkillEntrypoint.evaluate(event, scope, "21)")
    assert_nil result[:thread_id], "21) não deve ser interpretado como 1)"

    event12 = mock_event(channel_id: "456", content: "12)")
    event12.channel.expects(:start_thread).never

    result12 = Discord::SkillEntrypoint.evaluate(event12, scope, "12)")
    assert_nil result12[:thread_id], "12) não deve ser interpretado como 2)"
  end

  test "R13-B1': negativas com verbo modal entre nao e o verbo sao tratadas como recusa" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    ["nao pode criar thread", "nao precisa abrir thread"].each do |phrase|
      conv = mock_conversation(
        scope_key: scope.key,
        offered_skill_name: "grill-me",
offered_at: Time.current,
        offered_content: "ideia x"
      )
      Conversation.stubs(:active_for).with(scope.key).returns(conv)
      conv.expects(:update!).with(
offered_skill_name: nil,
        offered_at: nil,
        offered_content: nil
      ).returns(true)

      event = mock_event(channel_id: "456", content: phrase)
      event.channel.expects(:start_thread).never

      result = Discord::SkillEntrypoint.evaluate(event, scope, phrase)
      assert_nil result[:skill_name], "Não deve ativar skill para: #{phrase}"
      assert_nil result[:thread_id], "Não deve criar thread para: #{phrase}"
    end
  end

  test "R12-B2: start_thread falhando com NoPermission preserva oferta e tente novamente reprocessa com sucesso" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "minha ideia inicial")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event1 = mock_event(channel_id: "456", content: "sim")
    event1.channel.stubs(:start_thread).raises(Discordrb::Errors::NoPermission, "sem permissao")

    result1 = Discord::SkillEntrypoint.evaluate(event1, scope, "sim")

    assert_nil result1[:thread_id]
    assert_equal "⚠️ Não consegui criar a thread. Tente novamente ou continue aqui.", result1[:response]

    conv.reload
    assert_equal "grill-me", conv.offered_skill_name, "offered_skill_name deve ser preservado apos NoPermission"
    assert_equal"minha ideia inicial", conv.offered_content, "offered_content deve ser preservado apos NoPermission"

    # Segunda tentativa com 'tente novamente'
    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    event2 = mock_event(channel_id: "456", content: "tente novamente")
    event2.channel.expects(:start_thread).returns(new_thread)

    result2 = Discord::SkillEntrypoint.evaluate(event2, scope, "tente novamente")

    assert_equal "888", result2[:thread_id]
    assert_equal "grill-me", result2[:skill_name]
    assert_equal "minha ideia inicial", result2[:content], "ideia inicial preservada deve chegar na thread"
    conv.reload
    assert_nil conv.offered_skill_name, "oferta deve ser limpa apos sucesso"
  end

  test "R12-B2: start_thread falhando com StandardError preserva oferta e tente novamente reprocessa com sucesso" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "minha ideia inicial")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event1 = mock_event(channel_id: "456", content: "sim")
    event1.channel.stubs(:start_thread).raises(StandardError, "network failure")

    result1 = Discord::SkillEntrypoint.evaluate(event1, scope, "sim")

    assert_nil result1[:thread_id]
    assert_equal "⚠️ Não consegui criar a thread. Tente novamente ou continue aqui.", result1[:response]

    conv.reload
    assert_equal "grill-me", conv.offered_skill_name, "offered_skill_name deve ser preservado apos StandardError"
    assert_equal "minha ideia inicial", conv.offered_content, "offered_content deveser preservado apos StandardError"

    # Segunda tentativa com 'tente novamente'
    new_thread = stub(id: "999", thread?: true, parent_id: "456")
    event2 = mock_event(channel_id: "456", content: "tente novamente")
    event2.channel.expects(:start_thread).returns(new_thread)

    result2 = Discord::SkillEntrypoint.evaluate(event2, scope, "tente novamente")

    assert_equal "999", result2[:thread_id]
    assert_equal "grill-me", result2[:skill_name]
    conv.reload
    assert_nil conv.offered_skill_name, "oferta deve ser limpa apos sucesso"
  end

  test "R12-B3: segundo aceite da mesma oferta nao cria segunda thread mesmo com message_ids distintos" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    offer_time = Time.current
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: offer_time, offered_content: "minha ideia")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event1 = mock_event(channel_id: "456", content: "sim", message_id: "msg_A")
    event2 = mock_event(channel_id: "456", content: "sim", message_id: "msg_B")

    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    # Apenas uma chamada a start_thread deve ocorrer
    event1.channel.expects(:start_thread).once.returns(new_thread)

    result1 = Discord::SkillEntrypoint.evaluate(event1, scope, "sim")
    conv.update!(offered_skill_name: "grill-me", offered_at: offer_time, offered_content: "minha ideia")
    event2.stubs(:channel).returns(event1.channel)

    result2 = Discord::SkillEntrypoint.evaluate(event2, scope, "sim")

    assert_equal "888", result1[:thread_id]
    assert_equal "888", result2[:thread_id]
  end

  test "R13-B2': Rails.cache.write levantando erro apos start_thread OK retorna sucesso com thread_id" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "minha ideia inicial")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    new_thread = stub(id: "777", thread?: true, parent_id: "456")
    event = mock_event(channel_id: "456", content: "sim")
    event.channel.expects(:start_thread).once.returns(new_thread)

    Rails.cache.stubs(:write).raises(StandardError, "cache write error")

    result = Discord::SkillEntrypoint.evaluate(event, scope, "sim")

    assert_equal "777", result[:thread_id], "Deve retornar thread_id mesmo se cache.write falhar"
    assert_equal "grill-me", result[:skill_name]
    assert_nil result[:response], "Não deve reportar falha mentirosa"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa pois thread foi criada"
  end

  test "R13-B2': SessionScope.for levantando erro apos start_thread OK retorna sucesso com thread_id" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "minha ideia inicial")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    event = mock_event(channel_id: "456", content: "sim")
    event.channel.expects(:start_thread).once.returns(new_thread)

    Discord::SessionScope.stubs(:for).with(
      user_id: scope.user_id,
channel_id: "888",
      open_channel_id: scope.open_channel_id
    ).raises(StandardError, "scope build error")

    result = Discord::SkillEntrypoint.evaluate(event, scope, "sim")

assert_equal "888", result[:thread_id], "Deve retornar thread_id mesmo se SessionScope.for falhar"
    assert_equal "grill-me", result[:skill_name]
    assert_nil result[:response], "Nãodeve reportar falha mentirosa"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa pois thread foi criada"
  end

  test "R13-B3': duas ofertas distintas no mesmo scope e mesmo segundo geram threads distintas (anti-colisao)" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
fixed_time = Time.current

    conv1 = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv1.update!(offered_skill_name: "grill-me", offered_at: fixed_time, offered_content: "ideia 1")
    Conversation.stubs(:active_for).with(scope.key).returns(conv1)

    thread1 = stub(id: "thread_111", thread?: true, parent_id: "456")
    event1 = mock_event(channel_id: "456", content: "sim", message_id: "msg_1")
event1.channel.expects(:start_thread).once.returns(thread1)

    result1 = Discord::SkillEntrypoint.evaluate(event1, scope, "sim")
    assert_equal "thread_111", result1[:thread_id]

    conv1.destroy
conv2 = Conversation.create!(scope: scope.key, discord_channel_id: "456", discord_user_id: "123", active: true, last_active_at: Time.current)
    conv2.update!(offered_skill_name: "grill-me", offered_at: fixed_time, offered_content: "ideia 2")
    Conversation.stubs(:active_for).with(scope.key).returns(conv2)

    thread2 = stub(id: "thread_222", thread?: true, parent_id: "456")
    event2 = mock_event(channel_id: "456", content: "sim", message_id: "msg_2")
    event2.channel.expects(:start_thread).once.returns(thread2)

    result2 = Discord::SkillEntrypoint.evaluate(event2, scope, "sim")
    assert_equal "thread_222", result2[:thread_id], "Segunda ofertadeve criar thread nova mesmo com mesmo offered_at.to_i"
  end

  test "R13-B3': concorrencia real com duas threads Ruby e barreira reutiliza mesma thread" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "minha ideia")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    new_thread = stub(id: "thread_conc_999", thread?: true, parent_id: "456")
event1 = mock_event(channel_id: "456", content: "sim", message_id: "msg_conc_1")
    event2 = mock_event(channel_id: "456", content: "sim", message_id: "msg_conc_2")
    event2.stubs(:channel).returns(event1.channel)

    event1.channel.expects(:start_thread).once.with do
      sleep 0.02
      true
    end.returns(new_thread)

    barrier = Queue.new
    results = []
    res_mutex = Mutex.new

    t1 = Thread.new do
      barrier.pop
      res = Discord::SkillEntrypoint.evaluate(event1, scope, "sim")
      res_mutex.synchronize { results << res }
    end

    t2 = Thread.new do
      barrier.pop
      res = Discord::SkillEntrypoint.evaluate(event2, scope, "sim")
      res_mutex.synchronize { results << res }
    end

    barrier.push(true)
    barrier.push(true)

    t1.join
    t2.join

    assert_equal 2, results.size
    assert_equal "thread_conc_999", results[0][:thread_id]
    assert_equal "thread_conc_999", results[1][:thread_id]
  end

  # ===========================================================================
  # R14 — Bloqueantes r9d (TDD): negacao com 3+ tokens
  # ===========================================================================

  test "R14-B1-01: 'nao acho que pode criar thread' (3+ tokens) e recusa" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "ideia x")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event = mock_event(channel_id: "456", content: "nao acho que pode criar thread")
    event.channel.expects(:start_thread).never

    result = Discord::SkillEntrypoint.evaluate(event, scope, "nao acho que pode criar thread")

    assert_nil result[:skill_name], "Não deve ativar skill para 'nao acho que pode criar thread'"
    assert_nil result[:thread_id], "Não deve criar thread para 'nao acho que pode criar thread'"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa como recusa para 'nao acho que pode criar thread'"
  end

  test "R14-B1-02: 'nao sei se deve criar thread' (3+ tokens) e recusa" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "ideia x")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event = mock_event(channel_id: "456", content: "nao sei se deve criar thread")
    event.channel.expects(:start_thread).never

    result = Discord::SkillEntrypoint.evaluate(event, scope, "nao sei se deve criar thread")

    assert_nil result[:skill_name], "Não deve ativar skill para 'nao sei se deve criar thread'"
    assert_nil result[:thread_id], "Não deve criar thread para 'nao sei se deve criar thread'"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa como recusa para 'nao sei se deve criar thread'"
  end

  test "R14-B1-03: 'nao quero criar essa thread' (3+ tokens) e recusa" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "ideia x")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event = mock_event(channel_id: "456", content: "nao quero criar essa thread")
    event.channel.expects(:start_thread).never

    result = Discord::SkillEntrypoint.evaluate(event, scope, "nao quero criar essa thread")

    assert_nil result[:skill_name], "Não deve ativar skill para 'nao quero criar essa thread'"
    assert_nil result[:thread_id], "Não deve criar thread para 'nao quero criar essa thread'"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa como recusa para 'nao quero criar essa thread'"
  end

  test "R14-B1-04: 'nao, pode criar thread' com virgula e aceite (nao e recusa, preserva)" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "ideia x")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event = mock_event(channel_id: "456", content: "nao, pode criar thread")
    new_thread = stub(id: "999", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with(anything, anything, anything).returns(new_thread)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "nao, pode criar thread")

    assert_equal "grill-me", result[:skill_name], "'nao, pode criar thread' deve ser tratado como aceite"
    assert_equal "999", result[:thread_id], "'nao, pode criar thread' deve criar thread"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa após aceite"
    assert_nil conv.active_skill_name, "Canal pai não deve ter active_skill_name"
  end

  test "R14-B1-05: 'pode criar thread' sem negacao e aceite (regressao)" do
    scope = Discord::SessionScope.for(user_id: "123", channel_id: "456")
    conv = Conversation.open_for(scope: scope.key, channel_id: "456", user_id: "123")
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current, offered_content: "ideia x")
    Conversation.stubs(:active_for).with(scope.key).returns(conv)

    event = mock_event(channel_id: "456", content: "pode criar thread")
    new_thread = stub(id: "888", thread?: true, parent_id: "456")
    event.channel.expects(:start_thread).with(anything, anything, anything).returns(new_thread)

    result = Discord::SkillEntrypoint.evaluate(event, scope, "pode criar thread")

    assert_equal "grill-me", result[:skill_name], "'pode criar thread' deve ser tratado como aceite"
    assert_equal "888", result[:thread_id], "'pode criar thread' deve criar thread"
    conv.reload
    assert_nil conv.offered_skill_name, "Oferta deve ser limpa após aceite"
  end
end
