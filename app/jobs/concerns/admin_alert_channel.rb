# frozen_string_literal: true

module AdminAlertChannel
  extend ActiveSupport::Concern

  private

  def ensure_admin_channel
    channel_id = ENV["DISCORD_ADMIN_CHANNEL_ID"]
    return channel_id if channel_id.present?

    guilds = DiscordApiClient.get_bot_guilds
    return nil if guilds.empty?

    guild_id = guilds.first["id"]
    channel = DiscordApiClient.create_text_channel(guild_id, "system-alerts")
    channel_id = channel["id"]

    Rails.logger.info "[#{self.class.name}] Canal admin criado: #{channel_id}"
    channel_id
  end
end
