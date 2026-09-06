# frozen_string_literal: true

require_relative "thread_channel_unresolved_error"

module Discord
  # Proxy simples para eventos de Discord quando a resposta deve ser enviada
  # para uma thread diferente do canal original.
  #
  # Usado pelo DiscordBotService para redirecionar respostas para threads
  # criadas pelo SkillEntrypoint.
  #
  # IMPORTANTE — alinhamento com a API REAL da gem discordrb-3.8.0:
  #   - Discordrb::Channel tem send_message(content, tts=false, embed=nil, ...)
  #     (posicional, ver lib/discordrb/data/channel.rb:483). NAO tem respond,
  #     edit_response ou edit_message.
  #   - respond existe como alias de send_message apenas no modulo Respondable
  #     (events/message.rb:94), presente em MessageEvent/MessageIDEvent, nao em
  #     Channel.
  #   - edit_response existe em Interaction (data/interaction.rb:229) e em
  #     InteractionCreateEvent (events/interactions.rb:73-76, delegado), nao em
  #     Channel.
  #
  # Causa-raiz do bug de producao (06/09 03:34 UTC):
  #   respond() chamava thread_channel.respond(content) — Channel NAO tem respond.
  #   => NoMethodError => rescue StandardError silencioso => fallback
  #   @original_event.respond (canal PAI). Corrigido: respond agora usa
  #   thread_channel.send_message(content) (posicional).
  #
  # Decisao de design documentada no teste (thread_event_proxy_test.rb):
  #   - Se a thread channel existe: respond/send_message/edit_response mandam no
  #     thread via Channel#send_message (posicional). Nao ha fallback para o
  #     canal pai.
  #   - Se a thread channel NAO foi encontrada (guild.channels.find nil — possivel
  #     em producao quando o cache do gateway ainda nao refletiu a thread
  #     recem-criada): levanta Discord::ThreadChannelUnresolvedError (erro nomeado)
  #     com log de ERROR. O rescue do handle_message / handle_skill_slash_command
  #     devolve "⚠️ Erro ao processar" ao usuario — melhor que responder no canal
  #     errado (bug original).
  #   - edit_response do proxy NAO edita a mensagem de deferimento da interaction
  #     (que fica no canal pai). Como nao ha message_id da thread para editar,
  #     edit_response do proxy = send_message no thread (nova mensagem). Isso e
  #     intencional: o objetivo e responder NA THREAD, nao no canal pai.
  #   - send_message do proxy mapeia a assinatura keyword (content:, ephemeral:)
  #     para a chamada posicional de Channel#send_message. ephemeral e ignorado
  #     (Channel nao suporta mensagens ephemeral — e um conceito de interaction
  #     response). No uso real (respond_deferred, L655 do bot service), ephemeral
  #     e sempre false, entao nao ha perda de comportamento.

  class ThreadEventProxy
    attr_reader :original_event

    def initialize(event, thread_channel_id)
      @original_event = event
      @thread_channel_id = thread_channel_id
    end

    def user
      @original_event.user
    end

    def channel
      # Lazily fetch the thread channel
      @thread_channel ||= begin
        return @original_event.channel unless @thread_channel_id.present?
        begin
          @original_event.channel.guild.channels.find { |c| c.id.to_s == @thread_channel_id.to_s } ||
            @original_event.channel
        rescue StandardError
          @original_event.channel
        end
      end
    end

    def message
      @original_event.message
    end

    # Responde no canal da thread (se existir). Usa Channel#send_message
    # (posicional) — API real da gem.
    def respond(content)
      if @thread_channel_id.present?
        thread_channel = resolve_thread_channel
        thread_channel.send_message(content)
        return
      end
      @original_event.respond(content)
    end

    # Edit_response do proxy = send_message no thread (nova mensagem).
    # Nao edita a mensagem de deferimento da interaction (que fica no canal pai),
    # pois nao ha message_id da thread para editar.
    def edit_response(content: nil, ephemeral: false)
      unless @thread_channel_id.present?
        raise StandardError, "ThreadEventProxy: channel_id nao informado para edit_response"
      end
      thread_channel = resolve_thread_channel
      thread_channel.send_message(content)
    end

    # Send_message do proxy: mapeia assinatura keyword para Channel#send_message
    # posicional. ephemeral e ignorado (Channel nao suporta mensagens ephemeral).
    def send_message(content: nil, ephemeral: false)
      unless @thread_channel_id.present?
        raise StandardError, "ThreadEventProxy: channel_id nao informado para send_message"
      end
      thread_channel = resolve_thread_channel
      # Channel#send_message(content, tts=false, embed=nil, attachments=nil,
      #   allowed_mentions=nil, message_reference=nil, components=nil, flags=0)
      thread_channel.send_message(content, false, nil, nil, nil, nil, nil, 0)
    end

    # Metodos adicionais que podem ser necessarios — delegam para o evento
    # original (ex.: InteractionCreateEvent delega edit_response/send_message
    # para o interaction subjacente).
    def method_missing(method, *args, &block)
      @original_event.send(method, *args, &block)
    end

    def respond_to_missing?(method, include_private = false)
      @original_event.respond_to?(method, include_private) || super
    end

    private

    # Resolve o canal da thread a partir do thread_channel_id.
    # Leva em conta o cenario de cache do gateway: guild.channels.find pode
    # retornar nil para uma thread recem-criada. Nesse caso, levanta
    # ThreadChannelUnresolvedError (erro nomeado) em vez de fallback
    # silencioso para o canal pai.
    def resolve_thread_channel
      return @original_event.channel unless @thread_channel_id.present?

      thread_channel = @original_event.channel.guild.channels.find do |c|
        c.id.to_s == @thread_channel_id.to_s
      end

      unless thread_channel
        Rails.logger.error(
          "[ThreadEventProxy] thread channel id=#{@thread_channel_id} nao encontrada " \
          "em guild.channels (guild.id=#{@original_event.channel.guild.id}). " \
          "ThreadChannelUnresolvedError instead of silent fallback to parent channel."
        )
        raise Discord::ThreadChannelUnresolvedError.new(@thread_channel_id)
      end

      thread_channel
    end
  end
end
