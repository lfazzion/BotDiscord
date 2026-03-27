# frozen_string_literal: true

require 'test_helper'

class RawgClientTest < ActiveSupport::TestCase
  test "fetch_upcoming_games returns parsed JSON on success" do
    ENV.stubs(:fetch).with('RAWG_API_KEY').returns('test_api_key')
    stub_request(:get, /api\.rawg\.io\/api\/games/)
      .to_return(status: 200, body: '{"results":[{"id":1,"name":"Upcoming Game"}]}')

    result = ScrapingServices::RawgClient.fetch_upcoming_games

    assert_not_nil result
    assert_equal "Upcoming Game", result["results"].first["name"]
  end

  test "fetch_popular_games returns parsed JSON on success" do
    ENV.stubs(:fetch).with('RAWG_API_KEY').returns('test_api_key')
    stub_request(:get, /api\.rawg\.io\/api\/games/)
      .to_return(status: 200, body: '{"results":[{"id":2,"name":"Popular Game","rating":4.5}]}')

    result = ScrapingServices::RawgClient.fetch_popular_games

    assert_not_nil result
    assert_equal "Popular Game", result["results"].first["name"]
  end

  test "sends API key as query parameter" do
    ENV.stubs(:fetch).with('RAWG_API_KEY').returns('my_secret_key')
    stub_request(:get, /api\.rawg\.io\/api\/games/)
      .with(query: hash_including(key: 'my_secret_key'))
      .to_return(status: 200, body: '{"results":[]}')

    result = ScrapingServices::RawgClient.fetch_upcoming_games
    assert_not_nil result
  end

  test "returns nil on HTTP error" do
    ENV.stubs(:fetch).with('RAWG_API_KEY').returns('test_key')
    stub_request(:get, /api\.rawg\.io\/api\/games/)
      .to_return(status: 403, body: '{"error":"Forbidden"}')

    result = ScrapingServices::RawgClient.fetch_upcoming_games

    assert_nil result
  end

  test "returns nil on timeout" do
    ENV.stubs(:fetch).with('RAWG_API_KEY').returns('test_key')
    stub_request(:get, /api\.rawg\.io\/api\/games/).to_timeout

    result = ScrapingServices::RawgClient.fetch_upcoming_games

    assert_nil result
  end
end
