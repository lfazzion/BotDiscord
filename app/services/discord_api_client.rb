# frozen_string_literal: true

require 'net/http'
require 'json'

class DiscordApiClient
  API_BASE = 'https://discord.com/api/v10'

  class << self
    def get_channel(channel_id)
      response = request(:get, "/channels/#{channel_id}")
      JSON.parse(response.body)
    end

    def create_text_channel(guild_id, name)
      body = { name: name, type: 0 }.to_json
      response = request(:post, "/guilds/#{guild_id}/channels", body)
      JSON.parse(response.body)
    end

    def send_message(channel_id, content)
      body = { content: content }.to_json
      response = request(:post, "/channels/#{channel_id}/messages", body)
      JSON.parse(response.body)
    end

    def get_bot_guilds
      response = request(:get, '/users/@me/guilds')
      JSON.parse(response.body)
    end

    private

    def request(method, path, body = nil)
      uri = URI("#{API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      case method
      when :get
        req = Net::HTTP::Get.new(uri)
      when :post
        req = Net::HTTP::Post.new(uri)
        req.body = body
        req['Content-Type'] = 'application/json'
      end

      req['Authorization'] = "Bot #{ENV['DISCORD_BOT_TOKEN']}"

      response = http.request(req)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error "[DiscordApiClient] Erro #{response.code}: #{response.body}"
        raise "Discord API error: #{response.code} #{response.message}"
      end

      response
    end
  end
end
