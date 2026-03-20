# PRD - Fase 3: O Cérebro Inteligente - Multi LLM

## Objetivos

Implementar a capacidade de avaliação orgânica do sistema BotDiscord com:
1. **Orquestrador de IA (AiRouter)** — roteia requests entre modelos LLM baseado em quotas e contexto
2. **Repositório YAML de Prompts** — centraliza e versiona prompts com injeção de timestamp e macros ERB
3. **Pipeline de Discovery Autônomo** — jobs que exploram o grau social dos influenciadores e descobrem handles relacionados

---

## Arquivos Afetados

### Criação (Novos)

| Caminho | Descrição |
|---------|-----------|
| `app/services/ai_router.rb` | Serviço orquestrador de LLM com roteamento por modelo |
| `app/services/llm/base_client.rb` | Classe abstrata de cliente LLM (RubyLLM wrapper) |
| `app/services/llm/gemini_client.rb` | Cliente Gemini 3.1 Flash Lite (via Google AI API) |
| `app/services/llm/gemma_client.rb` | Cliente Gemma 3 27B (via Google AI API) |
| `app/services/llm/openrouter_client.rb` | Cliente OpenRouter (Claude 3.5, etc.) |
| `config/initializers/ruby_llm.rb` | Configuração inicial do RubyLLM |
| `config/prompts/system/base.yml` | Prompt base do sistema (injeção de tempo, null vs zero) |
| `config/prompts/system/discovery.yml` | Prompt de classificação de perfis descobertos |
| `config/prompts/system/analysis.yml` | Prompt de análise batch de métricas |
| `config/prompts/partials/_rules.yml` | Parcial compartilhado: regras Null vs Zero |
| `config/prompts/partials/_time_injection.yml` | Parcial: injeção de timestamp |
| `lib/llm/prompt_loader.rb` | Loader YAML + ERB com injeção de contexto |
| `app/jobs/discovery_job.rb` | Job de pipeline autônomo de tracking |
| `app/services/discovery/social_graph_analyzer.rb` | Analisa menções, comentários e perfis relacionados |
| `app/services/discovery/profile_classifier.rb` | Classifica handles em CONCORRENTE/PATROCINADOR_PROSPECTO/IGNORAR |
| `db/migrate/XXXXXXX_create_discovered_profiles.rb` | Migration: tabela de handles descobertos |

### Modificação (Existentes)

| Caminho | Mudança |
|---------|---------|
| `Gemfile` | Adicionar `gem 'ruby_llm', '~> 1.12'` |
| `.env` | Adicionar `GOOGLE_AI_API_KEY`, `OPENROUTER_API_KEY` |
| `config/initializers/scraping_modules.rb` | Require do LLM e Prompt modules |
| `config/application.rb` | Autoload `lib/llm` (se necessário) |
| `config/recurring.yml` | Cron para `DiscoveryJob` |
| `app/jobs/application_job.rb` | Sem alteração (já tem rescue de rate limit) |

---

## Referências Técnicas

### Gemas

- **ruby_llm v1.12+** — Gem unificada que suporta Gemini, OpenAI, Anthropic, OpenRouter via interface única
  - Docs: https://rubyllm.com/tools
  - Config: https://rubyllm.com/configuration
  - Suporte nativo a `config.gemini_api_key` e `config.openrouter_api_key`
  - Tool calling: `class MyTool < RubyLLM::Tool` com `param`/`params DSL`
  - Chat: `RubyLLM.chat(model: 'google/gemini-3.1-flash-lite')`

### Limites de API (Google AI Studio - 2026)

| Modelo | RPM | TPM | RPD |
|--------|-----|-----|-----|
| Gemini 3.1 Flash Lite | 15 | 250K | 500 |
| Gemma 3 27B | 30 | 15K | 14.400 |

### Padrões do Codebase

- **Serviços**: `app/services/`, sufixo `Service`, lógica de negócios nunca em models/controllers
- **Jobs**: `app/jobs/`, sufixo `Job`, idempotent via `find_or_initialize_by`, rate limit → retry em 6h
- **Null vs Zero**: métricas como `nil` quando indisponível, `default: 0` NUNCA
- **Logging**: `[ClassName]` prefixo nos logs
- **ERB/Time Injection**: `<current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>>`

