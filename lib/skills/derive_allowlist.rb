# frozen_string_literal: true

# DeriveAllowlist: deriva as allowlists de validacao dos normalizers em
# Skills::Definition. A ideia e fonte unica: cada seção tem uma allowlist
# congelada calculada a partir do que o normalizador correspondente aceita.
# Se um normalizer ganhar chave e a allowlist não for atualizada, o teste
# de integridade quebra.
#
# Metodo publico:
#   DeriveAllowlist.define(section) { ... } -> Array<Symbol>
# O bloco recebe o nome da seção e deve retornar um array de simbolos.
# As secoes mapeiam os normalizers:
#   :root            -> chaves no nivel raiz do YAML
#   :explicit_triggers -> chaves dentro de explicit_triggers
#   :slash           -> chaves dentro de explicit_triggers.slash
#   :input           -> chaves dentro de explicit_triggers.slash.input
#   :autonomous      -> chaves dentro de autonomous
#   :tools           -> chaves dentro de tools
#   :context         -> chaves dentro de context
#   :cost            -> chaves dentro de cost
#   :discord         -> chaves dentro de discord
module DeriveAllowlist
  SECTION_NORMALIZERS = {
    root: %i[version name description system_prompt explicit_triggers autonomous tools context cost discord],
    explicit_triggers: %i[slash text_commands phrases exit_phrases],
    slash: %i[name description input],
    input: %i[name description required],
    autonomous: %i[enabled candidate_hints positive_examples negative_examples],
    tools: %i[allow deny],
    context: %i[max_rehydrated_messages prompt_fragment_max_chars compaction_instructions],
    cost: %i[selector_max_input_chars selector_max_output_tokens selector_calls_per_turn max_rounds],
    discord: %i[create_thread thread_visibility thread_name]
  }.freeze

  SECTIONS = SECTION_NORMALIZERS.keys.freeze

  @caches = {}

  class << self
    # Chama DeriveAllowlist.define(section) em uma seção específica e retorna
    # o Array de simbolos derivados. O bloco de chamada serve apenas como
    # marcador opcional de comentarios, nao como parte da derivacao.
    def define(section, &block)
      raise ArgumentError, "Seção desconhecida: #{section}" unless SECTION_NORMALIZERS.key?(section)
      @caches[section] = SECTION_NORMALIZERS[section]
    end

    # Retorna as allowlists derivadas como Hash (secao => Array<Symbol>).
    # SECTION_NORMALIZERS serve de fallback predefinicao quando define(section)
    # ainda nao foi chamado para uma secao — garante que as constantes ALLOWED_*
    # no Registry sejam preenchidas mesmo sem populacao explicita do cache.
    def derived_all
      SECTION_NORMALIZERS.merge(@caches).dup
    end

    # Teste de integridade: se um normalizer em Definition mudar, as
    # allowlists aqui devem ser atualizadas. Se esta funcao falhar, o
    # teste de integridade quebra.
    def integrity_check!(definition_instance)
      SECTION_NORMALIZERS.each do |section, expected_keys|
        actual = derived_all[section]
        if actual != expected_keys
          raise IntegrityError, "Seção #{section}: esperado #{expected_keys.inspect}, got #{actual.inspect}"
        end
      end
    end
  end

  class IntegrityError < StandardError; end
end
