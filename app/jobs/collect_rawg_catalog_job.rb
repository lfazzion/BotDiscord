# frozen_string_literal: true

class CollectRawgCatalogJob < ApplicationJob
  queue_as :default

  def perform
    total = 0

    data = ScrapingServices::RawgClient.fetch_upcoming_games
    if data&.dig("results").is_a?(Array)
      data["results"].each { |item| save_catalog(item) }
      total += data["results"].size
    end

    data = ScrapingServices::RawgClient.fetch_popular_games
    if data&.dig("results").is_a?(Array)
      data["results"].each { |item| save_catalog(item) }
      total += data["results"].size
    end

    Rails.logger.info "[CollectRawgCatalogJob] Coleta RAWG concluída: #{total} jogos"
  rescue StandardError => e
    Rails.logger.error "[CollectRawgCatalogJob] Erro: #{e.message}"
  end

  private

  def save_catalog(item)
    catalog = ExternalCatalog.find_or_initialize_by(source: "rawg", external_id: item["id"].to_s)
    return if catalog.updated_at && catalog.updated_at > 24.hours.ago

    release_date = item["released"] ? Date.parse(item["released"]) : nil

    catalog.assign_attributes(
      title: item["name"],
      media_type: "game",
      description: nil,
      release_date: release_date,
      popularity: item["added"],
      vote_average: item["rating"].to_f > 0 ? item["rating"] : nil,
      vote_count: item["ratings_count"].to_i > 0 ? item["ratings_count"] : nil,
      poster_url: item["background_image"],
      genres: item["genres"]&.map { |g| g["name"] }&.join(","),
      status: release_date && release_date > Date.current ? "upcoming" : "released",
      metadata: item.except("name", "released", "rating", "ratings_count", "added", "background_image", "genres")
    )

    catalog.save! if catalog.changed?
  end
end
