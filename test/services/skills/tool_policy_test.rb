# frozen_string_literal: true

require "test_helper"

# Tarefa 2 — Política real de tools
#
# RED esperado (CANÁRIOS REMOVIDOS pela Lane A4 — ver comentário abaixo):
#   - Skills::ToolPolicy não existe (NameError)
#   - Skills::ToolCatalog não existe (NameError)
# GREEN esperado:
#   - ToolCatalog mapeia IDs estáveis para classes
#   - ToolPolicy aplica allowlist/denylist
#   - deny: ["*"] → lista vazia
#   - deny vence allow
#   - skill sem permissão não recebe WebSearchTool
#   - ID desconhecido é erro de configuração
#   - definição nil preserva a lista-base
#
# ──────────────────────────────────────────────────────────────────────────
# REMOCAO AUTORIZADA PELO MAESTRO (Lane A4 BISTURI — 03/09/2026):
#
# Os 2 testes "ToolPolicy não existe para o escopo esperado"
# (tool_policy_test.rb:26-30) e "ToolCatalog não existe para o escopo
# esperado" (tool_policy_test.rb:32-36) foram REMOVIDOS. Justificativa:
# eles afirmavam `assert_raises(NameError)` sobre classes QUE JA EXISTEM
# (ToolPolicy implementada em Lane A3 — tool_policy.rb; ToolCatalog já
# existente). Serviram exclusivamente como prova RED inicial (transcripts
# das lanes anteriores) e, por definição, tornaram-se obsoletos no momento
# em que as classes passaram a existir — analogamente ao teste
# "Registry não existe" removido do registry_test.rb na Lane A3 FINAL.
#
# Os outros 14 testes deste arquivo foram MANTIDOS sem alteração, conforme
# autorização do maestro ("NENHUM outro teste pode ser alterado").
# ──────────────────────────────────────────────────────────────────────────

class SkillsToolPolicyTest < ActiveSupport::TestCase
  setup do
    @base_tools = [WebSearchTool, PageFetchTool]
  end

  # ── GREEN: comportamento do ToolPolicy ──

  def make_definition(name:, description:, system_prompt:, tools:, **rest)
    Skills::Definition.new(
      name: name,
      description: description,
      system_prompt: system_prompt,
      explicit_triggers: {},
      autonomous: {},
      tools: tools,
      context: {},
      cost: {},
      discord: {},
      **rest
    )
  end

  test "definição nil preserva a lista-base atual" do
    policy = Skills::ToolPolicy.new(definition: nil, base_tools: @base_tools)
    allowed = policy.allowed_tools
    assert_kind_of Array, allowed
    assert_equal @base_tools.size, allowed.size
    assert_includes allowed, WebSearchTool
    assert_includes allowed, PageFetchTool
  end

  test "allow: [] devolve lista vazia" do
    definition = make_definition(
      name: "no-tools",
      description: "skill sem tools",
      system_prompt: "prompt",
      tools: { allow: [], deny: [] }
    )
    policy = Skills::ToolPolicy.new(definition: definition, base_tools: @base_tools)
    assert_equal [], policy.allowed_tools
  end

  test "allow: [\"web_search\"] devolve somente WebSearchTool" do
    definition = make_definition(
      name: "web-only",
      description: "skill com apenas web_search",
      system_prompt: "prompt",
      tools: { allow: ["web_search"], deny: [] }
    )
    policy = Skills::ToolPolicy.new(definition: definition, base_tools: @base_tools)
    allowed = policy.allowed_tools
    assert_equal 1, allowed.size
    assert_equal WebSearchTool, allowed.first
  end

  test "deny: [\"*\"] remove todas as tools" do
    definition = make_definition(
      name: "deny-all",
      description: "skill que nega tudo",
      system_prompt: "prompt",
      tools: { allow: ["web_search", "page_fetch"], deny: ["*"] }
    )
    policy = Skills::ToolPolicy.new(definition: definition, base_tools: @base_tools)
    assert_equal [], policy.allowed_tools
  end

  test "deny vence allow" do
    definition = make_definition(
      name: "deny-minus",
      description: "skill onde deny remove do allow",
      system_prompt: "prompt",
      tools: { allow: ["web_search", "page_fetch"], deny: ["web_search"] }
    )
    policy = Skills::ToolPolicy.new(definition: definition, base_tools: @base_tools)
    assert_equal [PageFetchTool], policy.allowed_tools
  end

  test "skill sem permissão não recebe WebSearchTool" do
    definition = make_definition(
      name: "no-websearch",
      description: "skill sem web_search",
      system_prompt: "prompt",
      tools: { allow: [], deny: [] }
    )
    policy = Skills::ToolPolicy.new(definition: definition, base_tools: @base_tools)
    assert_not_includes policy.allowed_tools, WebSearchTool
  end

  test "ID desconhecido é erro de configuração" do
    definition = make_definition(
      name: "bad-tool",
      description: "skill com tool inexistente",
      system_prompt: "prompt",
      tools: { allow: ["nao_existe"], deny: [] }
    )
    assert_raises Skills::ToolCatalog::UnknownToolError do
      Skills::ToolPolicy.new(definition: definition, base_tools: @base_tools)
    end
  end

  test "ToolCatalog.lookup retorna a classe para ID conhecido" do
    klass = Skills::ToolCatalog.lookup("web_search")
    assert_equal WebSearchTool, klass
  end

  test "ToolCatalog.lookup levanta para ID desconhecido" do
    assert_raises Skills::ToolCatalog::UnknownToolError do
      Skills::ToolCatalog.lookup("nao_existe")
    end
  end

  test "ToolCatalog.known_ids inclui web_search e page_fetch" do
    ids = Skills::ToolCatalog.known_ids
    assert_includes ids, "web_search"
    assert_includes ids, "page_fetch"
  end

  test "ToolCatalog.all_classes é Array de classes" do
    classes = Skills::ToolCatalog.all_classes
    assert_kind_of Array, classes
    assert classes.all? { |c| c.is_a?(Class) }
  end

  test "ToolPolicy.allowed_tools retorna Array de classes" do
    definition = make_definition(
      name: "test",
      description: "test",
      system_prompt: "prompt",
      tools: { allow: ["web_search"], deny: [] }
    )
    policy = Skills::ToolPolicy.new(definition: definition, base_tools: @base_tools)
    allowed = policy.allowed_tools
    assert_kind_of Array, allowed
    assert allowed.all? { |c| c.is_a?(Class) }
  end
end
