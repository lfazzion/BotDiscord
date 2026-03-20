# SPEC.md - Fase 2: Motor de Coleta Híbrida Militar

## 1. Resumo

Implementação de sistema de coleta de dados resiliente contra bloqueios modernos (TLS Fingerprint, Cloudflare, DataDome) combinando múltiplas estratégias: RSS via REXML, yt-dlp para YouTube, Ferrum stealth para SPAs, e Python Nodriver/Camoufox como fallback.

---

## 2. ARQUIVOS A CRIAR

### 2.1 Core Services (Scraping)

#### `/home/igorvilela/BotDiscord/lib/scraping/services/rss_parser_service.rb`
**Objetivo**: Parser RSS nativo via REXML para Google News
**Criação**: Arquivo NOVO

```ruby
# Lógica: parse_google_news(query, days) -> GET RSS -> REXML.parse -> []
#         parse_feed(xml_content) -> REXML::Document -> items[]
# Dependências: rexml (stdlib), net/http (stdlib)
```

---

#### `/home/igorvilela/BotDiscord/lib/scraping/services/youtube_scraper_service.rb`
**Objetivo**: Wrapper yt-dlp subprocess para extração de metadados YouTube
**Criação**: Arquivo NOVO

```ruby
# Lógica: extract_channel_metadata(channel_url, proxy) -> Open3.capture3 yt-dlp --dump-json
#         extract_videos_batch(channel_url, limit, proxy) -> Open3.capture3 yt-dlp --flat-playlist
#         parse_metadata(json) -> extrai channel_id, title, subscriber_count, etc.
#         parse_video_list(output) -> split '|' -> videos[]
# Dependências: open3 (stdlib), json (stdlib)
```

---

#### `/home/igorvilela/BotDiscord/lib/scraping/services/http_stealth_client.rb`
**Objetivo**: Typhoeus HTTP client com TLS fingerprint spoofing
**Criação**: Arquivo NOVO

```ruby
# Lógica: initialize(fingerprint, proxy) -> configura Typhoeus headers
#         get(url, options) -> request(:get, url, options)
#         post(url, options) -> request(:post, url, options)
#         request_options(url, options) -> headers fingerprint + proxy
#         handle_response(response) -> valida 403/429/503 -> raise RateLimitError
# Dependências: typhoeus
# Browser fingerprints: :chrome_latest, :safari_latest
```

---

### 2.2 Ferrum Stealth Scrapers

#### `/home/igorvilela/BotDiscord/lib/scraping/scrapers/ferrum_scraper_base.rb`
**Objetivo**: Classe base para scrapers Ferrum com stealth headers
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - USER_AGENTS = [] (4 UAs para rotation)
#   - BLOCKED_RESOURCES = %w[image font stylesheet media]
#   - initialize(proxy, user_agent) -> build_browser -> Ferrum::Browser.new
#   - visit(url, wait_for) -> browser.goto + wait_for_selector
#   - execute_script(script) -> browser.evaluate
#   - find_element/find_elements(selector) -> browser.at_css/css
#   - random_delay -> sleep(rand(1.5..4.5))
#   - wait_for_selector(selector, timeout) -> polling loop
#   - build_browser -> options: headless, window_size, browser_options (disable-blink-features, no-sandbox, etc.)
# Dependências: ferrum (já instalado)
```

---

#### `/home/igorvilela/BotDiscord/lib/scraping/scrapers/instagram_scraper.rb`
**Objetivo**: Scraper Instagram via Ferrum (profile + posts)
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - scrape_profile(username) -> visit("/#{username}/") -> execute_script(PROFILE_SCRIPT) -> parse
#   - scrape_posts(username, limit) -> scroll loop -> execute_script(POSTS_SCRIPT) -> parse
#   - PROFILE_SCRIPT: window._sharedData.entry_data.ProfilePage[0].graphql.user
#   - POSTS_SCRIPT: edge_owner_to_timeline_media.edges
#   - parse_post(post) -> mapeia GraphImage/GraphVideo/GraphSidecar -> tipo
#   - handle_http_error -> raise RateLimitError se 403/429
# Herda de: FerrumScraperBase
```

---

