Rails.application.configure do
  config.eager_load = false
  config.log_level = :debug
  config.cache_store = :file_store, Rails.root.join("tmp", "cache")
end
