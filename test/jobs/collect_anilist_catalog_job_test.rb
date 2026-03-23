# frozen_string_literal: true

require 'test_helper'

class CollectAnilistCatalogJobTest < ActiveJob::TestCase
  test "should enqueue in default queue" do
    assert_equal 'default', CollectAnilistCatalogJob.new.queue_name
  end

  test "should create catalog from Anilist data" do
    ScrapingServices::AnilistClient.stubs(:fetch_trending_anime).returns({
      "data" => {
        "Page" => {
          "media" => [
            {
              "id" => 4001,
              "title" => { "english" => "Test Anime", "romaji" => "Tesuto Anime" },
              "description" => "<p>A great anime</p>",
              "startDate" => { "year" => 2026, "month" => 4, "day" => 1 },
              "popularity" => 5000,
              "averageScore" => 85,
              "episodes" => 12,
              "coverImage" => { "large" => "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/test.jpg" },
              "genres" => ["Action", "Drama"],
              "status" => "RELEASING"
            }
          ]
        }
      }
    })

    assert_difference 'ExternalCatalog.count', 1 do
      CollectAnilistCatalogJob.perform_now
    end

    catalog = ExternalCatalog.find_by(source: "anilist", external_id: "4001")
    assert_not_nil catalog
    assert_equal "Test Anime", catalog.title
    assert_equal "anime", catalog.media_type
    assert_equal "A great anime", catalog.description
    assert_equal 8.5, catalog.vote_average
    assert_equal "ja", catalog.original_language
  end

  test "should use romaji title when english is nil" do
    ScrapingServices::AnilistClient.stubs(:fetch_trending_anime).returns({
      "data" => {
        "Page" => {
          "media" => [
            {
              "id" => 4002,
              "title" => { "english" => nil, "romaji" => "Romaji Title" },
              "startDate" => { "year" => 2026, "month" => 1, "day" => 1 },
              "status" => "FINISHED"
            }
          ]
        }
      }
    })

    CollectAnilistCatalogJob.perform_now

    catalog = ExternalCatalog.find_by(source: "anilist", external_id: "4002")
    assert_equal "Romaji Title", catalog.title
  end

  test "should be idempotent" do
    create(:external_catalog, source: "anilist", external_id: "4001", title: "Existing", updated_at: 25.hours.ago)

    ScrapingServices::AnilistClient.stubs(:fetch_trending_anime).returns({
      "data" => {
        "Page" => {
          "media" => [
            { "id" => 4001, "title" => { "english" => "Updated Anime" }, "status" => "FINISHED" }
          ]
        }
      }
    })

    assert_no_difference 'ExternalCatalog.count' do
      CollectAnilistCatalogJob.perform_now
    end

    catalog = ExternalCatalog.find_by(source: "anilist", external_id: "4001")
    assert_equal "Updated Anime", catalog.title
  end

  test "should not crash when client returns nil" do
    ScrapingServices::AnilistClient.stubs(:fetch_trending_anime).returns(nil)

    assert_no_difference 'ExternalCatalog.count' do
      CollectAnilistCatalogJob.perform_now
    end
  end
end
