# frozen_string_literal: true

require 'test_helper'

class CollectIgdbCatalogJobTest < ActiveJob::TestCase
  test "should enqueue in default queue" do
    assert_equal 'default', CollectIgdbCatalogJob.new.queue_name
  end

  test "should create catalog from IGDB data" do
    ScrapingServices::IgdbClient.stubs(:fetch_popular_games).returns([
      {
        "id" => 3001,
        "name" => "Test Game",
        "summary" => "A great game",
        "first_release_date" => 1700000000,
        "rating" => 90.5,
        "rating_count" => 1500,
        "cover" => { "url" => "https://images.igdb.com/igdb/image/upload/t_cover_big/co1234.jpg" },
        "genres" => [{ "name" => "RPG" }, { "name" => "Adventure" }],
        "status" => 0
      }
    ])
    ScrapingServices::IgdbClient.stubs(:fetch_upcoming_games).returns([])

    assert_difference 'ExternalCatalog.count', 1 do
      CollectIgdbCatalogJob.perform_now
    end

    catalog = ExternalCatalog.find_by(source: "igdb", external_id: "3001")
    assert_not_nil catalog
    assert_equal "Test Game", catalog.title
    assert_equal "game", catalog.media_type
    assert_equal "RPG,Adventure", catalog.genres
    assert_equal "released", catalog.status
  end

  test "should be idempotent" do
    create(:external_catalog, source: "igdb", external_id: "3001", title: "Existing", updated_at: 25.hours.ago)

    ScrapingServices::IgdbClient.stubs(:fetch_popular_games).returns([
      { "id" => 3001, "name" => "Updated Game", "first_release_date" => 1700000000, "rating" => 95.0, "rating_count" => 2000, "status" => 0 }
    ])
    ScrapingServices::IgdbClient.stubs(:fetch_upcoming_games).returns([])

    assert_no_difference 'ExternalCatalog.count' do
      CollectIgdbCatalogJob.perform_now
    end

    catalog = ExternalCatalog.find_by(source: "igdb", external_id: "3001")
    assert_equal "Updated Game", catalog.title
  end

  test "should skip records updated within 24 hours" do
    create(:external_catalog, source: "igdb", external_id: "3001", title: "Old Game", updated_at: 1.hour.ago)

    ScrapingServices::IgdbClient.stubs(:fetch_popular_games).returns([
      { "id" => 3001, "name" => "New Game", "first_release_date" => 1700000000, "status" => 0 }
    ])
    ScrapingServices::IgdbClient.stubs(:fetch_upcoming_games).returns([])

    CollectIgdbCatalogJob.perform_now

    catalog = ExternalCatalog.find_by(source: "igdb", external_id: "3001")
    assert_equal "Old Game", catalog.title
  end

  test "should not crash when client returns nil" do
    ScrapingServices::IgdbClient.stubs(:fetch_popular_games).returns(nil)
    ScrapingServices::IgdbClient.stubs(:fetch_upcoming_games).returns(nil)

    assert_no_difference 'ExternalCatalog.count' do
      CollectIgdbCatalogJob.perform_now
    end
  end
end
