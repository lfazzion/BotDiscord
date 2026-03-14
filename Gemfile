source 'https://rubygems.org'

ruby '~> 3.4'

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
end

gem 'bootsnap', require: false
