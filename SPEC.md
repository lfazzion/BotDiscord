# SPEC — Fase 3: O Cérebro Inteligente - Multi LLM

> Especificação tática derivada do `PRD.md`. Cada arquivo listado com caminho absoluto, mudanças por linha e pseudocódigo.

---

## 1. ARQUIVOS A CRIAR

---

### 1.1 `lib/llm/base_client.rb`

Classe abstrata base para todos os clientes LLM. Não é instanciada diretamente.

```ruby
# frozen_string_literal: true

module Llm
  class BaseClient
    class QuotaExceededError < StandardError; end

    # --- Subclasses DEVEM sobrescrever ---
    def model_id
      raise NotImplementedError, "#{self.class}#model_id não implementado"
    end

    def daily_quota_key
      raise NotImplementedError, "#{self.class}#daily_quota_key não implementado"
    end

    def max_daily_requests
      raise NotImplementedError, "#{self.class}#max_daily_requests não implementado"
    end

    # --- Interface pública ---

    # @param prompt [String] mensagem do usuário
    # @param system [String, nil] system instructions
    # @param tools [Array<Class>] classes RubyLLM::Tool
    # @return [RubyLLM::Message] resposta do modelo
    def complete(prompt, system: nil, tools: [])
      check_quota!
      track_request!

      chat = RubyLLM.chat(model: model_id)
      chat.with_instructions(system) if system
      tools.each { |t| chat.with_tool(t) }

      Rails.logger.info "[#{self.class.name}] Requisição enviada (model: #{model_id})"
      chat.ask(prompt)
    end

    private

    def check_quota!
      count = daily_request_count
      if count >= max_daily_requests
        Rails.logger.warn "[#{self.class.name}] Quota diária atingida: #{count}/#{max_daily_requests}"
        raise QuotaExceededError, "#{self.class.name} excedeu #{max_daily_requests} requests/dia"
      end
    end

    def track_request!
      cache_key = daily_cache_key
      current = SolidCache.read(cache_key).to_i
      SolidCache.write(cache_key, current + 1, expires_in: 26.hours)
    end

    def daily_request_count
      SolidCache.read(daily_cache_key).to_i
    end

    def daily_cache_key
      "#{daily_quota_key}:#{Date.current.iso8601}"
    end
  end
end
```

**Lógica detalhada:**
- `check_quota!` lê do SolidCache (já configurado no projeto, `gem 'solid_cache'`). Usa chave `gemini_daily:2026-03-20` como exemplo.
- `track_request!` incrementa após cada chamada, com TTL de 26h para auto-limpeza.
- Subclasses só precisam declarar `model_id`, `daily_quota_key`, `max_daily_requests`.
- Não usa `raise` para erros de API — usa o padrão do projeto para rate-limit (que o `ApplicationJob` já trata). Para quota interna, usa `QuotaExceededError` custom que o AiRouter resgata.

---

### 1.2 `lib/llm/gemini_client.rb`

```ruby
# frozen_string_literal: true

module Llm
  class GeminiClient < BaseClient
    # Gemini 3.1 Flash Lite: 250K TPM, 15 RPM, 500 RPD
    MODEL_ID = 'google/gemini-3.1-flash-lite'
    MAX_DAILY = 480 # margem de segurança dos 500 RPD

    def model_id = MODEL_ID
    def daily_quota_key = 'gemini_daily'
    def max_daily_requests = MAX_DAILY
  end
end
```

---

### 1.3 `lib/llm/gemma_client.rb`

```ruby
# frozen_string_literal: true

module Llm
  class GemmaClient < BaseClient
    # Gemma 3 27B: 15K TPM, 30 RPM, 14.400 RPD
    MODEL_ID = 'google/gemma-3-27b'
    MAX_DAILY = 14_000 # margem de segurança dos 14.400 RPD
    TPM_SAFE_THRESHOLD = 8_000 # acima disso, escalar para OpenRouter

    def model_id = MODEL_ID
    def daily_quota_key = 'gemma_daily'
    def max_daily_requests = MAX_DAILY

    def self.tpm_safe_threshold
      TPM_SAFE_THRESHOLD
    end
  end
end
```

---

