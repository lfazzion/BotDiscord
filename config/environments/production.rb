Rails.application.configure do
  # ── Logging ────────────────────────────────────────────────────────────────
  # Emite logs em JSON para facilitar parsing em containers
  config.log_level = :info
  config.log_tags = [ :request_id ]

  # ── Cache ───────────────────────────────────────────────────────────────────
  # Solid Cache persiste no shard `cache` do SQLite (storage/production_cache.sqlite3)
  config.cache_store = :solid_cache_store

  # ── Active Job / Solid Queue ────────────────────────────────────────────────
  # Solid Queue persiste no shard `queue` do SQLite (storage/production_queue.sqlite3)
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # ── Miscelânea ───────────────────────────────────────────────────────────────
  config.eager_load = true
  config.consider_all_requests_local = false
end
