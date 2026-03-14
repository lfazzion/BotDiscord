class SocialProfile < ApplicationRecord
  PLATFORMS = %w[twitter instagram youtube tiktok].freeze

  has_many :social_posts, dependent: :destroy
  has_many :profile_snapshots, dependent: :destroy

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :platform_username, presence: true
  validates :platform_user_id, presence: true
  validates :platform, uniqueness: { scope: :platform_user_id }

  scope :verified, -> { where(verified: true) }
  scope :by_platform, ->(platform) { where(platform: platform) }

  def engagement_rate
    return nil if followers_count.nil? || followers_count.zero?

    posts = social_posts.last(10)
    return nil if posts.empty?

    total_engagement = posts.sum do |post|
      [(post.likes_count || 0), (post.comments_count || 0), (post.shares_count || 0)].sum
    end
    avg_engagement = total_engagement.to_f / posts.size
    (avg_engagement / followers_count * 100).round(2)
  end
end