### 1.4 `lib/llm/openrouter_client.rb`

```ruby
# frozen_string_literal: true

module Llm
  class OpenrouterClient < BaseClient
    # Claude 3.5 Sonnet via OpenRouter — fallback pesado para chat
    MODEL_ID = 'anthropic/claude-3.5-sonnet'
    MAX_DAILY = 400 # conservador para tier gratuito/pago básico

    def model_id = MODEL_ID
    def daily_quota_key = 'openrouter_daily'
    def max_daily_requests = MAX_DAILY
  end
end
```

**Nota:** O model ID `anthropic/claude-3.5-sonnet` é o slug padrão do OpenRouter. Se o usuário preferir outro modelo (ex: `google/gemini-2.5-pro`), basta trocar a constante.

---

### 1.5 `app/services/ai_router.rb`

Serviço orquestrador. Único ponto de entrada para chamadas LLM no projeto.

```ruby
# frozen_string_literal: true

class AiRouter
  ESTIMATED_TOKENS_PER_CHAR = 0.25 # ~4 chars = 1 token (inglês; português é similar)
  GEMMA_TPM_THRESHOLD = Llm::GemmaClient.tpm_safe_threshold

  class << self
    # @param prompt [String, Hash] mensagem ou { system:, user: } do PromptLoader
    # @param context [:background, :interactive] tipo de chamada
    # @param tools [Array<Class>] RubyLLM::Tool classes
    # @return [RubyLLM::Message]
    def complete(prompt, context: :interactive, tools: [])
      system_msg, user_msg = extract_messages(prompt)
      estimated_tokens = estimate_tokens(user_msg)

      client = select_client(context, estimated_tokens)
      Rails.logger.info "[AiRouter] Roteando para #{client.class.name} " \
                        "(ctx: #{context}, ~#{estimated_tokens} tokens)"

      client.complete(user_msg, system: system_msg, tools: tools)
    rescue Llm::BaseClient::QuotaExceededError => e
      handle_quota_exceeded(e, context, estimated_tokens)
    end

    private

    def extract_messages(prompt)
      if prompt.is_a?(Hash)
        [prompt[:system], prompt[:user]]
      else
        [nil, prompt.to_s]
      end
    end

    def select_client(context, estimated_tokens)
      case context
      when :background
        Llm::GeminiClient.new
      when :interactive
        if estimated_tokens > GEMMA_TPM_THRESHOLD
          Llm::OpenrouterClient.new
        else
          Llm::GemmaClient.new
        end
      else
        raise ArgumentError, "Contexto desconhecido: #{context}. Use :background ou :interactive"
      end
    end

    def estimate_tokens(text)
      return 0 if text.nil?

      (text.length * ESTIMATED_TOKENS_PER_CHAR).ceil
    end

    def handle_quota_exceeded(error, context, estimated_tokens)
      Rails.logger.warn "[AiRouter] #{error.message}. Tentando fallback..."
      raise error unless context == :background

      # Gemini quota estourou → fallback para OpenRouter mesmo em background
      Rails.logger.warn "[AiRouter] Gemini esgotado. Fallback para OpenRouter (background)."
      Llm::OpenrouterClient.new.complete("", system: nil, tools: []) # placeholder de teste
      # Re-raise para caller decidir retry
      raise error
    end
  end
end
```

**Lógica de roteamento:**
- `:background` → sempre Gemini 3.1 Flash Lite (max ingestão de tokens)
- `:interactive` → Gemma 3 27B (rápido, 14K RPD), ou OpenRouter se tokens > 8K
- Se Gemini quota estourar, loga warning e re-raise para caller (DiscoveryJob deve tratar)

---

### 1.6 `lib/llm/prompt_loader.rb`

Carrega YAML de `config/prompts/`, renderiza ERB com locals e partials.

