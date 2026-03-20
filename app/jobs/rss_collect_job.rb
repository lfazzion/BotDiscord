# frozen_string_literal: true

class RssCollectJob < ApplicationJob
  queue_as :default

  def perform(query, days: 1)
    articles = ScrapingServices::RssParserService.parse_google_news(query: query, days: days)

    articles.each do |article|
      news = NewsArticle.find_or_initialize_by(link: article[:link])
      news.assign_attributes(
        title: article[:title],
        description: article[:description],
        pub_date: article[:pub_date],
        source: article[:source],
        query_used: query
      )

      news.save! if news.changed?
    end

    Rails.logger.info "[RssCollectJob] #{articles.size} artigos coletados para '#{query}'"

    RssCollectJob.set(wait: 1.hour).perform_later(query, days: days)
  rescue StandardError => e
    Rails.logger.error "[RssCollectJob] Erro ao coletar RSS '#{query}': #{e.message}"
    RssCollectJob.set(wait: 6.hours).perform_later(query, days: days)
  end
end
