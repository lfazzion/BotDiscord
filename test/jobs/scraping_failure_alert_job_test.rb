# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/services/discord_api_client'
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

    DiscordApiClient.stubs(:get_bot_guilds).returns([])

    Rails.logger.expects(:warn).with('[ScrapingFailureAlertJob] Canal admin não configurado')

    job = ScrapingFailureAlertJob.new
    job.perform('twitter', 42, 'Error', 'rate_limit')
  end

  test 'build_alert_message contém informações corretas' do
    ENV['DISCORD_ADMIN_CHANNEL_ID'] = '987654'

    DiscordApiClient.stubs(:send_message).returns(true)

    job = ScrapingFailureAlertJob.new
    job.perform('instagram', 99, 'Access denied by captcha', 'captcha')

    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')
  end
end
