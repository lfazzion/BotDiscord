class ProfileSnapshot < ApplicationRecord
  SNAPSHOT_DEDUP_WINDOW = 2.hours

  belongs_to :social_profile

  validates :social_profile_id, presence: true
  validates :recorded_at, presence: true

  scope :recent, -> { where("recorded_at >= ?", SNAPSHOT_DEDUP_WINDOW.ago) }
  scope :ordered, -> { order(recorded_at: :desc) }

  def self.find_or_create_idempotent(profile_id)
    recent_snapshot = recent.where(social_profile_id: profile_id).first
    return recent_snapshot if recent_snapshot

    create!(social_profile_id: profile_id, followers_count: nil, following_count: nil, posts_count: nil)
  end
end
