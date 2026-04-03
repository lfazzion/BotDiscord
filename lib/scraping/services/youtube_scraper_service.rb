# frozen_string_literal: true

require 'open3'
require 'json'
require 'timeout'

module ScrapingServices
  class YoutubeScraperService
    class << self
      def extract_channel_metadata(channel_url, proxy: nil)
        command = build_metadata_command(channel_url, proxy)
        output, _, status = execute_yt_dlp(command)

        return nil unless status.success? && output.strip.present?

        parse_metadata(JSON.parse(output.strip))
      rescue JSON::ParserError => e
        Rails.logger.error "[YoutubeScraperService] JSON inválido ao extrair metadata: #{e.message}"
        nil
      rescue StandardError => e
        Rails.logger.error "[YoutubeScraperService] Erro ao extrair metadata: #{e.message}"
        nil
      end

      def extract_videos_detailed(channel_url, limit: 10, proxy: nil)
        command = build_videos_command(channel_url, limit, proxy)
        output, _, status = execute_yt_dlp(command)

        return extract_videos_flat(channel_url, limit: limit, proxy: proxy) unless status.success? && output.strip.present?

        parse_video_list(output.strip)
      rescue StandardError => e
        Rails.logger.error "[YoutubeScraperService] Erro ao extrair videos detalhados: #{e.message}"
        extract_videos_flat(channel_url, limit: limit, proxy: proxy)
      end

      private

      def extract_videos_flat(channel_url, limit: 10, proxy: nil)
        command = build_videos_flat_command(channel_url, limit, proxy)
        output, _, status = execute_yt_dlp(command)

        return [] unless status.success? && output.strip.present?

        parse_video_list(output.strip)
      rescue StandardError => e
        Rails.logger.error "[YoutubeScraperService] Erro ao extrair videos flat: #{e.message}"
        []
      end

      def build_metadata_command(channel_url, proxy)
        cmd = [
          'yt-dlp',
          '--dump-json',
          '--no-download',
          '--flat-playlist',
          '--playlist-items', '1',
          channel_url
        ]
        cmd += ['--proxy', proxy] if proxy.present?
        cmd
      end

      def build_videos_command(channel_url, limit, proxy)
        videos_url = "#{channel_url}/videos"
        cmd = [
          'yt-dlp',
          '--dump-json',
          '--no-download',
          '--playlist-end', limit.to_s,
          videos_url
        ]
        cmd += ['--proxy', proxy] if proxy.present?
        cmd
      end

      def build_videos_flat_command(channel_url, limit, proxy)
        videos_url = "#{channel_url}/videos"
        cmd = [
          'yt-dlp',
          '--flat-playlist',
          '--dump-json',
          '--no-download',
          '--playlist-end', limit.to_s,
          videos_url
        ]
        cmd += ['--proxy', proxy] if proxy.present?
        cmd
      end

      def execute_yt_dlp(command)
        Timeout.timeout(120) { Open3.capture3(*command) }
      end

      def parse_metadata(data)
        {
          channel_id: data['channel_id'] || data['playlist_channel_id'] || data['id'],
          title: data['channel'] || data['uploader'] || data['playlist_channel'] || data['playlist_uploader'] || data['title'],
          description: data['description'],
          subscriber_count: data['channel_follower_count'],
          video_count: data['playlist_count'],
          thumbnail_url: data['thumbnail'] || data['channel_thumbnail_url'],
          avatar_url: data['thumbnail'] || data['channel_thumbnail_url']
        }
      end

      def parse_video_list(output)
        videos = []
        output.each_line do |line|
          next if line.strip.empty?

          data = JSON.parse(line.strip)
          videos << {
            platform_post_id: data['id'],
            title: data['title'],
            post_type: 'video',
            posted_at: data['upload_date'] ? Date.parse(data['upload_date']) : nil,
            views_count: data['view_count'],
            likes_count: data['like_count'],
            comments_count: data['comment_count'],
            thumbnail_url: data['thumbnail'],
            video_url: data['url'] || "https://www.youtube.com/watch?v=#{data['id']}"
          }
        rescue JSON::ParserError
          next
        end
        videos
      end
    end
  end
end