```ruby
# frozen_string_literal: true

module Llm
  class PromptLoader
    PROMPTS_DIR = Rails.root.join('config/prompts')
    PARTIALS_DIR = PROMPTS_DIR.join('partials')

    class PromptNotFoundError < ArgumentError; end

    class << self
      # Carrega um prompt YAML e renderiza ERB com variáveis locais.
      #
      # @param name [String] nome do prompt (ex: 'discovery')
      # @param locals [Hash] variáveis para ERB (ex: handles: array)
      # @return [Hash] { system: String, user: String }
      def load(name, **locals)
        file_path = PROMPTS_DIR.join("system/#{name}.yml")
        raise PromptNotFoundError, "Prompt '#{name}' não encontrado em #{file_path}" unless file_path.exist?

        raw = file_path.read
        yaml = YAML.safe_load(ERB.new(raw).result(binding), permitted_classes: [Symbol])

        system_text = render_template(yaml['system'], **locals)
        user_text = render_template(yaml['user_template'], **locals)

        {
          system: system_text.strip,
          user: user_text.strip
        }
      end

      # Método chamado pelos ERB templates como `partial('rules')`
      def partial(name)
        file_path = PARTIALS_DIR.join("_#{name}.yml")
        return "" unless file_path.exist?

        yaml = YAML.safe_load(file_path.read, permitted_classes: [Symbol])
        yaml['content'].to_s
      end

      private

      def render_template(template, **locals)
        return "" if template.nil?

        # ERB com accesso a locals via binding
        b = binding
        locals.each { |k, v| b.local_variable_set(k, v) }
        ERB.new(template).result(b)
      end
    end
  end
end
```

**Nota técnica sobre ERB e `partial`:**
O YAML contém strings com `<%= partial 'rules' %>`. Quando `ERB.new(raw).result(binding)` executa, o `binding` inclui o método `Llm::PromptLoader.partial` como método de classe acessível. O `render_template` usa `binding` + `local_variable_set` para injetar variáveis como `handles` nos templates `user_template`.

---

### 1.7 `config/prompts/partials/_rules.yml`

```yaml
content: |
  REGRAS CRÍTICAS:
  - NUNCA invente dados que não existam na entrada fornecida.
  - Valores numéricos ausentes (likes, views, followers) devem ser retornados como null, NUNCA como 0.
  - Quando um dado estiver faltando, declare explicitamente: "dados insuficientes".
  - Retorne sempre JSON válido e parseável.
```

---

### 1.8 `config/prompts/partials/_time_injection.yml`

```erb
content: |
  <current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>>
```

**Nota:** Este arquivo usa ERB literal. O `PromptLoader` executa `ERB.new(raw).result(binding)` no arquivo principal, então o ERB dentro deste YAML parcial será resolvido em cascata.

---

### 1.9 `config/prompts/system/discovery.yml`

```erb
name: discovery
system: |
  <%= Llm::PromptLoader.partial('rules') %>
  <%= Llm::PromptLoader.partial('time_injection') %>

  Você é um classificador de perfis sociais de influenciadores.
  Receberá handles mencionados ou comentários de posts e deve classificá-los.

  Categorias obrigatórias (enum fixo):
  - CONCORRENTE: outro influenciador do mesmo nicho
  - PATROCINADOR_PROSPECTO: marca ou empresa que poderia patrocinar
  - IGNORAR: bot, spam, amigo pessoal sem relevância comercial

  Retorne APENAS um JSON array válido, sem markdown:
  [{"handle": "@usuario", "platform": "instagram", "categoria": "CONCORRENTE", "razao": "..."}]

  Não adicione texto fora do JSON.

user_template: |
  Handles descobertos para classificação:
  <% handles.each do |h| %>
  - Platform: <%= h[:platform] %> | Handle: <%= h[:username] %> | Bio: <%= h[:bio] || "N/A" %>
  <% end %>

  Total: <%= handles.size %> handles. Classifique cada um.
```

---

### 1.10 `config/prompts/system/base.yml`

```erb
name: base
system: |
  <%= Llm::PromptLoader.partial('rules') %>
  <%= Llm::PromptLoader.partial('time_injection') %>

  Você é um assistente de análise de dados para influenciadores digitais.
  Responda de forma concisa e baseada apenas em dados fornecidos.

user_template: |
  <%= user_message %>
```

---

### 1.11 `config/prompts/system/analysis.yml`

