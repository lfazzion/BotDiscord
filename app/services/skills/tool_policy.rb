# frozen_string_literal: true

module Skills
  # Aplica allow/deny de uma Definition sobre a lista-base de tools do
  # ChatSessionManager. Esta é a fronteira efetiva que decide quais tools
  # chegam ao `RubyLLM::Chat` antes do `ask`.
  #
  # Regras (em ordem):
  # 1. definition == nil → preserva a lista-base intacta.
  # 2. allow vazio → nenhuma tool.
  # 3. deny contém "*" → nenhuma tool (deny vence allow).
  # 4. deny remove itens do allow.
  # 5. IDs não presentes no ToolCatalog levantam UnknownToolError na construção.
  class ToolPolicy
    WILDCARD = "*".freeze

    attr_reader :base_tools, :definition

    def initialize(definition:, base_tools:)
      @base_tools = Array(base_tools)
      @definition = definition

      validate! if @definition
    end

    def allowed_tools
      return @base_tools.dup unless @definition

      allow_ids = allow_list
      deny_ids = deny_list

      # Só consideramos classes que estejam na lista-base — isso impede que
      # allow: ["page_fetch"] reative uma tool desligada pela feature flag
      # quando base_tools não a contém (invariante 8 do plano de skill-system).
      return [] if deny_ids.include?(WILDCARD)
      base_set = @base_tools.to_set
      allowed_classes = allow_ids
                        .map { |id| Skills::ToolCatalog.lookup(id) }
                        .select { |klass| klass && base_set.include?(klass) }
      allowed_classes.reject! { |klass| deny_ids.include?(tool_id_for(klass)) }
      allowed_classes
    end

    private

    def allow_list
      tools = @definition.is_a?(Skills::Definition) ? @definition.tools : (@definition[:tools] || {})
      Array(tools[:allow]).map(&:to_s)
    end

    def deny_list
      tools = @definition.is_a?(Skills::Definition) ? @definition.tools : (@definition[:tools] || {})
      Array(tools[:deny]).map(&:to_s)
    end

    def validate!
      allow_ids = allow_list
      deny_ids = deny_list

      allow_ids.each do |id|
        unless Skills::ToolCatalog.known_ids.include?(id.to_s)
          raise Skills::ToolCatalog::UnknownToolError, "tool desconhecida '#{id}'"
        end
      end

      deny_ids.each do |id|
        next if id.to_s == WILDCARD
        unless Skills::ToolCatalog.known_ids.include?(id.to_s)
          raise Skills::ToolCatalog::UnknownToolError, "tool desconhecida '#{id}' em deny"
        end
      end
    end

    def tool_id_for(klass)
      Skills::ToolCatalog.known_ids.find { |id| Skills::ToolCatalog.lookup(id) == klass }
    end
  end
end