# frozen_string_literal: true

class CollectAnilistCatalogJob < ApplicationJob
  queue_as :default

  def perform
    total = 0

    # Trending (em exibição)
    data = ScrapingServices::AnilistClient.fetch_trending_anime
    media_list = data&.dig("data", "Page", "media")
    if media_list.is_a?(Array)
      media_list.each { |item| save_catalog(item) }
      total += media_list.size
    end

    # Próximos lançamentos
    data = ScrapingServices::AnilistClient.fetch_upcoming_anime
    media_list = data&.dig("data", "Page", "media")
    if media_list.is_a?(Array)
      media_list.each { |item| save_catalog(item) }
      total += media_list.size
    end

    # Em exibição atual
    data = ScrapingServices::AnilistClient.fetch_releasing_anime
    media_list = data&.dig("data", "Page", "media")
    if media_list.is_a?(Array)
      media_list.each { |item| save_catalog(item) }
      total += media_list.size
    end

    Rails.logger.info "[CollectAnilistCatalogJob] Coleta Anilist concluída: #{total} animes"
  rescue StandardError => e
    Rails.logger.error "[CollectAnilistCatalogJob] Erro: #{e.message}"
  end

  private

  def save_catalog(item)
    catalog = ExternalCatalog.find_or_initialize_by(source: "anilist", external_id: item["id"].to_s)
    return if catalog.updated_at && catalog.updated_at > 24.hours.ago

    start_date = item["startDate"]
    release_date = if start_date&.dig("year")
                     Date.new(start_date["year"], start_date["month"] || 1, start_date["day"] || 1)
                   end

    score = item["averageScore"]
    pop = item["popularity"]

    anilist_status = item["status"]&.downcase
    mapped_status = case anilist_status
                    when "not_yet_released" then "upcoming"
                    when "finished" then "released"
                    when "releasing" then "releasing"
                    when "cancelled" then "cancelled"
                    else "released"
                    end

    catalog.assign_attributes(
      title: item.dig("title", "english") || item.dig("title", "romaji"),
      media_type: "anime",
      description: item["description"]&.gsub(/<[^>]+>/, "")&.strip,
      release_date: release_date,
      popularity: pop,
      vote_average: score ? (score.to_f / 10.0) : nil,
      vote_count: pop,
      poster_url: item.dig("coverImage", "large"),
      genres: item["genres"]&.join(","),
      status: mapped_status,
      original_language: "ja",
      metadata: item.except("title", "description", "startDate", "averageScore",
                             "popularity", "coverImage", "genres", "status")
    )

    catalog.save! if catalog.changed?
  end
end
