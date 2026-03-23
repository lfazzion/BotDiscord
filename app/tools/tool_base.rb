# frozen_string_literal: true

class ToolBase < RubyLLM::Tool
  def execute(**kwargs)
    Rails.logger.info "[#{self.class.name}] chamado com #{kwargs.inspect}"
    run(**kwargs)
  end

  private

  def clamp(value, min, max)
    [[value.to_i, min].max, max].min
  end

  def success(data)
    { status: :success, data: data }
  end

  def error(reason)
    { status: :error, reason: reason }
  end

  def format_profile(profile)
    {
      id: profile.id,
      platform: profile.platform,
      username: profile.platform_username,
      display_name: profile.display_name,
      followers_count: profile.followers_count,
      following_count: profile.following_count,
      bio: profile.bio,
      verified: profile.verified,
      platform_url: profile.platform_url
    }
  end

  def format_post(post)
    {
      id: post.id,
      platform_post_id: post.platform_post_id,
      post_type: post.post_type,
      content: post.content,
      likes_count: post.likes_count,
      comments_count: post.comments_count,
      shares_count: post.shares_count,
      views_count: post.views_count,
      posted_at: post.posted_at,
      engagement_count: post.engagement_count
    }
  end
end
