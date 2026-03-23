# frozen_string_literal: true

class CollectTmdbCatalogJob < ApplicationJob
  queue_as :default

  def perform
    collect_movies
    collect_tv_shows
    Rails.logger.info "[CollectTmdbCatalogJob] Coleta TMDB concluída"
  rescue StandardError => e
    Rails.logger.error "[CollectTmdbCatalogJob] Erro: #{e.message}"
  end

  private

  def collect_movies
    data = ScrapingServices::TmdbClient.fetch_upcoming_movies
    return unless data&.dig("results")

    data["results"].each { |item| save_catalog(item, "movie") }
  end

  def collect_tv_shows
    data = ScrapingServices::TmdbClient.fetch_on_the_air_tv
    return unless data&.dig("results")

    data["results"].each { |item| save_catalog(item, "tv") }
  end

  def save_catalog(item, media_type)
    catalog = ExternalCatalog.find_or_initialize_by(source: "tmdb", external_id: item["id"].to_s)
    return if catalog.updated_at && catalog.updated_at > 24.hours.ago

    catalog.assign_attributes(
      title: item["title"] || item["name"],
      media_type: media_type,
      description: item["overview"],
      release_date: item["release_date"] || item["first_air_date"],
      popularity: item["popularity"],
      vote_average: item["vote_average"].to_f > 0 ? item["vote_average"] : nil,
      vote_count: item["vote_count"].to_i > 0 ? item["vote_count"] : nil,
      poster_url: item["poster_path"] ? "https://image.tmdb.org/t/p/w500#{item["poster_path"]}" : nil,
      genres: item["genre_ids"]&.join(","),
      original_language: item["original_language"],
      adult: item["adult"] || false,
      status: item["release_date"].present? && item["release_date"] > Date.current.to_s ? "upcoming" : "released",
      metadata: item.except("title", "name", "overview", "release_date", "first_air_date", "poster_path", "genre_ids")
    )

    catalog.save! if catalog.changed?
  end
end
