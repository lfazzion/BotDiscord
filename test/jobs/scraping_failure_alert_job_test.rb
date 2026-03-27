# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/services/discord_api_client'
require_relative '../../app/services/alert_throttler'
require_relative '../../app/jobs/concerns/admin_alert_channel'
require_relative '../../app/jobs/scraping_failure_alert_job'

class ScrapingFailureAlertJobTest < ActiveSupport::TestCase
  test 'perform envia mensagem de alerta ao Discord' do
    ENV['DISCORD_ADMIN_CHANNEL_ID'] = '987654'

    DiscordApiClient.stubs(:send_message).returns(true)

    job = ScrapingFailureAlertJob.new
    job.perform('twitter', 42, 'Connection timeout', 'timeout')

    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')
  end

  test 'perform loga warning quando canal admin não configurado' do
    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')
    Rails.cache.delete('discord:admin_channel_id')

    DiscordApiClient.stubs(:get_bot_guilds).returns([])

    Rails.logger.expects(:warn).with('[ScrapingFailureAlertJob] Canal admin não configurado')

    job = ScrapingFailureAlertJob.new
    job.perform('twitter', 42, 'Error', 'unknown_error')
  end

  test 'build_alert_message contém informações corretas' do
    ENV['DISCORD_ADMIN_CHANNEL_ID'] = '987654'

    DiscordApiClient.stubs(:send_message).returns(true)

    job = ScrapingFailureAlertJob.new
    job.perform('instagram', 99, 'Access denied by captcha', 'captcha')

    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')
  end

  test 'perform não envia alerta quando throttled' do
    ENV['DISCORD_ADMIN_CHANNEL_ID'] = '987654'
    ENV['ALERT_THROTTLE_ENABLED'] = 'true'

    Rails.cache.write('alert_throttle:timeout', 10, expires_in: 1.hour)

    Rails.logger.expects(:warn).with('[ScrapingFailureAlertJob] Throttled: timeout')

    job = ScrapingFailureAlertJob.new
    job.perform('twitter', 42, 'Connection timeout', 'timeout')

    Rails.cache.delete('alert_throttle:timeout')
    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')
    ENV.delete('ALERT_THROTTLE_ENABLED')
  end
end