#### `/home/igorvilela/BotDiscord/lib/scraping/scrapers/twitter_scraper.rb`
**Objetivo**: Scraper Twitter/X via Ferrum
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - scrape_profile(username) -> visit twitter.com/username -> extract_user_data()
#   - scrape_tweets(username, limit) -> scroll -> extract_tweets()
#   - USER_SCRIPT: window.__INITIAL_STATE__.users[username]
#   - TWEETS_SCRIPT: extract list_items_stream-items
#   - parse_tweet(tweet) -> mapeia para SocialPost
#   - handle_http_error -> RateLimitError se 403/429
# Herda de: FerrumScraperBase
```

---

### 2.3 Python Bridge

#### `/home/igorvilela/BotDiscord/lib/scraping/python_bridge/nodriver_runner.rb`
**Objetivo**: Executor Ruby subprocess para scripts Python Nodriver
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - PYTHON_SCRIPT_PATH = Rails.root.join('scripts/python')
#   - NODRIVER_SCRIPT = nodriver_instagram.py
#   - scrape_instagram_profile(username, proxy) -> build_command('profile', ...) -> execute
#   - scrape_instagram_posts(username, limit, proxy) -> build_command('posts', ...) -> execute
#   - build_command(mode, username, limit, proxy) -> ['python3', script, args]
#   - execute(command) -> Open3.capture3(timeout: 180s) -> JSON.parse
#   - rate_limit?(stderr) -> checa '429', 'Blocked', 'Captcha', 'rate limit'
# Dependências: open3 (stdlib)
```

---

#### `/home/igorvilela/BotDiscord/lib/scraping/python_bridge/camoufox_service.rb`
**Objetivo**: Wrapper Camoufox CLI via subprocess
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - CAMOUFOX_SCRIPT = camoufox_scrape.py
#   - scrape_url(url, proxy) -> execute(['python3', script, url, --proxy proxy])
#   - scrape_batch(urls, proxy) -> loop scrape_url
#   - Similar pattern a nodriver_runner.rb
# Dependências: open3 (stdlib)
```

---

### 2.4 Rate Limit Handler

#### `/home/igorvilela/BotDiscord/lib/scraping/rate_limit_handler.rb`
**Objetivo**: Handler centralizado de erros de rate limit
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - RateLimitError < StandardError (attr_reader: retry_after, original_error)
#   - RateLimitHandler class:
#     - RATE_LIMIT_PATTERNS = [/429/i, /403/i, /rate.?limit/i, /blocked/i, /captcha/i, /cloudflare/i, /datadome/i]
#     - DEFAULT_BACKOFF = 6.hours, HEAVY_BACKOFF = 12.hours
#     - handle_error(error, context) -> rate_limited? -> determine_backoff -> raise RateLimitError
#     - rate_limited?(error) -> match patterns
#     - determine_backoff(error, context) -> cloudflare/datadome -> 12h; retry_count > 2 -> 12h; 429 -> 2h; default -> 6h
#     - suspicious_block?(error) -> 'connection reset', 'timeout', 'empty response' -> 12h
```

---

### 2.5 Python Scripts

#### `/home/igorvilela/BotDiscord/scripts/python/nodriver_instagram.py`
**Objetivo**: Scraper Instagram via Nodriver (anti-detect browser)
**Criação**: Arquivo NOVO (dentro de scripts/python/)

```python
# Lógica:
#   - scrape_profile(username, proxy) -> uc.start -> page.get(instagram.com/{username}) -> await asyncio.sleep(3) -> evaluate JS
#   - scrape_posts(username, limit) -> scroll loop -> evaluate JS
#   - JS extraction: window._sharedData.entry_data.ProfilePage[0].graphql.user
#   - CLI args: parser.add_argument('username'), --mode (profile/posts), --limit, --proxy
#   - main(): asyncio.run() -> print(json.dumps(result))
# Dependências: nodriver>=0.0.35
```

---

#### `/home/igorvilela/BotDiscord/scripts/python/camoufox_scrape.py`
**Objetivo**: Scraper via Camoufox CLI
**Criação**: Arquivo NOVO (dentro de scripts/python/)

```python
# Lógica:
#   - scrape_page(url, proxy) -> camoufox.launch -> page.goto -> page.content()
#   - CLI args: --url, --proxy, --output (json file)
#   - main(): parse_args -> scrape_page -> save json
# Dependências: camoufox>=2.0.0
```

---

### 2.6 Scraping Jobs

