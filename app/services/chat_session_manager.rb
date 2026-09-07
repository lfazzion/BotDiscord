# frozen_string_literal: true

# Cache quente de RubyLLM::Chat por escopo, com a conversa vivendo no SQLite.
#
# O TTL não encerra mais conversa: ele só despeja o objeto da memória. A
# fronteira entre conversas é o /new. Em cache miss a conversa é reidratada do
# banco, então reiniciar o container não perde nada.
#
# RubyLLM::Chat guarda estado mutável de mensagens e não é thread-safe. No canal
# compartilhado duas pessoas podem falar ao mesmo tempo no MESMO objeto, então
# toda chamada roda dentro do mutex daquele escopo.
#
# Dois mutexes, dois donos: o de ESCOPO (`with_scope_lock`) serializa quem mexe
# num RubyLLM::Chat específico. O GLOBAL (`mutex`) é o único autorizado a tocar
# os Hashes `sessions_cache` e `mutexes`, que hospedam TODOS os escopos — o de
# escopo não protege Hash nenhum. Ordem de aquisição fixa para nunca formar
# ciclo: quem já segura o de escopo pode pedir o global (em blocos curtos, só
# para tocar os Hashes), mas nenhum caminho faz o inverso — segurar o global e
# pedir um de escopo.
class ChatSessionManager
  TTL_MINUTES = 30
  BLANK_RESPONSE_WARNING = "⚠️ O modelo não respondeu dessa vez. Tenta perguntar de novo?"

  # Tudo que faz um elo cair, e NÃO só `RubyLLM::Error`.
  #
  # `ConfigurationError` (chave ausente na config da gem) e `ModelNotFoundError`
  # (id fora do registry) descendem direto de `StandardError`, não de
  # `RubyLLM::Error` — verificado nos `ancestors` da gem 1.14.0. São exatamente
  # os dois erros que provedor novo e modelo novo produzem. `Faraday::Error`
  # cobre timeout, DNS e conexão recusada, que também escapam do `RubyLLM::Error`
  # e que, numa cadeia de três hosts diferentes, são o caso comum.
  #
  # Listar classe-mãe em vez de subclasses é a lição de 2026-08-06 registrada em
  # docs/MEMORY.md: `rescue` por lista de permissão, e o caso não previsto é
  # exatamente o que fura a rede de proteção.
  CHAIN_ERRORS = [
    RubyLLM::Error,
    RubyLLM::ConfigurationError,
    RubyLLM::ModelNotFoundError,
    Faraday::Error
  ].freeze

  # Snapshot da cadeia de um turno. Tirado UMA vez no início de `ask` (dentro do
  # lock de escopo) e passado para prepare_chat/ask_through_chain/touch_session,
  # para que um YAML que mude NO MEIO do turno não misture o chat do elo A com a
  # assinatura/elo B (Sol R1-A, achado 2). `links` relê o YAML a cada chamada;
  # fixar o snapshot impede essa re-leitura pontual.
  TurnLinks = Struct.new(:links, :primary, keyword_init: true)

  # Dois limites distintos, e não um. PAGE_SIZE é quantas linhas cabem numa
  # mensagem do Discord (cada linha tem ~80 chars, 20 cabem sem quebrar).
  # SESSIONS_MAX é só guarda de memória para a consulta não crescer sem limite —
  # não é limite de uso.
  DEFAULT_PAGE_SIZE = 20
  MAX_PAGE_SIZE = 100
  DEFAULT_SESSIONS_MAX = 500

  Page = Struct.new(:conversations, :first_index, :number, :total_pages, :total, keyword_init: true)
  Apagada = Struct.new(:title, :message_count, keyword_init: true)

  class << self
    # Skill System v2 (Tarefa 7): `requested_skill:` é resolvido e persistido
    # DENTRO do `with_scope_lock` (mesmo lock que serializa o turno) — se
    # outro turno concorrente resolvesse a skill fora daqui, o cache quente
    # poderia ser armado com prompt/tools antigos antes de o `ask` terminar de
    # montar o seu. Default nil = chat normal preservado.
    def ask(scope:, content:, user_id:, username:, requested_skill: nil)
      with_scope_lock(scope.key) do
        Thread.current[:cleitin_actor] = { user_id: user_id, username: username }
        Thread.current[:cleitin_turn] = SecureRandom.hex(8)
        # F3b (30/08/2026): o `ask` é o ÚNICO entrypoint do bot que executa
        # tools via RubyLLM. Setar `:cleitin_origin = :discord` aqui cobre
        # TODA chamada que o bot fizer (web_search e qualquer outra que
        # passe pelo mesmo `Thread.current`). Chave distinta de `:cleitin_actor`
        # (que é hash de auditoria/ACL) para não conflitar com a checagem
        # existente em `profile_management_tools.rb:17`.
        Thread.current[:cleitin_origin] = :discord
        # F5a (30/08/2026): o `WebSearchTool` precisa do scope.key da conversa
        # ativa para isolar o contador de buscas pagas por turno/escopo. Esse
        # scope mora no `ChatSessionManager`, não chega à tool via parâmetros
        # — gravamos aqui (dentro do lock de escopo) e limpamos no ensure.
        # O teto de buscas pagas vale para Discord e MCP (MCP não pula mais).
        Thread.current[:cleitin_conversation_scope_key] = scope.key
        SearchApiRouter.reset_paid_search_count!(scope.key)
        # L1-R1C: zera jitter/backoff acumulados do SearXNG no início do turno —
        # sem isto o cooldown de um turno anterior vazava para o próximo.
        WebSearchTool.reset_searxng_turn_state!(scope.key)
        inicio = Time.now
        Rails.logger.info "[ChatSessionManager] Iniciando ask — " \
                          "scope=#{scope.key} user=#{user_id} " \
                          "chars=#{content.to_s.length} requested_skill=#{requested_skill.inspect}"
        begin
          conversation = conversation_for(scope)

          # R7-Item5 / R8-Item3a / R8-Item3b: capturar skill anterior antes de possivel troca
          previous_skill_name = conversation.active_skill_name

          # Resolver a skill DEFINITIVA deste turno DENTRO do lock. A Lane D
          # entrega `Skills::Registry.fetch?` (nil para nome desconhecido). A
          # persistência também é aqui: se o turno cair, a conversa fica com
          # a skill persistida (próximo turno reidrata a partir dela).
          # Pedido explícito de um nome desconhecido NÃO trava o turno — cai
          # em chat normal, mesmo padrão do `Selector` (fail-closed).
          active_skill_name = resolve_and_persist_active_skill(
            conversation: conversation, requested_skill: requested_skill
          )
          definition = active_skill_name ? Skills::Registry.fetch?(active_skill_name) : nil

          # Snapshot ÚNICO da cadeia deste turno (Sol R1-A, achado 2): tirado uma
          # vez aqui, dentro do lock de escopo, e passado para baixo. Se o YAML
          # mudar no meio do turno, prepare_chat/ask_through_chain/touch_session
          # continuam usando ESTE snapshot — o chat do elo A nunca é rotulado com
          # a assinatura/elo B.
          links = Llm::ModelChain.links
          turn = TurnLinks.new(
            links: links,
            primary: links.first
          )

          chat = prepare_chat(scope, conversation, turn, skill: definition)
          texto = ask_through_chain(chat, outgoing_content(conversation, content, username),
                                    scope: scope, conversation: conversation, turn: turn,
                                    skill: definition)

          if texto.blank?
            Rails.logger.info "[ChatSessionManager] ask concluído em #{format("%.1f", (Time.now - inicio))}s chars=#{texto.to_s.length}"
            next handle_blank_response(scope, conversation, previous_skill_name: previous_skill_name)
          end

          # Título e mensagens só são persistidos DEPOIS da resposta — ver
          # outgoing_content — e em transação. O título antes da resposta gravava
          # uma pergunta que não existe quando a cadeia vinha em branco ou
          # estourava; e três escritas soltas deixavam `user` órfão se a segunda
          # falhasse (ex.: SQLITE_BUSY). O rescue despeja o cache quente: sem o
          # despejo, a próxima reidratação leria do banco a pergunta sem resposta
          # e duplicaria a fala do usuário.
          begin
            ActiveRecord::Base.transaction do
              conversation.assign_title_from(content)
              ChatMessage.create!(conversation: conversation, role: "user", content: content,
                                  discord_user_id: user_id, discord_username: username)
              ChatMessage.create!(conversation: conversation, role: "assistant", content: texto)
              conversation.touch_activity!
            end
          rescue StandardError => e
            Rails.logger.error "[ChatSessionManager] Falha ao persistir o turno " \
                               "(#{e.class.name}: #{e.message}) — despejando cache quente"
            evict(scope.key)
            raise
          end
          Rails.logger.info "[ChatSessionManager] ask concluído em #{format("%.1f", (Time.now - inicio))}s chars=#{texto.to_s.length}"
          texto
        rescue StandardError => e
          # R7-Item5 / R8-Item3a: em exceção, SEMPRE restaura para o estado
          # anterior (mesmo quando era nil). Se não fizermos rollback, a
          # skill nova persistiria no banco mesmo após falha do turno.
          # update_columns pula validações — a skill já foi validada quando
          # foi gravada pela primeira vez; usar update! faria a restauração
          # falhar se o registry estiver indisponível no momento do rescue.
          conversation&.update_columns(active_skill_name: previous_skill_name)
          raise
        ensure
          Thread.current[:cleitin_actor] = nil
          Thread.current[:cleitin_turn] = nil
          Thread.current[:cleitin_origin] = nil
          # F5a: limpar a scope key do Thread.current no fim do turno. Sem isso,
          # uma próxima thread Puma que pegue este mesmo slot (a `Thread.current`
          # é por-thread, mas o ensure roda sempre) leria a chave residual. Aqui
          # a chave é por-turno do bot, então no fim do `ask` ela some — mesmo
          # padrão defensivo das outras chaves.
          Thread.current[:cleitin_conversation_scope_key] = nil
          SearchApiRouter.reset_paid_search_count!(scope.key)
          WebSearchTool.reset_searxng_turn_state!(scope.key)
        end
      end
    end

    def reset!(scope)
      with_scope_lock(scope.key) do
        Conversation.active_for(scope.key)&.close!
        evict(scope.key)
        nil
      end
    end

    def page_size
      configured = ENV["DISCORD_SESSIONS_PAGE_SIZE"].to_i
      return DEFAULT_PAGE_SIZE unless configured.positive?

      [[configured, 1].max, MAX_PAGE_SIZE].min
    end

    def sessions_max
      configured = ENV["DISCORD_SESSIONS_MAX"].to_i
      configured.positive? ? configured : DEFAULT_SESSIONS_MAX
    end

    # Lista ordenada INTEIRA (até o teto de memória). Quem fatia é `page`. Isso é
    # o que permite numeração contínua: o índice 25 é o índice 25 da lista toda,
    # independentemente de qual página está na tela.
    #
    # `left_joins` + `group` carregam a contagem de mensagens NA MESMA consulta
    # (msg_count) — antes, cada linha da listagem disparava um COUNT separado
    # (N+1) no renderizador. Bônus da troca por left_joins: conversas sem
    # mensagem aparecem com 0, em vez de sumirem da lista.
    def sessions(scope)
      Conversation.where(scope: scope.key)
                  .left_joins(:chat_messages)
                  .group(:id)
                  .select("conversations.*, COUNT(chat_messages.id) AS msg_count")
                  .recent.limit(sessions_max).to_a
    end

    # Total de conversas visíveis na listagem (respeitando o teto de memória).
    # É um COUNT barato: nos caminhos de erro o bot usa isto em vez de
    # reexecutar `sessions` inteira só para saber o tamanho da lista.
    def sessions_total(scope)
      [Conversation.where(scope: scope.key).count, sessions_max].min
    end

    # nil quando a página pedida não existe. Lista vazia devolve página 1 vazia,
    # não nil — "não há conversas" e "essa página não existe" são erros
    # diferentes e merecem textos diferentes.
    def page(scope, numero = 1)
      todas = sessions(scope)
      total_paginas = [(todas.size / page_size.to_f).ceil, 1].max
      pedida = numero.to_i
      pedida = 1 if pedida < 1
      return nil if pedida > total_paginas

      inicio = (pedida - 1) * page_size
      Page.new(conversations: todas[inicio, page_size] || [], first_index: inicio + 1,
               number: pedida, total_pages: total_paginas, total: todas.size)
    end

    # Devolve a Conversation retomada, ou :fora_da_faixa. Nunca clampa: quem pede
    # a conversa 99 numa lista de 5 tem que ver "não existe conversa 99", e não a
    # quinta conversa fingindo ser a nonagésima nona.
    #
    # Exceção: lista vazia devolve nil, não :fora_da_faixa. Isso preserva o
    # contrato do teste pré-existente "resume! devolve nil para índice fora da
    # lista" (bloqueador de revisão anterior, intocável) — a lista vazia é o
    # único caso em que os dois comportamentos coexistem sem colidir, porque os
    # testes novos de :fora_da_faixa sempre partem de uma lista não-vazia.
    def resume!(scope, index)
      with_scope_lock(scope.key) do
        lista = sessions(scope)
        alvo = at_index(lista, index)
        next (lista.empty? ? nil : :fora_da_faixa) if alvo.nil?

        Conversation.where(scope: scope.key, active: true).where.not(id: alvo.id)
                    .find_each(&:close!)
        alvo.update!(active: true, last_active_at: Time.current)
        evict(scope.key)
        alvo
      end
    end

    # Apaga de verdade: a conversa e as mensagens saem do banco (dependent: :destroy,
    # em transação). Sem lixeira e sem desfazer — o motivo de existir o comando é
    # não deixar registro. Recusa a conversa em andamento: apagá-la exigiria
    # despejar o cache quente e reabrir conversa, e o dono preferiu obrigar o /new
    # antes, que é um gesto que ele já conhece.
    def destroy!(scope, index)
      with_scope_lock(scope.key) do
        lista = sessions(scope)
        next :lista_vazia if lista.empty?

        alvo = at_index(lista, index)
        next :fora_da_faixa if alvo.nil?
        next :em_andamento if alvo.active

        resultado = Apagada.new(title: alvo.title, message_count: alvo.msg_count)
        alvo.destroy!
        resultado
      end
    end

    # TODA leitura/escrita de sessions_cache (e de mutexes) passa pelo mutex
    # GLOBAL — nunca pelo de escopo, que protege outra coisa (o objeto Chat).
    def cleanup_expired
      mutex.synchronize do
        sessions_cache.delete_if { |_key, session| session[:expires_at] < Time.current }
      end
      Rails.logger.info "[ChatSessionManager] Cleanup concluído. Sessões ativas: #{sessions_cache.size}"
    end

    def evict(scope_key)
      mutex.synchronize { sessions_cache.delete(scope_key) }
    end

    # Um chat novo amarrado a UM elo. O ajuste de raciocínio entra aqui e é
    # grudento no objeto: por isso um chat construído para um elo nunca é
    # reaproveitado em outro.
    #
    # `link:` é obrigatório de propósito: os dois chamadores de produção já
    # passam um `Link` explícito, e o valor-padrão antigo (`Llm::ModelChain.primary`)
    # é `nil` sem chave nenhuma configurada — `link.model` nesse caso levanta
    # `NoMethodError`, que NÃO está em `CHAIN_ERRORS` e derrubaria o turno em
    # vez de cair para o elo seguinte (ou, sem elo nenhum, mostrar o aviso).
    #
    # Skill System v2 (Tarefa 7): `skill:` é a definição ativa resolvida no
    # `ask` (Lane C). Quando presente: o fragmento vai como `skill:` no
    # `PromptLoader.load`, e as tools passam pelo `Skills::ToolPolicy` antes
    # de `chat.with_tool` (invariante 8 do plano: tools proibidas não são
    # apenas desencorajadas pelo prompt — não são anexadas).
    def build_chat(link:, skill: nil)
      chat = RubyLLM.chat(model: link.model, provider: link.provider)
      chat.with_thinking(effort: link.effort) if link.effort.present?
      chat.with_params(**link.params) if link.params.present?
      policy = build_tool_policy(definition: skill, base_tools: all_tool_classes)
      policy.allowed_tools.each { |tool_class| chat.with_tool(tool_class) }
      # Note: skill fragment is added by ConversationRehydrator.apply!, not here
      # to avoid duplication. PromptLoader.load is called without skill param.
      prompt = Llm::PromptLoader.load("chatbot", user_message: "")
      chat.with_instructions("#{prompt[:system]}\n\n#{model_identity(link)}")
      chat
    end

    # Skill System v2 (Tarefa 7): `Skills::ToolPolicy` é da Lane D (Tarefa 2).
    # Lane D entregou (tool_policy_test verde). Stub removido — chamado real.
    def build_tool_policy(definition:, base_tools:)
      Skills::ToolPolicy.new(definition: definition, base_tools: base_tools)
    end

    # O modelo não sabe qual modelo ele é, e quando perguntado ele INVENTA com
    # confiança: em 08/08/2026, atendido pelo `poolside/laguna-s-2.1`, o bot
    # respondeu que estava usando "openrouter/mistral-small-3.1-8x22b" — um id
    # que nem existe (`mistral-small` e `8x22B` são modelos diferentes) — e ainda
    # elogiou o Mistral.
    #
    # Não dá para cravar no YAML do prompt: o elo em uso muda em tempo de
    # execução (queda do primário, chave ausente), então a única fonte de verdade
    # é o `link` que está montando ESTE chat. Chega aqui pelo mesmo caminho que o
    # timestamp — injetado no prompt, não deduzido pelo modelo.
    def model_identity(link)
      "<modelo_em_uso: #{link.model}>\n<rota_em_uso: #{link.label}>\n" \
        "Se perguntarem qual modelo ou qual IA você usa, responda exatamente o que está acima. " \
        "NUNCA adivinhe nem invente nome de modelo, e não diga que é de outro fornecedor."
    end

    private

    # Índice de 1 em diante, sem clamp. Fora da faixa devolve nil, e cada chamador
    # transforma isso na mensagem certa com o tamanho real da lista na tela.
    def at_index(lista, index)
      posicao = index.to_i
      # O teto contra `lista.size` não é otimização: sem o clamp, o índice chega
      # cru e sem limite de dígitos, e `lista[bignum]` levanta RangeError ("bignum
      # too big to convert into 'long'). Isso virava "⚠️ Erro ao processar" em vez
      # da resposta educada com o intervalo real — o buraco que tirar o clamp abriu.
      return nil unless posicao.positive? && posicao <= lista.size

      lista[posicao - 1]
    end

    def conversation_for(scope)
      Conversation.active_for(scope.key) || open_conversation(scope)
    end

    def open_conversation(scope)
      Conversation.open_for(scope: scope.key, channel_id: scope.channel_id,
                            user_id: scope.user_id, shared: scope.shared)
    end

    # Compacta se precisar e devolve o chat quente do escopo, ou nil em cache
    # miss. NÃO constrói o chat: quem constrói é a cadeia, dentro do `rescue`,
    # porque `RubyLLM.chat` pode levantar `ConfigurationError` ou
    # `ModelNotFoundError` e essas quedas têm de cair para o elo seguinte em vez
    # de derrubar o turno.
    #
    # `turn` é o snapshot da cadeia deste turno (Sol R1-A, achado 2); a assinatura
    # de invalidação é derivada do primary do snapshot, NÃO de uma re-leitura do
    # YAML.
    #
    # Skill System v2 (Tarefa 7): a assinatura do cache quente agora inclui
    # [primary, skill_name, skill_digest]. Trocar a definição no YAML, mudar
    # de skill ou desativar o modo invalida o chat sem esperar o TTL de 30 min
    # (invariante 7 do plano).
    def prepare_chat(scope, conversation, turn, skill: nil)
      primary = turn.primary
      if primary && ConversationCompactor.needs_compaction?(conversation, model_id: primary.model,
                                                                       provider: primary.provider)
        compactou = ConversationCompactor.compact!(conversation, model_id: primary.model,
                                                                 provider: primary.provider)
        evict(scope.key) if compactou
      end

      cached = cache_read(scope.key)
      return nil unless cached && cached[:expires_at] > Time.current

      # Invalidação por assinatura (29/08): trocar o YAML de cadeia NÃO trocaria
      # o modelo em sessões já aquecidas (o cache dura 30 min e guardava só chat +
      # expires_at) — violando "troca vale imediatamente sem restart". A assinatura
      # do primary (provider, model, effort, params) é comparada com a config
      # atual; divergência => descarta o objeto quente (a conversa está no banco,
      # só o chat é reidratado no próximo turno). Não toca em mais nada.
      cached_assinatura_primary = cached[:assinatura_primary]
      atual_assinatura_primary = primary_signature(primary)
      if cached_assinatura_primary != atual_assinatura_primary
        Rails.logger.info "[ChatSessionManager] primary mudou (#{cached_assinatura_primary.inspect} -> " \
                          "#{atual_assinatura_primary.inspect}) — descartando chat quente para reidratar"
        evict(scope.key)
        return nil
      end

      # Skill System v2 (Tarefa 7): mesma lógica para a skill. A Lane C NÃO usa
      # Thread.current para guardar o modo: a fonte durável é o
      # `conversation.active_skill_name` (Tarefa 6). Em cache miss (turno
      # seguinte, restart), o `ask` resolve a skill da conversa persistida, e o
      # `prepare_chat` recebe esse resultado via `skill:`. Comparação aqui:
      # [nome, digest] do cache vs do turno — divergência => descarta.
      atual_assinatura_skill = skill_signature(skill)
      cached_assinatura_skill = cached[:assinatura_skill]
      if cached_assinatura_skill != atual_assinatura_skill
        Rails.logger.info "[ChatSessionManager] skill mudou (#{cached_assinatura_skill.inspect} -> " \
                          "#{atual_assinatura_skill.inspect}) — descartando chat quente para reidratar"
        evict(scope.key)
        return nil
      end

      cached[:chat]
    end

    # Assinatura do elo primário informado: suficiente para detectar troca de
    # modelo, rota ou params (ex.: as tags do Nous). nil quando não há primary.
    # Recebe o link explícito (do snapshot do turno) e NÃO relê o YAML.
    def primary_signature(primary)
      return nil if primary.nil?

      [primary.provider, primary.model, primary.effort, primary.params].freeze
    end

    # Skill System v2 (Tarefa 7): assinatura da skill ativa. Mesmo padrão de
    # `primary_signature`: nil quando não há skill, e [nome, digest] quando
    # há. O `digest` é o da `Skills::Definition` (Lane D) — recálculo a cada
    # chamada aqui é seguro porque o Definition memoiza.
    def skill_signature(definition)
      return nil if definition.nil?

      [definition.name, definition.digest].freeze
    end

    def touch_session(scope_key, chat, turn, skill: nil)
      primary = turn.primary
      mutex.synchronize do
        sessions_cache[scope_key] = {
          chat: chat,
          expires_at: Time.current + TTL_MINUTES.minutes,
          # Assinatura do primary do snapshot deste turno — usada por prepare_chat
          # para detectar troca de cadeia sem esperar o TTL. Veio do snapshot, não
          # de re-leitura do YAML (Sol R1-A, achado 2).
          assinatura_primary: primary_signature(primary),
          # Skill System v2 (Tarefa 7): assinatura da skill ativa deste turno.
          # Permite a `prepare_chat` descartar o cache quente quando o YAML
          # muda, quando o usuário troca de modo, ou quando o modo é desativado.
          assinatura_skill: skill_signature(skill)
        }
      end
      chat
    end

    # Resolve a skill deste turno e a persiste na conversa, DENTRO do lock.
    # Quem resolve é `Skills::Registry.fetch?` (Lane D). Pedido explícito de
    # nome desconhecido => fica como está (chat normal); o turno NÃO aborta.
    # A persistência atualiza `active_skill_name` mesmo quando o valor NÃO
    # muda — só se precisar — para manter uma única fonte de verdade da decisão.
    def resolve_and_persist_active_skill(conversation:, requested_skill:)
      # Modo já ativo E sem pedido novo: mantém. (O `Selector` daLane D pode
      # ter escolhido autonomamente antes do `ask` e gravado na conversa;
      # quando o usuário chega no `ask` sem requested_skill, a decisão já está
      # tomada.)
      if requested_skill.nil? && conversation.active_skill_name.present?
        return conversation.active_skill_name
      end

      # Pedido explícito: valida no registry antes de aceitar. Sem requested_skill => nil (chat normal / exit do modo)
      novo = if requested_skill.nil?
               nil
             else
               Skills::Registry.fetch?(requested_skill) ? requested_skill.to_s : nil
             end

      # Persiste só quando muda — em rede de hot-path, evita UPDATE desnecessário.
      if conversation.active_skill_name != novo
        conversation.update!(active_skill_name: novo)
      end

      novo
    end

    def cache_read(scope_key)
      mutex.synchronize { sessions_cache[scope_key] }
    end

    # A fala deste turno só é persistida DEPOIS que a resposta chega (ver #ask):
    # persistir antes duplicava a pergunta no modelo — em cache miss a
    # reidratação lê `live_messages` do banco e a injeta via add_message, e o
    # chat.ask logo em seguida mandava a MESMA fala de novo. Aqui só formata o
    # texto deste turno para o chat quente, que ainda não o tem — carimbo de
    # autor quando a sala é compartilhada, com o nome saneado contra
    # personificação do papel `<autor>:` (reusa o sanitizador do ChatMessage,
    # que é quem já resolve esse problema para as falas persistidas).
    def outgoing_content(conversation, content, username)
      return content unless conversation.shared && username.present?

      "#{sanitized_username(username)}: #{content}"
    end

    # Reusa o reader público de ChatMessage — que já sabe neutralizar controle,
    # `:`, tamanho e nomes reservados (assistente, system...) — em vez de copiar
    # a lista de nomes reservados aqui. A instância não é salva; existe só para
    # emprestar o método.
    def sanitized_username(raw_username)
      ChatMessage.new(discord_username: raw_username).discord_username
    end

    # Percorre a cadeia inteira, em ordem, até alguém responder.
    #
    # O primeiro elo reaproveita o chat quente quando existe. Todo elo seguinte
    # reconstrói do banco — nunca do objeto que acabou de falhar, que já está
    # sujo (a gem chamou `add_message role: :user` antes de estourar e, no meio
    # de tool calls, pode ter deixado um assistant(tool_calls) sem resultado
    # casado).
    #
    # Resposta em branco NÃO é "cadeia esgotada": é rotina em modelo free (ver
    # `handle_blank_response`) e é tratada como falha DAQUELE elo, igual a uma
    # exceção — segue para o próximo. Só devolve nil (branco) quando TODOS os
    # elos vierem em branco, e quem chama (`ask`) já sabe transformar nil em
    # `BLANK_RESPONSE_WARNING`.
    def ask_through_chain(quente, content, scope:, conversation:, turn:, skill: nil)
      links = turn.links
      if links.empty?
        Rails.logger.error "[ChatSessionManager] Nenhum elo de LLM disponível — " \
                           "nenhuma chave configurada (POOLSESIDE_API_KEY, NOUS_API_KEY, OPENROUTER_API_KEY)"
        return nil
      end

      ultimo = links.size - 1

      links.each_with_index do |link, indice|
        # A construção mora DENTRO do rescue de propósito: `RubyLLM.chat` resolve
        # provedor e modelo, e é aí que nascem ConfigurationError e
        # ModelNotFoundError.
        atual = if indice.zero? && quente
                  quente
                else
                  ConversationRehydrator.apply!(build_chat(link: link, skill: skill), conversation.reload,
                                                skill: skill)
                end

        texto = extract(atual.ask(content))

        if texto.blank?
          proximo = indice < ultimo ? ", tentando #{links[indice + 1].label}..." : " — cadeia esgotada"
          Rails.logger.warn "[ChatSessionManager] Elo #{link.label} devolveu resposta em branco#{proximo}"
          evict(scope.key)
          next
        end

        Rails.logger.info "[ChatSessionManager] Respondido por #{link.label}"
        # Só o elo primário volta para o cache. O objeto de um elo secundário
        # carrega o esforço daquele elo, e `with_model` não desfaz
        # `with_thinking`/`with_params` — guardá-lo levaria a configuração errada
        # para o turno seguinte, em silêncio. O preço é uma reidratação a mais.
        touch_session(scope.key, atual, turn, skill: skill) if indice.zero?
        return texto
      rescue *CHAIN_ERRORS => e
        proximo = indice < ultimo ? ", tentando #{links[indice + 1].label}..." : " — cadeia esgotada"
        Rails.logger.warn "[ChatSessionManager] Elo #{link.label} falhou " \
                          "(#{e.class.name}: #{e.message})#{proximo}"
        evict(scope.key)
        raise if indice == ultimo
      rescue StandardError => e
        # Erro que NÃO é falha de rota (ex.: exceção de tool subindo por dentro
        # de `atual.ask` — ActiveRecord::StatementInvalid, timeout de banco...)
        # não é motivo para tentar o elo seguinte: é motivo para abortar o
        # turno JÁ. Sem este rescue, o objeto que acabou de falhar (com uma
        # fala `user` pendurada, e possivelmente um `assistant(tool_calls)` sem
        # resultado casado) escapava do `rescue *CHAIN_ERRORS` — que só cobre a
        # lista de falha de ROTA — e sobrevivia os 30 min de TTL no cache
        # quente, fazendo todo turno seguinte reenviar a pergunta órfã ao
        # modelo.
        Rails.logger.error "[ChatSessionManager] Elo #{link.label} levantou erro fora de CHAIN_ERRORS " \
                          "(#{e.class.name}: #{e.message}) — abortando o turno e limpando o cache"
        evict(scope.key)
        raise
      end

      nil
    end

    # Resposta vazia é rotina em modelo free, não exceção. ChatMessage exige
    # content presente, então isto nunca vira registro — e o chat quente já tem a
    # troca (o gem faz add_message da resposta em branco por dentro), então
    # despeja para não divergir do banco: a próxima leitura reidrata sem este
    # turno, em vez de arriscar dois `user` consecutivos numa reidratação futura.
    #
    # Além disso, se havia uma skill ativa no início do turno, ela é restaurada
    # para evitar modo parcial (skill persistida mas sem mensagens válidas).
    # R8-Item3b: recebe `previous_skill_name` para restaurar o estado correto.
    def handle_blank_response(scope, conversation = nil, previous_skill_name: nil)
      evict(scope.key)
      if conversation
        conversation.update!(active_skill_name: previous_skill_name)
      end
      BLANK_RESPONSE_WARNING
    end

    def extract(response)
      response.respond_to?(:content) ? response.content.to_s : response.to_s
    end

    # `mutexes` nunca é podado: mutexes de escopo nascem e ficam. O vazamento é
    # limitado ao número de escopos (canais/usuários), e o custo de mantê-los é
    # menor que a janela de corrida que a poda abria — removê-los sob o global
    # deixava um buraco entre a revalidação abaixo e o `synchronize`, quando
    # outra thread podia deletar o mutex e criar um novo, e duas threads
    # sincronizariam em mutexes DIFERENTES para o MESMO escopo, mutando o mesmo
    # RubyLLM::Chat em paralelo. A revalidação de identidade sob o global ANTES
    # de travar permanece como rede de segurança: se o mutex registrado já não
    # é o que pegamos, recomeça com o atual.
    def with_scope_lock(scope_key, &block)
      loop do
        m = scope_mutex(scope_key)
        return m.synchronize(&block) if mutex.synchronize { mutexes[scope_key].equal?(m) }
      end
    end

    def scope_mutex(scope_key)
      mutex.synchronize { mutexes[scope_key] ||= Mutex.new }
    end

    def sessions_cache
      @sessions ||= {}
    end

    def mutexes
      @mutexes ||= {}
    end

    def mutex
      @mutex ||= Mutex.new
    end

    def all_tool_classes
      tools = [
        ProfileLookupTool, ProfileListTool, ProfileSearchTool, ProfileCompareTool,
        AddProfileTool, SetProfileMonitoringTool, RemoveProfileTool, PromoteProspectTool,
        RecentPostsTool, TopPostsTool, PostsByTypeTool, PostEngagementTool,
        EngagementRateTool, SnapshotTrendTool, ProfileRankingTool,
        ProspectsTool, UnclassifiedProfilesTool,
        UpcomingCatalogTool, PopularCatalogTool,
        UpcomingEventsTool, RecentArticlesTool,
        WebSearchTool, PlatformSearchTool,
        TopicAddTool, TopicListTool, TopicRemoveTool,
        CreateSentimentTargetTool, RunSentimentAnalysisTool, SentimentStatusTool
      ]
      tools << PageFetchTool if ENV["ENABLE_PAGE_FETCH"].to_s.downcase == "true"
      tools
    end
  end
end
