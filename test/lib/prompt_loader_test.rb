require 'test_helper'

class PromptLoaderTest < ActiveSupport::TestCase
  test 'load should return hash with system and user keys' do
    handles = [{ platform: 'instagram', username: '@test_user', bio: 'Test bio' }]
    result = Llm::PromptLoader.load('discovery', handles: handles)

    assert_instance_of Hash, result
    assert_includes result.keys, :system
    assert_includes result.keys, :user
  end

  test 'load should raise error for missing prompt' do
    assert_raises Llm::PromptLoader::PromptNotFoundError do
      Llm::PromptLoader.load('nonexistent_prompt_xyz')
    end
  end

  test 'load discovery prompt should contain classification categories' do
    handles = [{ platform: 'twitter', username: '@someone', bio: nil }]
    result = Llm::PromptLoader.load('discovery', handles: handles)

    assert_includes result[:system], 'CONCORRENTE'
    assert_includes result[:system], 'PATROCINADOR_PROSPECTO'
    assert_includes result[:system], 'IGNORAR'
  end

  test 'load discovery prompt should include handles in user message' do
    handles = [
      { platform: 'instagram', username: '@user1', bio: 'Bio 1' },
      { platform: 'twitter', username: '@user2', bio: nil }
    ]
    result = Llm::PromptLoader.load('discovery', handles: handles)

    assert_includes result[:user], '@user1'
    assert_includes result[:user], '@user2'
    assert_includes result[:user], 'Bio 1'
    assert_includes result[:user], 'N/A'
  end

  test 'partial rules should contain null vs zero rules' do
    rules = Llm::PromptLoader.partial('rules')

    assert_includes rules, 'null'
    assert_includes rules, 'NUNCA'
    assert_includes rules, 'JSON'
  end

  test 'partial time_injection should contain current datetime' do
    time_partial = Llm::PromptLoader.partial('time_injection')

    assert_includes time_partial, 'current_datetime'
    assert time_partial.include?(Time.current.year.to_s),
           'Time injection should contain current year'
  end

  test 'partial should return empty string for missing partial' do
    result = Llm::PromptLoader.partial('nonexistent_xyz')
    assert_equal '', result
  end

  test 'load base prompt should return system and user template' do
    result = Llm::PromptLoader.load('base', user_message: 'hello')

    assert_instance_of String, result[:system]
    assert_instance_of String, result[:user]
    assert_includes result[:user], 'hello'
  end

  test 'load analysis prompt should require profile and posts' do
    profile = create(:social_profile)
    create_list(:social_post, 2, social_profile: profile)
    posts = profile.social_posts.to_a

    result = Llm::PromptLoader.load('analysis', profile: profile, posts: posts)

    assert_includes result[:user], profile.platform
    assert_includes result[:user], profile.platform_username
    assert_includes result[:system], 'JSON'
  end

  test 'all prompt files should have name field' do
    %w[base discovery analysis].each do |name|
      file = Rails.root.join("config/prompts/system/#{name}.yml")
      assert file.exist?, "Prompt file #{name}.yml should exist"
      yaml = YAML.safe_load(file.read)
      assert yaml['name'], "Prompt #{name} should have a name field"
    end
  end
end
