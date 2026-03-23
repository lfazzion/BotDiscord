# frozen_string_literal: true

class CollectIgdbCatalogJob < ApplicationJob
  queue_as :default

  def perform
    data = ScrapingServices::IgdbClient.fetch_popular_games
    return unless data.is_a?(Array)

    data.each { |item| save_catalog(item) }
    Rails.logger.info "[CollectIgdbCatalogJob] Coleta IGDB concluída: #{data.size} jogos"
  rescue StandardError => e
    Rails.logger.error "[CollectIgdbCatalogJob] Erro: #{e.message}"
  end

  private

  def save_catalog(item)
    catalog = ExternalCatalog.find_or_initialize_by(source: "igdb", external_id: item["id"].to_s)
    return if catalog.updated_at && catalog.updated_at > 24.hours.ago

    catalog.assign_attributes(
      title: item["name"],
      media_type: "game",
      description: item["summary"],
      release_date: item["first_release_date"] ? Time.at(item["first_release_date"]).to_date : nil,
      popularity: item["rating"],
      vote_average: item["rating"].to_f > 0 ? item["rating"] : nil,
      vote_count: item["rating_count"].to_i > 0 ? item["rating_count"] : nil,
      poster_url: item.dig("cover", "url"),
      genres: item["genres"]&.map { |g| g["name"] }&.join(","),
      status: item["status"] == 0 ? "released" : "upcoming",
      metadata: item.except("name", "summary", "first_release_date", "rating", "rating_count", "cover", "genres")
    )

    catalog.save! if catalog.changed?
  end
end