```erb
name: analysis
system: |
  <%= Llm::PromptLoader.partial('rules') %>
  <%= Llm::PromptLoader.partial('time_injection') %>

  Você é um analista de métricas de redes sociais.
  Receberá dados agregados de posts e snapshots de perfil.
  Identifique tendências, picos de engajamento e oportunidades.

  Retorne análise em JSON estruturado:
  {
    "tendencia_followers": "crescimento|queda|estavel",
    "media_engajamento": <número ou null>,
    "post_maior_impacto": <post_id ou null>,
    "recomendacoes": ["..."]
  }

user_template: |
  Perfil: <%= profile.platform %> / @<%= profile.platform_username %>
  Seguidores atuais: <%= profile.followers_count || "N/A" %>
  Posts dos últimos 30 dias:
  <% posts.each do |p| %>
  - ID: <%= p.id %> | Likes: <%= p.likes_count || "N/A" %> | Comments: <%= p.comments_count || "N/A" %> | Views: <%= p.views_count || "N/A" %>
  <% end %>

  Analise os dados e retorne o JSON.
```

---

### 1.12 `config/initializers/ruby_llm.rb`

```ruby
# frozen_string_literal: true

# config/initializers/ruby_llm.rb
#
# Configuração global do RubyLLM. Suporta Gemini nativamente e OpenRouter
# via openrouter_api_key. O provider é escolhido automaticamente pelo
# prefixo do model_id (ex: 'google/gemini-*' → Gemini, 'anthropic/*' → OpenRouter).

RubyLLM.configure do |config|
  config.gemini_api_key = ENV.fetch('GOOGLE_AI_API_KEY', nil)
  config.openrouter_api_key = ENV.fetch('OPENROUTER_API_KEY', nil)
  config.logger = Rails.logger
  config.log_level = Rails.env.production? ? :info : :debug
  config.request_timeout = 120
end
```

---

### 1.13 `app/models/discovered_profile.rb`

```ruby
# frozen_string_literal: true

class DiscoveredProfile < ApplicationRecord
  CLASSIFICATIONS = %w[CONCORRENTE PATROCINADOR_PROSPECTO IGNORAR].freeze

  belongs_to :source_profile, class_name: 'SocialProfile', optional: true

  validates :platform, presence: true
  validates :username, presence: true
  validates :platform, uniqueness: { scope: :username }
  validates :classification, inclusion: { in: CLASSIFICATIONS }, allow_nil: true

  scope :unclassified, -> { where(classification: nil) }
  scope :stale_classification, -> { where('classified_at < ?', 7.days.ago).or(unclassified) }
  scope :prospects, -> { where(classification: 'PATROCINADOR_PROSPECTO') }
end
```

---

### 1.14 `db/migrate/20260320000001_create_discovered_profiles.rb`

```ruby
# frozen_string_literal: true

class CreateDiscoveredProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :discovered_profiles do |t|
      t.string :platform, null: false
      t.string :username, null: false
      t.text :bio
      t.string :profile_url
      t.string :classification          # CONCORRENTE | PATROCINADOR_PROSPECTO | IGNORAR | nil
      t.text :classification_reason
      t.references :source_profile, foreign_key: { to_table: :social_profiles }
      t.datetime :classified_at

      t.timestamps
    end

    add_index :discovered_profiles, [:platform, :username], unique: true
    add_index :discovered_profiles, :classification
  end
end
```

---

### 1.15 `app/services/discovery/social_graph_analyzer.rb`

Serviço puro. Extrai @handles dos posts de um perfil.

```ruby
# frozen_string_literal: true

module Discovery
  class SocialGraphAnalyzer
    HANDLE_REGEX = /@([a-zA-Z0-9._]{2,50})/

    class << self
      # Extrai handles únicos mencionados nos posts recentes de um perfil.
      #
      # @param profile [SocialProfile]
      # @param days [Integer] janela de tempo para buscar posts
      # @return [Array<Hash>] [{ platform:, username:, bio: }]
      def extract_handles(profile, days: 15)
        posts = profile.social_posts.recent(days)
        raw_handles = extract_raw_handles(posts)
        filter_known_handles(raw_handles, profile)
      end

      private

      def extract_raw_handles(posts)
        handles = Set.new

        posts.each do |post|
          next if post.content.blank?

          post.content.scan(HANDLE_REGEX) do |match|
            handles << match.first.downcase
          end
        end

        handles.map do |username|
          { platform: 'unknown', username: "@#{username}", bio: nil }
        end
      end

      def filter_known_handles(raw_handles, source_profile)
        known_usernames = SocialProfile.where(
          platform_username: raw_handles.map { |h| h[:username].delete_prefix('@') }
        ).pluck(:platform_username).to_set

        existing_discovered = DiscoveredProfile.where(
          username: raw_handles.map { |h| h[:username].delete_prefix('@') }
        ).where('classified_at > ?', 7.days.ago).pluck(:username).to_set

        raw_handles.reject do |h|
          clean = h[:username].delete_prefix('@')
          known_usernames.include?(clean) || existing_discovered.include?(clean)
        end
      end
    end
  end
end
```

