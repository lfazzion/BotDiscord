class SocialPost < ApplicationRecord
  POST_TYPES = %w[image video text reel story].freeze

  belongs_to :social_profile

  validates :platform_post_id, presence: true
  validates :post_type, presence: true, inclusion: { in: POST_TYPES }
  validates :platform_post_id, uniqueness: { scope: :social_profile_id }

  scope :recent, ->(days = 30) { where('posted_at >= ?', days.days.ago) }
  scope :by_type, ->(type) { where(post_type: type) }
  scope :by_profile_and_recent, lambda { |profile_id, days = 30|
    where(social_profile_id: profile_id).where('posted_at >= ?', days.days.ago)
  }

  def engagement_count
    [likes_count, comments_count, shares_count].compact.sum
  end

  def engagement_rate(profile_followers)
    return nil if profile_followers.nil? || profile_followers.zero?

    ((likes_count.to_i + comments_count.to_i + shares_count.to_i) / profile_followers.to_f * 100).round(2)
  end

  def media_url
    return nil unless media_urls.present?

    media_urls.first
  end
end
