# frozen_string_literal: true

require 'test_helper'
require_relative '../../../app/services/discord_api_client'
require_relative '../../../app/jobs/concerns/admin_alert_channel'

class AdminAlertChannelTest < ActiveSupport::TestCase
  class DummyJob
    include AdminAlertChannel

    def self.name
      'DummyJob'
    end
  end

  test 'ensure_admin_channel retorna ENV quando configurado' do
    ENV['DISCORD_ADMIN_CHANNEL_ID'] = '123456'

    job = DummyJob.new
    channel_id = job.send(:ensure_admin_channel)

    assert_equal '123456', channel_id

    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')
  end

  test 'ensure_admin_channel cria canal quando ENV não configurado' do
    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')

    DiscordApiClient.stubs(:get_bot_guilds).returns([{ 'id' => 'guild789' }])
    DiscordApiClient.stubs(:create_text_channel).returns({ 'id' => 'channel456' })

    job = DummyJob.new
    channel_id = job.send(:ensure_admin_channel)

    assert_equal 'channel456', channel_id
  end

  test 'ensure_admin_channel retorna nil quando sem guilds' do
    ENV.delete('DISCORD_ADMIN_CHANNEL_ID')

    DiscordApiClient.stubs(:get_bot_guilds).returns([])

    job = DummyJob.new
    channel_id = job.send(:ensure_admin_channel)

    assert_nil channel_id
  end
end
