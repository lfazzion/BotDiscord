# frozen_string_literal: true

require 'test_helper'

class CollectRawgCatalogJobTest < ActiveJob::TestCase
  test "should enqueue in default queue" do
    assert_equal 'default', CollectRawgCatalogJob.new.queue_name
  end

  test "should create catalog from RAWG data" do
    future_date = (Date.current + 30.days).to_s
    ScrapingServices::RawgClient.stubs(:fetch_upcoming_games).returns({
      "results" => [
        {
          "id" => 5001,
          "name" => "Test RAWG Game",
          "released" => future_date,
          "rating" => 4.2,
          "ratings_count" => 500,
          "added" => 8000,
          "background_image" => "https://media.rawg.io/media/games/test.jpg",
          "genres" => [{ "name" => "RPG" }, { "name" => "Indie" }]
        }
      ]
    })
    ScrapingServices::RawgClient.stubs(:fetch_popular_games).returns({ "results" => [] })

    assert_difference 'ExternalCatalog.count', 1 do
      CollectRawgCatalogJob.perform_now
    end

    catalog = ExternalCatalog.find_by(source: "rawg", external_id: "5001")
    assert_not_nil catalog
    assert_equal "Test RAWG Game", catalog.title
    assert_equal "game", catalog.media_type
    assert_equal "RPG,Indie", catalog.genres
    assert_equal "upcoming", catalog.status
    assert_equal 8000, catalog.popularity
    assert_in_delta 4.2, catalog.vote_average, 0.01
  end

  test "should set status to released for past release dates" do
    past_date = (Date.current - 30.days).to_s
    ScrapingServices::RawgClient.stubs(:fetch_upcoming_games).returns({ "results" => [] })
    ScrapingServices::RawgClient.stubs(:fetch_popular_games).returns({
      "results" => [
        {
          "id" => 5002,
          "name" => "Released Game",
          "released" => past_date,
          "rating" => 3.8,
          "ratings_count" => 200,
          "added" => 5000,
          "genres" => []
        }
      ]
    })

    CollectRawgCatalogJob.perform_now

    catalog = ExternalCatalog.find_by(source: "rawg", external_id: "5002")
    assert_equal "released", catalog.status
  end

  test "should be idempotent" do
    create(:external_catalog, source: "rawg", external_id: "5001", title: "Existing", updated_at: 25.hours.ago)

    ScrapingServices::RawgClient.stubs(:fetch_upcoming_games).returns({
      "results" => [
        { "id" => 5001, "name" => "Updated Game", "released" => nil, "rating" => 0, "ratings_count" => 0, "added" => 100 }
      ]
    })
    ScrapingServices::RawgClient.stubs(:fetch_popular_games).returns({ "results" => [] })

    assert_no_difference 'ExternalCatalog.count' do
      CollectRawgCatalogJob.perform_now
    end

    catalog = ExternalCatalog.find_by(source: "rawg", external_id: "5001")
    assert_equal "Updated Game", catalog.title
  end

  test "should skip records updated within 24 hours" do
    create(:external_catalog, source: "rawg", external_id: "5001", title: "Old Game", updated_at: 1.hour.ago)

    ScrapingServices::RawgClient.stubs(:fetch_upcoming_games).returns({
      "results" => [
        { "id" => 5001, "name" => "New Game", "released" => nil, "rating" => 0, "ratings_count" => 0, "added" => 100 }
      ]
    })
    ScrapingServices::RawgClient.stubs(:fetch_popular_games).returns({ "results" => [] })

    CollectRawgCatalogJob.perform_now

    catalog = ExternalCatalog.find_by(source: "rawg", external_id: "5001")
    assert_equal "Old Game", catalog.title
  end

  test "should not crash when client returns nil" do
    ScrapingServices::RawgClient.stubs(:fetch_upcoming_games).returns(nil)
    ScrapingServices::RawgClient.stubs(:fetch_popular_games).returns(nil)

    assert_no_difference 'ExternalCatalog.count' do
      CollectRawgCatalogJob.perform_now
    end
  end
end
