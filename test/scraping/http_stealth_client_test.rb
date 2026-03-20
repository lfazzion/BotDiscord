# frozen_string_literal: true

require 'test_helper'

class HttpStealthClientTest < ActiveSupport::TestCase
  test 'chrome fingerprint maps to correct impersonate profile' do
    client = ScrapingServices::HttpStealthClient.new(fingerprint: :chrome_latest)
    assert_equal :chrome_latest, client.fingerprint
    assert_equal :chrome, ScrapingServices::HttpStealthClient::IMPERSONATE_PROFILES[:chrome_latest]
  end

  test 'safari fingerprint maps to correct impersonate profile' do
    assert_equal :safari, ScrapingServices::HttpStealthClient::IMPERSONATE_PROFILES[:safari_latest]
  end

  test 'firefox fingerprint maps to correct impersonate profile' do
    assert_equal :firefox, ScrapingServices::HttpStealthClient::IMPERSONATE_PROFILES[:firefox_latest]
  end

  test 'chrome fallback fingerprint includes Sec-Ch-Ua headers' do
    client = ScrapingServices::HttpStealthClient.new(fingerprint: :chrome_latest)
    headers = client.send(:fallback_fingerprint)

    assert headers.key?('User-Agent')
    assert headers['User-Agent'].include?('Chrome')
    assert headers.key?('Sec-Ch-Ua')
    assert headers.key?('Sec-Fetch-Dest')
    assert headers.key?('Sec-Fetch-Mode')
  end

  test 'safari fallback fingerprint excludes Chrome indicators' do
    client = ScrapingServices::HttpStealthClient.new(fingerprint: :safari_latest)
    headers = client.send(:fallback_fingerprint)

    assert headers.key?('User-Agent')
    assert headers['User-Agent'].include?('Safari')
    assert headers['User-Agent'].exclude?('Chrome')
    refute headers.key?('Sec-Ch-Ua')
  end

  test 'build_fallback_headers merges custom headers' do
    client = ScrapingServices::HttpStealthClient.new(fingerprint: :chrome_latest)
    headers = client.send(:build_fallback_headers, { 'X-Custom' => 'test' })

    assert_equal 'test', headers['X-Custom']
    assert headers.key?('User-Agent')
  end

  test 'proxy is used when configured' do
    client = ScrapingServices::HttpStealthClient.new(proxy: 'http://proxy:8080')
    assert_equal 'http://proxy:8080', client.proxy
  end

  test 'defaults to chrome fingerprint' do
    client = ScrapingServices::HttpStealthClient.new
    assert_equal :chrome_latest, client.fingerprint
  end

  test 'handle_result returns nil for nil result' do
    client = ScrapingServices::HttpStealthClient.new
    result = client.send(:handle_result, nil, 'http://example.com')
    assert_nil result
  end

  test 'handle_result returns body for successful result' do
    client = ScrapingServices::HttpStealthClient.new
    result_data = { 'success' => true, 'body' => '<html>OK</html>', 'status_code' => 200 }
    result = client.send(:handle_result, result_data, 'http://example.com')
    assert_equal '<html>OK</html>', result
  end

  test 'handle_result returns nil for failed result' do
    client = ScrapingServices::HttpStealthClient.new
    result_data = { 'success' => false, 'error' => 'blocked', 'status_code' => 403 }
    result = client.send(:handle_result, result_data, 'http://example.com')
    assert_nil result
  end
end
