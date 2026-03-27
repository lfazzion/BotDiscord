# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/jobs/sqlite_backup_job'

class SqliteBackupJobTest < ActiveSupport::TestCase
  test 'perform chama bin/backup com sucesso' do
    SqliteBackupJob.any_instance.stubs(:system).returns(true)

    job = SqliteBackupJob.new
    job.perform
  end

  test 'perform levanta erro quando backup falha' do
    SqliteBackupJob.any_instance.stubs(:system).returns(false)

    job = SqliteBackupJob.new
    assert_raises RuntimeError do
      job.perform
    end
  end

  test 'perform usa path correto do banco' do
    expected_db = Rails.root.join("storage/production.sqlite3").to_s
    expected_dir = Rails.root.join("storage/backups").to_s

    SqliteBackupJob.any_instance.expects(:system).with(
      "/bin/bash",
      Rails.root.join("bin/backup").to_s,
      expected_db,
      expected_dir,
      "7"
    ).returns(true)

    ENV.delete('BACKUP_RETENTION_DAYS')

    job = SqliteBackupJob.new
    job.perform
  end
end
