# frozen_string_literal: true

require 'test_helper'

class EventTest < ActiveSupport::TestCase
  setup do
    @event = build(:event)
  end

  test "should be valid with valid attributes" do
    assert @event.valid?
  end

  test "title should be present" do
    @event.title = nil
    assert_not @event.valid?
    assert_includes @event.errors[:title], "can't be blank"
  end

  test "source_url should be unique" do
    create(:event, source_url: "https://example.com/event1")
    duplicate = build(:event, source_url: "https://example.com/event1")
    assert_not duplicate.valid?
  end

  test "source_url can be nil" do
    @event.source_url = nil
    assert @event.valid?
  end

  test "source should be in allowed list" do
    @event.source = "invalid_source"
    assert_not @event.valid?
    assert_includes @event.errors[:source], "is not included in the list"
  end

  test "source can be nil" do
    @event.source = nil
    assert @event.valid?
  end

  test "event_type should be in allowed list" do
    @event.event_type = "invalid_type"
    assert_not @event.valid?
    assert_includes @event.errors[:event_type], "is not included in the list"
  end

  test "event_type can be nil" do
    @event.event_type = nil
    assert @event.valid?
  end

  test "upcoming scope should return future events ordered by start_date" do
    future_event = create(:event, start_date: 30.days.from_now.to_date)
    past_event = create(:event, start_date: 30.days.ago.to_date)

    assert_includes Event.upcoming, future_event
    assert_not_includes Event.upcoming, past_event
  end

  test "by_type scope should filter correctly" do
    bgs = create(:event, event_type: "bgs")
    ccxp = create(:event, event_type: "ccxp")

    assert_includes Event.by_type("bgs"), bgs
    assert_not_includes Event.by_type("bgs"), ccxp
  end

  test "by_location scope should match partial location" do
    sp = create(:event, location: "São Paulo - Centro")
    rj = create(:event, location: "Rio de Janeiro")

    assert_includes Event.by_location("São Paulo"), sp
    assert_not_includes Event.by_location("São Paulo"), rj
  end

  test "recent scope should return events created within days" do
    recent = create(:event)
    old = create(:event)
    old.update_column(:created_at, 10.days.ago)

    assert_includes Event.recent(7), recent
    assert_not_includes Event.recent(7), old
  end
end
