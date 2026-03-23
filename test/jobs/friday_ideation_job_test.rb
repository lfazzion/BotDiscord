# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/services/discord_api_client'
require_relative '../../app/jobs/friday_ideation_job'

class FridayIdeationJobTest < ActiveSupport::TestCase
  test 'perform monta mensagem corretamente' do
    ENV['DISCORD_DIGEST_CHANNEL_ID'] = '123456'

    create(:event, title: 'BGS 2026', event_type: 'bgs', start_date: 3.days.from_now)
    create(:external_catalog, source: 'tmdb', title: 'Popular Movie', popularity: 80.0)
    create(:news_article, title: 'Tech News', source: 'tech', link: 'https://example.com/tech', pub_date: 1.day.ago)

    mock_response = stub(content: 'Sugestões de conteúdo do LLM')
    AiRouter.stubs(:complete).returns(mock_response)

    DiscordApiClient.stubs(:send_message).returns(true)

    job = FridayIdeationJob.new
    job.perform

    ENV.delete('DISCORD_DIGEST_CHANNEL_ID')
  end

  test 'perform cria canal se não existir' do
    ENV.delete('DISCORD_DIGEST_CHANNEL_ID')

    DiscordApiClient.stubs(:get_bot_guilds).returns([{ 'id' => 'guild123' }])
    DiscordApiClient.stubs(:create_text_channel).returns({ 'id' => 'channel456' })

    mock_response = stub(content: 'Sugestões de conteúdo do LLM')
    AiRouter.stubs(:complete).returns(mock_response)

    DiscordApiClient.stubs(:send_message).returns(true)

    job = FridayIdeationJob.new
    job.perform
  end
end
