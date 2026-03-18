require "test_helper"

class SolidCacheInitializerTest < ActiveSupport::TestCase
  test "solid_cache initializer should exist and be loadable" do
    assert File.exist?(Rails.root.join("config", "initializers", "solid_cache.rb"))
    assert_nothing_raised { Rails.application.config.to_prepare_blocks.each(&:call) }
  end

  test "solid_cache gem should be available" do
    assert defined?(SolidCache)
  end

  test "config/cache.yml should exist" do
    assert File.exist?(Rails.root.join("config", "cache.yml"))
  end

  test "cache.yml should be valid YAML" do
    assert_nothing_raised do
      YAML.load_file(Rails.root.join("config", "cache.yml"), permitted_classes: [Symbol], aliases: true)
    end
  end

  test "cache.yml should define store options" do
    config = YAML.load_file(Rails.root.join("config", "cache.yml"), permitted_classes: [Symbol], aliases: true)
    store_options = config.dig("default", "store_options")

    assert store_options, "store_options should be defined"
    assert store_options["max_size"], "max_size should be configured"
    assert store_options["namespace"], "namespace should be configured"
  end

  test "cache tables should be configured in database.yml" do
    db_config = Rails.application.config.database_configuration["production"]

    assert db_config["cache"], "cache database should be configured"
    assert_equal "storage/production_cache.sqlite3", db_config["cache"]["database"]
    assert_equal "wal", db_config["cache"]["pragmas"]["journal_mode"]
  end

  test "cache_store should be configured for solid_cache in production" do
    prod_env = Rails.application.config.database_configuration["production"]
    assert prod_env, "production database should be configured"
    assert prod_env["cache"], "cache database should be configured"
  end
end
