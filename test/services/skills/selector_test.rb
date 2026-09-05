require 'test_helper'

# Carga explícita dos serviços de skills (Zeitwerk já carrega automaticamente
# em produção, mas testes podem precisar de require explícito em alguns casos)
Rails.autoloaders.main.push_dir(Rails.root.join('app/services/skills'), namespace: Skills)

class SkillsSelectorTest < ActiveSupport::TestCase
  setup do
    # Zera cache e estado por teste
    Rails.cache.clear
    @registry = Skills::Registry.new
  end

  # ── Tarefa 5: Seletor autônomo e explícito ─────────────────────────────────

  test 'trigger slash escolhe grill sem chamar AiRouter' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.expects(:complete).never
    
    result = selector.call('/grill tenho uma ideia de produto')
    assert_equal 'grill-me', result
  end

  test 'frase explícita escolhe grill sem chamar AiRouter' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.expects(:complete).never
    
    result = selector.call('me grilla nessa ideia')
    assert_equal 'grill-me', result
  end

  test 'mensagem com hint candidato chama classificador' do
    selector = Skills::Selector.new(registry: @registry)
    
    # Mensagem contém hint mas não trigger explícito
    prompt = 'Tenho uma ideia vaga de produto e quero descobrir os buracos.'
    
    # Mock do AiRouter para simular resposta válida
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    result = selector.call(prompt, conversation_id: 'conv_123')
    assert_equal 'grill-me', result
  end

  test 'mensagem sem hint não chama classificador' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.expects(:complete).never
    
    result = selector.call('Oi, tudo bem?')
    assert_nil result
  end

  test 'JSON válido escolhe uma skill conhecida' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    # Usa mensagem que contém hint candidato
    result = selector.call('Tenho uma ideia vaga de produto', conversation_id: 'conv_123')
    assert_equal 'grill-me', result
  end

  test 'baixa confiança devolve nil' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.3 }.to_json)
    
    result = selector.call('Tenho uma ideia...', conversation_id: 'conv_123')
    assert_nil result
  end

  test 'resposta não JSON devolve nil' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.stubs(:complete).returns('Não entendi a pergunta')
    
    result = selector.call('Tenho uma ideia...', conversation_id: 'conv_123')
    assert_nil result
  end

  test 'nome desconhecido devolve nil' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.stubs(:complete).returns({ 'skill' => 'skill-inexistente', 'confidence' => 0.9 }.to_json)
    
    result = selector.call('Teste', conversation_id: 'conv_123')
    assert_nil result
  end

  test 'timeout/quota devolve nil' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.stubs(:complete).raises(Timeout::Error, 'Gateway timeout')
    
    result = selector.call('Teste', conversation_id: 'conv_123')
    assert_nil result
  end

  test 'só há uma chamada por turno' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.expects(:complete).once.returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    # Mensagem com hint candidato
    selector.call('Estou pensando em um novo produto', conversation_id: 'conv_456')
  end

  test 'input enviado é truncado conforme selector_max_input_chars' do
    selector = Skills::Selector.new(registry: @registry)
    
    max_input = @registry.selector_max_input_chars
    
    # Mensagem muito longa deve ser truncada
    long_message = 'x' * (max_input + 1000)
    
    captured_prompt = nil
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    AiRouter.expects(:complete).with do |prompt, **kwargs|
      captured_prompt = prompt
      true
    end.returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    # Mensagem com hint para forçar chamada ao classificador
    selector.call("tenho uma ideia #{long_message}", conversation_id: 'conv_789')
    
    # A implementação trunca a MENSAGEM (message[0...max_input]) antes de
    # compor o prompt. O prompt completo inclui catálogo + instruções, então
    # sua extensão total excede max_input. O que importa é que a mensagem
    # truncada está presente e a cauda (message[max_input..]) foi cortada.
    full_message = "tenho uma ideia #{long_message}"
    truncated_message = full_message[0...max_input]
    omitted_tail = full_message[max_input..]

    assert_not_nil captured_prompt
    assert_includes captured_prompt, truncated_message
    refute_includes captured_prompt, omitted_tail
  end

  test 'max_tokens vem de selector_max_output_tokens' do
    selector = Skills::Selector.new(registry: @registry)
    
    max_tokens = @registry.selector_max_output_tokens
    
    captured_params = nil
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    AiRouter.expects(:complete).with do |_, **kwargs|
      captured_params = kwargs[:params]
      true
    end.returns({ 'skill' => 'grill-me', 'confidence' => 0.9 }.to_json)
    
    # Mensagem com hint para forçar chamada ao classificador
    selector.call('não sei exatamente o que quero', conversation_id: 'conv_abc')
    
    assert_not_nil captured_params
    assert_equal max_tokens, captured_params[:max_tokens]
  end

  test 'modo já ativo não chama classificador' do
    selector = Skills::Selector.new(registry: @registry)
    
    AiRouter.expects(:complete).never
    
    result = selector.call('Continuar', conversation_id: 'conv_123', active_skill: 'grill-me')
    assert_equal 'grill-me', result
  end

  test 'fail-closed: segunda mensagem sem hint após negativa não chama classificador' do
    selector = Skills::Selector.new(registry: @registry)
    conversation_id = 'conv_fail_closed'
    
    # Primeira mensagem com hint -> classificador devolve nil (confiança baixa)
    AiRouter.stubs(:complete).returns({ 'skill' => 'grill-me', 'confidence' => 0.3 }.to_json)
    
    result1 = selector.call('Tenho uma ideia vaga...', conversation_id: conversation_id)
    assert_nil result1
    
    # Segunda mensagem também sem hint -> não deve chamar classificador (fail-closed)
    AiRouter.expects(:complete).never
    
    result2 = selector.call('Vou pensar sobre isso...', conversation_id: conversation_id)
    assert_nil result2
  end

  test 'registry loads grill-me from config/skills' do
    skill = @registry.fetch('grill-me')
    assert_not_nil skill
    assert_equal 'grill-me', skill[:name]
    assert skill[:description].present?
  end

  test 'registry explicit_match returns nil for non-matching message' do
    result = @registry.explicit_match?('mensagem qualquer sem trigger')
    assert_nil result
  end

  test 'registry candidate_hints returns false for non-matching message' do
    result = @registry.candidate_hints?('mensagem sem hints')
    assert_equal false, result
  end

  test 'registry candidate_hints returns true for matching hint' do
    result = @registry.candidate_hints?('tenho uma ideia')
    assert_equal true, result
  end
end
