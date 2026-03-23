# frozen_string_literal: true

require 'test_helper'

class TmdbClientTest < ActiveSupport::TestCase
  test "fetch_upcoming_movies returns parsed JSON on success" do
    ENV.stubs(:fetch).with('TMDB_API_KEY').returns('test_key')
    stub_request(:get, /api.themoviedb.org\/3\/movie\/upcoming/)
      .to_return(status: 200, body: '{"results":[{"id":1,"title":"Test Movie"}]}')

    result = ScrapingServices::TmdbClient.fetch_upcoming_movies

    assert_not_nil result
    assert_equal "Test Movie", result["results"].first["title"]
  end

  test "fetch_on_the_air_tv returns parsed JSON on success" do
    ENV.stubs(:fetch).with('TMDB_API_KEY').returns('test_key')
    stub_request(:get, /api.themoviedb.org\/3\/tv\/on_the_air/)
      .to_return(status: 200, body: '{"results":[{"id":2,"name":"Test Show"}]}')

    result = ScrapingServices::TmdbClient.fetch_on_the_air_tv

    assert_not_nil result
    assert_equal "Test Show", result["results"].first["name"]
  end

  test "fetch_popular_movies returns parsed JSON on success" do
    ENV.stubs(:fetch).with('TMDB_API_KEY').returns('test_key')
    stub_request(:get, /api.themoviedb.org\/3\/movie\/popular/)
      .to_return(status: 200, body: '{"results":[{"id":3,"title":"Popular Movie"}]}')

    result = ScrapingServices::TmdbClient.fetch_popular_movies

    assert_not_nil result
    assert_equal "Popular Movie", result["results"].first["title"]
  end

  test "returns nil on HTTP 401" do
    ENV.stubs(:fetch).with('TMDB_API_KEY').returns('bad_key')
    stub_request(:get, /api.themoviedb.org/)
      .to_return(status: 401, body: '{"status_message":"Invalid API key"}')

    result = ScrapingServices::TmdbClient.fetch_upcoming_movies

    assert_nil result
  end

  test "returns nil on timeout" do
    ENV.stubs(:fetch).with('TMDB_API_KEY').returns('test_key')
    stub_request(:get, /api.themoviedb.org/).to_timeout

    result = ScrapingServices::TmdbClient.fetch_upcoming_movies

    assert_nil result
  end

  test "sends Bearer auth header" do
    ENV.stubs(:fetch).with('TMDB_API_KEY').returns('my_api_key')
    stub_request(:get, /api.themoviedb.org\/3\/movie\/upcoming/)
      .with(headers: { "Authorization" => "Bearer my_api_key" })
      .to_return(status: 200, body: '{"results":[]}')

    result = ScrapingServices::TmdbClient.fetch_upcoming_movies
    assert_not_nil result
  end
end
