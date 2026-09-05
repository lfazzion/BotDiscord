# frozen_string_literal: true

# Persiste o modo/skill ativo da conversa (Skill System v2 — Tarefa 6).
#
# Justificativa: Conversation passa a ser a fonte durável do modo ativo
# (plano §3.6: "Conversation.active_skill_name é a fonte durável. Thread.current
# continua reservado a metadados do turno, nunca como armazenamento do modo").
# Thread.current não sobrevive a cache miss/restart; esta coluna sim.
#
# Ativação e persistência acontecem DENTRO de with_scope_lock (ChatSessionManager
# Tarefa 7). Nada nesta migration toca esse fluxo — ela só adiciona a coluna.
class AddActiveSkillNameToConversations < ActiveRecord::Migration[8.1]
  def up
    add_column :conversations, :active_skill_name, :string
    # Index simples: o caminho quente do `with_scope_lock` ainda é o índice
    # parcial único em (scope) WHERE active = 1. Esta coluna só é filtrada
    # pontualmente (reidratação/compactação) — o volume por conversa é 1,
    # então um índice composto não paga o custo de atualização de cada turno.
    add_index :conversations, :active_skill_name, where: "active_skill_name IS NOT NULL",
              name: "index_conversations_on_active_skill_name"
  end

  def down
    remove_index :conversations, name: "index_conversations_on_active_skill_name"
    remove_column :conversations, :active_skill_name
  end
end