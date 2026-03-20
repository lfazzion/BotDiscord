# frozen_string_literal: true

module ScrapingServices
  class HttpStealthClient
    IMPERSONATE_PROFILES = {
      chrome_latest: :chrome,
      safari_latest: :safari,
      firefox_latest: :firefox,
      chrome_android: :chrome_android,
      edge_latest: :edge
    }.freeze

    attr_reader :fingerprint, :proxy

    def initialize(fingerprint: :chrome_latest, proxy: nil)
      @fingerprint = fingerprint
      @proxy = proxy
    end

    def get(url, options = {})
      request(:get, url, options)
    end

    def post(url, options = {})
      request(:post, url, options)
    end

    private

    def request(method, url, options = {})
      profile = IMPERSONATE_PROFILES.fetch(@fingerprint, :chrome)

      client = CurlImpersonateClient.new(profile: profile, proxy: @proxy)

      result = if method == :get
                 client.get(url, headers: options[:headers] || {})
               else
                 client.post(url, body: options[:body], headers: options[:headers] || {})
               end

      handle_result(result, url)
    rescue ScrapingServices::RateLimitError => e
      raise e
    rescue StandardError => e
      Rails.logger.warn "[HttpStealthClient] curl_cffi falhou, fallback Typhoeus: #{e.message}"
      fallback_request(method, url, options)
    end

    def handle_result(result, url)
      return nil if result.nil?

      unless result['success']
        error_msg = result['error'] || "HTTP #{result['status_code']}"
        Rails.logger.warn "[HttpStealthClient] #{error_msg} em #{url}"
        return nil
      end

      result['body']
    end

    def fallback_request(method, url, options = {})
      require 'typhoeus'

      headers = build_fallback_headers(options[:headers])

      typhoeus_options = {
        headers: headers,
        timeout: 30,
        connecttimeout: 10,
        followlocation: true,
        maxredirs: 5,
        accept_encoding: 'gzip, deflate, br'
      }

      typhoeus_options[:proxy] = @proxy if @proxy
      typhoeus_options[:body] = options[:body] if options[:body]

      response = Typhoeus::Request.send(method, url, typhoeus_options)
      handle_fallback_response(response)
    end

    def build_fallback_headers(custom_headers = {})
      base_headers = fallback_fingerprint.dup
      base_headers.merge(custom_headers || {})
    end

    def fallback_fingerprint
      case @fingerprint
      when :safari_latest
        {
          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Accept-Encoding' => 'gzip, deflate, br',
          'Connection' => 'keep-alive'
        }
      else
        {
          'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Accept-Encoding' => 'gzip, deflate, br',
          'Connection' => 'keep-alive',
          'Sec-Ch-Ua' => '"Not_A Brand";v="8", "Chromium";v="131", "Google Chrome";v="131"',
          'Sec-Ch-Ua-Mobile' => '?0',
          'Sec-Ch-Ua-Platform' => '"Windows"',
          'Sec-Fetch-Dest' => 'document',
          'Sec-Fetch-Mode' => 'navigate',
          'Sec-Fetch-Site' => 'none',
          'Sec-Fetch-User' => '?1',
          'Upgrade-Insecure-Requests' => '1'
        }
      end
    end

    def handle_fallback_response(response)
      if [403, 429, 503].include?(response.code)
        raise RateLimitHandler.handle_error(
          StandardError.new("HTTP #{response.code}: #{response.body&.first(200)}"),
          retry_count: 0
        )
      end

      if response.timed_out?
        raise RateLimitHandler.handle_error(
          StandardError.new("Timeout ao acessar #{response.effective_url}"),
          retry_count: 0
        )
      end

      if response.success?
        response.body
      else
        Rails.logger.warn "[HttpStealthClient] HTTP #{response.code} em #{response.effective_url}"
        nil
      end
    end
  end
end
