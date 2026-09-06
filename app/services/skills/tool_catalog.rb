# frozen_string_literal: true

module Skills
  # Catálogo estável de tools: mapeia IDs declarativos para classes Ruby.
  # Uma skill nunca chama constantize sobre valor de configuração — só aqui.
  class ToolCatalog
    # IDs estáveis -> classes de tool já existentes no projeto.
    # Mantido em sintonia com ChatSessionManager.all_tool_classes.
    MAP = {
      "profile_lookup"       => "ProfileLookupTool",
      "profile_list"         => "ProfileListTool",
      "profile_search"       => "ProfileSearchTool",
      "profile_compare"      => "ProfileCompareTool",
      "add_profile"          => "AddProfileTool",
      "set_profile_monitoring" => "SetProfileMonitoringTool",
      "remove_profile"       => "RemoveProfileTool",
      "promote_prospect"     => "PromoteProspectTool",
      "recent_posts"         => "RecentPostsTool",
      "top_posts"            => "TopPostsTool",
      "posts_by_type"        => "PostsByTypeTool",
      "post_engagement"      => "PostEngagementTool",
      "engagement_rate"      => "EngagementRateTool",
      "snapshot_trend"       => "SnapshotTrendTool",
      "profile_ranking"      => "ProfileRankingTool",
      "prospects"            => "ProspectsTool",
      "unclassified_profiles" => "UnclassifiedProfilesTool",
      "upcoming_catalog"     => "UpcomingCatalogTool",
      "popular_catalog"      => "PopularCatalogTool",
      "upcoming_events"      => "UpcomingEventsTool",
      "recent_articles"      => "RecentArticlesTool",
      "web_search"           => "WebSearchTool",
      "platform_search"      => "PlatformSearchTool",
      "topic_add"            => "TopicAddTool",
      "topic_list"           => "TopicListTool",
      "topic_remove"         => "TopicRemoveTool",
      "page_fetch"           => "PageFetchTool"
    }.freeze

    class UnknownToolError < StandardError; end

    class << self
      def lookup(id)
        id = id.to_s
        name = MAP[id]
        raise UnknownToolError, "_tool_id desconhecido: #{id}" unless name
        # Lazy + auditavel: o MAP e a FONTE unica (nunca constantize valor de
        # configuracao); aqui resolvemos strings FIXAS do catalogo. Lazy porque
        # no eager_load as tool classes (app/tools/) podem nao estar definidas
        # quando este arquivo e avaliado (boot crash 06/09).
        Object.const_get(name)
      end

      def known_ids
        MAP.keys
      end

      def all_classes
        MAP.keys.map { |id| lookup(id) }
      end
    end
  end
end
