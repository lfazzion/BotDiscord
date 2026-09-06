# frozen_string_literal: true

module Discord
  # SkillEntrypoint: avalia se uma mensagem deve ativar uma skill e gerencia
  # a criação de thread quando necessário.
  #
  # Fluxo:
  # 1. Trigger explícito (/grill, !grill, frases) -> usa name direto, sem classificador
  # 2. Modo já ativo -> mantém
  # 3. Ofert pendente -> interpreta resposta (aceitar/continuar/outra)
  # 4. Hint candidato -> classificador uma vez (fail-closed)
  # 5. Skill detectada com create_thread? -> cria thread pública se não estiver em thread
  #
  # Retorno: hash com :skill_name, :scope (possivelmente com thread_id), :response (em caso de erro)
  class SkillEntrypoint
    OFFER_TIMEOUT_MINUTES = 30

    class ThreadVisibilityError < StandardError; end

    class << self
      def evaluate(event, scope, content)
        registry = Skills::Registry.new

        # 3. Verifica oferta pendente (precisamos dela antes do trigger explícito)
        # R5a: cria conversa automaticamente se não existir (defeito c)
        conversation = Conversation.active_for(scope.key)
        conversation = Conversation.open_for(
          scope: scope.key,
          channel_id: scope.channel_id,
          user_id: event.user&.id
        ) if conversation.nil?

        # 1. Trigger explícito (sem classificador)
        explicit = registry.explicit_match?(content)
        if explicit
          definition = registry.fetch?(explicit)
          # Limpa oferta pendente se existir (usuário iniciou nova interação)
          if conversation&.offered_skill_name.present?
            clear_offered_skill(conversation)
          end
          return resolve_thread(explicit, definition, event, scope, content)
        end

        # 2. Modo já ativo (persistido na conversa)
        active = conversation&.active_skill_name
        return { skill_name: active, scope: scope, content: content } if active.present?

        # 3. Verifica oferta pendente
        if conversation&.offered_skill_name.present?
          return handle_pending_offer(registry, conversation, event, scope, content)
        end

        # 4. Classificador (autônomo, uma vez)
        selector = Skills::Selector.new(registry: registry)
        skill_name = selector.call(content, conversation_id: scope.key)
        return { skill_name: nil, scope: scope, content: content } if skill_name.nil?

        # 5. Resolve thread (ou oferta se create_thread?)
        definition = registry.fetch?(skill_name)
        if definition&.create_thread? && conversation.present?
          save_offered_skill(conversation, skill_name, content)
          return offer_response(skill_name, scope, content)
        end

        resolve_thread(skill_name, definition, event, scope, content)
      end

      private

      def save_offered_skill(conversation, skill_name, content)
        conversation.update!(
          offered_skill_name: skill_name,
          offered_at: Time.current,
          offered_content: content  # R5a: persiste ideia original
        )
      end

      def offer_response(skill_name, scope, content)
        {
          skill_name: skill_name,
          scope: scope,
          content: content,
          response: "🤔 Detectei que você quer usar a skill '#{skill_name}'. " \
                    "Deseja: (1) criar uma thread pública para isso? ou (2) continuar aqui no canal?"
        }
      end

      def handle_pending_offer(registry, conversation, event, scope, content)
        # Verifica se a oferta expirou
        if offer_expired?(conversation)
          clear_offered_skill(conversation)
          # Re-processa normalmente sem recursão
          selector = Skills::Selector.new(registry: registry)
          skill_name = selector.call(content, conversation_id: scope.key)
          return { skill_name: nil, scope: scope, content: content } if skill_name.nil?
          definition = registry.fetch?(skill_name)
          if definition&.create_thread?
            save_offered_skill(conversation, skill_name, content)
            return offer_response(skill_name, scope, content)
          end
          resolve_thread(skill_name, definition, event, scope, content)
        end

        # Interpreta a resposta do usuário
        normalized = I18n.transliterate(content.to_s).downcase.strip

        # R14-B1: Negacao com 3+ tokens — precedencia semantica
        #
        # REGRAS:
        # 1. Nao no INICIO da frase + verbo de acao em qualquer posicao posterior,
        #    SEM virgula separando = RECUSA (ex: "nao acho que pode criar thread")
        # 2. Com virgula ("nao, pode criar") = NAO é recusa → cai em aceite
        # 3. FrasesFixas como "nao quero", "assim nao", "deixa", etc. = RECUSA
        #
        # Implementacao:
        # - Frases fixas (nao quero, assim nao, deixa, cancela, cancelar,
        #   recuso, recusar, sem thread) -> RECUSA
        # - "nao" no início + verbo de criacao downstream (sem virgula) -> RECUSA
        # - "nao, " (com virgula) -> NAO é recusa
        # - "nao" exato (sozinho) -> continuacao (handled abaixo)
        #
        refused = normalized.match?(/\A(?:assim nao|nao quero|deixa|cancela|cancelar|recuso|recusar|sem thread|nao\s+(?:(?:\w+\s+){0,2})?(?:criar|crie|abra|abrir|fazer|cria|faca)(?:\s+(?:a\s+)?thread)?|nao\s+thread|nao\b(?!,)(?:.*?\b(?:criar|crie|abra|abrir|fazer|cria|faca)\b)(?:\s+(?:a\s+)?thread)?)/)

        if refused
          clear_offered_skill(conversation)
          return { skill_name: nil, scope: scope, content: content }
        end

        # HOTFIX-OPTION-DIGIT (06/09): "1" puro e "2" puro não eram aceitos pelo parser,
        # apesar da offer_response oferecer "(1)" e "(2)" — o dono respondeu "1" e a oferta
        # foi engolida pelo else final. Manter \A1\) e \A2\) (já existentes) e adicionar
        # \A1\z e \A2\z para cobrir a resposta curta do usuário.
        # R14-B1: continuacao — "continua", "aqui", "opcao 2", "nao" exato, "2)", "2"
        continued = normalized.match?(/\A(?:continua|aqui|opcao 2)\b/) ||
                    normalized == 'nao' ||
                    normalized.match?(/\A2\)/) ||
                    normalized.match?(/\A2\z/)

        if continued
          # R5a: captura skill_name e conteúdo original ANTES de chamar activate_skill
          skill_name = conversation.offered_skill_name
          original_content = conversation.offered_content.presence || content
          activate_skill(conversation, skill_name)
          return { skill_name: skill_name, scope: scope, content: original_content }
        end

        # R14-B1: aceite — "sim", "thread", "criar", "cliquei", "opcao 1",
        #            "tente novamente", "tentar novamente", "tenta de novo", "1)",
        #            "1"
        #            OU mensagem que contém verbo de criacao (nao recusado)
        accepted = normalized.match?(/\A(?:sim|thread|criar|cliquei|opcao 1|tente novamente|tentar novamente|tenta de novo)\z/) ||
                   normalized.match?(/\A1\)/) ||
                   normalized.match?(/\A1\z/)

        # R14-B1: se nao é recusa e contem verbo de criacao -> aceite
        # Isso cobre: "pode criar thread", "nao, pode criar thread",
        #            "sim, cria a thread", etc.
        has_creation_verb = normalized.match?(/\b(?:criar|crie|abra|abrir|fazer|cria|faca)\b/)

        if accepted || has_creation_verb
          skill_name = conversation.offered_skill_name
          original_content = conversation.offered_content.presence || content
          definition = registry.fetch?(skill_name)

                    # R12-B3 / R13-B3': chave de idempotência baseada na oferta da conversa com id e precisão temporal,
                    # garantindo que ofertas distintas no mesmo segundo não colidem,
                    # e dois aceites concorrentes da mesma oferta reutilizem a mesma thread.
                    offered_time_precision = conversation.offered_at&.strftime("%Y%m%dT%H%M%S%6N") || conversation.offered_at&.to_f
                    offer_cache_key = "skill_thread_offer:#{scope.key}:#{conversation.id}:#{offered_time_precision || skill_name}"
          result = resolve_thread(skill_name, definition, event, scope, original_content, custom_key: offer_cache_key)

          # R12-B2: só limpa a oferta se a thread foi resolvida com sucesso
          if result[:thread_id].present?
            clear_offered_skill(conversation)
          end

          return result
        elsif continued
          # R5a: captura skill_name e conteúdo original ANTES de chamar activate_skill
          skill_name = conversation.offered_skill_name
          original_content = conversation.offered_content.presence || content
          activate_skill(conversation, skill_name)
          return { skill_name: skill_name, scope: scope, content: original_content }
        else
          # Mensagem não interpretada como aceite/continuacao:
          # re-classifica antes de descartar — evita engoli-la quando há
          # oferta pendente antiga e a nova mensagem é re-classificavel.
          selector = Skills::Selector.new(registry: registry)
          skill_name = selector.call(content, conversation_id: scope.key)
          if skill_name.present?
            definition = registry.fetch?(skill_name)
            if definition&.create_thread? && conversation.present?
              clear_offered_skill(conversation)
              save_offered_skill(conversation, skill_name, content)
              return offer_response(skill_name, scope, content)
            end
            clear_offered_skill(conversation)
            return resolve_thread(skill_name, definition, event, scope, content)
          end

          # Classified nil: mantém comportamento anterior — descarta e vai embora.
          clear_offered_skill(conversation)
          return { skill_name: nil, scope: scope, content: content }
        end
      end

      def offer_expired?(conversation)
        return false if conversation.offered_at.nil?
        (Time.current - conversation.offered_at) > OFFER_TIMEOUT_MINUTES.minutes
      end

      def clear_offered_skill(conversation)
        conversation.update!(
          offered_skill_name: nil,
          offered_at: nil,
          offered_content: nil  # R5a: limpa também o conteúdo
        )
      end

      def activate_skill(conversation, skill_name)
        conversation.update!(
          active_skill_name: skill_name,
          offered_skill_name: nil,
          offered_at: nil,
          offered_content: nil  # R5a: limpa também o conteúdo
        )
      end

      def build_result(skill_name, event, scope, content)
        definition = Skills::Registry.new.fetch?(skill_name)
        resolve_thread(skill_name, definition, event, scope, content)
      end

      def resolve_thread(skill_name, definition, event, scope, content, custom_key: nil)
        return { skill_name: skill_name, scope: scope, content: content } unless definition&.create_thread?
        return {skill_name: skill_name, scope: scope, content: content, thread_id: scope.channel_id } if event.channel.thread?
        return { skill_name: skill_name, scope: scope, content: content } unless event.channel.respond_to?(:start_thread)

        # R6: chave inclui ID da mensagem/interação para evitar colisão entre
        # mensagens distintas com conteúdo idêntico.
        msg_id = event.message.respond_to?(:id) ? event.message.id : nil
        cache_key = custom_key || "skill_thread:#{scope.key}:#{scope.user_id}:#{msg_id || content.hash}"
        cached_thread_id = Rails.cache.read(cache_key)
        if cached_thread_id
          thread_scope = Discord::SessionScope.for(
            user_id: scope.user_id,
            channel_id: cached_thread_id.to_s,
            open_channel_id: scope.open_channel_id
          )
          return {
            skill_name: skill_name,
            scope: thread_scope,
            content: content,
            thread_id: cached_thread_id.to_s
          }
        end

        # R6: atomicidade — lock global garante que apenas uma thread é criada
        # por mensagem, mesmo sob concorrência.
        @@thread_mutex ||= Mutex.new
        @@thread_mutex.synchronize do
          # Dupla checagem após adquirir o lock
          cached_thread_id = Rails.cache.read(cache_key)
          if cached_thread_id
            thread_scope = Discord::SessionScope.for(
              user_id: scope.user_id,
              channel_id: cached_thread_id.to_s,
              open_channel_id: scope.open_channel_id
            )
            return {
              skill_name: skill_name,
              scope: thread_scope,
              content: content,
              thread_id: cached_thread_id.to_s
            }
          end

          begin
            # Lane B (04/09/2026): nome e visibilidade da thread vêm da definição
            # da skill, não estão hardcoded como "Grill:" ou type: 11.
            thread_name_template = definition&.dig(:discord, :thread_name) || "Skill: %s"
            thread_name = format(thread_name_template, content.to_s)
            # Truncar nome muito longo respeitando o limite do Discord (100 chars)
            thread_name = thread_name[0...100] if thread_name.length > 100
            thread_visibility = definition&.dig(:discord, :thread_visibility) || "public"
            # R7-Item4: rejeitar visibilidade desconhecida
            case thread_visibility.to_s.downcase
            when "private"
              thread_type = 12
            when "public"
              thread_type = 11
            else
              raise Discord::SkillEntrypoint::ThreadVisibilityError,
                    "thread_visibility invalido: #{thread_visibility}. Valores permitidos: public, private"
            end
            thread = event.channel.start_thread(
              thread_name,
              10080,
              type: thread_type
            )
            created_thread_id = thread&.id&.to_s

            Rails.cache.write(cache_key, created_thread_id, expires_in: 1.hour)

            thread_scope = Discord::SessionScope.for(
              user_id: scope.user_id,
              channel_id: created_thread_id,
              open_channel_id: scope.open_channel_id
            )

            {
              skill_name: skill_name,
              scope: thread_scope,
              content: content,
              thread_id: created_thread_id
            }
          rescue Discordrb::Errors::NoPermission
            {
              skill_name: skill_name,
              scope: scope,
              content: content,
              response: "⚠️ Não consegui criar a thread. Tente novamente ou continue aqui."
            }
          rescue ThreadVisibilityError
            # Re-raise para que erro de validação não seja convertido em resposta
            raise
          rescue StandardError => e
            Rails.logger.error "[SkillEntrypoint] Erro ao criar thread: #{e.class.name}: #{e.message}"
            if created_thread_id.present?
              {
                skill_name: skill_name,
                scope: (defined?(thread_scope) && thread_scope) ? thread_scope : scope,
                content: content,
                thread_id: created_thread_id
              }
            else
              {
                skill_name: skill_name,
                scope: scope,
                content: content,
                response: "⚠️ Não consegui criar a thread. Tente novamente ou continue aqui."
              }
            end
          end
        end
      end
    end
  end
end