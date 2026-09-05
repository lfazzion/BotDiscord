# frozen_string_literal: true

module Skills
  class Definition
    attr_reader :name, :description, :system_prompt, :explicit_triggers,
                :autonomous, :tools, :context, :cost, :discord,
                :raw_payload

    def initialize(raw)
      @raw_payload = raw
      @name = raw.fetch(:name).to_s
      @description = raw.fetch(:description).to_s
      @system_prompt = raw.fetch(:system_prompt).to_s
      @explicit_triggers = normalize_explicit_triggers(raw[:explicit_triggers] || {})
      @autonomous = normalize_autonomous(raw[:autonomous] || {})
      @tools = normalize_tools(raw[:tools] || {})
      @context = normalize_context(raw[:context] || {})
      @cost = normalize_cost(raw[:cost] || {})
      @discord = normalize_discord(raw[:discord] || {})
    end

    def prompt_fragment
      @system_prompt
    end

    # Compatibilidade com callers que consomem o registro como Hash
    # (ex.: Skills::Selector e o teste "registry loads grill-me from
    # config/skills" — selector_test.rb:181-185). Mantemos a interface
    # declarativa do Definition (.name, .description, .digest) e expomos
    # também o acesso indexado [:name] para não quebrar o seletor.
    def [](key)
      key = key.to_sym if key.is_a?(String)
      respond_to?(key) ? send(key) : @raw_payload[key]
    end

    def dig(*keys)
      keys.reduce(self) { |acc, k| acc.is_a?(Definition) ? acc[k] : acc&.[](k) }
    end

    def explicit_match?(content)
      return false unless content.is_a?(String) && content.present?
      explicit_triggers&.any? do |kind, entry|
        case kind
        when :slash
          detect_slash_match?(content, entry)
        when :text_commands
          entry.any? { |cmd| content.include?(cmd.to_s) }
        when :phrases
          entry.any? { |p| content.include?(p.to_s) }
        when :exit_phrases
          entry.any? { |p| content.include?(p.to_s) }
        end
      end
    end

    def slug
      @name.downcase
    end

    def eql?(other)
      other.is_a?(self.class) && digest == other.digest
    end

    def hash
      digest.hash
    end

    def ==(other)
      eql?(other)
    end

    def digest
      @digest ||= Digest::SHA256.hexdigest(material_for_digest)
    end

    def tool_ids
      tools[:allow].map(&:to_s)
    end

    def deny_all?
      tools[:deny].map(&:to_s).include?('*')
    end

    def deny_ids
      tools[:deny].reject { |id| id.to_s == '*' }
    end

    def max_rehydrated_messages
      Integer(context[:max_rehydrated_messages]) rescue nil
    end

    def prompt_fragment_max_chars
      Integer(context[:prompt_fragment_max_chars]) rescue nil
    end

    def compaction_instructions
      @context[:compaction_instructions].to_s
    end

    def selector_max_input_chars
      Integer(cost[:selector_max_input_chars]) rescue nil
    end

    def selector_max_output_tokens
      Integer(cost[:selector_max_output_tokens]) rescue nil
    end

    def max_rounds
      v = cost[:max_rounds]
      return v unless v.is_a?(String)
      return nil if v.strip.downcase == 'null'
      Integer(v) rescue nil
    end

    def explicit_trigger_slash_name
      explicit_triggers&.[](:slash)&.[](:name)
    end

    def exit_phrases
      explicit_triggers&.[](:exit_phrases) || []
    end

    def create_thread?
      discord&.[](:create_thread).to_s == 'true'
    end

    private

    def normalize_explicit_triggers(raw)
      return {} unless raw.is_a?(Hash)
      out = {}
      slash = raw[:slash]
      if slash
        raise ArgumentError, 'explicit_triggers.slash deve ser um hash' unless slash.is_a?(Hash)
        out[:slash] = {
          name: slash[:name].to_s,
          description: slash[:description].to_s,
          input: normalize_input(slash[:input])
        }
      end
      tc = raw[:text_commands]
      out[:text_commands] = Array(tc).map(&:to_s) if tc
      ph = raw[:phrases]
      out[:phrases] = Array(ph).map(&:to_s) if ph
      ex = raw[:exit_phrases]
      out[:exit_phrases] = Array(ex).map(&:to_s) if ex
      out
    end

    def normalize_input(raw)
      return {} unless raw.is_a?(Hash)
      {
        name: raw[:name].to_s,
        description: raw[:description].to_s,
        required: raw[:required].to_s == 'true'
      }
    end

    def normalize_autonomous(raw)
      return {} unless raw.is_a?(Hash)
      {
        enabled: raw[:enabled].to_s == 'true',
        candidate_hints: Array(raw[:candidate_hints]).map(&:to_s),
        positive_examples: Array(raw[:positive_examples]).map(&:to_s),
        negative_examples: Array(raw[:negative_examples]).map(&:to_s)
      }
    end

    def normalize_tools(raw)
      raise ArgumentError, 'tools deve ser um hash' unless raw.is_a?(Hash)
      {
        allow: Array(raw[:allow]).map(&:to_s),
        deny: Array(raw[:deny]).map(&:to_s)
      }
    end

    def normalize_context(raw)
      raise ArgumentError, 'context deve ser um hash' unless raw.is_a?(Hash)
      {
        max_rehydrated_messages: raw[:max_rehydrated_messages],
        prompt_fragment_max_chars: raw[:prompt_fragment_max_chars],
        compaction_instructions: raw[:compaction_instructions].to_s
      }
    end

    def normalize_cost(raw)
      raise ArgumentError, 'cost deve ser um hash' unless raw.is_a?(Hash)
      {
        selector_max_input_chars: raw[:selector_max_input_chars],
        selector_max_output_tokens: raw[:selector_max_output_tokens],
        selector_calls_per_turn: raw[:selector_calls_per_turn],
        max_rounds: raw[:max_rounds]
      }
    end

    def normalize_discord(raw)
      raise ArgumentError, 'discord deve ser um hash' unless raw.is_a?(Hash)
      raw
    end

    def detect_slash_match?(content, slash_entry)
      prefix = "/#{slash_entry[:name]}"
      content.strip.start_with?(prefix)
    end

    def material_for_digest
      @raw_payload.reject { |k, _| k.to_sym == :discord }.to_hash.sort_by { |k, _| k.to_s }.map { |k, v|
        [k, v.is_a?(Hash) ? v.sort_by { |kk, _| kk.to_s }.to_h : v]
      }.flatten(1).join("\x00")
    end
  end
end
