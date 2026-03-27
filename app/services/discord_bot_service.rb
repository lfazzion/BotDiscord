# frozen_string_literal: true

require 'discordrb'
require 'concurrent'

class DiscordBotService
  class << self
    def start
      @running = Concurrent::AtomicBoolean.new(true)

      bot = Discordrb::Bot.new(
        token: ENV['DISCORD_BOT_TOKEN'],
        intents: %i[servers server_messages direct_messages message_content]
      )

      bot.message(content: /./) do |event|
        next unless event.channel.private?

        handle_message(event)
      end

      bot.mention do |event|
        handle_message(event)
      end

      cleanup_thread = Thread.new do
        while @running.true?
          sleep 300
          ChatSessionManager.cleanup_expired
        end
      end

      Signal.trap('TERM') do
        Rails.logger.info '[DiscordBotService] Recebido TERM, parando...'
        @running.make_false
        bot.stop
      end

      Signal.trap('INT') do
        Rails.logger.info '[DiscordBotService] Recebido INT, parando...'
        @running.make_false
        bot.stop
      end

      Rails.logger.info '[DiscordBotService] Iniciando bot...'
      bot.run
    ensure
      @running&.make_false
      cleanup_thread&.join(5)
    end

    def handle_message(event)
      user_id = event.user.id.to_s
      channel_id = event.channel.id.to_s
      content = event.message.content.to_s
                        .gsub(/<@!?\d+>/, '')   # Remove menções <@123> ou <@!123>
                        .gsub(/\s+/, ' ')        # Colapsa espaços extras
                        .strip

      return if content.empty?

      typing_running = Concurrent::AtomicBoolean.new(true)
      typing_thread = Thread.new do
        while typing_running.true?
          event.channel.start_typing
          sleep 4
        end
      end

      begin
        chat = ChatSessionManager.get_or_create(user_id, channel_id)
        response = chat.ask(content)

        response_text = response.respond_to?(:content) ? response.content : response.to_s

        if response_text.length > 2000
          chunks = Discordrb.split_message(response_text)
          chunks.each { |chunk| event.respond(chunk) }
        else
          event.respond(response_text)
        end
      rescue RubyLLM::ContextLengthExceededError, RubyLLM::RateLimitError,
             RubyLLM::PaymentRequiredError, RubyLLM::OverloadedError => e
        Rails.logger.warn "[DiscordBotService] Modelo primário falhou (#{e.class.name}), tentando fallback..."
        begin
          fallback_chat = ChatSessionManager.create_fallback_chat
          response = fallback_chat.ask(content)
          response_text = response.respond_to?(:content) ? response.content : response.to_s

          if response_text.length > 2000
            chunks = Discordrb.split_message(response_text)
            chunks.each { |chunk| event.respond(chunk) }
          else
            event.respond(response_text)
          end
        rescue StandardError => fallback_error
          Rails.logger.error "[DiscordBotService] Fallback também falhou: #{fallback_error.message}"
          event.respond('⚠️ Sistema sobrecarregado. Tente mais tarde.')
        end
      rescue StandardError => e
        Rails.logger.error "[DiscordBotService] Erro: #{e.class.name} - #{e.message}"
        event.respond('⚠️ Erro ao processar. Tente novamente.')
      ensure
        typing_running.make_false
        typing_thread&.join(1)
      end
    end
  end
end
