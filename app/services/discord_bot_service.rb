# frozen_string_literal: true

require 'discordrb'

class DiscordBotService
  class << self
    def start
      bot = Discordrb::Bot.new(
        token: ENV['DISCORD_BOT_TOKEN'],
        intents: %i[messages message_content]
      )

      bot.message(content: /./) do |event|
        next unless event.channel.private?

        handle_message(event)
      end

      bot.mention do |event|
        handle_message(event)
      end

      Thread.new do
        loop do
          sleep 300
          ChatSessionManager.cleanup_expired
        end
      end

      Rails.logger.info '[DiscordBotService] Iniciando bot...'
      bot.run
    end

    def handle_message(event)
      user_id = event.user.id.to_s
      channel_id = event.channel.id.to_s
      content = event.message.content.to_s.strip

      return if content.empty?

      typing_thread = Thread.new do
        loop do
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
      rescue Llm::BaseClient::QuotaExceededError
        event.respond('⚠️ Sistema sobrecarregado. Tente mais tarde.')
      rescue StandardError => e
        Rails.logger.error "[DiscordBotService] Erro: #{e.message}"
        event.respond('⚠️ Erro ao processar. Tente novamente.')
      ensure
        typing_thread&.kill
      end
    end
  end
end
