# frozen_string_literal: true

# Uma conversa do Discord. O escopo decide se ela é individual
# ("u:<user_id>:c:<channel_id>") ou compartilhada pela sala inteira ("c:<channel_id>").
# O índice parcial único garante no máximo uma ativa por escopo — a fronteira entre
# conversas é o comando /new, e não mais o TTL de 30 minutos.
#
# A coluna `active_skill_name` (Skill System v2 — Tarefa 6) é a fonte durável do
# modo/skill ativo: Thread.current não sobrevive a cache miss/restart, e a
# reidratação/compactação precisam dela para reconstruir o chat quente. A
# validação fica aqui (não no ChatSessionManager) para que qualquer caminho que
# crie/atualize uma Conversation passe pelo mesmo gate — vale inclusive para o
# factory de teste e para o `resume!` (que não muda a skill, mas o read não
# pode carregar lixo).
class Conversation < ApplicationRecord
  TITLE_LIMIT = 80

  has_many :chat_messages, dependent: :destroy

  validates :scope, presence: true
  validates :discord_channel_id, presence: true
  # A skill ativa, quando presente, deve ser uma DEFINIÇÃO VÁLIDA do registro.
  # nil é permitido (chat normal). Esse gate é o mesmo do plano §3.1: "configuração
  # inválida falha antes da chamada LLM" — uma string solta varreria o caminho
  # para PromptLoader/ToolPolicy e silenciosamente usaria fragmento/tool_policy
  # de um nome nunca validado. Skills::Registry.fetch? é o método da Lane D
  # que devolve nil para nome desconhecido.
  validate :active_skill_name_must_be_known, if: -> { active_skill_name.present? && will_save_change_to_active_skill_name? }

  # Tarefa 7 — oferta pendente: o nome só pode ser uma skill conhecida do
  # registro. Nil é permitido (sem oferta). O registro é consultado com
  # `will_save_change_to_*` para evitar validação em redescarregamentos inertes.
  validate :offered_skill_name_must_be_known, if: -> { offered_skill_name.present? && will_save_change_to_offered_skill_name? }

  # Tarefa 7 — ao ativar um modo (active_skill_name), a oferta pendente
  # (offered_skill_name / offered_at) é consumida e zerada automaticamente.
  # Isso evita que uma conversa "ativa" termine com uma oferta flutuante
  # que ninguém vai mais resolver.
  before_save :clear_offered_when_activating, if: -> { active_skill_name.present? && active_skill_name_changed? }

  # Tarefa 7 — quando a conversa é fechada (`/new`), a oferta pendente é
  # descartada. O plano a trata como estado transitório da sessão anterior;
  # uma nova sessão não herda ofertas.
  before_save :clear_offered_when_closing, if: -> { will_save_change_to_active?(from: true, to: false) }

  # Desempate por id: dois registros podem cair no mesmo last_active_at (ex.:
  # /new fecha uma conversa e abre outra quase no mesmo instante), e sem
  # segundo critério a ordem de empate é indefinida no SQLite — /resume por
  # índice podia acertar conversas diferentes em chamadas consecutivas.
  scope :recent, -> { order(last_active_at: :desc, id: :desc) }

  class << self
    def active_for(scope)
      find_by(scope: scope, active: true)
    end

    # Idempotente. Duas mensagens simultâneas no canal compartilhado podem correr
    # aqui ao mesmo tempo; o índice parcial único converte a corrida em
    # RecordNotUnique, e a releitura devolve a conversa que venceu.
    #
    # `active_skill_name:` é o kwarg da Tarefa 6 (Skill System). É repassado
    # para o `create!` interno — e a validação `active_skill_name_must_be_known`
    # dispara nesse momento. Default nil preserva as chamadas atuais
    # (ChatSessionManager.open_conversation é um dos chamadores).
    def open_for(scope:, channel_id:, user_id: nil, shared: false, active_skill_name: nil)
      active_for(scope) || create!(
        scope: scope,
        discord_channel_id: channel_id,
        discord_user_id: user_id,
        shared: shared,
        active: true,
        last_active_at: Time.current,
        active_skill_name: active_skill_name
      )
    rescue ActiveRecord::RecordNotUnique
      active_for(scope) || raise
    end
  end

  def assign_title_from(content)
    return if title.present?

    update!(title: content.to_s.strip[0, TITLE_LIMIT])
  end

  def touch_activity!
    update!(last_active_at: Time.current)
  end

  def close!
    update!(active: false)
  end

  private

  # Validação do gate de skill (Tarefa 6). `Skills::Registry.fetch?(name)` é o
  # método da Lane D — devolve `nil` quando o nome não está no registro. Sem ele,
  # qualquer string seria aceita e chegaria a PromptLoader/ToolPolicy como se
  # fosse uma definição válida. Mantido como `errors.add(:base, ...)` em vez de
  # `errors.add(:active_skill_name, ...)` porque a chave é fraca: o atributo
  # em si é texto livre, o problema é o CONTEÚDO dele.
  def active_skill_name_must_be_known
    return if Skills::Registry.fetch?(active_skill_name)

    errors.add(:base,
               "active_skill_name=#{active_skill_name.inspect} não consta no Skills::Registry")
  end

  # Tarefa 7 — gate de oferta: garante que só se grava uma oferta de skill
  # cujo nome existe no registro. Nil é sempre permitido (sem oferta).
  def offered_skill_name_must_be_known
    return if Skills::Registry.fetch?(offered_skill_name)

    errors.add(:base,
               "offered_skill_name=#{offered_skill_name.inspect} não consta no Skills::Registry")
  end

  # Tarefa 7 — quando o modo ativo está sendo setado (transição nil -> nome ou
  # nome antigo -> novo nome), descarta a oferta pendente. O consumo da oferta
  # é o "sim" implícito do usuário.
  def clear_offered_when_activating
    self.offered_skill_name = nil
    self.offered_at = nil
  end

  # Tarefa 7 — /new (close!) descarta oferta pendente. Nova conversa nasce
  # sem herdar o estado transitório da anterior.
  def clear_offered_when_closing
    self.offered_skill_name = nil
    self.offered_at = nil
  end
end
