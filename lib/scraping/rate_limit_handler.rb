# frozen_string_literal: true

module ScrapingServices
  class RateLimitError < StandardError
    attr_reader :retry_after, :original_error

    def initialize(message, retry_after: 6.hours, original_error: nil)
      super(message)
      @retry_after = retry_after
      @original_error = original_error
    end
  end

  class RateLimitHandler
    RATE_LIMIT_PATTERNS = [
      /429/i,
      /403/i,
      /503/i,
      /rate.?limit/i,
      /blocked/i,
      /captcha/i,
      /cloudflare/i,
      /datadome/i
    ].freeze

    SUSPICIOUS_PATTERNS = [
      /connection.?reset/i,
      /timeout/i,
      /empty.?response/i,
      /net::(read|open)_timeout/i
    ].freeze

    DEFAULT_BACKOFF = 6.hours
    HEAVY_BACKOFF   = 12.hours

    class << self
      def handle_error(error, context = {})
        raise error unless rate_limited?(error)

        retry_after = determine_backoff(error, context)
        raise RateLimitError.new(
          "Rate limit detectado: #{error.message}",
          retry_after: retry_after,
          original_error: error
        )
      end

      def rate_limited?(error)
        message = error.message.to_s
        RATE_LIMIT_PATTERNS.any? { |pattern| message.match?(pattern) }
      end

      def determine_backoff(error, context = {})
        message = error.message.to_s

        return HEAVY_BACKOFF if suspicious_block?(error)
        return HEAVY_BACKOFF if (context[:retry_count] || 0) > 2
        return HEAVY_BACKOFF if message.match?(/cloudflare|datadome/i)
        return 2.hours       if message.match?(/429/i)

        DEFAULT_BACKOFF
      end

      def suspicious_block?(error)
        message = error.message.to_s
        SUSPICIOUS_PATTERNS.any? { |pattern| message.match?(pattern) }
      end
    end
  end
end
