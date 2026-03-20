# frozen_string_literal: true

module ScrapingServices
  class TwitterScraper < FerrumScraperBase
    TWITTER_BASE_URL = 'https://twitter.com'
    X_BASE_URL = 'https://x.com'

    USER_SCRIPT = <<~JS
      (function() {
        try {
          var state = window.__INITIAL_STATE__;
          if (state && state.entities && state.entities.users) {
            var users = state.entities.users;
            var keys = Object.keys(users);
            if (keys.length > 0) {
              var user = users[keys[0]];
              return JSON.stringify({
                user_id: user.id_str,
                username: user.screen_name,
                display_name: user.name,
                bio: user.description,
                followers_count: user.followers_count,
                following_count: user.friends_count,
                posts_count: user.statuses_count,
                is_verified: user.verified,
                profile_image_url: user.profile_image_url_https
              });
            }
          }
          return null;
        } catch(e) {
          return JSON.stringify({error: e.message});
        }
      })()
    JS

    TWEETS_SCRIPT = <<~JS
      (function() {
        try {
          var tweets = [];
          var items = document.querySelectorAll('[data-testid="tweet"]');
          items.forEach(function(item) {
            try {
              var tweetText = item.querySelector('[data-testid="tweetText"]');
              var timeEl = item.querySelector('time');
              var linkEl = item.querySelector('a[href*="/status/"]');
              var likesEl = item.querySelector('[data-testid="like"]');
              var retweetsEl = item.querySelector('[data-testid="retweet"]');
              var repliesEl = item.querySelector('[data-testid="reply"]');

              var statusUrl = linkEl ? linkEl.getAttribute('href') : '';
              var statusMatch = statusUrl.match(/\\/status\\/(\\d+)/);

              tweets.push({
                platform_post_id: statusMatch ? statusMatch[1] : null,
                caption: tweetText ? tweetText.innerText : null,
                posted_at: timeEl ? timeEl.getAttribute('datetime') : null,
                post_type: 'text',
                likes_count: null,
                comments_count: null,
                shares_count: null
              });
            } catch(e) {}
          });
          return JSON.stringify(tweets);
        } catch(e) {
          return JSON.stringify({error: e.message});
        }
      })()
    JS

    def scrape_profile(username)
      base = username.start_with?('x_') ? X_BASE_URL : TWITTER_BASE_URL
      visit("#{base}/#{username}", wait_for: "[data-testid='UserName']")

      result = execute_script(USER_SCRIPT)
      return nil if result.nil?

      parsed = JSON.parse(result)
      raise ScrapingServices::RateLimitError, 'Perfil bloqueado ou suspenso' if parsed['error']

      parsed.deep_symbolize_keys
    rescue JSON::ParserError => e
      Rails.logger.error "[TwitterScraper] JSON inválido ao scraping perfil #{username}: #{e.message}"
      nil
    end

    def scrape_tweets(username, limit: 20)
      base = username.start_with?('x_') ? X_BASE_URL : TWITTER_BASE_URL
      visit("#{base}/#{username}", wait_for: "[data-testid='tweet']")

      all_tweets = []
      scroll_attempts = 0
      max_scrolls = (limit / 10.0).ceil + 3

      while all_tweets.size < limit && scroll_attempts < max_scrolls
        result = execute_script(TWEETS_SCRIPT)
        break if result.nil?

        tweets = JSON.parse(result)
        tweets.each do |tweet|
          break if all_tweets.size >= limit
          next if tweet['platform_post_id'].nil?

          all_tweets << parse_tweet(tweet)
        end

        browser.evaluate('window.scrollTo(0, document.body.scrollHeight)')
        random_delay
        scroll_attempts += 1
      end

      all_tweets.uniq { |t| t[:platform_post_id] }
    rescue JSON::ParserError => e
      Rails.logger.error "[TwitterScraper] JSON inválido ao scraping tweets #{username}: #{e.message}"
      all_tweets || []
    end

    private

    def parse_tweet(tweet)
      {
        platform_post_id: tweet['platform_post_id'].to_s,
        post_type: 'text',
        caption: tweet['caption'],
        posted_at: tweet['posted_at'] ? Time.parse(tweet['posted_at']) : nil,
        likes_count: tweet['likes_count'],
        comments_count: tweet['comments_count'],
        shares_count: tweet['shares_count']
      }
    end
  end
end
