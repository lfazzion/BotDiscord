require "test_helper"

class Phase1InfrastructureTest < ActiveSupport::TestCase
  test "all Phase 1 models should exist" do
    assert defined?(SocialProfile), "SocialProfile model not found"
    assert defined?(SocialPost), "SocialPost model not found"
    assert defined?(ProfileSnapshot), "ProfileSnapshot model not found"
  end

  test "SNAPSHOT_DEDUP_WINDOW constant should be defined" do
    assert_equal 2.hours, ProfileSnapshot::SNAPSHOT_DEDUP_WINDOW
  end

  test "all migrations should exist" do
    migrate_dir = Rails.root.join("db", "migrate")

    profile_migration = Dir.glob("#{migrate_dir}/*create_social_profiles*").first
    post_migration = Dir.glob("#{migrate_dir}/*create_social_posts*").first
    snapshot_migration = Dir.glob("#{migrate_dir}/*create_profile_snapshots*").first

    assert profile_migration, "SocialProfile migration not found"
    assert post_migration, "SocialPost migration not found"
    assert snapshot_migration, "ProfileSnapshot migration not found"
  end

  test "all tables should exist in test database" do
    assert_queries_table_exists(:social_profiles)
    assert_queries_table_exists(:social_posts)
    assert_queries_table_exists(:profile_snapshots)
  end

  test "solid_queue tables should exist" do
    assert_queries_table_exists(:solid_queue_jobs)
    assert_queries_table_exists(:solid_queue_ready_executions)
    assert_queries_table_exists(:solid_queue_claimed_executions)
    assert_queries_table_exists(:solid_queue_failed_executions)
    assert_queries_table_exists(:solid_queue_processes)
  end

  test "solid_cache tables should exist" do
    assert_queries_table_exists(:solid_cache_entries)
  end

  test "queue database pool should be adequate for worker threads" do
    db_config = Rails.application.config.database_configuration["production"]
    queue_pool = db_config["queue"]["pool"]

    if queue_pool.is_a?(Integer)
      assert queue_pool >= 8,
        "Queue pool (#{queue_pool}) must be >= 8 for 4 worker threads + dispatcher + supervisor"
    end
  end

  test "numeric columns should accept nil (null safety)" do
    profile = create(:social_profile, followers_count: nil, following_count: nil)
    assert_nil profile.followers_count
    assert_nil profile.following_count

    post = create(:social_post, likes_count: nil, comments_count: nil, views_count: nil)
    assert_nil post.likes_count
    assert_nil post.comments_count
    assert_nil post.views_count

    snapshot = create(:profile_snapshot, followers_count: nil, following_count: nil, posts_count: nil)
    assert_nil snapshot.followers_count
    assert_nil snapshot.following_count
    assert_nil snapshot.posts_count
  end

  test "verified column should have default: false" do
    col = ActiveRecord::Base.connection.columns(:social_profiles).find { |c| c.name == "verified" }
    assert_equal false, col.default, "verified column should default to false"
  end

  private

  def assert_queries_table_exists(table_name)
    assert ActiveRecord::Base.connection.table_exists?(table_name),
           "Table #{table_name} should exist"
  end
end
