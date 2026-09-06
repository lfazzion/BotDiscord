# frozen_string_literal: true

module Discord
  # Erro nomeado para o caso em que o ThreadEventProxy nao consegue resolver o
  # canal da thread a partir do thread_channel_id (guild.channels.find retorna nil).
  #
  # Decision: ao inves de fallback silencioso para o canal pai (o bug original de
  # 06/09 03:34 UTC onde respondia no canal pai), levantamos essa excecao e
  # registramos ERROR. O rescue do handle_message / handle_skill_slash_command
  # devolve "⚠️ Erro ao processar" ao usuario — preferivel a mandar a resposta
  # no canal errado. Este arquivo e exigido pelo thread_event_proxy_test.rb.
  class ThreadChannelUnresolvedError < StandardError
    attr_reader :thread_channel_id

    def initialize(thread_channel_id)
      @thread_channel_id = thread_channel_id
      super("ThreadChannelUnresolvedError: thread channel id=#{thread_channel_id} nao encontrada em guild.channels")
    end
  end
end
