# frozen_string_literal: true

module ScrapingLimits
  RATE_LIMITS = {
    instagram: {
      requests_per_hour: 60,
      backoff: 6.hours,
      use_python_scraper: true
    },
    twitter: {
      requests_per_hour: 40,
      backoff: 6.hours,
      use_python_scraper: true
    },
    youtube: {
      requests_per_hour: 100,
      backoff: 2.hours,
      use_python_scraper: false
    },
    rss: {
      requests_per_hour: 200,
      backoff: 1.hour,
      use_python_scraper: false
    }
  }.freeze

  PROXY_CONFIG = {
    enabled: ENV['USE_PROXY'] == 'true',
    pool_rotation: true,
    sticky_session: true,
    min_success_rate: 0.8
  }.freeze

  class << self
    def for_platform(platform)
      RATE_LIMITS[platform.to_sym] || RATE_LIMITS[:instagram]
    end
  end
end
