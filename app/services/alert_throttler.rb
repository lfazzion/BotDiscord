# frozen_string_literal: true

class AlertThrottler
  ALERT_LIMIT = 10
  WINDOW = 1.hour

  def self.throttle?(alert_type)
    return false if ENV["ALERT_THROTTLE_ENABLED"] != "true"

    key = "alert_throttle:#{alert_type}"
    count = Rails.cache.read(key).to_i
    count >= ALERT_LIMIT
  end

  def self.record(alert_type)
    return if ENV["ALERT_THROTTLE_ENABLED"] != "true"

    key = "alert_throttle:#{alert_type}"
    count = Rails.cache.increment(key, 1, expires_in: WINDOW)
    Rails.cache.write(key, 1, expires_in: WINDOW) if count.nil?
  end

  def self.reset(alert_type)
    key = "alert_throttle:#{alert_type}"
    Rails.cache.delete(key)
  end
end
