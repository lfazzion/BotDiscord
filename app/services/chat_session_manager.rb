# frozen_string_literal: true

class ChatSessionManager
  TTL_MINUTES = 30

  class << self
    def get_or_create(user_id, channel_id)
      key = session_key(user_id, channel_id)
      session = sessions[key]

      if session && session[:expires_at] > Time.current
        session[:expires_at] = Time.current + TTL_MINUTES.minutes
        return session[:chat]
      end

      chat = RubyLLM.chat
      all_tool_classes.each { |tool_class| chat.with_tool(tool_class) }

      sessions[key] = {
        chat: chat,
        expires_at: Time.current + TTL_MINUTES.minutes
      }

      chat
    end

    def cleanup_expired
      sessions.delete_if { |_key, session| session[:expires_at] < Time.current }
      Rails.logger.info "[ChatSessionManager] Cleanup concluído. Sessões ativas: #{sessions.size}"
    end

    def session_key(user_id, channel_id)
      "#{user_id}:#{channel_id}"
    end

    private

    def sessions
      @sessions ||= {}
    end

    def all_tool_classes
      [
        ProfileLookupTool, ProfileListTool, ProfileSearchTool, ProfileCompareTool,
        RecentPostsTool, TopPostsTool, PostsByTypeTool, PostEngagementTool,
        EngagementRateTool, SnapshotTrendTool, ProfileRankingTool,
        ProspectsTool, UnclassifiedProfilesTool,
        UpcomingCatalogTool, PopularCatalogTool,
        UpcomingEventsTool, RecentArticlesTool
      ]
    end
  end
end
