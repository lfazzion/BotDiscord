# frozen_string_literal: true

require 'test_helper'

class AnilistClientTest < ActiveSupport::TestCase
  test "fetch_trending_anime returns parsed JSON on success" do
    response_body = {
      data: {
        Page: {
          media: [
            { id: 1, title: { english: "Test Anime" }, popularity: 1000 }
          ]
        }
      }
    }.to_json

    stub_request(:post, "https://graphql.anilist.co")
      .to_return(status: 200, body: response_body)

    result = ScrapingServices::AnilistClient.fetch_trending_anime

    assert_not_nil result
    assert_equal "Test Anime", result["data"]["Page"]["media"].first["title"]["english"]
  end

  test "sends GraphQL body as JSON" do
    stub_request(:post, "https://graphql.anilist.co")
      .with(headers: { "Content-Type" => "application/json" })
      .to_return(status: 200, body: '{"data":{"Page":{"media":[]}}}')

    result = ScrapingServices::AnilistClient.fetch_trending_anime
    assert_not_nil result
  end

  test "returns nil on HTTP error" do
    stub_request(:post, "https://graphql.anilist.co")
      .to_return(status: 500, body: '{"errors":[{"message":"Internal error"}]}')

    result = ScrapingServices::AnilistClient.fetch_trending_anime

    assert_nil result
  end

  test "returns nil on timeout" do
    stub_request(:post, "https://graphql.anilist.co").to_timeout

    result = ScrapingServices::AnilistClient.fetch_trending_anime

    assert_nil result
  end
end
