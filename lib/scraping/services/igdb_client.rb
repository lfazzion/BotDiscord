# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ScrapingServices
  class IgdbClient
    BASE_URL = "https://api.igdb.com/v4"
    class << self
      def fetch_popular_games(limit: 50)
        query = <<~APICALYPSE
          fields name,summary,first_release_date,rating,rating_count,cover.url,genres.name,platforms.name,status;
          sort rating desc;
          limit #{limit};
          where rating != null & first_release_date != null;
        APICALYPSE
        post("/games", query)
      end

      def fetch_upcoming_games(limit: 50)
        timestamp = Time.current.to_i
        query = <<~APICALYPSE
          fields name,summary,first_release_date,cover.url,genres.name,platforms.name,status;
          sort first_release_date asc;
          limit #{limit};
          where first_release_date > #{timestamp};
        APICALYPSE
        post("/games", query)
      end

      private

      def post(path, body)
        uri = URI("#{BASE_URL}#{path}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request['Client-ID'] = ENV.fetch('IGDB_CLIENT_ID')
        request['Authorization'] = "Bearer #{ENV.fetch('IGDB_ACCESS_TOKEN')}"
        request['Accept'] = 'application/json'
        request['Content-Type'] = 'text/plain'
        request.body = body

        response = http.request(request)

        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[IgdbClient] HTTP #{response.code} em #{path}"
        nil
      rescue StandardError => e
        Rails.logger.error "[IgdbClient] Erro: #{e.message}"
        nil
      end
    end
  end
end
