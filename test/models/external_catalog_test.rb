# frozen_string_literal: true

require 'test_helper'

class ExternalCatalogTest < ActiveSupport::TestCase
  setup do
    @catalog = build(:external_catalog)
  end

  test "should be valid with valid attributes" do
    assert @catalog.valid?
  end

  test "source should be present" do
    @catalog.source = nil
    assert_not @catalog.valid?
    assert_includes @catalog.errors[:source], "can't be blank"
  end

  test "source should be in allowed list" do
    @catalog.source = "invalid_source"
    assert_not @catalog.valid?
    assert_includes @catalog.errors[:source], "is not included in the list"
  end

  test "external_id should be present" do
    @catalog.external_id = nil
    assert_not @catalog.valid?
    assert_includes @catalog.errors[:external_id], "can't be blank"
  end

  test "title should be present" do
    @catalog.title = nil
    assert_not @catalog.valid?
    assert_includes @catalog.errors[:title], "can't be blank"
  end

  test "media_type should be in allowed list" do
    @catalog.media_type = "invalid_type"
    assert_not @catalog.valid?
    assert_includes @catalog.errors[:media_type], "is not included in the list"
  end

  test "media_type can be nil" do
    @catalog.media_type = nil
    assert @catalog.valid?
  end

  test "should be unique per source and external_id" do
    create(:external_catalog, source: "tmdb", external_id: "12345")
    duplicate = build(:external_catalog, source: "tmdb", external_id: "12345")
    assert_not duplicate.valid?
  end

  test "should allow same external_id on different sources" do
    create(:external_catalog, source: "tmdb", external_id: "12345")
    different_source = build(:external_catalog, source: "igdb", external_id: "12345")
    assert different_source.valid?
  end

  test "by_source scope should filter correctly" do
    tmdb = create(:external_catalog, source: "tmdb")
    igdb = create(:external_catalog, source: "igdb")

    assert_includes ExternalCatalog.by_source("tmdb"), tmdb
    assert_not_includes ExternalCatalog.by_source("tmdb"), igdb
  end

  test "by_media_type scope should filter correctly" do
    movie = create(:external_catalog, media_type: "movie")
    game = create(:external_catalog, media_type: "game")

    assert_includes ExternalCatalog.by_media_type("movie"), movie
    assert_not_includes ExternalCatalog.by_media_type("movie"), game
  end

  test "upcoming scope should return records with status upcoming and release_date" do
    upcoming = create(:external_catalog, status: "upcoming", release_date: 30.days.from_now.to_date)
    released = create(:external_catalog, status: "released", release_date: 10.days.from_now.to_date)
    no_date = create(:external_catalog, status: "upcoming", release_date: nil)

    assert_includes ExternalCatalog.upcoming, upcoming
    assert_not_includes ExternalCatalog.upcoming, released
    assert_not_includes ExternalCatalog.upcoming, no_date
  end

  test "popular scope should return records ordered by popularity desc" do
    create(:external_catalog, popularity: 10.0)
    high = create(:external_catalog, popularity: 99.0)

    results = ExternalCatalog.popular
    assert_equal high, results.first
  end

  test "with_nil_metrics trait should accept nil values" do
    catalog = build(:external_catalog, :with_nil_metrics)

    assert_nil catalog.popularity
    assert_nil catalog.vote_average
    assert_nil catalog.vote_count
    assert catalog.valid?
  end
end
