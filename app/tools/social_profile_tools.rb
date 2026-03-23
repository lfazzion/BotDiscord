# frozen_string_literal: true

class ProfileLookupTool < ToolBase
  description 'Busca perfil por username e plataforma'

  param :username, type: :string, desc: 'Username do perfil', required: true
  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: true

  def run(username:, platform:)
    profile = SocialProfile.find_by(platform: platform, platform_username: username)
    return error("Perfil não encontrado: #{username} em #{platform}") unless profile

    success(format_profile(profile))
  end
end

class ProfileListTool < ToolBase
  description 'Lista perfis por plataforma com paginação'

  param :platform, type: :string, desc: 'Plataforma (twitter/instagram/youtube/tiktok)', required: false
  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 10)', required: false

  def run(platform: nil, limit: 10)
    limit = clamp(limit, 1, 50)
    profiles = SocialProfile.all
    profiles = profiles.by_platform(platform) if platform.present?
    profiles = profiles.order(followers_count: :desc).limit(limit)

    success(profiles.map { |p| format_profile(p) })
  end
end

class ProfileSearchTool < ToolBase
  description 'Busca perfis por termo na bio ou display_name'

  param :query, type: :string, desc: 'Termo de busca', required: true
  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 10)', required: false

  def run(query:, limit: 10)
    limit = clamp(limit, 1, 30)
    sanitized = SocialProfile.sanitize_sql_like(query)
    profiles = SocialProfile.where('bio LIKE ? OR display_name LIKE ?', "%#{sanitized}%", "%#{sanitized}%").limit(limit)

    success(profiles.map { |p| format_profile(p) })
  end
end

class ProfileCompareTool < ToolBase
  description 'Compara dois perfis lado a lado'

  param :username_a, type: :string, desc: 'Username do primeiro perfil', required: true
  param :platform_a, type: :string, desc: 'Plataforma do primeiro perfil', required: true
  param :username_b, type: :string, desc: 'Username do segundo perfil', required: true
  param :platform_b, type: :string, desc: 'Plataforma do segundo perfil', required: true

  def run(username_a:, platform_a:, username_b:, platform_b:)
    profile_a = SocialProfile.find_by(platform: platform_a, platform_username: username_a)
    return error("Perfil não encontrado: #{username_a} em #{platform_a}") unless profile_a

    profile_b = SocialProfile.find_by(platform: platform_b, platform_username: username_b)
    return error("Perfil não encontrado: #{username_b} em #{platform_b}") unless profile_b

    success({
              profile_a: format_profile(profile_a),
              profile_b: format_profile(profile_b)
            })
  end
end
