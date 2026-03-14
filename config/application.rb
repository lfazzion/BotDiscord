require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_text/railtie"
require "active_storage/railtie"
require "action_mailbox/railtie"
require "rails/test_unit/railtie"
require "sprockets/railtie"

Bundler.require(*Rails.groups)

module BotDiscord
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = false
    config.session_store :cookie_store, key: '_bot_discord_session'
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
