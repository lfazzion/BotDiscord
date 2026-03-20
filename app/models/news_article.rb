# frozen_string_literal: true

# Modelo para artigos de notícias coletados via RSS
class NewsArticle < ApplicationRecord
  validates :link, presence: true, uniqueness: true

  scope :recent, ->(days = 7) { where('pub_date >= ?', days.days.ago) }
  scope :by_source, ->(source) { where(source: source) }
  scope :by_query, ->(query) { where(query_used: query) }
end
