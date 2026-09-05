# frozen_string_literal: true

# Testes para o módulo DeriveAllowlist e a integração com Skills::Registry.
#
# Objetivo: provar que as allowlists derivadas dos normalizers são corretas
# e que o teste de integridade quebra se um normalizer ganhar nova chave
# sem atualizar a allowlist correspondente.

require "test_helper"

class DeriveAllowlistTest < ActiveSupport::TestCase
  test "define retorna array de simbolos para cada seção" do
    # As seções mapeiam os normalizers em definition.rb:129-199:
    expected = {
      root: %i[version name description system_prompt explicit_triggers autonomous tools context cost discord],
      explicit_triggers: %i[slash text_commands phrases exit_phrases],
      slash: %i[name description input],
      input: %i[name description required],
      autonomous: %i[enabled candidate_hints positive_examples negative_examples],
      tools: %i[allow deny],
      context: %i[max_rehydrated_messages prompt_fragment_max_chars compaction_instructions],
      cost: %i[selector_max_input_chars selector_max_output_tokens selector_calls_per_turn max_rounds],
      discord: %i[create_thread thread_visibility thread_name]
    }

    DeriveAllowlist::SECTION_NORMALIZERS.each_key do |section|
      result = DeriveAllowlist.derived_all[section]
      assert_equal expected[section], result, "Seção #{section} diverge"
    end
  end

  test "integrity_check! passa quando allowlists estão sincronizadas" do
    # O teste de integridade deve passar porque as allowlists foram derivadas
    # diretamente dos normalizers em definition.rb.
    # R9-Item2: usar Definition real em vez de nil para provar sincronia real.
    definition = Skills::Definition.new(
      version: 1,
      name: "test-skill",
      description: "Test skill for integrity check",
      system_prompt: "You are a test skill.",
      explicit_triggers: {
        slash: { name: "test", description: "Test slash", input: { name: "topic", description: "Topic", required: false } },
        text_commands: ["!test"],
        phrases: ["test phrase"],
        exit_phrases: ["exit test"]
      },
      autonomous: { enabled: false, candidate_hints: [], positive_examples: [], negative_examples: [] },
      tools: { allow: [], deny: ["*"] },
      context: { max_rehydrated_messages: 100, prompt_fragment_max_chars: 6000, compaction_instructions: "" },
      cost: { selector_max_input_chars: 4000, selector_max_output_tokens: 64, selector_calls_per_turn: 1, max_rounds: "null" },
      discord: { create_thread: false }
    )

    assert_nothing_raised do
      DeriveAllowlist.integrity_check!(definition)
    end
  end

  test "integrity_check! lança IntegrityError quando allowlist diverge" do
    # Simula uma divergência: altera a allowlist de :root e verifica que
    # o teste de integridade quebra.
    # R9-Item2: usar Definition real em vez de nil.
    definition = Skills::Definition.new(
      version: 1,
      name: "test-skill",
      description: "Test skill for integrity check",
      system_prompt: "You are a test skill.",
      explicit_triggers: {},
      autonomous: {},
      tools: {},
      context: {},
      cost: {},
      discord: {}
    )

    original = DeriveAllowlist.derived_all[:root].dup
    DeriveAllowlist.instance_variable_get(:@caches)[:root] = original + [:nova_chave]

    error = assert_raises(DeriveAllowlist::IntegrityError) do
      DeriveAllowlist.integrity_check!(definition)
    end
    assert_match(/Seção root/, error.message)
  ensure
    # Restaura o valor original
    DeriveAllowlist.instance_variable_get(:@caches)[:root] = original
  end

  test "define lança ArgumentError para seção desconhecida" do
    assert_raises(ArgumentError) do
      DeriveAllowlist.define(:secao_inexistente)
    end
  end
end

