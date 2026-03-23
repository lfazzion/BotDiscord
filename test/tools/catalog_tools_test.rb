# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/tools/tool_base'
require_relative '../../app/tools/catalog_tools'

class CatalogToolsTest < ActiveSupport::TestCase
  test 'upcoming com source filter' do
    create(:external_catalog, source: 'tmdb', title: 'Movie A', media_type: 'movie', status: 'upcoming',
                              release_date: 1.month.from_now)
    create(:external_catalog, source: 'igdb', title: 'Game B', media_type: 'game', status: 'upcoming',
                              release_date: 2.months.from_now)

    tool = UpcomingCatalogTool.new
    result = tool.execute(source: 'tmdb')
    assert_equal :success, result[:status]
    assert_equal 1, result[:data].size
    assert_equal 'tmdb', result[:data].first[:source]
  end

  test 'upcoming com media_type filter' do
    create(:external_catalog, source: 'tmdb', title: 'Movie A', media_type: 'movie', status: 'upcoming',
                              release_date: 1.month.from_now)
    create(:external_catalog, source: 'tmdb', title: 'Show B', media_type: 'tv', status: 'upcoming',
                              release_date: 2.months.from_now)

    tool = UpcomingCatalogTool.new
    result = tool.execute(media_type: 'movie')
    assert_equal :success, result[:status]
    assert_equal 1, result[:data].size
    assert_equal 'movie', result[:data].first[:media_type]
  end

  test 'popular ordena por popularity' do
    create(:external_catalog, source: 'tmdb', title: 'Popular A', popularity: 50.0)
    create(:external_catalog, source: 'tmdb', title: 'Popular B', popularity: 90.0)

    tool = PopularCatalogTool.new
    result = tool.execute
    assert_equal :success, result[:status]
    assert_equal 90.0, result[:data].first[:popularity]
  end

  test 'popular respeita limit' do
    create_list(:external_catalog, 5, source: 'tmdb', popularity: 10.0)
    tool = PopularCatalogTool.new
    result = tool.execute(limit: 2)
    assert_equal :success, result[:status]
    assert_operator result[:data].size, :<=, 2
  end
end
