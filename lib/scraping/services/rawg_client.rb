# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ScrapingServices
  class RawgClient
    BASE_URL = "https://api.rawg.io/api"

    class << self
      def fetch_upcoming_games(limit: 20)
        from = Date.current.to_s
        to = (Date.current + 6.months).to_s
        get("/games", dates: "#{from},#{to}", ordering: "-added", page_size: limit)
      end

      def fetch_popular_games(limit: 20)
        get("/games", ordering: "-added", page_size: limit, dates: "2025-01-01,#{Date.current}")
      end

      private

      def get(path, params = {})
        params[:key] = ENV.fetch('RAWG_API_KEY')
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'application/json'

        response = http.request(request)

        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[RawgClient] HTTP #{response.code} em #{path}"
        nil
      rescue StandardError => e
        Rails.logger.error "[RawgClient] Erro: #{e.message}"
        nil
      end
    end
  end
end