#### `/home/igorvilela/BotDiscord/app/jobs/scrape_instagram_job.rb`
**Objetivo**: Job para coleta Instagram com rate limit handling
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - SNAPSHOT_DEDUP_WINDOW = 2.hours
#   - perform(profile_id, options) ->
#       1. find SocialProfile
#       2. should_collect? -> check last snapshot
#       3. scrape_profile -> use_python_scraper? -> NodriverRunner OR InstagramScraper
#       4. update_profile -> SocialProfile.update!
#       5. create_snapshot -> ProfileSnapshot.find_or_create_idempotent
#   - should_collect? -> last_snapshot.nil? || Time.current - last_snapshot > 2.hours
#   - use_python_scraper? -> options[:use_python] || ENV['USE_NODRIVER']
#   - current_proxy -> ProxyPool.next if ENV['USE_PROXY']
#   - scrape_profile -> try NodriverRunner OR InstagramScraper.new
#   - retry_count -> executions.count (last hour)
# Rescue: ScrapingServices::RateLimitError -> retry_job(wait: e.retry_after)
# Herda de: ApplicationJob
```

---

#### `/home/igorvilela/BotDiscord/app/jobs/scrape_twitter_job.rb`
**Objetivo**: Job para coleta Twitter/X
**Criação**: Arquivo NOVO

```ruby
# Lógica: Similar a ScrapeInstagramJob
#   - scrape_profile -> TwitterScraper OR Nodriver
#   - update_profile -> SocialProfile.update!
#   - create_snapshot -> ProfileSnapshot
#   - use_python_scraper? fallback
```

---

#### `/home/igorvilela/BotDiscord/app/jobs/scrape_youtube_job.rb`
**Objetivo**: Job para coleta YouTube via yt-dlp
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - perform(profile_id, options) ->
#       1. find SocialProfile (platform: youtube)
#       2. channel_url = "https://www.youtube.com/#{platform_username}"
#       3. metadata = YoutubeScraperService.extract_channel_metadata(channel_url, proxy)
#       4. videos = YoutubeScraperService.extract_videos_batch(channel_url, limit: 50, proxy)
#       5. update_profile -> SocialProfile.update!
#       6. create_posts -> SocialPost.find_or_initialize_by(platform_post_id)
#       7. create_snapshot -> ProfileSnapshot
```

---

#### `/home/igorvilela/BotDiscord/app/jobs/rss_collect_job.rb`
**Objetivo**: Job para coleta RSS (Google News)
**Criação**: Arquivo NOVO

```ruby
# Lógica:
#   - perform(query, days: 1) ->
#       1. articles = RssParserService.parse_google_news(query: query, days: days)
#       2. articles.each -> NewsArticle.find_or_create_by(link: article[:link])
#       3. update article -> title, description, pub_date, source
#       4. schedule next run
```

---

### 2.7 Configuration Files

#### `/home/igorvilela/BotDiscord/config/initializers/scraping_limits.rb`
**Objetivo**: Configuração centralizada de rate limits
**Criação**: Arquivo NOVO

```ruby
# Lógica: ScrapingLimits module com:
#   - RATE_LIMITS = { instagram: { requests_per_hour: 60, backoff: 6.hours, use_python_scraper: true }, ... }
#   - PROXY_CONFIG = { enabled: ENV['USE_PROXY'], pool_rotation: true, sticky_session: true, min_success_rate: 0.8 }
```

---

#### `/home/igorvilela/BotDiscord/requirements.txt`
**Objetivo**: Dependências Python
**Criação**: Arquivo NOVO

```
nodriver>=0.0.35
camoufox>=2.0.0
httpx>=0.27.0
aiohttp>=3.10.0
```

---

### 2.8 Docker Files

#### `/home/igorvilela/BotDiscord/docker/Dockerfile.python`
**Objetivo**: Docker image para scraper Python sidecar
**Criação**: Arquivo NOVO

```dockerfile
# Base: python:3.12-slim
# Install: wget, gnupg, ca-certificates, lsb-release, ffmpeg
# pip install: nodriver, camoufox, httpx, aiohttp, playwright
# playwright install chromium --with-deps
# COPY scripts/python /app/scripts
# CMD ["python3", "-u", "-m", "http.server", "8080"]
```

---

#### `/home/igorvilela/BotDiscord/docker/docker-compose.yml` (ATUALIZAÇÃO)
**Modificação**: Adicionar serviço python-scraper e network scraping-data

```yaml
# Adicionar em services:
python-scraper:
  build:
    context: ..
    dockerfile: Dockerfile.python
  volumes:
    - ./scripts/python:/app/scripts
    - scraping-data:/data
  environment:
    - PYTHONUNBUFFERED=1
  networks:
    - internal
  restart: unless-stopped

# Adicionar em networks: (já existe internal)

# Adicionar em volumes:
scraping-data:
```

