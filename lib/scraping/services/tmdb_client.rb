# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ScrapingServices
  class TmdbClient
    BASE_URL = "https://api.themoviedb.org/3"
    class << self
      def fetch_upcoming_movies(page: 1, language: "pt-BR")
        get("/movie/upcoming", page: page, language: language)
      end

      def fetch_on_the_air_tv(page: 1, language: "pt-BR")
        get("/tv/on_the_air", page: page, language: language)
      end

      def fetch_popular_movies(page: 1, language: "pt-BR")
        get("/movie/popular", page: page, language: language)
      end

      private

      def get(path, params = {})
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{ENV.fetch('TMDB_API_KEY')}"
        request['Accept'] = 'application/json'

        response = http.request(request)

        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[TmdbClient] HTTP #{response.code} em #{path}"
        nil
      rescue StandardError => e
        Rails.logger.error "[TmdbClient] Erro: #{e.message}"
        nil
      end
    end
  end
end
