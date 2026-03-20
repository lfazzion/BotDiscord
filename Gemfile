source 'https://rubygems.org'

ruby '~> 4.0'

gem 'rails', '~> 8.1.0'
gem 'sqlite3', '~> 2.6'
gem 'puma', '~> 6.0'
gem 'solid_queue', '~> 1.0'
gem 'solid_cache', '~> 1.0'
gem 'redis', '>= 4.0.1'

group :development, :test do
  gem 'debug', platforms: %i[mri mingw x64_mingw]
end

group :test do
  gem 'minitest', '~> 5.0'
  gem 'minitest-reporters'
  gem 'webmock'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'mocha'
end

gem 'ferrum'             # Headless Chrome via WebSocket (chromedp/headless-shell)
gem 'typhoeus', '~> 1.4' # HTTP client com proxy e SSL support
gem 'bootsnap', require: false
gem 'tzinfo-data'