---

### 2.9 Test Files

#### `/home/igorvilela/BotDiscord/test/scraping/rss_parser_service_test.rb`
**Objetivo**: Testes RssParserService
**Criação**: Arquivo NOVO

```ruby
# Testes:
#   - parse_google_news returns articles
#   - parse_feed handles malformed HTML
#   - parse_feed handles nil values
```

---

#### `/home/igorvilela/BotDiscord/test/scraping/youtube_scraper_service_test.rb`
**Objetivo**: Testes YoutubeScraperService
**Criação**: Arquivo NOVO

```ruby
# Testes:
#   - extract_channel_metadata returns valid data (skip unless yt-dlp available)
#   - extract_videos_batch parses output
#   - handles invalid json
```

---

#### `/home/igorvilela/BotDiscord/test/scraping/http_stealth_client_test.rb`
**Objetivo**: Testes HttpStealthClient
**Criação**: Arquivo NOVO

```ruby
# Testes:
#   - chrome fingerprint sends correct headers
#   - raises RateLimitError on 429
#   - raises RateLimitError on 503
#   - proxy is used when configured
```

---

#### `/home/igorvilela/BotDiscord/test/scraping/rate_limit_handler_test.rb`
**Objetivo**: Testes RateLimitHandler
**Criação**: Arquivo NOVO

```ruby
# Testes:
#   - rate_limited? matches 429 pattern
#   - rate_limited? matches cloudflare pattern
#   - determine_backoff returns 12h for cloudflare
#   - determine_backoff returns 2h for 429
#   - suspicious_block? detects connection reset
```

---

## 3. ARQUIVOS A MODIFICAR

### 3.1 `/home/igorvilela/BotDiscord/config/initializers/ferrum.rb`
**Modificação**: Adicionar stealth options, user-agent rotation, proxy support

**Linhas 54-69** - Modificar `self.browser_options`:

```ruby
# ANTES (linhas 54-69):
def self.browser_options
  {
    ws_url:  discover_stealth_ws_url,
    timeout: 30,
    process_timeout: 30,
    headless: true
  }
end

# DEPOIS:
def self.browser_options
  stealth_opts = {
    ws_url:  discover_stealth_ws_url,
    timeout: 30,
    process_timeout: 30,
    headless: true,
    window_size: [1366, 768]
  }

  stealth_opts[:browser_options] = {
    'disable-blink-features' => 'AutomationControlled',
    'no-sandbox' => nil,
    'disable-dev-shm-usage' => nil,
    'disable-gpu' => nil,
    'disable-web-security' => nil
  }.compact

  if ENV['SCRAPING_PROXY'].present?
    stealth_opts[:browser_options]['--proxy-server'] = ENV['SCRAPING_PROXY']
  end

  stealth_opts
end

STEALTH_USER_AGENTS = [
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
].freeze

def self.random_user_agent
  STEALTH_USER_AGENTS.sample
end

def self.stealth_browser_options
  opts = browser_options
  opts[:browser_options]['--user-agent'] = random_user_agent
  opts
end
```

---

### 3.2 `/home/igorvilela/BotDiscord/app/jobs/application_job.rb`
**Modificação**: Reforçar rescue_from RateLimitError

```ruby
# ANTES:
rescue_from "ScrapingServices::RateLimitError" do |exception|
  Rails.logger.warn "[ApplicationJob] Rate-limit detectado..."
  retry_job wait: 6.hours
end

# DEPOIS:
rescue_from ScrapingServices::RateLimitError, NameError do |exception|
  error_class = exception.is_a?(NameError) ? StandardError : ScrapingServices::RateLimitError
  retry_after = if exception.respond_to?(:retry_after)
                  exception.retry_after
                else
                  6.hours
                end

  Rails.logger.warn "[#{self.class.name}] Rate-limit detectado: #{exception.message}. " \
                    "Reagendando para +#{(retry_after / 3600).round}h."
  retry_job wait: retry_after
end
```

---

### 3.3 `/home/igorvilela/BotDiscord/app/models/social_profile.rb`
**Modificação**: Adicionar scopes para coleta

