# frozen_string_literal: true

require 'test_helper'

class IgdbClientTest < ActiveSupport::TestCase
  test "fetch_popular_games returns parsed JSON on success" do
    ENV.stubs(:fetch).with('IGDB_CLIENT_ID').returns('test_client_id')
    ENV.stubs(:fetch).with('IGDB_CLIENT_SECRET').returns('test_client_secret')
    stub_request(:post, "https://id.twitch.tv/oauth2/token")
      .to_return(status: 200, body: '{"access_token":"test_oauth_token"}')
    stub_request(:post, "https://api.igdb.com/v4/games")
      .to_return(status: 200, body: '[{"id":1,"name":"Test Game","rating":90.0}]')

    result = ScrapingServices::IgdbClient.fetch_popular_games

    assert_not_nil result
    assert_equal "Test Game", result.first["name"]
  end

  test "fetch_upcoming_games returns parsed JSON on success" do
    ENV.stubs(:fetch).with('IGDB_CLIENT_ID').returns('test_client_id')
    ENV.stubs(:fetch).with('IGDB_CLIENT_SECRET').returns('test_client_secret')
    stub_request(:post, "https://id.twitch.tv/oauth2/token")
      .to_return(status: 200, body: '{"access_token":"test_oauth_token"}')
    stub_request(:post, "https://api.igdb.com/v4/games")
      .to_return(status: 200, body: '[{"id":2,"name":"Upcoming Game"}]')

    result = ScrapingServices::IgdbClient.fetch_upcoming_games

    assert_not_nil result
    assert_equal "Upcoming Game", result.first["name"]
  end

  test "sends correct headers" do
    ENV.stubs(:fetch).with('IGDB_CLIENT_ID').returns('my_client_id')
    ENV.stubs(:fetch).with('IGDB_CLIENT_SECRET').returns('my_client_secret')
    stub_request(:post, "https://id.twitch.tv/oauth2/token")
      .to_return(status: 200, body: '{"access_token":"my_oauth_token"}')
    stub_request(:post, "https://api.igdb.com/v4/games")
      .with(headers: {
        "Client-ID" => "my_client_id",
        "Authorization" => "Bearer my_oauth_token",
        "Content-Type" => "text/plain"
      })
      .to_return(status: 200, body: '[]')

    result = ScrapingServices::IgdbClient.fetch_popular_games
    assert_equal [], result
  end

  test "returns nil on HTTP error" do
    ENV.stubs(:fetch).with('IGDB_CLIENT_ID').returns('bad_id')
    ENV.stubs(:fetch).with('IGDB_CLIENT_SECRET').returns('bad_secret')
    stub_request(:post, "https://id.twitch.tv/oauth2/token")
      .to_return(status: 200, body: '{"access_token":"bad_token"}')
    stub_request(:post, "https://api.igdb.com/v4/games")
      .to_return(status: 401, body: '{"message":"Invalid token"}')

    result = ScrapingServices::IgdbClient.fetch_popular_games

    assert_nil result
  end

  test "returns nil on timeout" do
    ENV.stubs(:fetch).with('IGDB_CLIENT_ID').returns('test_id')
    ENV.stubs(:fetch).with('IGDB_CLIENT_SECRET').returns('test_secret')
    stub_request(:post, "https://id.twitch.tv/oauth2/token")
      .to_return(status: 200, body: '{"access_token":"test_oauth_token"}')
    stub_request(:post, "https://api.igdb.com/v4/games").to_timeout

    result = ScrapingServices::IgdbClient.fetch_popular_games

    assert_nil result
  end
end
