# frozen_string_literal: true

# Carregamento manual dos módulos de scraping (excluídos do autoload Zeitwerk)
# para evitar conflitos de namespace (path scraping/ -> namespace ScrapingServices)
Rails.application.config.after_initialize do
  require Rails.root.join('lib/scraping/rate_limit_handler')
  require Rails.root.join('lib/scraping/services/rss_parser_service')
  require Rails.root.join('lib/scraping/services/youtube_scraper_service')
  require Rails.root.join('lib/scraping/services/http_stealth_client')
  require Rails.root.join('lib/scraping/scrapers/ferrum_scraper_base')
  require Rails.root.join('lib/scraping/scrapers/instagram_scraper')
  require Rails.root.join('lib/scraping/scrapers/twitter_scraper')
  require Rails.root.join('lib/scraping/python_bridge/nodriver_runner')
  require Rails.root.join('lib/scraping/python_bridge/camoufox_service')
end