```ruby
# NOVO SCOPE após by_platform:
scope :needs_collection, -> {
  where.not(last_collected_at: nil)
    .where('last_collected_at < ?', 2.hours.ago)
}

scope :pending_first_collection, -> {
  where(last_collected_at: nil)
}

scope :by_platform_and_needs_collection, ->(platform) {
  by_platform(platform).where('last_collected_at IS NULL OR last_collected_at < ?', 2.hours.ago)
}

# NOVO MÉTODO após engagement_rate:
def should_collect?(window = 2.hours)
  return true if last_collected_at.nil?
  Time.current - last_collected_at > window
end

def platform_url
  case platform
  when 'instagram' then "https://www.instagram.com/#{platform_username}/"
  when 'twitter' then "https://twitter.com/#{platform_username}/"
  when 'youtube' then "https://www.youtube.com/@#{platform_username}" rescue "https://www.youtube.com/channel/#{platform_user_id}"
  when 'tiktok' then "https://www.tiktok.com/@#{platform_username}/"
  end
end

# NOVO CALLBACK:
before_save :set_platform_url

private

def set_platform_url
  self.platform_url ||= case platform
    when 'instagram' then "https://www.instagram.com/#{platform_username}/"
    when 'twitter' then "https://twitter.com/#{platform_username}/"
    when 'youtube' then "https://www.youtube.com/@#{platform_username}" rescue "https://www.youtube.com/channel/#{platform_user_id}"
    when 'tiktok' then "https://www.tiktok.com/@#{platform_username}/"
  end
end
```

---

### 3.4 `/home/igorvilela/BotDiscord/app/models/social_post.rb`
**Modificação**: Adicionar campos para metadados e métodos

```ruby
# NOVO SCOPE após by_type:
scope :by_profile_and_recent, ->(profile_id, days = 30) {
  where(social_profile_id: profile_id).where("posted_at >= ?", days.days.ago)
}

# NOVO MÉTODO após engagement_count:
def engagement_rate(profile_followers)
  return nil if profile_followers.nil? || profile_followers.zero?
  ((likes_count.to_i + comments_count.to_i + shares_count.to_i) / profile_followers.to_f * 100).round(2)
end

def media_url
  return nil unless media_urls.present?
  media_urls.first
end
```

---

### 3.5 `/home/igorvilela/BotDiscord/Gemfile`
**Modificação**: Adicionar gems para scraping

```ruby
# ANTES (linha 24-25):
gem 'ferrum'             # Headless Chrome via WebSocket (chromedp/headless-shell)
gem 'bootsnap', require: false

# DEPOIS:
gem 'ferrum'             # Headless Chrome via WebSocket (chromedp/headless-shell)
gem 'typhoeus', '~> 1.4' # HTTP client com proxy e SSL support
gem 'bootsnap', require: false
```

---

## 4. DIRETÓRIOS A CRIAR

```
lib/scraping/
├── services/           # NOVO
├── scrapers/           # NOVO
└── python_bridge/      # NOVO

scripts/
└── python/             # NOVO

test/
└── scraping/           # NOVO
```

---

## 5. MIGRATIONS NECESSÁRIAS

### `/home/igorvilela/BotDiscord/db/migrate/xxxx_add_scraping_fields_to_social_profile.rb`
```ruby
class AddScrapingFieldsToSocialProfile < ActiveRecord::Migration[8.0]
  def change
    add_column :social_profiles, :last_collected_at, :datetime
    add_column :social_profiles, :collection_status, :string, default: 'pending'
    add_column :social_profiles, :platform_url, :string
    add_column :social_profiles, :bio, :text
    add_column :social_profiles, :verified, :boolean, default: false
  end
end
```

### `/home/igorvilela/BotDiscord/db/migrate/xxxx_add_media_fields_to_social_post.rb`
```ruby
class AddMediaFieldsToSocialPost < ActiveRecord::Migration[8.0]
  def change
    add_column :social_posts, :media_urls, :json, default: []
    add_column :social_posts, :video_url, :string
    add_column :social_posts, :thumbnail_url, :string
    add_column :social_posts, :shares_count, :integer
    add_column :social_posts, :views_count, :integer
  end
end
```

### `/home/igorvilela/BotDiscord/db/migrate/xxxx_create_news_articles.rb`
```ruby
class CreateNewsArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :news_articles do |t|
      t.string :title
      t.text :description
      t.string :link, null: false
      t.string :source
      t.datetime :pub_date
      t.string :query_used
      t.timestamps
    end
    add_index :news_articles, :link, unique: true
    add_index :news_articles, :pub_date
  end
end
```

