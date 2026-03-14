require "test_helper"

class ProfileSnapshotTest < ActiveSupport::TestCase
  setup do
    @profile = create(:social_profile)
    @snapshot = build(:profile_snapshot, social_profile: @profile)
  end

  test "should be valid with valid attributes" do
    assert @snapshot.valid?
  end

  test "social_profile should be present" do
    @snapshot.social_profile_id = nil
    assert_not @snapshot.valid?
    assert_includes @snapshot.errors[:social_profile_id], "can't be blank"
  end

  test "recorded_at should be present" do
    @snapshot.recorded_at = nil
    assert_not @snapshot.valid?
    assert_includes @snapshot.errors[:recorded_at], "can't be blank"
  end

  test "recent scope should return snapshots from last 2 hours" do
    recent_snapshot = create(:profile_snapshot, recorded_at: Time.current)
    old_snapshot = create(:profile_snapshot, recorded_at: 3.hours.ago)

    assert_includes ProfileSnapshot.recent, recent_snapshot
    assert_not_includes ProfileSnapshot.recent, old_snapshot
  end

  test "ordered scope should return snapshots in descending order" do
    old_snapshot = create(:profile_snapshot, recorded_at: 1.day.ago)
    recent_snapshot = create(:profile_snapshot, recorded_at: Time.current)

    ordered = ProfileSnapshot.ordered
    assert_equal recent_snapshot, ordered.first
    assert_equal old_snapshot, ordered.last
  end

  test "find_or_create_idempotent should return existing recent snapshot" do
    existing = create(:profile_snapshot, social_profile: @profile, recorded_at: Time.current)

    result = ProfileSnapshot.find_or_create_idempotent(@profile.id)

    assert_equal existing.id, result.id
  end

  test "find_or_create_idempotent should create new when no recent snapshot" do
    create(:profile_snapshot, social_profile: @profile, recorded_at: 3.hours.ago)

    assert_difference "ProfileSnapshot.count", 1 do
      ProfileSnapshot.find_or_create_idempotent(@profile.id)
    end
  end

  test "should handle nil counts correctly (null vs zero)" do
    snapshot_with_nil = create(:profile_snapshot,
      followers_count: nil,
      following_count: nil,
      posts_count: nil)

    assert_nil snapshot_with_nil.followers_count
    assert_nil snapshot_with_nil.following_count
    assert_nil snapshot_with_nil.posts_count
    assert_not_equal 0, snapshot_with_nil.followers_count
  end

  test "should belong to social_profile" do
    assert_association @snapshot, :social_profile, :belongs_to
  end
end
