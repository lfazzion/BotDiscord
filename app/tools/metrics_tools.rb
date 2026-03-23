# frozen_string_literal: true

class EngagementRateTool < ToolBase
  description 'Calcula a taxa de engajamento de um perfil'

  param :username, type: :string, desc: 'Username do perfil', required: true
  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: true

  def run(username:, platform:)
    profile = SocialProfile.find_by(platform: platform, platform_username: username)
    return error("Perfil não encontrado: #{username} em #{platform}") unless profile

    rate = profile.engagement_rate
    posts_analyzed = profile.social_posts.last(10)&.size || 0

    success({
              engagement_rate: rate,
              followers: profile.followers_count,
              posts_analyzed: posts_analyzed
            })
  end
end

class SnapshotTrendTool < ToolBase
  description 'Retorna tendência de snapshots de métricas de um perfil'

  param :username, type: :string, desc: 'Username do perfil', required: true
  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: true
  param :days, type: :integer, desc: 'Número de dias para buscar (padrão 30)', required: false

  def run(username:, platform:, days: 30)
    profile = SocialProfile.find_by(platform: platform, platform_username: username)
    return error("Perfil não encontrado: #{username} em #{platform}") unless profile

    snapshots = profile.profile_snapshots
                       .where('recorded_at >= ?', days.days.ago)
                       .ordered
                       .limit(20)

    success(snapshots.map do |s|
      {
        recorded_at: s.recorded_at,
        followers_count: s.followers_count,
        posts_count: s.posts_count
      }
    end)
  end
end

class ProfileRankingTool < ToolBase
  description 'Retorna ranking de perfis por métrica'

  param :platform, type: :string, desc: 'Plataforma (opcional)', required: false
  param :metric, type: :string, desc: 'Métrica (followers/engagement)', required: true
  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 10)', required: false

  def run(metric:, platform: nil, limit: 10)
    limit = clamp(limit, 1, 50)

    case metric
    when 'followers'
      profiles = SocialProfile.where.not(followers_count: nil)
      profiles = profiles.by_platform(platform) if platform.present?
      profiles = profiles.order(followers_count: :desc).limit(limit)
      success(profiles.map { |p| format_profile(p) })
    when 'engagement'
      profiles = SocialProfile.where.not(followers_count: nil)
      profiles = profiles.by_platform(platform) if platform.present?
      ranked = profiles.select { |p| p.engagement_rate.present? }
                       .sort_by { |p| -p.engagement_rate }
                       .first(limit)
      success(ranked.map { |p| format_profile(p).merge(engagement_rate: p.engagement_rate) })
    else
      error("Métrica inválida: #{metric}. Use 'followers' ou 'engagement'.")
    end
  end
end
