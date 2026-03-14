require "test_helper"

class SQLiteWALTest < ActiveSupport::TestCase
  test "WAL initializer should exist" do
    assert File.exist?(Rails.root.join("config", "initializers", "sqlite_wal.rb"))
  end
end
