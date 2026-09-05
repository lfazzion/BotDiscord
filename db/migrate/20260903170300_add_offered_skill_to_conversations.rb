# frozen_string_literal: true

# Persiste a oferta pendente de skill na conversa (Tarefa 7 — oferta pendente).
#
# `offered_skill_name` armazena o nome da skill proposta ao usuário mas ainda
# não confirmada. `offered_at` registra quando a oferta foi feita.
# Ambos são nil quando não há oferta pendente.
#
# A validação (nome desconhecido rejeitado, limpa ao ativar modo ou /new) fica
# no model Conversation, não aqui.
class AddOfferedSkillToConversations < ActiveRecord::Migration[8.1]
  def up
    add_column :conversations, :offered_skill_name, :string
    add_column :conversations, :offered_at, :datetime
  end

  def down
    remove_column :conversations, :offered_at
    remove_column :conversations, :offered_skill_name
  end
end
