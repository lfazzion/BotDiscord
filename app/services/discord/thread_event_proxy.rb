# frozen_string_literal: true

module Discord
  # Proxy simples para eventos de Discord quando a resposta deve ser enviada
  # para uma thread diferente do canal original.
  #
  # Usado pelo DiscordBotService para redirecionar respostas para threads
  # criadas pelo SkillEntrypoint.
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

    def respond(content)
      # Try to get the thread channel and respond there
      if @thread_channel_id.present?
        begin
          thread_channel = @original_event.channel.guild.channels.find { |c| c.id.to_s == @thread_channel_id.to_s }
          if thread_channel
            thread_channel.respond(content)
            return
          end
        rescue StandardError
          # Fall through to original behavior
        end
      end
      @original_event.respond(content)
    end

    # R6: edit_response e send_message devem cair na thread, não no evento original.
    # Sem fallback silencioso: se a thread nao for encontrada, levanta erro.
    def edit_response(content: nil, ephemeral: false)
      unless @thread_channel_id.present?
        raise StandardError, "ThreadEventProxy: channel_id nao informado para edit_response"
      end
      begin
        thread_channel = @original_event.channel.guild.channels.find { |c| c.id.to_s == @thread_channel_id.to_s }
        raise StandardError, "ThreadEventProxy: thread #{@thread_channel_id} nao encontrada" unless thread_channel
        thread_channel.edit_response(content: content, ephemeral: ephemeral)
      rescue StandardError
        # Re-raise sem fallback - nao volta para o original
        raise
      end
    end

    def send_message(content: nil, ephemeral: false)
      unless @thread_channel_id.present?
        raise StandardError, "ThreadEventProxy: channel_id nao informado para send_message"
      end
      begin
        thread_channel = @original_event.channel.guild.channels.find { |c| c.id.to_s == @thread_channel_id.to_s }
        raise StandardError, "ThreadEventProxy: thread #{@thread_channel_id} nao encontrada" unless thread_channel
        thread_channel.send_message(content: content, ephemeral: ephemeral)
      rescue StandardError
        # Re-raise sem fallback - nao volta para o original
        raise
      end
    end

    # Métodos adicionais que podem ser necessários
    def method_missing(method, *args, &block)
      @original_event.send(method, *args, &block)
    end

    def respond_to_missing?(method, include_private = false)
      @original_event.respond_to?(method, include_private) || super
    end
  end
end
