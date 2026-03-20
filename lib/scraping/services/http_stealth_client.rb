# frozen_string_literal: true

require 'typhoeus'

module ScrapingServices
  class HttpStealthClient
    FINGERPRINTS = {
      chrome_latest: {
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
      }.freeze,
      safari_latest: {
        'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language' => 'en-US,en;q=0.9',
        'Accept-Encoding' => 'gzip, deflate, br',
        'Connection' => 'keep-alive'
      }.freeze
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
      headers = build_headers(options[:headers])

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
      handle_response(response)
    end

    def build_headers(custom_headers = {})
      base_headers = FINGERPRINTS.fetch(@fingerprint, FINGERPRINTS[:chrome_latest]).dup
      base_headers.merge(custom_headers || {})
    end

    def handle_response(response)
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
