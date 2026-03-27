require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'

Bundler.require(*Rails.groups)

module BotDiscord
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = false
    config.session_store :cookie_store, key: '_bot_discord_session'
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store
    config.autoload_lib(ignore: %w[assets tasks scraping llm])

    # Tools têm múltiplas classes por arquivo — require explícito necessário
    Rails.autoloaders.main.ignore(Rails.root.join("app/tools"))

    config.active_record.database_selector = { delay: 2.seconds }
    config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
    config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
  end
end
