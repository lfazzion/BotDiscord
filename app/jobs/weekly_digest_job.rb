# frozen_string_literal: true

class WeeklyDigestJob < ApplicationJob
  queue_as :default

  def perform
    channel_id = ensure_digest_channel
    return unless channel_id

    message = build_weekly_digest
    DiscordApiClient.send_message(channel_id, message)

    Rails.logger.info "[WeeklyDigestJob] Digest enviado para canal #{channel_id}"
  end

  private

  def ensure_digest_channel
    channel_id = ENV['DISCORD_DIGEST_CHANNEL_ID']
    return channel_id if channel_id.present?

    guilds = DiscordApiClient.get_bot_guilds
    return nil if guilds.empty?

    guild_id = guilds.first['id']
    channel = DiscordApiClient.create_text_channel(guild_id, 'digest-updates')
    channel_id = channel['id']

    Rails.logger.info "[WeeklyDigestJob] Canal digest criado: #{channel_id}"
    channel_id
  end

  def build_weekly_digest
    lines = ["**📊 Digest Semanal — #{Date.current.strftime('%d/%m/%Y')}**"]
    lines << ''

    top_profiles = SocialProfile.where.not(followers_count: nil)
                                .order(followers_count: :desc)
                                .limit(5)

    if top_profiles.any?
      lines << '**Top 5 Perfis por Seguidores:**'
      top_profiles.each_with_index do |p, i|
        lines << "#{i + 1}. **#{p.display_name || p.platform_username}** (#{p.platform}) — #{p.followers_count} seguidores"
      end
      lines << ''
    end

    recent_posts = SocialPost.where('posted_at >= ?', 7.days.ago).count
    lines << "**Posts coletados na semana:** #{recent_posts}"

    new_prospects = DiscoveredProfile.prospects
                                     .where('classified_at >= ?', 7.days.ago)
                                     .count
    lines << "**Novos prospects:** #{new_prospects}"

    lines.join("\n")
  end
end
