require "active_record/connection_adapters/sqlite3_adapter"

module ActiveRecord
  module ConnectionAdapters
    class SQLite3Adapter
      def configure_connection
        super
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        execute("PRAGMA busy_timeout=5000")
      end
    end
  end
end
