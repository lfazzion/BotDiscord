class SocialPost < ApplicationRecord
  POST_TYPES = %w[image video text reel story].freeze

  belongs_to :social_profile

  validates :platform_post_id, presence: true
  validates :post_type, presence: true, inclusion: { in: POST_TYPES }
  validates :platform_post_id, uniqueness: { scope: :social_profile_id }

  scope :recent, ->(days = 30) { where("posted_at >= ?", days.days.ago) }
  scope :by_type, ->(type) { where(post_type: type) }

  def engagement_count
    [likes_count, comments_count, shares_count].compact.sum
  end
end
