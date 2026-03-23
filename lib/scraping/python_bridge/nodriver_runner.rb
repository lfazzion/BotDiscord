# frozen_string_literal: true

require 'open3'
require 'json'
require 'timeout'

module ScrapingServices
  class NodriverRunner
    PYTHON_SCRIPT_PATH = Rails.root.join('scripts/python')
    NODRIVER_SCRIPT = 'nodriver_instagram.py'

    class << self
      def scrape_instagram_profile(username, proxy: nil)
        command = build_command('profile', username, proxy: proxy)
        result = execute(command)
        return nil if result.nil?

        result.deep_symbolize_keys
      end

      def scrape_instagram_posts(username, limit: 12, proxy: nil)
        command = build_command('posts', username, limit: limit, proxy: proxy)
        result = execute(command)
        return [] if result.nil?

        result.map { |post| post.deep_symbolize_keys }
      end

      def scrape_twitter_profile(username, proxy: nil)
        command = build_command('profile', username, platform: 'twitter', proxy: proxy)
        result = execute(command)
        return nil if result.nil?

        result.deep_symbolize_keys
      end

      private

      def build_command(mode, username, limit: nil, platform: nil, proxy: nil)
        script = platform == 'twitter' ? 'nodriver_twitter.py' : NODRIVER_SCRIPT
        script_path = PYTHON_SCRIPT_PATH.join(script).to_s

        cmd = ['python3', '-u', script_path, username, '--mode', mode]
        cmd += ['--limit', limit.to_s] if limit
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
          Rails.logger.error "[NodriverRunner] Falha (exit #{status.exitstatus}): #{stderr}"
          return nil
        end

        return nil if stdout.strip.empty?

        JSON.parse(stdout.strip)
      rescue JSON::ParserError => e
        Rails.logger.error "[NodriverRunner] JSON inválido: #{e.message}"
        nil
      end

      def rate_limit?(stderr)
        patterns = ['429', 'Blocked', 'Captcha', 'rate limit', '403 Forbidden']
        patterns.any? { |p| stderr.include?(p) }
      end
    end
  end
end