---

## Requisitos Técnicos

### 1. AiRouter (`app/services/ai_router.rb`)

**Responsabilidade**: Roteia chamadas LLM baseado no tipo de tarefa e orçamento de tokens.

**Lógica de Roteamento**:

```
SE contexto é background job (batch/descoberta):
  → Gemini 3.1 Flash Lite (250K TPM, 500 RPD — batching obrigatório)

SE contexto é chat/interativo:
  SE prompt > 8K tokens estimados:
    → OpenRouter (Claude 3.5 via Google) — fallback pesado
  SENÃO:
    → Gemma 3 27B (15K TPM, 14.4K RPD — operação padrão)
```

**Interface esperada**:

```ruby
# Uso simples
response = AiRouter.complete(
  prompt: "Analise este perfil...",
  context: :background  # ou :interactive
)

# Com tool calling
response = AiRouter.complete(
  prompt: "Classifique estes handles",
  context: :background,
  tools: [ProfileClassifierTool]
)

# Com system prompt via prompt loader
prompt = Llm::PromptLoader.load('discovery', handles: found_handles)
response = AiRouter.complete(prompt: prompt, context: :background)
```

**Rate Limit Guardian** (baseado em docs/estrategia_multi_model_ai.md):
- Se `expected_tokens > GEMMA_TPM_SAFE_THRESHOLD (8_000)` → escalar para Gemini/OpenRouter
- Logar cada decisão de roteamento
- Contar requests diários por modelo via Solid Cache

### 2. LLM Clients (`app/services/llm/`)

**Arquitetura**: Wrapper em torno do RubyLLM, mantendo a API consistente mas adicionando:
- Controle de quota diária (counters em Solid Cache)
- Logging padronizado `[GeminiClient]`, `[GemmaClient]`
- Tratamento de erros específico por provider

```ruby
module Llm
  class GeminiClient < BaseClient
    MODEL_ID = 'google/gemini-3.1-flash-lite'

    def complete(prompt, tools: [], system: nil)
      track_request!
      check_quota!
      chat = RubyLLM.chat(model: MODEL_ID)
      chat.with_instructions(system) if system
      tools.each { |t| chat.with_tool(t) }
      chat.ask(prompt)
    end

    private

    def check_quota!
      daily_count = cache_read("gemini_daily_#{Date.current.iso8601}", default: 0)
      raise QuotaExceededError if daily_count >= 480 # margem de segurança dos 500 RPD
    end
  end
end
```

### 3. Prompt Loader (`lib/llm/prompt_loader.rb`)

**Estrutura de diretórios**:

```
config/prompts/
├── system/
│   ├── base.yml          # prompt base do sistema
│   ├── discovery.yml     # classificação de perfis
│   └── analysis.yml      # análise batch
└── partials/
    ├── _rules.yml         # regras Null vs Zero
    └── _time_injection.yml # timestamp
```

**Formato YAML**:

```yaml
# config/prompts/system/discovery.yml
name: discovery
system: |
  <%= partial 'rules' %>
  <%= partial 'time_injection' %>

  Você é um classificador de perfis sociais. Receberá handles mencionados
  ou comentários de um influenciador e deve classificá-los em categorias.

  Categorias válidas: CONCORRENTE, PATROCINADOR_PROSPECTO, IGNORAR

  Retorne APENAS um JSON array com objetos:
  [{ "handle": "@usuario", "categoria": "CONCORRENTE", "razao": "..." }]

user_template: |
  Handles encontrados:
  <% handles.each do |h| %>
  - <%= h[:platform] %>: <%= h[:username] %> | Bio: <%= h[:bio] %>
  <% end %>

  Classifique cada handle.
```

**Interface**:

```ruby
# Carrega e renderiza
prompt = Llm::PromptLoader.load('discovery', handles: found_handles)
# => { system: "...", user: "..." }

# Usa com AiRouter
AiRouter.complete(prompt: prompt, context: :background)
```

**Macros ERB obrigatórios**:
- `partial 'rules'` → injeta regras Null vs Zero
- `partial 'time_injection'` → injeta `<current_datetime: 2026-03-20 15:30:00 -0300>`

