# frozen_string_literal: true

require 'test_helper'

class ScrapeInstagramJobTest < ActiveJob::TestCase
  setup do
    @profile = create(:social_profile, :instagram, platform_username: 'test_user')
    @scraper_data = {
      user_id: '12345',
      username: 'test_user',
      full_name: 'Test User',
      biography: 'A bio',
      followers_count: 10_000,
      following_count: 500,
      posts_count: 200,
      is_private: false,
      is_verified: true,
      profile_pic_url: 'https://example.com/pic.jpg'
    }
  end

  test 'should enqueue in default queue' do
    assert_equal 'default', ScrapeInstagramJob.new.queue_name
  end

  test 'should update profile and create snapshot on success' do
    mock_scraper = mock('scraper')
    mock_scraper.stubs(:scrape_profile).returns(@scraper_data)
    mock_scraper.stubs(:close)
    ScrapingServices::InstagramScraper.stubs(:new).returns(mock_scraper)

    ScrapeInstagramJob.perform_now(@profile.id)

    @profile.reload
    assert_equal 'Test User', @profile.display_name
    assert_equal 10_000, @profile.followers_count
    assert_equal 'success', @profile.collection_status
    assert_not_nil @profile.last_collected_at
    assert_equal 1, ProfileSnapshot.where(social_profile: @profile).count
  end

  test 'should skip when scraper returns nil' do
    mock_scraper = mock('scraper')
    mock_scraper.stubs(:scrape_profile).returns(nil)
    mock_scraper.stubs(:close)
    ScrapingServices::InstagramScraper.stubs(:new).returns(mock_scraper)

    ScrapeInstagramJob.perform_now(@profile.id)

    @profile.reload
    assert_nil @profile.last_collected_at
    assert_equal 0, ProfileSnapshot.where(social_profile: @profile).count
  end

  test 'should update profile with NodriverRunner (Python scraper)' do
    ENV['USE_NODRIVER'] = 'true'
    ScrapingServices::NodriverRunner.stubs(:scrape_instagram_profile).returns(@scraper_data)

    ScrapeInstagramJob.perform_now(@profile.id)

    @profile.reload
    assert_equal 'Test User', @profile.display_name
    assert_equal 10_000, @profile.followers_count
    assert_equal 'success', @profile.collection_status
  ensure
    ENV.delete('USE_NODRIVER')
  end

  test 'should skip when profile was recently collected' do
    @profile.update!(last_collected_at: 30.minutes.ago)
    ScrapingServices::InstagramScraper.expects(:new).never

    ScrapeInstagramJob.perform_now(@profile.id)
  end

  test 'should be idempotent for snapshots within same hour' do
    mock_scraper = mock('scraper')
    mock_scraper.stubs(:scrape_profile).returns(@scraper_data)
    mock_scraper.stubs(:close)
    ScrapingServices::InstagramScraper.stubs(:new).returns(mock_scraper)

    ScrapeInstagramJob.perform_now(@profile.id)
    first_count = ProfileSnapshot.where(social_profile: @profile).count

    ScrapeInstagramJob.perform_now(@profile.id)

    assert_equal first_count, ProfileSnapshot.where(social_profile: @profile).count
  end

  test 'should set error status on StandardError' do
    mock_scraper = mock('scraper')
    mock_scraper.stubs(:scrape_profile).raises(StandardError.new('timeout'))
    mock_scraper.stubs(:close)
    ScrapingServices::InstagramScraper.stubs(:new).returns(mock_scraper)

    assert_raises(StandardError) do
      ScrapeInstagramJob.perform_now(@profile.id)
    end

    @profile.reload
    assert_equal 'error', @profile.collection_status
  end

  test 'should set rate_limited status on RateLimitError' do
    mock_scraper = mock('scraper')
    mock_scraper.stubs(:scrape_profile).raises(ScrapingServices::RateLimitError.new('429'))
    mock_scraper.stubs(:close)
    ScrapingServices::InstagramScraper.stubs(:new).returns(mock_scraper)

    ScrapeInstagramJob.perform_now(@profile.id)

    @profile.reload
    assert_equal 'rate_limited', @profile.collection_status
  end
end
