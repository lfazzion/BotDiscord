# frozen_string_literal: true

# Persiste o conteúdo original da ideia do usuário (R5a — R4 fix).
#
# `offered_content` armazena o texto exato que o usuário digitou quando a
# skill foi detectada automaticamente (antes de fazer a oferta de thread).
# É usado para repassar essa ideia original ao primeiro turno da skill,
# em vez de passar a resposta do usuário ("sim", "continua aqui", etc.).
class AddOfferedContentToConversations < ActiveRecord::Migration[8.1]
  def up
    add_column :conversations, :offered_content, :text
  end

  def down
    remove_column :conversations, :offered_content
  end
end