### 4. Discovery Job (`app/jobs/discovery_job.rb`)

**Trigger**: Recurring via `config/recurring.yml` (2x por semana)

**Fluxo**:

1. Buscar `SocialProfile` com posts recentes (últimos 15 dias)
2. Extrair `@mentions` dos `content` dos `SocialPost`
3. Extrair comentários com mais engajamento (se disponível via scraper)
4. Para cada handle descoberto:
   a. Se não existe em `SocialProfile` → salvar em `DiscoveredProfile`
   b. Chamar `ProfileClassifier` via AiRouter (batch, context: :background)
   c. Atualizar `classification` no `DiscoveredProfile`
5. Se classificação = `PATROCINADOR_PROSPECTO` → criar notificação/fila para análise manual

**Idempotência**:
- `find_or_initialize_by(username:, platform:)` no `DiscoveredProfile`
- Ignorar handles já classificados (updated_at < 7 dias)

### 5. Migration: `discovered_profiles`

```ruby
create_table :discovered_profiles do |t|
  t.string :platform, null: false
  t.string :username, null: false
  t.text :bio
  t.string :profile_url
  t.string :classification  # CONCORRENTE, PATROCINADOR_PROSPECTO, IGNORAR
  t.text :classification_reason
  t.references :source_profile, foreign_key: { to_table: :social_profiles }
  t.datetime :classified_at
  t.timestamps
end
add_index :discovered_profiles, [:platform, :username], unique: true
```

### 6. Variáveis de Ambiente (`.env`)

```bash
GOOGLE_AI_API_KEY=your-google-ai-studio-key
OPENROUTER_API_KEY=your-openrouter-key
```

---

## Snippets de Código de Referência

### RubyLLM Tool Calling (padrão existente no gem)

```ruby
class ProfileClassifierTool < RubyLLM::Tool
  description "Classifica um perfil social em categoria"
  param :platform, desc: "Plataforma (twitter, instagram, youtube)"
  param :username, desc: "Username do perfil"
  param :bio, desc: "Biografia do perfil", required: false

  def execute(platform:, username:, bio: nil)
    # Clamp se necessário
    # Retorna HASH/ARRAY puro, nunca string formatada
    {
      platform: platform,
      username: username,
      has_sufficient_data: bio.present?,
      suggestion: classify_by_bio(bio)
    }
  end
end
```

### Prompt Loader com ERB (referência do contexto do projeto)

```ruby
# lib/llm/prompt_loader.rb
module Llm
  class PromptLoader
    PROMPTS_DIR = Rails.root.join('config/prompts')

    def self.load(name, **locals)
      file = PROMPTS_DIR.join("system/#{name}.yml")
      raise ArgumentError, "Prompt '#{name}' não encontrado" unless file.exist?

      yaml = YAML.safe_load(ERB.new(file.read).result(binding), permitted_classes: [Symbol])
      {
        system: render_erb(yaml['system'], **locals),
        user: render_erb(yaml['user_template'], **locals)
      }
    end

    def self.partial(name)
      file = PROMPTS_DIR.join("partials/_#{name}.yml")
      return "" unless file.exist?

      yaml = YAML.safe_load(file.read, permitted_classes: [Symbol])
      yaml['content'] || ""
    end

    private

    def self.render_erb(template, **locals)
      ERB.new(template).result_with_hash(locals)
    end
  end
end
```

### Gemfile Addition

```ruby
gem 'ruby_llm', '~> 1.12'  # Unificada: Gemini + OpenRouter + Tool Calling
```

---

## Validação

- [ ] `AiRouter` roteia corretamente por contexto (:background → Gemini, :interactive → Gemma)
- [ ] Contador diário de requests funciona (Solid Cache)
- [ ] Prompt Loader carrega YAML e renderiza ERB com timestamp
- [ ] DiscoveryJob é idempotente (re-run não duplica)
- [ ] Null vs Zero preservado em todas as queries de métricas
- [ ] Rate limits do Google AI respeitados (logging verificável)
- [ ] `bin/rails test` passa
- [ ] `bundle exec rubocop` sem ofensas (se configurado)
