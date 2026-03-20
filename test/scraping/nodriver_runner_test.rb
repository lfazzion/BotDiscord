# frozen_string_literal: true

require 'test_helper'

class NodriverRunnerTest < ActiveSupport::TestCase
  test 'scrape_instagram_profile builds correct command' do
    expected_cmd = [
      'python3', '-u',
      Rails.root.join('scripts/python/nodriver_instagram.py').to_s,
      'testuser', '--mode', 'profile'
    ]

    Open3.expects(:capture3).with(*expected_cmd, timeout: 180).returns([
                                                                         '{"user_id": "123", "username": "testuser", "full_name": "Test"}',
                                                                         '',
                                                                         stub(success?: true)
                                                                       ])

    result = ScrapingServices::NodriverRunner.scrape_instagram_profile('testuser')

    assert_not_nil result
    assert_equal '123', result[:user_id]
    assert_equal 'testuser', result[:username]
  end

  test 'scrape_instagram_posts builds command with limit' do
    expected_cmd = [
      'python3', '-u',
      Rails.root.join('scripts/python/nodriver_instagram.py').to_s,
      'testuser', '--mode', 'posts', '--limit', '6'
    ]

    Open3.expects(:capture3).with(*expected_cmd, timeout: 180).returns([
                                                                         '[{"platform_post_id": "p1", "caption": "Post 1"}]',
                                                                         '',
                                                                         stub(success?: true)
                                                                       ])

    result = ScrapingServices::NodriverRunner.scrape_instagram_posts('testuser', limit: 6)

    assert_equal 1, result.size
    assert_equal 'p1', result.first[:platform_post_id]
  end

  test 'scrape_instagram_posts builds command with proxy' do
    expected_cmd = [
      'python3', '-u',
      Rails.root.join('scripts/python/nodriver_instagram.py').to_s,
      'testuser', '--mode', 'posts', '--limit', '12', '--proxy', 'http://proxy:8080'
    ]

    Open3.expects(:capture3).with(*expected_cmd, timeout: 180).returns([
                                                                         '[]',
                                                                         '',
                                                                         stub(success?: true)
                                                                       ])

    result = ScrapingServices::NodriverRunner.scrape_instagram_posts('testuser', proxy: 'http://proxy:8080')
    assert_empty result
  end

  test 'scrape_twitter_profile uses nodriver_twitter.py script' do
    expected_cmd = [
      'python3', '-u',
      Rails.root.join('scripts/python/nodriver_twitter.py').to_s,
      'twitteruser', '--mode', 'profile'
    ]

    Open3.expects(:capture3).with(*expected_cmd, timeout: 180).returns([
                                                                         '{"user_id": "456", "username": "twitteruser", "full_name": "Twitter User"}',
                                                                         '',
                                                                         stub(success?: true)
                                                                       ])

    result = ScrapingServices::NodriverRunner.scrape_twitter_profile('twitteruser')

    assert_not_nil result
    assert_equal '456', result[:user_id]
    assert_equal 'twitteruser', result[:username]
  end

  test 'returns nil when stdout is empty' do
    Open3.expects(:capture3).returns(['', '', stub(success?: true)])

    result = ScrapingServices::NodriverRunner.scrape_instagram_profile('testuser')
    assert_nil result
  end

  test 'returns nil when process fails' do
    Open3.expects(:capture3).returns(['', 'error', stub(success?: false, exitstatus: 1)])

    result = ScrapingServices::NodriverRunner.scrape_instagram_profile('testuser')
    assert_nil result
  end

  test 'raises RateLimitError on 429 in stderr' do
    Open3.expects(:capture3).returns(['', 'HTTP 429 Too Many Requests', stub(success?: false)])

    assert_raises(ScrapingServices::RateLimitError) do
      ScrapingServices::NodriverRunner.scrape_instagram_profile('testuser')
    end
  end

  test 'raises RateLimitError on Captcha in stderr' do
    Open3.expects(:capture3).returns(['', 'Captcha detected', stub(success?: false)])

    assert_raises(ScrapingServices::RateLimitError) do
      ScrapingServices::NodriverRunner.scrape_instagram_profile('testuser')
    end
  end

  test 'raises RateLimitError on 403 Forbidden in stderr' do
    Open3.expects(:capture3).returns(['', '403 Forbidden', stub(success?: false)])

    assert_raises(ScrapingServices::RateLimitError) do
      ScrapingServices::NodriverRunner.scrape_instagram_profile('testuser')
    end
  end

  test 'returns nil on invalid JSON' do
    Open3.expects(:capture3).returns(['not json', '', stub(success?: true)])

    result = ScrapingServices::NodriverRunner.scrape_instagram_profile('testuser')
    assert_nil result
  end
end
