require "test_helper"

class SQLiteWALTest < ActiveSupport::TestCase
  test "WAL initializer should exist" do
    assert File.exist?(Rails.root.join("config", "initializers", "sqlite_wal.rb"))
  end

  test "WAL initializer should define configure_connection override" do
    initializer_content = File.read(Rails.root.join("config", "initializers", "sqlite_wal.rb"))
    assert_includes initializer_content, "journal_mode=WAL"
    assert_includes initializer_content, "synchronous=NORMAL"
    assert_includes initializer_content, "busy_timeout"
  end

  test "database.yml should configure WAL for production" do
    db_config = Rails.application.config.database_configuration["production"]
    assert db_config, "Production database config not found"

    primary = db_config["primary"]
    assert_equal "wal", primary["pragmas"]["journal_mode"], "Primary DB should use WAL mode"

    queue = db_config["queue"]
    assert_equal "wal", queue["pragmas"]["journal_mode"], "Queue DB should use WAL mode"
    assert queue["pool"], "Queue DB should have explicit pool size"

    cache = db_config["cache"]
    assert_equal "wal", cache["pragmas"]["journal_mode"], "Cache DB should use WAL mode"
  end

  test "numeric columns should NOT have default: 0 (null safety)" do
    profile_columns = ActiveRecord::Base.connection.columns(:social_profiles)
    post_columns = ActiveRecord::Base.connection.columns(:social_posts)
    snapshot_columns = ActiveRecord::Base.connection.columns(:profile_snapshots)

    followers = profile_columns.find { |c| c.name == "followers_count" }
    following = profile_columns.find { |c| c.name == "following_count" }
    likes = post_columns.find { |c| c.name == "likes_count" }
    views = post_columns.find { |c| c.name == "views_count" }

    assert followers.nil? || followers.default.nil? || followers.default == false,
           "followers_count should NOT have default: 0"
    assert following.nil? || following.default.nil? || following.default == false,
           "following_count should NOT have default: 0"
    assert likes.nil? || likes.default.nil? || likes.default == false,
           "likes_count should NOT have default: 0"
    assert views.nil? || views.default.nil? || views.default == false,
           "views_count should NOT have default: 0"
  end
end