---

### 1.16 `app/services/discovery/profile_classifier.rb`

Serviço que classifica handles via LLM.

```ruby
# frozen_string_literal: true

module Discovery
  class ProfileClassifier
    MAX_BATCH_SIZE = 30

    class << self
      # Classifica um array de handles usando o LLM via AiRouter.
      #
      # @param handles [Array<Hash>] [{ platform:, username:, bio: }]
      # @param source_profile [SocialProfile] perfil de origem
      # @return [Array<Hash>] [{ handle:, platform:, categoria:, razao: }]
      def classify(handles, source_profile:)
        return [] if handles.empty?

        batch = handles.first(MAX_BATCH_SIZE)
        prompt = Llm::PromptLoader.load('discovery', handles: batch)

        response = AiRouter.complete(prompt: prompt, context: :background)
        parse_classification(response.content, source_profile)
      rescue Llm::BaseClient::QuotaExceededError => e
        Rails.logger.warn "[ProfileClassifier] Quota esgotada, adiando classificação: #{e.message}"
        []
      end

      private

      def parse_classification(raw_response, source_profile)
        cleaned = raw_response.strip
                               .gsub(/\A```json\s*/, '')
                               .gsub(/\A```\s*/, '')
                               .gsub(/\s*```\z/, '')
                               .strip

        JSON.parse(cleaned).map(&:symbolize_keys)
      rescue JSON::ParserError => e
        Rails.logger.error "[ProfileClassifier] JSON inválido do LLM: #{e.message}"
        []
      end
    end
  end
end
```

**Lógica detalhada:**
- `MAX_BATCH_SIZE = 30` — clamp para não estourar limites de token do Gemma/Gemini
- Limpa markdown fences que LLMs frequentemente adicionam (` ```json ... ``` `)
- Se quota estourar, retorna array vazio silenciosamente (o DiscoveryJob reagenda)
- `symbolize_keys` para manter consistência com o restante do codebase (hash keys simbólicas)

---

### 1.17 `app/jobs/discovery_job.rb`

```ruby
# frozen_string_literal: true

class DiscoveryJob < ApplicationJob
  queue_as :default

  DAYS_WINDOW = 15

  def perform
    profiles = SocialProfile.where.not(last_collected_at: nil)
                            .where('last_collected_at > ?', 1.day.ago)

    Rails.logger.info "[DiscoveryJob] Analisando #{profiles.size} perfis para discovery"

    profiles.find_each do |profile|
      process_profile(profile)
    end
  end

  private

  def process_profile(profile)
    handles = Discovery::SocialGraphAnalyzer.extract_handles(profile, days: DAYS_WINDOW)
    return if handles.empty?

    Rails.logger.info "[DiscoveryJob] #{handles.size} handles novos encontrados em @#{profile.platform_username}"

    classifications = Discovery::ProfileClassifier.classify(handles, source_profile: profile)

    classifications.each do |result|
      save_discovered_profile(result, profile)
    end
  rescue Llm::BaseClient::QuotaExceededError => e
    Rails.logger.warn "[DiscoveryJob] Quota LLM esgotada ao processar #{profile.platform_username}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[DiscoveryJob] Erro ao processar perfil #{profile.id}: #{e.message}"
  end

  def save_discovered_profile(result, source_profile)
    handle = result[:handle].to_s.delete_prefix('@')
    return if handle.blank?

    dp = DiscoveredProfile.find_or_initialize_by(
      platform: result[:platform] || source_profile.platform,
      username: handle
    )

    dp.assign_attributes(
      classification: normalize_classification(result[:categoria]),
      classification_reason: result[:razao],
      source_profile: source_profile,
      classified_at: Time.current
    )

    dp.save! if dp.changed?

    if dp.classification == 'PATROCINADOR_PROSPECTO'
      Rails.logger.info "[DiscoveryJob] Prospecto detectado: @#{handle}"
    end
  end

  def normalize_classification(raw)
    return nil if raw.nil?

    value = raw.to_s.upcase.strip
    return value if DiscoveredProfile::CLASSIFICATIONS.include?(value)

    'IGNORAR'
  end
