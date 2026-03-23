# frozen_string_literal: true

class RecentPostsTool < ToolBase
  description 'Lista posts recentes de um perfil'

  param :username, type: :string, desc: 'Username do perfil', required: true
  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: true
  param :days, type: :integer, desc: 'Número de dias para buscar (padrão 30)', required: false
  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 10)', required: false

  def run(username:, platform:, days: 30, limit: 10)
    profile = SocialProfile.find_by(platform: platform, platform_username: username)
    return error("Perfil não encontrado: #{username} em #{platform}") unless profile

    limit = clamp(limit, 1, 50)
    posts = profile.social_posts.recent(days).order(posted_at: :desc).limit(limit)

    success(posts.map { |p| format_post(p) })
  end
end

class TopPostsTool < ToolBase
  description 'Lista posts mais populares de um perfil por likes'

  param :username, type: :string, desc: 'Username do perfil', required: true
  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: true
  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 5)', required: false

  def run(username:, platform:, limit: 5)
    profile = SocialProfile.find_by(platform: platform, platform_username: username)
    return error("Perfil não encontrado: #{username} em #{platform}") unless profile

    limit = clamp(limit, 1, 20)
    posts = profile.social_posts.order(likes_count: :desc).limit(limit)

    success(posts.map { |p| format_post(p) })
  end
end

class PostsByTypeTool < ToolBase
  description 'Lista posts de um perfil filtrados por tipo'

  param :username, type: :string, desc: 'Username do perfil', required: true
  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: true
  param :post_type, type: :string, desc: 'Tipo de post (image/video/text/reel/story)', required: true
  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 10)', required: false

  def run(username:, platform:, post_type:, limit: 10)
    profile = SocialProfile.find_by(platform: platform, platform_username: username)
    return error("Perfil não encontrado: #{username} em #{platform}") unless profile

    limit = clamp(limit, 1, 50)
    posts = profile.social_posts.by_type(post_type).recent(30).limit(limit)

    success(posts.map { |p| format_post(p) })
  end
end

class PostEngagementTool < ToolBase
  description 'Retorna métricas de engajamento de um post específico'

  param :username, type: :string, desc: 'Username do perfil', required: true
  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: true
  param :post_id, type: :integer, desc: 'ID do post', required: true

  def run(username:, platform:, post_id:)
    profile = SocialProfile.find_by(platform: platform, platform_username: username)
    return error("Perfil não encontrado: #{username} em #{platform}") unless profile

    post = profile.social_posts.find_by(id: post_id)
    return error("Post não encontrado com ID: #{post_id}") unless post

    success({
              post_id: post.id,
              engagement_count: post.engagement_count,
              engagement_rate: post.engagement_rate(profile.followers_count),
              likes_count: post.likes_count,
              comments_count: post.comments_count,
              shares_count: post.shares_count
            })
  end
end
