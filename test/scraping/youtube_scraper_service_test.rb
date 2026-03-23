# frozen_string_literal: true

require 'test_helper'

class YoutubeScraperServiceTest < ActiveSupport::TestCase
  test 'extract_channel_metadata returns valid data when yt-dlp available' do
    skip 'yt-dlp not installed' unless system('which yt-dlp > /dev/null 2>&1')

    result = ScrapingServices::YoutubeScraperService.extract_channel_metadata(
      'https://www.youtube.com/@YouTube'
    )

    assert_not_nil result
    assert result[:channel_id].present?
    assert result[:title].present?
  end

  test 'extract_videos_batch parses output correctly' do
    skip 'yt-dlp not installed' unless system('which yt-dlp > /dev/null 2>&1')

    videos = ScrapingServices::YoutubeScraperService.extract_videos_batch(
      'https://www.youtube.com/@YouTube',
      limit: 3
    )

    assert videos.is_a?(Array)
    return if videos.empty?

    video = videos.first
    assert video[:platform_post_id].present?
    assert video[:post_type] == 'video'
  end

  test 'parse_metadata handles missing fields' do
    data = { 'id' => 'UC123', 'title' => 'Test Channel' }
    result = ScrapingServices::YoutubeScraperService.send(:parse_metadata, data)

    assert_equal 'UC123', result[:channel_id]
    assert_equal 'Test Channel', result[:title]
    assert_nil result[:subscriber_count]
  end

  test 'parse_video_list handles empty output' do
    videos = ScrapingServices::YoutubeScraperService.send(:parse_video_list, '')
    assert_empty videos
  end

  test 'returns nil when command times out' do
    Timeout.expects(:timeout).raises(Timeout::Error)

    result = ScrapingServices::YoutubeScraperService.extract_channel_metadata(
      'https://www.youtube.com/@YouTube'
    )

    assert_nil result
  end
end
