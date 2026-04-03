# frozen_string_literal: true

module ScrapingServices
  class InstagramScraper < FerrumScraperBase
    INSTAGRAM_BASE_URL = 'https://www.instagram.com'

    PROFILE_SCRIPT = <<~JS
      (function() {
        try {
          var data = window._sharedData;
          if (data && data.entry_data && data.entry_data.ProfilePage && data.entry_data.ProfilePage[0]) {
            var user = data.entry_data.ProfilePage[0].graphql.user;
            return JSON.stringify({
              user_id: user.id,
              username: user.username,
              full_name: user.full_name,
              biography: user.biography,
              followers_count: user.edge_followed_by.count,
              following_count: user.edge_follow.count,
              posts_count: user.edge_owner_to_timeline_media.count,
              is_private: user.is_private,
              is_verified: user.is_verified,
              profile_pic_url: user.profile_pic_url_hd
            });
          }
          return null;
        } catch(e) {
          return JSON.stringify({error: e.message});
        }
      })()
    JS

    POSTS_SCRIPT = <<~JS
      (function() {
        try {
          var data = window._sharedData;
          if (data && data.entry_data && data.entry_data.ProfilePage && data.entry_data.ProfilePage[0]) {
            var media = data.entry_data.ProfilePage[0].graphql.user.edge_owner_to_timeline_media;
            var posts = media.edges.map(function(edge) {
              var node = edge.node;
              return {
                platform_post_id: node.id,
                post_type: node.__typename,
                caption: node.edge_media_to_caption.edges.length > 0 ? node.edge_media_to_caption.edges[0].node.text : null,
                likes_count: node.edge_media_preview_like ? node.edge_media_preview_like.count : null,
                comments_count: node.edge_media_to_comment ? node.edge_media_to_comment.count : null,
                posted_at: node.taken_at_timestamp,
                thumbnail_url: node.thumbnail_src,
                is_video: node.is_video,
                video_url: node.is_video ? node.video_url : null,
                shortcode: node.shortcode
              };
            });
            return JSON.stringify(posts);
          }
          return null;
        } catch(e) {
          return JSON.stringify({error: e.message});
        }
      })()
    JS

    def scrape_profile(username)
      visit("#{INSTAGRAM_BASE_URL}/#{username}/", wait_for: 'header')

      result = execute_script(PROFILE_SCRIPT)
      return nil if result.nil?

      parsed = JSON.parse(result)
      raise ScrapingServices::RateLimitError, 'Perfil privado ou bloqueado' if parsed['error']

      parsed.deep_symbolize_keys
    rescue JSON::ParserError => e
      Rails.logger.error "[InstagramScraper] JSON inválido ao scraping perfil #{username}: #{e.message}"
      nil
    end

    def scrape_posts(username, limit: 12)
      visit("#{INSTAGRAM_BASE_URL}/#{username}/", wait_for: 'article')

      all_posts = []
      scroll_attempts = 0
      max_scrolls = (limit / 12.0).ceil + 2

      while all_posts.size < limit && scroll_attempts < max_scrolls
        result = execute_script(POSTS_SCRIPT)
        break if result.nil?

        posts = JSON.parse(result)
        posts.each do |post|
          break if all_posts.size >= limit

          all_posts << parse_post(post)
        end

        browser.evaluate('window.scrollTo(0, document.body.scrollHeight)')
        random_delay
        scroll_attempts += 1
      end

      all_posts.uniq { |p| p[:platform_post_id] }
    rescue JSON::ParserError => e
      Rails.logger.error "[InstagramScraper] JSON inválido ao scraping posts #{username}: #{e.message}"
      all_posts || []
    end

    private

    def parse_post(post)
      post_type = case post['post_type']
                  when 'GraphImage' then 'image'
                  when 'GraphVideo' then 'video'
                  when 'GraphSidecar' then 'image'
                  else 'image'
                  end

      {
        platform_post_id: post['platform_post_id'].to_s,
        post_type: post_type,
        content: post['caption'],
        likes_count: post['likes_count'],
        comments_count: post['comments_count'],
        posted_at: post['posted_at'] ? Time.at(post['posted_at']) : nil,
        thumbnail_url: post['thumbnail_url'],
        video_url: post['video_url'],
        shortcode: post['shortcode']
      }
    end
  end
end