end
```

**Idempotência:**
- `find_or_initialize_by(platform:, username:)` — re-executar não duplica
- `classified_at` é atualizado a cada re-classificação
- Perfis já classificados nos últimos 7 dias são filtrados pelo `SocialGraphAnalyzer`

---

## 2. ARQUIVOS A MODIFICAR

---

### 2.1 `Gemfile` — Adicionar `ruby_llm`

**Linha de inserção:** Após linha 27 (`gem 'bootsnap'`), antes de `gem 'tzinfo-data'`.

```diff
 gem 'bootsnap', require: false
+gem 'ruby_llm', '~> 1.12'  # Unificada: Gemini + OpenRouter + Tool Calling
 gem 'tzinfo-data'
```

**Depois executar:** `bundle install` (ou `docker exec docker-app-1 bundle install`).

---

### 2.2 `.env` — Adicionar chaves de API

**Linha de inserção:** Após linha 5 (`SECRET_KEY_BASE=...`).

```diff
 SECRET_KEY_BASE=dev_secret_key_base_$(openssl rand -hex 32)
+GOOGLE_AI_API_KEY=your-google-ai-studio-key
+OPENROUTER_API_KEY=your-openrouter-key
```

**Importante:** `.env` está no `.gitignore` — nunca commitar.

---

### 2.3 `config/initializers/scraping_modules.rb` — Adicionar requires do LLM

**Linha de modificação:** Após linha 15 (último require de scraping), antes de `end`.

```diff
   require Rails.root.join('lib/scraping/scrapers/twitter_scraper')
+  # LLM Integration (lib/llm — excluído do autoload Zeitwerk)
+  require Rails.root.join('lib/llm/prompt_loader')
+  require Rails.root.join('lib/llm/base_client')
+  require Rails.root.join('lib/llm/gemini_client')
+  require Rails.root.join('lib/llm/gemma_client')
+  require Rails.root.join('lib/llm/openrouter_client')
 end
```

---

### 2.4 `config/application.rb` — Adicionar `llm` ao ignore list do autoload

**Linha de modificação:** Linha 18, expandir o array `ignore`.

```diff
-    config.autoload_lib(ignore: %w[assets tasks scraping])
+    config.autoload_lib(ignore: %w[assets tasks scraping llm])
```

**Motivo:** `lib/llm/` é carregado manualmente pelo initializer (mesmo padrão de `lib/scraping/`). Sem isso, Zeitwerk tentaria autoload e conflitaria com o `require` explícito.

---

### 2.5 `config/recurring.yml` — Adicionar cron do DiscoveryJob

**Linha de inserção:** Após linha 15 (último entry em `production:`).

```diff
 production:
   clear_solid_queue_finished_jobs:
     command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
     schedule: every hour at minute 12
