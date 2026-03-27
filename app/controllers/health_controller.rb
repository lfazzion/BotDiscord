# frozen_string_literal: true

class HealthController < ActionController::API
  def show
    ActiveRecord::Base.connection.execute("SELECT 1")
    render json: { status: "ok", db: "ok" }
  rescue StandardError => e
    Rails.logger.error "[HealthController] DB check failed: #{e.message}"
    render json: { status: "error", db: "error" }, status: :service_unavailable
  end
end
