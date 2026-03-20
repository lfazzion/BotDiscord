# frozen_string_literal: true

require 'test_helper'

class CamoufoxServiceTest < ActiveSupport::TestCase
  test 'scrape_url builds correct command without proxy' do
    expected_cmd = [
      'python3', '-u',
      Rails.root.join('scripts/python/camoufox_scrape.py').to_s,
      'https://example.com'
    ]

    Open3.expects(:capture3).with(*expected_cmd, timeout: 180).returns([
                                                                         '{"title": "Example", "content": "Hello world"}',
                                                                         '',
                                                                         stub(success?: true)
                                                                       ])

    result = ScrapingServices::CamoufoxService.scrape_url('https://example.com')

    assert_not_nil result
    assert_equal 'Example', result[:title]
    assert_equal 'Hello world', result[:content]
  end

  test 'scrape_url builds command with proxy' do
    expected_cmd = [
      'python3', '-u',
      Rails.root.join('scripts/python/camoufox_scrape.py').to_s,
      'https://example.com',
      '--proxy', 'http://proxy:8080'
    ]

    Open3.expects(:capture3).with(*expected_cmd, timeout: 180).returns([
                                                                         '{"title": "Example"}',
                                                                         '',
                                                                         stub(success?: true)
                                                                       ])

    result = ScrapingServices::CamoufoxService.scrape_url('https://example.com', proxy: 'http://proxy:8080')
    assert_not_nil result
  end

  test 'scrape_batch returns array of url/data pairs' do
    urls = ['https://example.com/1', 'https://example.com/2']

    Open3.expects(:capture3).twice.returns(
      ['{"title": "Page 1"}', '', stub(success?: true)],
      ['{"title": "Page 2"}', '', stub(success?: true)]
    )

    results = ScrapingServices::CamoufoxService.scrape_batch(urls)

    assert_equal 2, results.size
    assert_equal 'https://example.com/1', results.first[:url]
    assert_equal 'Page 1', results.first[:data][:title]
  end

  test 'returns nil when stdout is empty' do
    Open3.expects(:capture3).returns(['', '', stub(success?: true)])

    result = ScrapingServices::CamoufoxService.scrape_url('https://example.com')
    assert_nil result
  end

  test 'returns nil when process fails' do
    Open3.expects(:capture3).returns(['', 'error', stub(success?: false, exitstatus: 1)])

    result = ScrapingServices::CamoufoxService.scrape_url('https://example.com')
    assert_nil result
  end

  test 'raises RateLimitError on 429 in stderr' do
    Open3.expects(:capture3).returns(['', 'HTTP 429 rate limit', stub(success?: false)])

    assert_raises(ScrapingServices::RateLimitError) do
      ScrapingServices::CamoufoxService.scrape_url('https://example.com')
    end
  end

  test 'raises RateLimitError on Blocked in stderr' do
    Open3.expects(:capture3).returns(['', 'Blocked by Cloudflare', stub(success?: false)])

    assert_raises(ScrapingServices::RateLimitError) do
      ScrapingServices::CamoufoxService.scrape_url('https://example.com')
    end
  end

  test 'returns nil on invalid JSON' do
    Open3.expects(:capture3).returns(['not json', '', stub(success?: true)])

    result = ScrapingServices::CamoufoxService.scrape_url('https://example.com')
    assert_nil result
  end
end