class RegistryAllowlistDerivationTest < ActiveSupport::TestCase
  test "Registry usa allowlists derivadas dos normalizers" do
    # Prova que as constantes do Registry refletem as allowlists derivadas.
    assert_equal DeriveAllowlist.derived_all[:root], Skills::Registry::ALLOWED_ROOT_KEYS
    assert_equal DeriveAllowlist.derived_all[:explicit_triggers], Skills::Registry::ALLOWED_EXPLICIT_TRIGGERS_KEYS
    assert_equal DeriveAllowlist.derived_all[:slash], Skills::Registry::ALLOWED_SLASH_KEYS
    assert_equal DeriveAllowlist.derived_all[:input], Skills::Registry::ALLOWED_INPUT_KEYS
    assert_equal DeriveAllowlist.derived_all[:autonomous], Skills::Registry::ALLOWED_AUTONOMOUS_KEYS
    assert_equal DeriveAllowlist.derived_all[:tools], Skills::Registry::ALLOWED_TOOLS_KEYS
    assert_equal DeriveAllowlist.derived_all[:context], Skills::Registry::ALLOWED_CONTEXT_KEYS
    assert_equal DeriveAllowlist.derived_all[:cost], Skills::Registry::ALLOWED_COST_KEYS
    assert_equal DeriveAllowlist.derived_all[:discord], Skills::Registry::ALLOWED_DISCORD_KEYS
  end

  test "allowed_keys_for retorna allowlist correta para cada chave pai" do
    registry = Skills::Registry.new

    # Usa send para acessar método privado em testes
    assert_equal Skills::Registry::ALLOWED_EXPLICIT_TRIGGERS_KEYS, registry.send(:allowed_keys_for, :explicit_triggers)
    assert_equal Skills::Registry::ALLOWED_SLASH_KEYS, registry.send(:allowed_keys_for, :slash)
    assert_equal Skills::Registry::ALLOWED_INPUT_KEYS, registry.send(:allowed_keys_for, :input)
    assert_equal Skills::Registry::ALLOWED_AUTONOMOUS_KEYS, registry.send(:allowed_keys_for, :autonomous)
    assert_equal Skills::Registry::ALLOWED_TOOLS_KEYS, registry.send(:allowed_keys_for, :tools)
    assert_equal Skills::Registry::ALLOWED_CONTEXT_KEYS, registry.send(:allowed_keys_for, :context)
    assert_equal Skills::Registry::ALLOWED_COST_KEYS, registry.send(:allowed_keys_for, :cost)
    assert_equal Skills::Registry::ALLOWED_DISCORD_KEYS, registry.send(:allowed_keys_for, :discord)
    assert_equal Skills::Registry::ALLOWED_ROOT_KEYS, registry.send(:allowed_keys_for, :some_other_key)
  end

  test "grill-me carrega sem erro (input dentro de slash é permitido)" do
    registry = Skills::Registry.new
    skill = registry.fetch("grill-me")
    assert_not_nil skill
    assert_equal "grill-me", skill.name
  end

  test "second-skill carrega sem erro" do
    registry = Skills::Registry.new
    skill = registry.fetch("second-skill")
    assert_not_nil skill
    assert_equal "second-skill", skill.name
  end

  test "private-thread-skill carrega sem erro (thread_name em discord)" do
    registry = Skills::Registry.new
    skill = registry.fetch("private-thread-skill")
    assert_not_nil skill
    assert_equal "private-thread-skill", skill.name
  end

  test "rejeita chave desconhecida em nested discord" do
    registry = Skills::Registry.new
    assert_raises Skills::Registry::ConfigError do
      registry.fetch("nested-unknown-key")
    end
  end

  test "rejeita chave desconhecida no root" do
    registry = Skills::Registry.new
    assert_raises Skills::Registry::ConfigError do
      registry.fetch("unknown-key")
    end
  end

  test "all retorna skills válidas carregadas" do
    registry = Skills::Registry.new
    all = registry.all
    assert_includes all.map(&:name), "grill-me"
    assert_includes all.map(&:name), "second-skill"
  end

  test "produz digest estável" do
    registry = Skills::Registry.new
    skill = registry.fetch("grill-me")
    digest = skill.digest
    assert_match(/\A[a-f0-9]+\z/, digest)
    assert_equal digest, skill.digest
  end
end