+  discovery_job:
+    class: DiscoveryJob
+    queue: default
+    schedule: at 3am every tuesday and friday
```

**Rationale:** 2x/semana (terça e sexta, 3h da manhã) — suficiente para discovery sem queimar quota Gemini (500 RPD).

---

## 3. ARQUIVOS NÃO MODIFICADOS (Confirmados)

| Arquivo | Motivo |
|---------|--------|
| `app/jobs/application_job.rb` | Já tem `rescue_from ScrapingServices::RateLimitError`. O LLM não usa esse error type — quota é tratada internamente pelo `AiRouter` com `QuotaExceededError`. |
| `app/models/social_profile.rb` | Não precisa de alterações. `DiscoveryJob` usa `social_posts.recent(15)` já existente no `SocialPost` model. |
| `app/models/social_post.rb` | O scope `recent(days)` já existe (linha 10). |
| `lib/scraping/` | Nenhuma alteração. O LLM é uma camada independente. |
| `docker/` | Não precisa de alterações. RubyLLM usa Faraday HTTP (já incluído via Rails). |

---

## 4. ORDEM DE EXECUÇÃO

```
1.  Gemfile: adicionar ruby_llm → bundle install
2.  .env: adicionar GOOGLE_AI_API_KEY, OPENROUTER_API_KEY
3.  config/application.rb: adicionar 'llm' ao ignore list
4.  config/initializers/ruby_llm.rb: criar (configuração RubyLLM)
5.  config/initializers/scraping_modules.rb: adicionar requires LLM
6.  lib/llm/base_client.rb: criar
7.  lib/llm/gemini_client.rb: criar
8.  lib/llm/gemma_client.rb: criar
9.  lib/llm/openrouter_client.rb: criar
10. lib/llm/prompt_loader.rb: criar
11. config/prompts/partials/_rules.yml: criar
12. config/prompts/partials/_time_injection.yml: criar
13. config/prompts/system/base.yml: criar
14. config/prompts/system/discovery.yml: criar
15. config/prompts/system/analysis.yml: criar
16. app/services/ai_router.rb: criar
17. db/migrate/20260320000001_create_discovered_profiles.rb: criar
18. app/models/discovered_profile.rb: criar
19. app/services/discovery/social_graph_analyzer.rb: criar
20. app/services/discovery/profile_classifier.rb: criar
21. app/jobs/discovery_job.rb: criar
22. config/recurring.yml: adicionar cron do DiscoveryJob
23. bin/rails db:migrate
24. bin/rails test
```

---

## 5. DEPENDÊNCIAS ENTRE MÓDULOS

```
DiscoveryJob
  ├── SocialGraphAnalyzer (extrai @handles dos posts)
  ├── ProfileClassifier
  │     ├── PromptLoader.load('discovery', handles:)
  │     └── AiRouter.complete(prompt:, context: :background)
  │           ├── Llm::GeminiClient (background → Gemini 3.1 Flash Lite)
  │           ├── Llm::GemmaClient  (interactive → Gemma 3 27B)
  │           └── Llm::OpenrouterClient (fallback → Claude 3.5)
  └── DiscoveredProfile (persiste resultado)

Chatbot (Fase 5, futuro)
  └── AiRouter.complete(prompt:, context: :interactive)
        ├── Llm::GemmaClient (padrão)
        └── Llm::OpenrouterClient (se tokens > 8K)
```

---

## 6. VALIDAÇÃO DETALHADA

| # | Teste | Como verificar |
|---|-------|----------------|
| 1 | AiRouter roteia `:background` → Gemini | `AiRouter.complete(prompt: "test", context: :background)` — log mostra `[GeminiClient]` |
| 2 | AiRouter roteia `:interactive` curto → Gemma | `AiRouter.complete(prompt: "hi", context: :interactive)` — log mostra `[GemmaClient]` |
| 3 | AiRouter roteia `:interactive` longo → OpenRouter | Prompt > 8K chars — log mostra `[OpenrouterClient]` |
| 4 | Contador SolidCache incrementa | Após chamada, `SolidCache.read("gemini_daily:2026-03-20")` retorna 1 |
| 5 | PromptLoader carrega discovery.yml | `Llm::PromptLoader.load('discovery', handles: [{platform: 'ig', username: '@x', bio: nil}])` — retorna Hash com :system e :user |
| 6 | Time injection no prompt | System contém `<current_datetime: 2026-03-20 ...>` |
| 7 | DiscoveryJob é idempotente | Rodar 2x → `DiscoveredProfile.count` igual |
| 8 | Null vs Zero | Nenhum `default: 0` em migration; `DiscoveredProfile` não tem colunas numéricas |
| 9 | Migration roda | `bin/rails db:migrate` sem erros |
| 10 | QuotaExceededError é resgatada | Simular quota esgotada — AiRouter loga warning, não quebra o job |