---

## 6. FLUXO DE DECISÃO IMPLEMENTADO

```
ScrapeInstagramJob.perform(profile_id)
    │
    ├─► should_collect? ──NO──► return (skip)
    │                          (last snapshot < 2h)
    │
    └─► YES
        │
        ├─► use_python_scraper? ──YES──► NodriverRunner
        │                                    │
        │◄────────────────────────────────────┘
        │ (JSON result)
        │
        ├─► NO ──► InstagramScraper (Ferrum)
        │              │
        │◄─────────────┘
        │ (Hash result)
        │
        ├─► update_profile(SocialProfile)
        │
        ├─► create_snapshot(ProfileSnapshot)
        │
        └─► Rescue RateLimitError ──► retry_job(wait: 6.hours)
```

---

## 7. ORDEM DE IMPLEMENTAÇÃO

### Fase 2.1: Core Infrastructure (1 dia)
1. Criar diretórios: `lib/scraping/{services,scrapers,python_bridge}`
2. Criar `lib/scraping/rate_limit_handler.rb`
3. Criar `lib/scraping/services/rss_parser_service.rb`
4. Criar migrations: `add_scraping_fields_to_social_profile`, `add_media_fields_to_social_post`, `create_news_articles`
5. Modificar `Gemfile` (adicionar typhoeus)
6. Modificar `app/models/social_profile.rb`
7. Modificar `app/models/social_post.rb`

### Fase 2.2: Ferrum Scrapers (2 dias)
1. Criar `lib/scraping/scrapers/ferrum_scraper_base.rb`
2. Modificar `config/initializers/ferrum.rb` (adicionar stealth options)
3. Criar `lib/scraping/scrapers/instagram_scraper.rb`
4. Criar `lib/scraping/scrapers/twitter_scraper.rb`
5. Criar `app/jobs/scrape_instagram_job.rb`
6. Criar `app/jobs/scrape_twitter_job.rb`

### Fase 2.3: YouTube & RSS (1 dia)
1. Criar `lib/scraping/services/youtube_scraper_service.rb`
2. Criar `app/jobs/scrape_youtube_job.rb`
3. Criar `app/jobs/rss_collect_job.rb`
4. Criar `config/initializers/scraping_limits.rb`

### Fase 2.4: Python Bridge (2 dias)
1. Criar diretório `scripts/python`
2. Criar `scripts/python/nodriver_instagram.py`
3. Criar `scripts/python/camoufox_scrape.py`
4. Criar `lib/scraping/python_bridge/nodriver_runner.rb`
5. Criar `lib/scraping/python_bridge/camoufox_service.rb`
6. Criar `docker/Dockerfile.python`
7. Modificar `docker/docker-compose.yml`

### Fase 2.5: HTTP Stealth (1 dia)
1. Criar `lib/scraping/services/http_stealth_client.rb`

### Fase 2.6: Tests & Integration (1 dia)
1. Criar `test/scraping/rss_parser_service_test.rb`
2. Criar `test/scraping/youtube_scraper_service_test.rb`
3. Criar `test/scraping/http_stealth_client_test.rb`
4. Criar `test/scraping/rate_limit_handler_test.rb`
5. Modificar `app/jobs/application_job.rb`

---

## 8. EVITAR DUPLICAÇÃO - COMPONENTES EXISTENTES

| Componente Existente | NÃO REPETIR |
|----------------------|-------------|
| `FerumConfig.browser_options` | Usar em scrapers, não duplicar lógica de WS URL |
| `ApplicationJob.rescue_from` | Subclasses herdam automaticamente |
| `SocialProfile` scopes existentes | Adicionar novos scopes, não repetir `verified`, `by_platform` |
| `SocialPost` scopes existentes | Adicionar novos scopes |
| Docker Chrome network | Todos scrapers usam `docker-chrome` via `FerumConfig` |

---

## 9. VERIFICAÇÃO PRÉ-IMPLENTAÇÃO

Antes de iniciar, verificar:
- [ ] `lib/scraping/` directory does NOT exist yet
- [ ] `scripts/python/` directory does NOT exist yet
- [ ] `test/scraping/` directory does NOT exist yet
- [ ] Ferrum gem already installed (Gemfile line 24)
- [ ] Chrome container already configured in docker-compose.yml
- [ ] `app/jobs/application_job.rb` already has rate-limit rescue (needs enhancement)
- [ ] Models exist and have correct associations
