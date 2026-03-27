# frozen_string_literal: true

module AdminAlertChannel
  extend ActiveSupport::Concern

  CACHED_CHANNEL_KEY = "discord:admin_channel_id"

  private

  def ensure_admin_channel
    channel_id = ENV["DISCORD_ADMIN_CHANNEL_ID"]
    return channel_id if channel_id.present?

    cached = Rails.cache.read(CACHED_CHANNEL_KEY)
    return cached if cached.present?

    guilds = DiscordApiClient.get_bot_guilds
    return nil if guilds.empty?

    guild_id = guilds.first["id"]
    channel = DiscordApiClient.create_text_channel(guild_id, "system-alerts")
    channel_id = channel["id"]

    Rails.cache.write(CACHED_CHANNEL_KEY, channel_id, expires_in: 30.days)
    Rails.logger.info "[#{self.class.name}] Canal admin criado e cacheado: #{channel_id}"
    channel_id
  end
end
