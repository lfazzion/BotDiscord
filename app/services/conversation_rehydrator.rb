# frozen_string_literal: true

# Reconstrói o RubyLLM::Chat de uma conversa: resumo (quando existe) como
# instrução anexa, e a cauda viva como mensagens de verdade.
#
# Tool calls não voltam. Reidratar `tool_calls` sem os resultados originais
# quebra o protocolo do provedor — por isso só user/assistant são persistidos.
#
# Skill System v2 (Tarefa 8): quando a conversa tem `active_skill_name` válida,
# o fragmento da skill entra no bloco de contexto (entre o aviso de referência
# do resumo e o próprio resumo), e o teto de reidratação pode ser ENCOLHIDO
# pela skill mas nunca expandido acima de MAX_REHYDRATE. O Plano §3.1 diz
# "limites excessivos são erros" — sem o clamp, uma skill com `999` elevaria
# o teto global do bot.
class ConversationRehydrator
  DEFAULT_REHYDRATE = 30
  MAX_REHYDRATE = 100

  class << self
    def rehydrate_limit
      configured = ENV["DISCORD_REHYDRATE_MESSAGES"].to_i
      return DEFAULT_REHYDRATE unless configured.positive?

      [[configured, 1].max, MAX_REHYDRATE].min
    end

    # Skill System v2 (Tarefa 8): teto de reidratação por conversa, derivado
    # da skill ativa quando presente. Sempre clampado a MAX_REHYDRATE — uma
    # skill pode ENCOLHER o limite, nunca expandir. `Skills::Registry.fetch?`
    # (Lane D) é nil quando a coluna tem nome que saiu do registro; nesse
    # caso o limite é o global.
    def rehydrate_limit_for(conversation)
      base = rehydrate_limit
      return base unless conversation.respond_to?(:active_skill_name) &&
                          conversation.active_skill_name.present?

      definition = Skills::Registry.fetch?(conversation.active_skill_name)
      return base if definition.nil?

      limite_skill = definition.max_rehydrated_messages
      return base if limite_skill.nil? || limite_skill <= 0

      [limite_skill, MAX_REHYDRATE].min
    end

    def messages_for(conversation)
      ConversationCompactor.live_messages(conversation).last(rehydrate_limit_for(conversation))
    end

    def context_block(conversation)
      partes = []
      partes << Llm::PromptLoader.partial("multi_user") if conversation.shared
      if conversation.summary.present?
        partes << Llm::PromptLoader.partial("compaction_notice")
        partes << conversation.summary
      end
      # Skill System v2 (Tarefa 8): fragmento da skill ativa entra no bloco.
      # nil quando a skill sumiu do registro — `fetch?` devolve nil — para que
      # drift de YAML não injet texto órfão. Mesmo padrão da Conversation:
      # validação dura contra o registry.
      definition = active_definition(conversation)
      partes << skill_fragment_block(definition) if definition
      return nil if partes.empty?

      partes.join("\n\n")
    end

    def apply!(chat, conversation, skill: nil)
      # Skill System v2 (Tarefa 8): o chat quente já chega com prompt base
      # injetado por `build_chat`. Aqui anexamos o bloco de reidratação
      # (resumo + fragmento da skill + cauda). Quando o chamador passa
      # `skill:` explícito, usamos esse (corresponde ao caminho de cache miss
      # onde a definição ativa já foi resolvida); caso contrário, lemos da
      # conversa persistida.
      definition = skill || active_definition(conversation)
      bloco = context_block_with_skill(conversation, definition)
      chat.with_instructions(bloco, append: true) if bloco.present?

      messages_for(conversation).each do |message|
        chat.add_message(role: message.role.to_sym, content: message.llm_content)
      end

      chat
    end

    private

    # Helper privado — usado tanto pelo context_block público quanto pelo
    # apply! quando recebe skill explícita.
    def active_definition(conversation)
      return nil unless conversation.respond_to?(:active_skill_name) &&
                          conversation.active_skill_name.present?

      Skills::Registry.fetch?(conversation.active_skill_name)
    end

    # Mesmo helper, mas aceita uma `definition` resolvida (cache miss).
    def context_block_with_skill(conversation, definition)
      partes = []
      partes << Llm::PromptLoader.partial("multi_user") if conversation.shared
      if conversation.summary.present?
        partes << Llm::PromptLoader.partial("compaction_notice")
        partes << conversation.summary
      end
      partes << skill_fragment_block(definition) if definition
      return nil if partes.empty?

      partes.join("\n\n")
    end

    # Cabeçalho fixo + fragmento. Delimitado para que, num futuro log/inspect,
    # a proveniência seja óbvia. O delimitador não é usado pelo modelo para
    # nada — PromptLoader já monta o system prompt com seu próprio separador.
    def skill_fragment_block(definition)
      "## SKILL ATIVA: #{definition.name}\n#{definition.prompt_fragment}"
    end
  end
end
