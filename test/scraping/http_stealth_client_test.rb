# frozen_string_literal: true

require 'test_helper'

class HttpStealthClientTest < ActiveSupport::TestCase
  test 'chrome fingerprint sends correct headers' do
    client = ScrapingServices::HttpStealthClient.new(fingerprint: :chrome_latest)
    headers = client.send(:build_headers)

    assert headers.key?('User-Agent')
    assert headers['User-Agent'].include?('Chrome')
    assert headers.key?('Sec-Ch-Ua')
    assert headers.key?('Sec-Fetch-Dest')
  end

  test 'safari fingerprint sends correct headers' do
    client = ScrapingServices::HttpStealthClient.new(fingerprint: :safari_latest)
    headers = client.send(:build_headers)

    assert headers.key?('User-Agent')
    assert headers['User-Agent'].include?('Safari')
    assert headers['User-Agent'].exclude?('Chrome')
  end

  test 'raises RateLimitError on 429 response' do
    skip 'requires network mock setup' unless defined?(Typhoeus)

    Typhoeus::Request.new('http://example.com')
    response = Typhoeus::Response.new(
      code: 429,
      body: 'Too Many Requests',
      mock: true
    )

    client = ScrapingServices::HttpStealthClient.new

    assert_raises(ScrapingServices::RateLimitError) do
      client.send(:handle_response, response)
    end
  end

  test 'raises RateLimitError on 503 response' do
    skip 'requires network mock setup' unless defined?(Typhoeus)

    response = Typhoeus::Response.new(
      code: 503,
      body: 'Service Unavailable',
      mock: true
    )

    client = ScrapingServices::HttpStealthClient.new

    assert_raises(ScrapingServices::RateLimitError) do
      client.send(:handle_response, response)
    end
  end

  test 'proxy is used when configured' do
    client = ScrapingServices::HttpStealthClient.new(proxy: 'http://proxy:8080')
    assert_equal 'http://proxy:8080', client.proxy
  end
end
