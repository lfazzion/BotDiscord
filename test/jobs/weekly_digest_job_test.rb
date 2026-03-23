# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/services/discord_api_client'
require_relative '../../app/jobs/weekly_digest_job'

class WeeklyDigestJobTest < ActiveSupport::TestCase
  test 'perform monta mensagem corretamente' do
    ENV['DISCORD_DIGEST_CHANNEL_ID'] = '123456'

    create(:social_profile, platform: 'twitter', platform_username: 'top_user', display_name: 'Top User',
                            followers_count: 10_000)

    DiscordApiClient.stubs(:send_message).returns(true)

    job = WeeklyDigestJob.new
    job.perform

    ENV.delete('DISCORD_DIGEST_CHANNEL_ID')
  end

  test 'perform cria canal se não existir' do
    ENV.delete('DISCORD_DIGEST_CHANNEL_ID')

    DiscordApiClient.stubs(:get_bot_guilds).returns([{ 'id' => 'guild123' }])
    DiscordApiClient.stubs(:create_text_channel).returns({ 'id' => 'channel456' })
    DiscordApiClient.stubs(:send_message).returns(true)

    job = WeeklyDigestJob.new
    job.perform
  end
end
