# frozen_string_literal: true

class CollectAnilistCatalogJob < ApplicationJob
  queue_as :default

  def perform
    data = ScrapingServices::AnilistClient.fetch_trending_anime
    media_list = data&.dig("data", "Page", "media")
    return unless media_list.is_a?(Array)

    media_list.each { |item| save_catalog(item) }
    Rails.logger.info "[CollectAnilistCatalogJob] Coleta Anilist concluída: #{media_list.size} animes"
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
      status: item["status"]&.downcase,
      original_language: "ja",
      metadata: item.except("title", "description", "startDate", "averageScore", "popularity", "coverImage", "genres")
    )

    catalog.save! if catalog.changed?
  end
end
