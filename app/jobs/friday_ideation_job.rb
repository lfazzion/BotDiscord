# frozen_string_literal: true

class FridayIdeationJob < ApplicationJob
  queue_as :default

  def perform
    channel_id = ensure_digest_channel
    return unless channel_id

    message = build_ideation_digest
    DiscordApiClient.send_message(channel_id, message)

    Rails.logger.info "[FridayIdeationJob] Digest de ideias enviado para canal #{channel_id}"
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

    Rails.logger.info "[FridayIdeationJob] Canal digest criado: #{channel_id}"
    channel_id
  end

  def build_ideation_digest
    lines = ["**💡 Ideias da Semana — #{Date.current.strftime('%d/%m/%Y')}**"]
    lines << ''

    upcoming_events = Event.upcoming.where('start_date <= ?', 7.days.from_now).limit(5)
    if upcoming_events.any?
      lines << '**Eventos da próxima semana:**'
      upcoming_events.each do |e|
        lines << "- **#{e.title}** (#{e.event_type}) — #{e.start_date&.strftime('%d/%m')}"
      end
      lines << ''
    end

    popular_catalogs = ExternalCatalog.popular.limit(5)
    if popular_catalogs.any?
      lines << '**Catálogos populares recentes:**'
      popular_catalogs.each do |c|
        lines << "- **#{c.title}** (#{c.source}/#{c.media_type})"
      end
      lines << ''
    end

    recent_articles = NewsArticle.recent(7).limit(5)
    if recent_articles.any?
      lines << '**Artigos recentes:**'
      recent_articles.each do |a|
        lines << "- **#{a.title}** — #{a.source}"
      end
      lines << ''
    end

    prompt = Llm::PromptLoader.load('chatbot', user_message: build_context(lines))
    response = AiRouter.complete(prompt, context: :background)

    lines << '**Sugestões de conteúdo:**'
    lines << response.content.to_s

    lines.join("\n")
  end

  def build_context(lines)
    <<~CONTEXT
      Com base nos dados abaixo, sugira 3 ideias de conteúdo para influenciadores digitais:

      #{lines.join("\n")}
    CONTEXT
  end
end
