# frozen_string_literal: true

require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "open_for cria conversa nova quando não há ativa" do
    conversation = Conversation.open_for(scope: "c:1", channel_id: "1", shared: true)

    assert conversation.persisted?
    assert conversation.active
    assert conversation.shared
    assert_not_nil conversation.last_active_at
  end

  test "open_for devolve a conversa ativa existente" do
    first = Conversation.open_for(scope: "c:1", channel_id: "1", shared: true)
    second = Conversation.open_for(scope: "c:1", channel_id: "1", shared: true)

    assert_equal first.id, second.id
  end

  test "open_for cria outra conversa depois de close!" do
    first = Conversation.open_for(scope: "c:1", channel_id: "1", shared: true)
    first.close!
    second = Conversation.open_for(scope: "c:1", channel_id: "1", shared: true)

    assert_not_equal first.id, second.id
    assert_not first.reload.active
  end

  test "só existe uma conversa ativa por escopo" do
    Conversation.open_for(scope: "c:1", channel_id: "1")

    assert_raises ActiveRecord::RecordNotUnique do
      Conversation.create!(scope: "c:1", discord_channel_id: "1", active: true, last_active_at: Time.current)
    end
  end

  test "escopos diferentes têm conversas ativas independentes" do
    a = Conversation.open_for(scope: "u:1:c:9", channel_id: "9", user_id: "1")
    b = Conversation.open_for(scope: "u:2:c:9", channel_id: "9", user_id: "2")

    assert_not_equal a.id, b.id
  end

  test "assign_title_from trunca em 80 caracteres" do
    conversation = Conversation.open_for(scope: "c:1", channel_id: "1")
    conversation.assign_title_from("a" * 200)

    assert_equal 80, conversation.title.length
  end

  test "assign_title_from não sobrescreve título existente" do
    conversation = Conversation.open_for(scope: "c:1", channel_id: "1")
    conversation.assign_title_from("primeiro")
    conversation.assign_title_from("segundo")

    assert_equal "primeiro", conversation.title
  end

  test "recent ordena da mais recente para a mais antiga" do
    velha = Conversation.create!(scope: "c:1", discord_channel_id: "1", active: false,
                                 last_active_at: 2.days.ago)
    nova = Conversation.create!(scope: "c:1", discord_channel_id: "1", active: false,
                                last_active_at: 1.hour.ago)

    assert_equal [nova.id, velha.id], Conversation.recent.pluck(:id)
  end

  test "recent desempata por id quando last_active_at é idêntico" do
    empatada_1 = Conversation.create!(scope: "c:1", discord_channel_id: "1", active: false,
                                      last_active_at: 1.hour.ago)
    empatada_2 = Conversation.create!(scope: "c:1", discord_channel_id: "1", active: false,
                                      last_active_at: empatada_1.last_active_at)

    assert_equal empatada_1.last_active_at, empatada_2.last_active_at
    assert_equal [empatada_2.id, empatada_1.id], Conversation.recent.pluck(:id)
  end

  # ===========================================================================
  # Tarefa 6 — Persistência do modo (Skill System)
  # Plano: tmp/hermes-plano-skill-system.md:502-517.
  #
  # RED esperado (rodar antes do GREEN):
  #   * coluna `active_skill_name` ainda não existe — Tarefa 6 não foi aplicada;
  #     qualquer leitura/escrita direta (incl. create!) estoura com
  #     ActiveModel::UnknownAttributeError ou ActiveRecord::StatementInvalid
  #     dependendo do caminho.
  #   * `open_for(..., active_skill_name:)` ainda não aceita o kwarg (ArgumentError).
  #   * validação de skill desconhecida ainda não existe.
  # ===========================================================================

  test "T6: coluna active_skill_name existe no schema" do
    assert_includes Conversation.column_names, "active_skill_name"
  end

  test "T6: open_for aceita o kwarg active_skill_name e o persiste" do
    conv = Conversation.open_for(scope: "c:99", channel_id: "99",
                                 active_skill_name: "grill-me")
    assert_equal "grill-me", conv.reload.active_skill_name
  end

  test "T6: open_for sem active_skill_name mantém nil (chat normal)" do
    conv = Conversation.open_for(scope: "c:99", channel_id: "99")
    assert_nil conv.active_skill_name
  end

  test "T6: open_for rejeita valor que não está no registro de skills" do
    # O teste prova a invariante 3 do plano ("configuração inválida falha antes
    # da chamada LLM"). Sem o registry stub, qualquer string seria aceita — o
    # que abre caminho para tool_policy e prompt_loader silenciosamente
    # receberem fragmento/tool policy de um nome nunca validado.
    Skills::Registry.stubs(:known_skill?).returns(false)

    assert_raises(ArgumentError, ActiveModel::ValidationError, ActiveRecord::RecordInvalid) do
      Conversation.open_for(scope: "c:99", channel_id: "99", active_skill_name: "skill-fantasma")
    end
  end

  test "T6: open_for aceita nome conhecido do registro (registry stubado)" do
    Skills::Registry.stubs(:known_skill?).returns(true)
    conv = Conversation.open_for(scope: "c:99", channel_id: "99",
                                 active_skill_name: "grill-me")
    assert_equal "grill-me", conv.reload.active_skill_name
  end

  test "T6: conversa fechada preserva seu active_skill_name histórico" do
    conv = Conversation.open_for(scope: "c:99", channel_id: "99",
                                 active_skill_name: "grill-me")
    conv.close!
    assert_equal "grill-me", conv.reload.active_skill_name,
                 "fechar a conversa não pode apagar o modo histórico — é a fonte durável do /resume"
  end

  test "T6: nova conversa após /new nasce sem active_skill_name" do
    primeira = Conversation.open_for(scope: "c:99", channel_id: "99",
                                     active_skill_name: "grill-me")
    primeira.close! # /new

    segunda = Conversation.open_for(scope: "c:99", channel_id: "99")
    assert_nil segunda.active_skill_name,
               "/new zera o modo por construção — conversa nova não herda skill da anterior"
  end

  # ===========================================================================
  # Tarefa 7 — Campo de oferta pendente
  # Plano: tmp/hermes-plano-oferta-pendente.md
  #
  # RED esperado (rodar antes do GREEN):
  #   * colunas `offered_skill_name` e `offered_at` ainda não existem — qualquer
  #     leitura/escrita direta (incl. create!) estoura com
  #     ActiveModel::UnknownAttributeError ou ActiveRecord::StatementInvalid
  #     dependendo do caminho.
  #   * validação de offered_skill_name desconhecido ainda não existe.
  #   * limpeza automática de offered ao ativar modo ou chamar /new ainda não existe.
  # ===========================================================================

  test "T7: coluna offered_skill_name existe no schema" do
    assert_includes Conversation.column_names, "offered_skill_name"
  end

  test "T7: coluna offered_at existe no schema" do
    assert_includes Conversation.column_names, "offered_at"
  end

  test "T7: offered_skill_name é nullable" do
    conv = Conversation.open_for(scope: "c:100", channel_id: "100")
    assert_nil conv.offered_skill_name
    assert_nil conv.offered_at
  end

  test "T7: pode atribuir offered_skill_name e offered_at" do
    conv = Conversation.open_for(scope: "c:100", channel_id: "100")
    travel_to(Time.at(1_700_000_000)) do
      conv.update!(offered_skill_name: "grill-me", offered_at: Time.current)
    end
    assert_equal "grill-me", conv.reload.offered_skill_name
    assert_not_nil conv.reload.offered_at
  end

  test "T7: rejeita offered_skill_name desconhecida" do
    conv = Conversation.open_for(scope: "c:100", channel_id: "100")
    Skills::Registry.stubs(:known_skill?).returns(false)

    assert_raises(ActiveRecord::RecordInvalid) do
      conv.update!(offered_skill_name: "skill-fantasma")
    end
    assert_nil conv.reload.offered_skill_name
  end

  test "T7: limpa offered ao ativar active_skill_name" do
    conv = Conversation.open_for(scope: "c:100", channel_id: "100")
    Skills::Registry.stubs(:known_skill?).returns(true)
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current)
    assert_equal "grill-me", conv.offered_skill_name

    conv.update!(active_skill_name: "grill-me")
    assert_nil conv.reload.offered_skill_name,
               "ao ativar modo, oferta pendente deve ser limpa"
    assert_nil conv.reload.offered_at
  end

  test "T7: limpa offered ao chamar /new (close!)" do
    conv = Conversation.open_for(scope: "c:100", channel_id: "100")
    Skills::Registry.stubs(:known_skill?).returns(true)
    conv.update!(offered_skill_name: "grill-me", offered_at: Time.current)
    assert_equal "grill-me", conv.offered_skill_name

    conv.close! # simula /new
    assert_nil conv.reload.offered_skill_name,
               "/new deve limpar oferta pendente"
    assert_nil conv.reload.offered_at
  end
end
