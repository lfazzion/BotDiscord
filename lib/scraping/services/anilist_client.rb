# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ScrapingServices
  class AnilistClient
    GRAPHQL_URL = "https://graphql.anilist.co"

    TRENDING_QUERY = <<~GRAPHQL
      query ($page: Int, $perPage: Int) {
        Page(page: $page, perPage: $perPage) {
          media(type: ANIME, sort: TRENDING_DESC) {
            id
            title { romaji english native }
            description(asHtml: false)
            startDate { year month day }
            popularity
            averageScore
            episodes
            coverImage { large }
            genres
            status
          }
        }
      }
    GRAPHQL

    class << self
      def fetch_trending_anime(page: 1, per_page: 20)
        execute(TRENDING_QUERY, page: page, perPage: per_page)
      end

      private

      def execute(query, variables = {})
        uri = URI(GRAPHQL_URL)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        request.body = JSON.generate({ query: query, variables: variables })

        response = http.request(request)

        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[AnilistClient] HTTP #{response.code}"
        nil
      rescue StandardError => e
        Rails.logger.error "[AnilistClient] Erro: #{e.message}"
        nil
      end
    end
  end
end
