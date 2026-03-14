ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "factory_bot_rails"

WebMock.disable_net_connect!(allow_localhost: true)

class ActiveSupport::TestCase
  fixtures :all
  include FactoryBot::Syntax::Methods
end
