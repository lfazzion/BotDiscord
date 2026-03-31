# frozen_string_literal: true

class ChatSessionManager
  TTL_MINUTES = 30
  FALLBACK_MODEL = 'gemini-3.1-flash-lite-preview'

  class << self
    def get_or_create(user_id, channel_id)
      key = session_key(user_id, channel_id)

      mutex.synchronize do
        session = sessions[key]

        if session && session[:expires_at] > Time.current
          session[:expires_at] = Time.current + TTL_MINUTES.minutes
          return session[:chat]
        end

        chat = build_chat
        sessions[key] = {
          chat: chat,
          expires_at: Time.current + TTL_MINUTES.minutes
        }

        chat
      end
    end

    def create_fallback_chat
      build_chat(model: FALLBACK_MODEL)
    end

    def cleanup_expired
      mutex.synchronize do
        sessions.delete_if { |_key, session| session[:expires_at] < Time.current }
      end
      Rails.logger.info "[ChatSessionManager] Cleanup concluído. Sessões ativas: #{sessions.size}"
    end

    def session_key(user_id, channel_id)
      "#{user_id}:#{channel_id}"
    end

    private

    def build_chat(model: nil)
      chat = model ? RubyLLM.chat(model: model) : RubyLLM.chat
      all_tool_classes.each { |tool_class| chat.with_tool(tool_class) }
      prompt = Llm::PromptLoader.load('chatbot', user_message: '')
      chat.with_instructions(prompt[:system])
      chat
    end

    def sessions
      @sessions ||= {}
    end

    def mutex
      @mutex ||= Mutex.new
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
