# frozen_string_literal: true

require_relative '../../../lib/skills/derive_allowlist'

module Skills
  # Registro de skills: carrega definições YAML, valida schema, expõe lookup.
  #
  # Responsabilidades:
  # - Carregar config/skills/*.yml
  # - Em ambiente de teste, também carrega test/support/skills/*.yml (fora do
  #   alcance do loader de fixtures do ActiveRecord, evitando FormatError)
  # - Validar schema (version, name, description, explicit_triggers, autonomous, cost)
  # - Expor métodos para o seletor: explicit_match?, candidate_hints?, all, fetch
  class Registry
    SKILLS_DIR = Rails.root.join('config/skills').to_s
    VERSION = 1

    class ConfigError < StandardError; end

    attr_reader :skills

    def initialize
      load_skills_into_registry!
    end

    def all
      @skills.values
    end

    def fetch(name)
      key = name.to_s
      if @invalid.fetch(key, nil)
        raise ConfigError, @invalid[key]
      end
      @skills[key]
    end

    def fetch?(name)
      key = name.to_s
      return nil if @invalid.key?(key)
      @skills[key]
    end

    # Lane D (03/09/2026): método de CLASSE que espelha `fetch` mas devolve nil
    # em vez de levantar quando o nome não existe — usado pelo Conversation
    # (app/models/conversation.rb:87) e pelo ChatSessionManager (app/services/
    # chat_session_manager.rb:104) para validação "existe no registry?" sem
    # precisar de catch de exceção. Antes da Lane D só existia a versão de
    # instância; testes da Lane C stubavam este método na classe diretamente,
    # então ele precisava existir como tal.
    #
    # Cria uma nova instância para cada chamada para garantir que stubs de
    # classe (ex.: `Skills::Registry.stubs(:fetch?)`) sejam respeitados.
    def self.fetch?(name)
      new.fetch?(name)
    end

    def explicit_match?(message)
      return nil unless message.is_a?(String)

      @skills.each_value do |skill|
        triggers = skill[:explicit_triggers]
        next unless triggers

        if triggers[:slash]
          slash_name = triggers[:slash][:name]&.to_s&.downcase
          next unless slash_name

          # Exigir fronteira após o slash: "/grill" casa mas "/grillery" não.
          msg = message.strip.downcase
          pattern = /\A\/#{Regexp.escape(slash_name)}(?:\s|\z)/
          if msg.match?(pattern)
            return skill[:name]
          end
        end

        text_commands = triggers[:text_commands] || []
        msg_lower = message.downcase
        text_commands.each do |cmd|
          return skill[:name] if msg_lower.include?(cmd.to_s.downcase)
        end

        phrases = triggers[:phrases] || []
        phrases.each do |phrase|
          return skill[:name] if msg_lower.include?(phrase.to_s.downcase)
        end
      end

      nil
    end

    # R9-Item1: detecta se alguma exit_phrase da skill corresponde ao conteúdo.
    # Retorna o nome da skill cuja exit_phrase casou, ou nil se nenhuma skill
    # tiver exit_phrases que correspondam.
    def exit_phrase_match?(message)
      return nil unless message.is_a?(String)

      @skills.each_value do |skill|
        next unless skill.respond_to?(:exit_phrases)
        exit_phrases = skill.exit_phrases
        next if exit_phrases.empty?

        msg_lower = message.to_s.downcase
        if exit_phrases.any? { |p| msg_lower.include?(p.to_s.downcase) }
          return skill[:name]
        end
      end

      nil
    end

    # Alias aceito por Skills::Selector (selector.rb:37).
    # O Registry expõe as duas formas para permitir nomes mais naturais
    # nos callers novos (registry_test.rb:107 chama `explicit_match`)
    # sem quebrar o seletor já verde.
    alias_method :explicit_match, :explicit_match?

    def candidate_hints?(message)
      return false unless message.is_a?(String)

      @skills.any? do |_name, skill|
        autonomous = skill[:autonomous]
        next false unless autonomous && autonomous[:enabled]

        hints = autonomous[:candidate_hints] || []
        message_lower = message.downcase
        hints.any? { |hint| message_lower.include?(hint.to_s.downcase) }
      end
    end

    def slash_definitions
      unless @trigger_conflicts.empty?
        raise ConfigError, "triggers duplicados detectados entre skills: #{@trigger_conflicts.join('; ')}"
      end
      @skills.values.flat_map do |skill|
        triggers = skill[:explicit_triggers]
        next [] unless triggers && triggers[:slash]

        slash = triggers[:slash]
        input = slash[:input] || {}

        [
          {
            name: slash[:name],
            description: slash[:description],
            input_name: input[:name] || 'topic',
            input_description: input[:description] || '',
            input_required: !!input[:required]
          }
        ]
      end
    end

    def selector_max_input_chars
      all.map { |s| (s[:cost] || {})[:selector_max_input_chars].to_i }.reject(&:zero?).min || 4000
    end

    def selector_max_output_tokens
      all.map { |s| (s[:cost] || {})[:selector_max_output_tokens].to_i }.reject(&:zero?).min || 64
    end

    def selector_calls_per_turn
      all.map { |s| (s[:cost] || {})[:selector_calls_per_turn].to_i }.reject(&:zero?).first || 1
    end

    private

    def load_skills_into_registry!
      @skills = {}
      @invalid = {}
      @trigger_index = Hash.new { |h, k| h[k] = [] }
      @trigger_owner = {}
      @trigger_conflicts = []
      seen_names = {}
      dirs = skill_dirs

      dirs.each do |dir|
        next unless Dir.exist?(dir)
        Dir.glob("#{dir}/*.yml").sort.each do |path|
          begin
            raw = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false, symbolize_names: true)
            raise ConfigError, "YAML inválido em #{path}" unless raw.is_a?(Hash)

            normalized = validate_and_normalize!(raw, path)
            name = normalized[:name]
            new_def = Skills::Definition.new(normalized)

            if @skills.key?(name)
              if @skills[name].digest == new_def.digest
                # Conteúdo idêntico nas duas fontes NÃO é duplicata (dedupe por digest)
                next
              else
                @skills.delete(name)
                @invalid[name] = "nome duplicado em #{path} (#{name} já carregado)"
                next
              end
            end

            if @invalid.key?(name)
              @invalid[name] = "nome duplicado em #{path} (#{name} já carregado)"
              next
            end

            conflict = trigger_conflict?(normalized)
            if conflict
              @trigger_conflicts << conflict
              @invalid[name] = "trigger duplicado em #{path} (#{conflict})"
              next
            end

            @skills[name] = new_def
            register_triggers!(normalized, name)
          rescue ConfigError => e
            # Lane A4 BISTURI (03/09/2026): falhas de validação precisam
            # propagar para @invalid[name] — antes da Lane A4, o rescue
            # engolia a falha silenciosamente (apenas logava), o que
            # impedia os testes "rejeita X" do registry_test.rb de
            # passarem. Agora preservamos o nome do YAML (lido cru, sem
            # validação completa) para que fetch(name) levante ConfigError.
            attempted_name = safe_yaml_name(raw) rescue raw_path_basename(path)
            Rails.logger.warn "[Skills::Registry] #{path}: #{e.message}"
            @invalid[attempted_name] ||= "configuração inválida em #{path}: #{e.message}"
          rescue ArgumentError => e
            Rails.logger.warn "[Skills::Registry] #{path}: #{e.message}"
            # Lane B (04/09/2026): ArgumentError também deve entrar em @invalid,
            # para que a skill defeituosa seja rejeitada ao invés de desaparecer
            # silenciosamente. Antes só logava.
            attempted_name = safe_yaml_name(raw) rescue raw_path_basename(path)
            @invalid[attempted_name] ||= "configuração inválida em #{path}: #{e.message}"
          rescue => e
            Rails.logger.warn "[Skills::Registry] erro inesperado em #{path}: #{e.class} — #{e.message}"
          end
        end
      end
    end

    # Extrai o nome do YAML cru (mesmo que falhe a validação completa)
    # para que o Registry possa associar a falha ao nome da skill.
    def safe_yaml_name(raw)
      raw.is_a?(Hash) ? raw[:name].to_s : nil
    end

    # Fallback quando o YAML não é parseável: usa o basename do arquivo
    # sem extensão, garantindo que @invalid ainda tenha uma chave útil.
    def raw_path_basename(path)
      File.basename(path, '.yml')
    end

    def skill_dirs
      dirs = [SKILLS_DIR]
      test_fixtures_dir = Rails.root.join('test/support/skills').to_s
      dirs << test_fixtures_dir if Rails.env.test? && Dir.exist?(test_fixtures_dir)
      dirs
    end

    # Chaves YAML reconhecidas no nível raiz (Lane A4 BISTURI — 03/09/2026):
    # mantemos uma allowlist explícita para falhar fechado quando alguém
    # adicionar uma chave nova sem intenção (typo, refactor parcial).
    #
    # Allowlists derivadas dos normalizers em definition.rb:129-199 (fonte unica).
    # Espelham as chaves que cada normalizador aceita, gerando o conjunto
    # congelado por seção. Se um normalizer ganhar chave e o conjunto não
    # for atualizado, o teste de integridade quebra.
    ALLOWED_ROOT_KEYS = DeriveAllowlist.derived_all[:root]
    ALLOWED_EXPLICIT_TRIGGERS_KEYS = DeriveAllowlist.derived_all[:explicit_triggers]
    ALLOWED_SLASH_KEYS = DeriveAllowlist.derived_all[:slash]
    ALLOWED_INPUT_KEYS = DeriveAllowlist.derived_all[:input]
    ALLOWED_AUTONOMOUS_KEYS = DeriveAllowlist.derived_all[:autonomous]
    ALLOWED_TOOLS_KEYS = DeriveAllowlist.derived_all[:tools]
    ALLOWED_CONTEXT_KEYS = DeriveAllowlist.derived_all[:context]
    ALLOWED_COST_KEYS = DeriveAllowlist.derived_all[:cost]
    ALLOWED_DISCORD_KEYS = DeriveAllowlist.derived_all[:discord]

    def validate_and_normalize!(data, path)
      validate_root_keys!(data, path)
      raise ConfigError, "version ausente ou inválida em #{path}" unless data[:version] == VERSION
      raise ConfigError, "name ausente em #{path}" if data[:name].nil? || data[:name].to_s.strip.empty?
      raise ConfigError, "description ausente em #{path}" if data[:description].nil? || data[:description].to_s.strip.empty?
      raise ConfigError, "name deve ser ASCII slug em #{path}" unless data[:name].to_s.match?(/\A[a-z0-9_-]+\z/)
      raise ConfigError, "system_prompt ausente em #{path}" if data[:system_prompt].nil? || data[:system_prompt].to_s.strip.empty?

      normalized = {
        name: data[:name].to_s,
        description: data[:description].to_s,
        system_prompt: data[:system_prompt].to_s,
        explicit_triggers: data[:explicit_triggers] || {},
        autonomous: data[:autonomous] || {},
        tools: data[:tools] || {},
        context: data[:context] || {},
        cost: data[:cost] || {},
        discord: data[:discord] || {}
      }

      validate_context!(normalized, path)
      validate_cost!(normalized, path)
      validate_tools!(normalized, path)
      validate_fragment_size!(normalized, path)
      normalized
    end

    # Lane A4 BISTURI: rejeita chaves desconhecidas no nível raiz do YAML.
    # Falha fechada: se uma chave nova for adicionada sem atualizar a
    # allowlist, o Registry levanta ConfigError antes de qualquer carregamento.
    # R8-Item5: extendida para validar recursivamente todos os níveis aninhados.
    def validate_root_keys!(data, path)
      return unless data.is_a?(Hash)
      validate_keys_recursive!(data, ALLOWED_ROOT_KEYS, path)
    end

    # Valida recursivamente todas as chaves em hashes aninhados.
    # R8-Item5: garante que chaves desconhecidas em qualquer nível (ex: discord.*) sejam rejeitadas.
    # R8c: usa allowlists específicas por campo para explicit_triggers e derivados.
    def validate_keys_recursive!(data, allowed_keys, path, current_path = nil)
      return unless data.is_a?(Hash)
      normalized_path = current_path ? "#{current_path}." : ""
      extra = data.keys.map(&:to_sym) - allowed_keys
      unless extra.empty?
        location = current_path || path
        raise ConfigError,
              "chave(s) desconhecida(s) em #{location}: #{extra.sort.join(', ')}"
      end
      data.each do |key, value|
        next unless value.is_a?(Hash)
        child_allowed = allowed_keys_for(key)
        validate_keys_recursive!(value, child_allowed, path, "#{normalized_path}#{key}")
      end
    end

    # Retorna a allowlist apropriada para o hash aninhado dado sua chave pai.
    # Derivada dos normalizers em Definition#normalize_* (fonte unica).
    def allowed_keys_for(key)
      case key.to_sym
      when :explicit_triggers
        ALLOWED_EXPLICIT_TRIGGERS_KEYS
      when :slash
        ALLOWED_SLASH_KEYS
      when :input
        ALLOWED_INPUT_KEYS
      when :autonomous
        ALLOWED_AUTONOMOUS_KEYS
      when :tools
        ALLOWED_TOOLS_KEYS
      when :context
        ALLOWED_CONTEXT_KEYS
      when :cost
        ALLOWED_COST_KEYS
      when :discord
        ALLOWED_DISCORD_KEYS
      else
        ALLOWED_ROOT_KEYS
      end
    end

    def validate_context!(normalized, path)
      ctx = normalized[:context]
      return unless ctx.is_a?(Hash)
      raise ConfigError, "max_rehydrated_messages deve ser positivo em #{path}" if ctx[:max_rehydrated_messages].to_i <= 0
      raise ConfigError, "prompt_fragment_max_chars deve ser positivo em #{path}" if ctx[:prompt_fragment_max_chars].to_i <= 0
    end

    def validate_cost!(normalized, path)
      cost = normalized[:cost]
      return unless cost.is_a?(Hash)
      raise ConfigError, "selector_max_input_chars deve ser positivo em #{path}" if cost[:selector_max_input_chars].to_i <= 0
      raise ConfigError, "selector_max_output_tokens deve ser positivo em #{path}" if cost[:selector_max_output_tokens].to_i <= 0
      # selector_calls_per_turn e max_rounds são opcionais, mas se presentes devem ser inteiros positivos.
      if cost[:selector_calls_per_turn].present?
        v = Integer(cost[:selector_calls_per_turn]) rescue nil
        raise ConfigError, "selector_calls_per_turn deve ser inteiro positivo em #{path}" unless v&.positive?
      end
      if cost[:max_rounds].present? && cost[:max_rounds].to_s.downcase != 'null'
        v = Integer(cost[:max_rounds]) rescue nil
        raise ConfigError, "max_rounds deve ser inteiro positivo ou null em #{path}" unless v&.positive?
      end
    end

    def validate_tools!(normalized, path)
      tools = normalized[:tools]
      raise ConfigError, "tools deve ser um hash em #{path}" unless tools.is_a?(Hash)
      allow = Array(tools[:allow])
      deny = Array(tools[:deny])
      allow.each do |id|
        unless Skills::ToolCatalog.known_ids.include?(id.to_s)
          raise ConfigError, "tool desconhecida '#{id}' em #{path}"
        end
      end
      # deny também é validado: IDs desconhecidos devem falhar fechado.
      deny.each do |id|
        next if id.to_s == '*'
        unless Skills::ToolCatalog.known_ids.include?(id.to_s)
          raise ConfigError, "tool desconhecida '#{id}' em deny de #{path}"
        end
      end
    end

    def validate_fragment_size!(normalized, path)
      ctx = normalized[:context] || {}
      max = ctx[:prompt_fragment_max_chars].to_i
      return if max <= 0
      length = normalized[:system_prompt].length
      return if length <= max
      raise ConfigError, "system_prompt excede o limite de #{max} caracteres (tem #{length}) em #{path}"
    end

    def trigger_conflict?(normalized)
      triggers = normalized[:explicit_triggers] || {}
      slash = triggers[:slash]
      if slash.is_a?(Hash) && slash[:name].to_s.present?
        key = "slash:#{slash[:name].to_s.downcase}"
        return "slash '#{slash[:name]}'" if @trigger_owner.key?(key)
      end
      Array(triggers[:text_commands]).each do |cmd|
        k = "tc:#{cmd.to_s.downcase}"
        return "text_command '#{cmd}'" if @trigger_owner.key?(k)
      end
      Array(triggers[:phrases]).each do |phrase|
        k = "ph:#{phrase.to_s.downcase}"
        return "phrase '#{phrase}'" if @trigger_owner.key?(k)
      end
      nil
    end

    def register_triggers!(normalized, name)
      triggers = normalized[:explicit_triggers] || {}
      slash = triggers[:slash]
      @trigger_owner["slash:#{slash[:name].to_s.downcase}"] = name if slash.is_a?(Hash) && slash[:name].to_s.present?
      Array(triggers[:text_commands]).each do |cmd|
        @trigger_owner["tc:#{cmd.to_s.downcase}"] = name
      end
      Array(triggers[:phrases]).each do |phrase|
        @trigger_owner["ph:#{phrase.to_s.downcase}"] = name
      end
    end
  end
end
