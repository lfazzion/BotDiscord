# frozen_string_literal: true

class ProspectsTool < ToolBase
  description 'Lista perfis prospectos (potenciais patrocinadores)'

  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 20)', required: false

  def run(limit: 20)
    limit = clamp(limit, 1, 50)
    prospects = DiscoveredProfile.prospects.limit(limit)

    success(prospects.map do |p|
      {
        id: p.id,
        platform: p.platform,
        username: p.username,
        classification: p.classification,
        classified_at: p.classified_at
      }
    end)
  end
end

class UnclassifiedProfilesTool < ToolBase
  description 'Lista perfis ainda não classificados'

  param :limit, type: :integer, desc: 'Número máximo de resultados (padrão 20)', required: false

  def run(limit: 20)
    limit = clamp(limit, 1, 50)
    unclassified = DiscoveredProfile.unclassified.limit(limit)

    success(unclassified.map do |p|
      {
        id: p.id,
        platform: p.platform,
        username: p.username,
        classification: p.classification,
        classified_at: p.classified_at
      }
    end)
  end
end
