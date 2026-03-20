# frozen_string_literal: true

class DiscoveredProfile < ApplicationRecord
  CLASSIFICATIONS = %w[CONCORRENTE PATROCINADOR_PROSPECTO IGNORAR].freeze

  belongs_to :source_profile, class_name: 'SocialProfile', optional: true

  validates :platform, presence: true
  validates :username, presence: true
  validates :platform, uniqueness: { scope: :username }
  validates :classification, inclusion: { in: CLASSIFICATIONS }, allow_nil: true

  scope :unclassified, -> { where(classification: nil) }
  scope :stale_classification, -> { where('classified_at < ?', 7.days.ago).or(unclassified) }
  scope :prospects, -> { where(classification: 'PATROCINADOR_PROSPECTO') }
end
