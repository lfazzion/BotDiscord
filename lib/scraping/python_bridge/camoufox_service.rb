# frozen_string_literal: true

require 'open3'
require 'json'
require 'timeout'

module ScrapingServices
  class CamoufoxService
    CAMOUFOX_SCRIPT = 'camoufox_scrape.py'

    class << self
      def scrape_url(url, proxy: nil)
        command = build_command(url, proxy)
        result = execute(command)
        return nil if result.nil?

        result.deep_symbolize_keys
      end

      def scrape_batch(urls, proxy: nil)
        urls.map do |url|
          data = scrape_url(url, proxy: proxy)
          { url: url, data: data }
        end
      end

      private

      def build_command(url, proxy)
        script_path = Rails.root.join('scripts/python', CAMOUFOX_SCRIPT).to_s
        cmd = ['python3', '-u', script_path, url]
        cmd += ['--proxy', proxy] if proxy
        cmd
      end

      def execute(command)
        stdout, stderr, status = Timeout.timeout(180) { Open3.capture3(*command) }

        if rate_limit?(stderr)
          raise RateLimitHandler.handle_error(
            StandardError.new(stderr),
            retry_count: 0
          )
        end

        unless status.success?
          Rails.logger.error "[CamoufoxService] Falha (exit #{status.exitstatus}): #{stderr}"
          return nil
        end

        return nil if stdout.strip.empty?

        JSON.parse(stdout.strip)
      rescue JSON::ParserError => e
        Rails.logger.error "[CamoufoxService] JSON inválido: #{e.message}"
        nil
      end

      def rate_limit?(stderr)
        patterns = ['429', 'Blocked', 'Captcha', 'rate limit', '403 Forbidden']
        patterns.any? { |p| stderr.include?(p) }
      end
    end
  end
end
