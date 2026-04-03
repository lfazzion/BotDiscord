# frozen_string_literal: true

require 'test_helper'

class ScrapeYoutubeJobTest < ActiveJob::TestCase
  setup do
    @profile = create(:social_profile, :youtube, platform_username: 'test_channel')
    @metadata = {
      channel_id: 'UC123',
      title: 'Test Channel',
      description: 'A channel',
      subscriber_count: 50_000,
      video_count: 100,
      thumbnail_url: 'https://example.com/thumb.jpg'
    }
    @videos = [
      {
        platform_post_id: 'vid1',
        title: 'Video 1',
        post_type: 'video',
        posted_at: 1.day.ago,
        views_count: 1000,
        thumbnail_url: 'https://example.com/t1.jpg',
        video_url: 'https://youtube.com/watch?v=vid1'
      },
      {
        platform_post_id: 'vid2',
        title: 'Video 2',
        post_type: 'video',
        posted_at: 2.days.ago,
        views_count: 2000,
        thumbnail_url: 'https://example.com/t2.jpg',
        video_url: 'https://youtube.com/watch?v=vid2'
      }
    ]
  end

  test 'should enqueue in default queue' do
    assert_equal 'default', ScrapeYoutubeJob.new.queue_name
  end

  test 'should raise ArgumentError for non-YouTube profile' do
    twitter_profile = create(:social_profile, :twitter, platform_username: 'twitter_user')

    assert_raises(ArgumentError) do
      ScrapeYoutubeJob.perform_now(twitter_profile.id)
    end
  end

  test 'should update profile, create posts and snapshot on success' do
    ScrapingServices::YoutubeScraperService.stubs(:extract_channel_metadata).returns(@metadata)
    ScrapingServices::YoutubeScraperService.stubs(:extract_videos_detailed).returns(@videos)

    assert_difference 'SocialPost.count', 2 do
      ScrapeYoutubeJob.perform_now(@profile.id)
    end

    @profile.reload
    assert_equal 'Test Channel', @profile.display_name
    assert_equal 50_000, @profile.followers_count
    assert_equal 'success', @profile.collection_status
    assert_not_nil @profile.last_collected_at
    assert_equal 1, ProfileSnapshot.where(social_profile: @profile).count
  end

  test 'should skip when metadata is nil' do
    ScrapingServices::YoutubeScraperService.stubs(:extract_channel_metadata).returns(nil)

    assert_no_difference 'ProfileSnapshot.count' do
      assert_no_difference 'SocialPost.count' do
        ScrapeYoutubeJob.perform_now(@profile.id)
      end
    end

    @profile.reload
    assert_nil @profile.last_collected_at
  end

  test 'should handle empty videos array' do
    ScrapingServices::YoutubeScraperService.stubs(:extract_channel_metadata).returns(@metadata)
    ScrapingServices::YoutubeScraperService.stubs(:extract_videos_detailed).returns([])

    assert_no_difference 'SocialPost.count' do
      ScrapeYoutubeJob.perform_now(@profile.id)
    end

    @profile.reload
    assert_equal 'success', @profile.collection_status
    assert_equal 1, ProfileSnapshot.where(social_profile: @profile).count
  end

  test 'should skip when profile was recently collected' do
    @profile.update!(last_collected_at: 30.minutes.ago)
    ScrapingServices::YoutubeScraperService.expects(:extract_channel_metadata).never

    ScrapeYoutubeJob.perform_now(@profile.id)
  end

  test 'should be idempotent for snapshots within same hour' do
    ScrapingServices::YoutubeScraperService.stubs(:extract_channel_metadata).returns(@metadata)
    ScrapingServices::YoutubeScraperService.stubs(:extract_videos_detailed).returns(@videos)

    ScrapeYoutubeJob.perform_now(@profile.id)
    first_count = ProfileSnapshot.where(social_profile: @profile).count

    ScrapeYoutubeJob.perform_now(@profile.id)

    assert_equal first_count, ProfileSnapshot.where(social_profile: @profile).count
  end

  test 'should set error status on StandardError' do
    ScrapingServices::YoutubeScraperService.stubs(:extract_channel_metadata).raises(StandardError.new('yt-dlp not found'))

    assert_raises(StandardError) do
      ScrapeYoutubeJob.perform_now(@profile.id)
    end

    @profile.reload
    assert_equal 'error', @profile.collection_status
  end

  test 'should set rate_limited status on RateLimitError' do
    ScrapingServices::YoutubeScraperService.stubs(:extract_channel_metadata).raises(ScrapingServices::RateLimitError.new('429'))

    ScrapeYoutubeJob.perform_now(@profile.id)

    @profile.reload
    assert_equal 'rate_limited', @profile.collection_status
  end
end
