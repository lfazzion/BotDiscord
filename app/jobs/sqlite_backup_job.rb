# frozen_string_literal: true

class SqliteBackupJob < ApplicationJob
  queue_as :critical

  def perform
    Rails.logger.info "[SqliteBackupJob] Iniciando backup do SQLite"

    db_path = Rails.root.join("storage/production.sqlite3").to_s
    backup_dir = Rails.root.join("storage/backups").to_s

    result = system(
      "/bin/bash",
      Rails.root.join("bin/backup").to_s,
      db_path,
      backup_dir,
      ENV["BACKUP_RETENTION_DAYS"] || "7"
    )

    if result
      Rails.logger.info "[SqliteBackupJob] Backup realizado com sucesso"
    else
      Rails.logger.error "[SqliteBackupJob] Backup falhou com código #{$CHILD_STATUS&.exitstatus}"
      raise "Backup do SQLite falhou"
    end
  end
end
