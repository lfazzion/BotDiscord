# frozen_string_literal: true

require 'open3'
require 'json'

module ScrapingServices
  class CurlImpersonateClient
    SCRIPT_PATH = Rails.root.join('scripts/python/curl_impersonate.py')

    IMPERSONATE_PROFILES = %i[chrome safari firefox chrome_android edge].freeze

    attr_reader :profile, :proxy

    def initialize(profile: :chrome, proxy: nil)
      @profile = IMPERSONATE_PROFILES.include?(profile) ? profile : :chrome
      @proxy = proxy
    end

    def get(url, headers: {})
      request(url, method: 'GET', headers: headers)
    end

    def post(url, body: nil, headers: {})
      request(url, method: 'POST', body: body, headers: headers)
    end

    private

    def request(url, method:, headers: {}, body: nil)
      command = build_command(url, method: method, headers: headers, body: body)
      execute(command)
    end

    def build_command(url, method:, headers: {}, body: nil)
      cmd = ['python3', '-u', SCRIPT_PATH.to_s, url, '--method', method, '--profile', @profile.to_s]

      cmd += ['--proxy', @proxy] if @proxy

      headers.each do |key, val|
        cmd += ['--header', "#{key}:#{val}"]
      end

      cmd += ['--body', body] if body

      cmd
    end

    def execute(command)
      stdout, stderr, status = Open3.capture3(*command, timeout: 60)

      if rate_limit?(stdout, stderr)
        raise RateLimitHandler.handle_error(
          StandardError.new(stderr.presence || stdout),
          retry_count: 0
        )
      end

      unless status.success?
        Rails.logger.error "[CurlImpersonateClient] Falha (exit #{status.exitstatus}): #{stderr}"
        return nil
      end

      return nil if stdout.strip.empty?

      parsed = JSON.parse(stdout.strip)
      return nil unless parsed['success']

      parsed
    rescue JSON::ParserError => e
      Rails.logger.error "[CurlImpersonateClient] JSON inválido: #{e.message}"
      nil
    end

    def rate_limit?(stdout, stderr)
      return true if ['429', 'Blocked', 'Captcha', 'rate limit', '403 Forbidden'].any? { |p| stderr.include?(p) }

      begin
        parsed = JSON.parse(stdout.strip)
        return true if parsed['error']&.include?('rate_limit')
      rescue JSON::ParserError
        # stdout não é JSON, ignorar
      end

      false
    end
  end
end
