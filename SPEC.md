# SPEC.md — Oracle & Sensibilidade de Mercado (Fase 4)

Implementação de datalake externo: catálogos (TMDB, IGDB, Anilist) + agregador de agenda RSS para eventos nerd brasileiros.

---

## Arquivos a Criar

| # | Path | Tipo | Descrição |
|---|------|------|-----------|
| 1 | `db/migrate/20260322000001_create_external_catalogs.rb` | Migration | Tabela `external_catalogs` — itens de catálogo de múltiplas fontes |
| 2 | `db/migrate/20260322000002_create_events.rb` | Migration | Tabela `events` — eventos nerd brasileiros |
| 3 | `app/models/external_catalog.rb` | Model | Model genérico com campo `source` (tmdb/igdb/anilist) e `metadata:json` |
| 4 | `app/models/event.rb` | Model | Model para eventos com datas, localização, fonte RSS |
| 5 | `lib/scraping/services/tmdb_client.rb` | Service | Cliente HTTP para TMDB v3 (Net::HTTP, Bearer auth) |
| 6 | `lib/scraping/services/igdb_client.rb` | Service | Cliente HTTP para IGDB v4 (Twitch OAuth2, query language) |
| 7 | `lib/scraping/services/anilist_client.rb` | Service | Cliente GraphQL para Anilist v2 (Net::HTTP POST) |
| 8 | `lib/scraping/services/events_rss_parser.rb` | Service | Parser RSS para eventos nerd (Google News RSS) |
| 9 | `app/jobs/collect_tmdb_catalog_job.rb` | Job | Job semanal coleta TMDB |
| 10 | `app/jobs/collect_igdb_catalog_job.rb` | Job | Job semanal coleta IGDB |
| 11 | `app/jobs/collect_anilist_catalog_job.rb` | Job | Job semanal coleta Anilist |
| 12 | `app/jobs/collect_events_rss_job.rb` | Job | Job diário coleta RSS de eventos |
| 13 | `test/factories/external_catalog.rb` | Factory | FactoryBot factory para ExternalCatalog |
| 14 | `test/factories/event.rb` | Factory | FactoryBot factory para Event |
| 15 | `test/models/external_catalog_test.rb` | Test | Testes do model ExternalCatalog |
| 16 | `test/models/event_test.rb` | Test | Testes do model Event |
| 17 | `test/scraping/tmdb_client_test.rb` | Test | Testes do TmdbClient com WebMock |
| 18 | `test/scraping/igdb_client_test.rb` | Test | Testes do IgdbClient com WebMock |
| 19 | `test/scraping/anilist_client_test.rb` | Test | Testes do AnilistClient com WebMock |
| 20 | `test/scraping/events_rss_parser_test.rb` | Test | Testes do EventsRssParser com WebMock |
| 21 | `test/jobs/collect_tmdb_catalog_job_test.rb` | Test | Testes do job TMDB |
| 22 | `test/jobs/collect_igdb_catalog_job_test.rb` | Test | Testes do job IGDB |
| 23 | `test/jobs/collect_anilist_catalog_job_test.rb` | Test | Testes do job Anilist |
| 24 | `test/jobs/collect_events_rss_job_test.rb` | Test | Testes do job Events RSS |

---

## Arquivos a Modificar

| # | Path | Mudanças |
|---|------|----------|
| 1 | `config/recurring.yml` | Adicionar 4 entradas de schedule: 3 jobs de catálogo (semanal, dias distintos) + 1 job de eventos (diário) |
| 2 | `app/models/CONTEXT.md` | Adicionar `ExternalCatalog` e `Event` à tabela de models |
| 3 | `app/jobs/CONTEXT.md` | Adicionar os 4 novos jobs à tabela de jobs |
| 4 | `lib/scraping/CONTEXT.md` | Adicionar os 4 novos services à tabela de services |

---

## Checklist de Implementação

### Passo 1: Migrations

- [ ] **Passo 1a: Migration `external_catalogs`**
  - Arquivo: `db/migrate/20260322000001_create_external_catalogs.rb`
  - O que fazer: Criar tabela com colunas:

```ruby
# frozen_string_literal: true

class CreateExternalCatalogs < ActiveRecord::Migration[8.0]
  def change
    create_table :external_catalogs do |t|
      t.string  :source,        null: false          # 'tmdb' | 'igdb' | 'anilist'
      t.string  :external_id,   null: false          # ID na API externa
      t.string  :title,         null: false
      t.string  :media_type                              # 'movie' | 'tv' | 'game' | 'anime'
      t.text    :description
      t.date    :release_date
      t.float   :popularity                               # nil se indisponível
      t.float   :vote_average                             # nil se indisponível
      t.integer :vote_count                               # nil se indisponível
      t.string  :poster_url
      t.string  :genres                                   # CSV ou JSON string
      t.json    :metadata,     default: {}               # dados específicos da fonte
      t.string  :original_language
      t.boolean :adult,        default: false
      t.string  :status                                   # 'upcoming' | 'released' | 'airing'

      t.timestamps
    end

    add_index :external_catalogs, [:source, :external_id], unique: true
    add_index :external_catalogs, :source
    add_index :external_catalogs, :media_type
    add_index :external_catalogs, :release_date
  end
end
```

- [ ] **Passo 1b: Migration `events`**
  - Arquivo: `db/migrate/20260322000002_create_events.rb`
  - O que fazer:

```ruby
# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string  :title,           null: false
      t.text    :description
      t.string  :source                              # 'rss' | 'manual'
      t.string  :source_url                          # URL do artigo RSS
      t.string  :location                             # 'São Paulo', 'São Bernardo do Campo', etc.
      t.date    :start_date
      t.date    :end_date
      t.string  :event_type                           # 'bgs' | 'ccxp' | 'anime_friends' | 'other'
      t.string  :image_url
      t.string  :organizer

      t.timestamps
    end

    add_index :events, :source_url, unique: true
    add_index :events, :event_type
    add_index :events, :start_date
    add_index :events, :location
  end
end
```

---

### Passo 2: Models

- [ ] **Passo 2a: Model `ExternalCatalog`**
  - Arquivo: `app/models/external_catalog.rb`
  - O que fazer: Model com validações, scopes, constantes:

```ruby
# frozen_string_literal: true

class ExternalCatalog < ApplicationRecord
  SOURCES = %w[tmdb igdb anilist].freeze
  MEDIA_TYPES = %w[movie tv game anime].freeze
  STATUSES = %w[upcoming released airing].freeze

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :external_id, presence: true
  validates :title, presence: true
  validates :media_type, inclusion: { in: MEDIA_TYPES }, allow_nil: true
  validates :source, uniqueness: { scope: :external_id }

  scope :by_source, ->(source) { where(source: source) }
  scope :by_media_type, ->(type) { where(media_type: type) }
  scope :recent, ->(days = 30) { where('created_at >= ?', days.days.ago) }
  scope :upcoming, -> { where(status: "upcoming").where.not(release_date: nil).order(:release_date) }
  scope :popular, -> { where.not(popularity: nil).order(popularity: :desc) }
end
```

- [ ] **Passo 2b: Model `Event`**
  - Arquivo: `app/models/event.rb`
  - O que fazer:

```ruby
# frozen_string_literal: true

class Event < ApplicationRecord
  SOURCES = %w[rss manual].freeze
  EVENT_TYPES = %w[bgs ccxp anime_friends other].freeze

  validates :title, presence: true
  validates :source_url, uniqueness: true, allow_nil: true
  validates :source, inclusion: { in: SOURCES }, allow_nil: true
  validates :event_type, inclusion: { in: EVENT_TYPES }, allow_nil: true

  scope :upcoming, -> { where('start_date >= ?', Date.current).order(:start_date) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :by_location, ->(location) { where('location LIKE ?', "%#{location}%") }
  scope :recent, ->(days = 7) { where('created_at >= ?', days.days.ago) }
end
```

---

### Passo 3: HTTP Clients / Services

- [ ] **Passo 3a: TmdbClient**
  - Arquivo: `lib/scraping/services/tmdb_client.rb`
  - O que fazer: Stateless service (`class << self`), `Net::HTTP`, Bearer auth via env var `TMDB_API_KEY`, `fetch_upcoming_movies`, `fetch_on_the_air_tv`, `fetch_popular_movies`. Rate limit: sleep 0.3s entre requests. Graceful degradation em erros HTTP. Log com `[TmdbClient]`.

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ScrapingServices
  class TmdbClient
    BASE_URL = "https://api.themoviedb.org/3"
    class << self
      def fetch_upcoming_movies(page: 1, language: "pt-BR")
        get("/movie/upcoming", page: page, language: language)
      end

      def fetch_on_the_air_tv(page: 1, language: "pt-BR")
        get("/tv/on_the_air", page: page, language: language)
      end

      def fetch_popular_movies(page: 1, language: "pt-BR")
        get("/movie/popular", page: page, language: language)
      end

      private

      def get(path, params = {})
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{ENV.fetch('TMDB_API_KEY')}"
        request['Accept'] = 'application/json'

        response = http.request(request)

        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[TmdbClient] HTTP #{response.code} em #{path}"
        nil
      rescue StandardError => e
        Rails.logger.error "[TmdbClient] Erro: #{e.message}"
        nil
      end
    end
  end
end
```

- [ ] **Passo 3b: IgdbClient**
  - Arquivo: `lib/scraping/services/igdb_client.rb`
  - O que fazer: `Net::HTTP` POST para `https://api.igdb.com/v4/games`, headers `Client-ID` + `Authorization: Bearer` via env vars (`IGDB_CLIENT_ID`, `IGDB_ACCESS_TOKEN`). Query language IGDB no body. Método `fetch_popular_games` e `fetch_upcoming_games`. Log com `[IgdbClient]`.

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ScrapingServices
  class IgdbClient
    BASE_URL = "https://api.igdb.com/v4"
    class << self
      def fetch_popular_games(limit: 50)
        query = <<~APICALYPSE
          fields name,summary,first_release_date,rating,rating_count,cover.url,genres.name,platforms.name,status;
          sort rating desc;
          limit #{limit};
          where rating != null & first_release_date != null;
        APICALYPSE
        post("/games", query)
      end

      def fetch_upcoming_games(limit: 50)
        timestamp = Time.current.to_i
        query = <<~APICALYPSE
          fields name,summary,first_release_date,cover.url,genres.name,platforms.name,status;
          sort first_release_date asc;
          limit #{limit};
          where first_release_date > #{timestamp};
        APICALYPSE
        post("/games", query)
      end

      private

      def post(path, body)
        uri = URI("#{BASE_URL}#{path}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request['Client-ID'] = ENV.fetch('IGDB_CLIENT_ID')
        request['Authorization'] = "Bearer #{ENV.fetch('IGDB_ACCESS_TOKEN')}"
        request['Accept'] = 'application/json'
        request['Content-Type'] = 'text/plain'
        request.body = body

        response = http.request(request)

        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[IgdbClient] HTTP #{response.code} em #{path}"
        nil
      rescue StandardError => e
        Rails.logger.error "[IgdbClient] Erro: #{e.message}"
        nil
      end
    end
  end
end
```

- [ ] **Passo 3c: AnilistClient**
  - Arquivo: `lib/scraping/services/anilist_client.rb`
  - O que fazer: `Net::HTTP` POST para `https://graphql.anilist.co`, body JSON `{ query: "...", variables: {...} }`. Sem API key. Métodos `fetch_trending_anime`, `fetch_upcoming_anime`. Rate limit: sleep 0.7s entre requests (90/min). Log com `[AnilistClient]`.

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module ScrapingServices
  class AnilistClient
    GRAPHQL_URL = "https://graphql.anilist.co"

    TRENDING_QUERY = <<~GRAPHQL
      query ($page: Int, $perPage: Int) {
        Page(page: $page, perPage: $perPage) {
          media(type: ANIME, sort: TRENDING_DESC) {
            id
            title { romaji english native }
            description(asHtml: false)
            startDate { year month day }
            popularity
            averageScore
            episodes
            coverImage { large }
            genres
            status
          }
        }
      }
    GRAPHQL

    class << self
      def fetch_trending_anime(page: 1, per_page: 20)
        execute(TRENDING_QUERY, page: page, perPage: per_page)
      end

      private

      def execute(query, variables = {})
        uri = URI(GRAPHQL_URL)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        request.body = JSON.generate({ query: query, variables: variables })

        response = http.request(request)

        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[AnilistClient] HTTP #{response.code}"
        nil
      rescue StandardError => e
        Rails.logger.error "[AnilistClient] Erro: #{e.message}"
        nil
      end
    end
  end
end
```

- [ ] **Passo 3d: EventsRssParser**
  - Arquivo: `lib/scraping/services/events_rss_parser.rb`
  - O que fazer: Reutilizar padrão de `RssParserService` (Net::HTTP + REXML). Hardcode URLs dos feeds (Google News RSS para BGS/CCXP/Anime Friends). Método `fetch_events` retornando array normalizado de hashes. Log com `[EventsRssParser]`.

```ruby
# frozen_string_literal: true

require 'rexml/document'
require 'net/http'
require 'uri'

module ScrapingServices
  class EventsRssParser
    FEEDS = [
      {
        type: "other",
        url: "https://news.google.com/rss/search?q=BGS+2026+OR+Brasil+Game+Show&hl=pt-BR&gl=BR&ceid=BR:pt-419"
      },
      {
        type: "other",
        url: "https://news.google.com/rss/search?q=CCXP+2026&hl=pt-BR&gl=BR&ceid=BR:pt-419"
      },
      {
        type: "other",
        url: "https://news.google.com/rss/search?q=Anime+Friends+2026&hl=pt-BR&gl=BR&ceid=BR:pt-419"
      }
    ].freeze

    class << self
      def fetch_events
        FEEDS.flat_map do |feed|
          items = parse_feed_url(feed[:url])
          items.map { |item| item.merge(event_type: feed[:type]) }
        end
      end

      private

      def parse_feed_url(url)
        xml = fetch(url)
        return [] unless xml

        parse_xml(xml)
      end

      def fetch(url)
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'

        response = http.request(request)
        return response.body if response.is_a?(Net::HTTPSuccess)

        Rails.logger.warn "[EventsRssParser] HTTP #{response.code} ao buscar #{url}"
        nil
      rescue StandardError => e
        Rails.logger.error "[EventsRssParser] Erro: #{e.message}"
        nil
      end

      def parse_xml(xml_content)
        doc = REXML::Document.new(xml_content)
        items = []

        doc.elements.each('rss/channel/item') do |item|
          title = item.elements['title']&.text
          link = item.elements['link']&.text
          description = item.elements['description']&.text
          pub_date = item.elements['pubDate']&.text

          next if title.nil? && link.nil?

          items << {
            title: title&.strip,
            source_url: link&.strip,
            description: description&.strip,
            start_date: pub_date ? Time.parse(pub_date).to_date : nil
          }
        end

        items
      rescue REXML::ParseException => e
        Rails.logger.error "[EventsRssParser] XML malformado: #{e.message}"
        []
      end
    end
  end
end
```

---

### Passo 4: Jobs

- [ ] **Passo 4a: CollectTmdbCatalogJob**
  - Arquivo: `app/jobs/collect_tmdb_catalog_job.rb`
  - O que fazer: Seguir padrão `RssCollectJob`. Chamar `TmdbClient.fetch_upcoming_movies` + `fetch_on_the_air_tv`. Iterar results, `find_or_initialize_by(source: "tmdb", external_id:)`, `assign_attributes`, `save! if changed?`. Dedup window: skip se `updated_at < 24h.ago`. Sleep 0.3s entre saves.

```ruby
# frozen_string_literal: true

class CollectTmdbCatalogJob < ApplicationJob
  queue_as :default

  def perform
    collect_movies
    collect_tv_shows
    Rails.logger.info "[CollectTmdbCatalogJob] Coleta TMDB concluída"
  rescue StandardError => e
    Rails.logger.error "[CollectTmdbCatalogJob] Erro: #{e.message}"
  end

  private

  def collect_movies
    data = ScrapingServices::TmdbClient.fetch_upcoming_movies
    return unless data&.dig("results")

    data["results"].each { |item| save_catalog(item, "movie") }
  end

  def collect_tv_shows
    data = ScrapingServices::TmdbClient.fetch_on_the_air_tv
    return unless data&.dig("results")

    data["results"].each { |item| save_catalog(item, "tv") }
  end

  def save_catalog(item, media_type)
    catalog = ExternalCatalog.find_or_initialize_by(source: "tmdb", external_id: item["id"].to_s)
    return if catalog.updated_at && catalog.updated_at > 24.hours.ago

    catalog.assign_attributes(
      title: item["title"] || item["name"],
      media_type: media_type,
      description: item["overview"],
      release_date: item["release_date"] || item["first_air_date"],
      popularity: item["popularity"],
      vote_average: item["vote_average"].to_f > 0 ? item["vote_average"] : nil,
      vote_count: item["vote_count"].to_i > 0 ? item["vote_count"] : nil,
      poster_url: item["poster_path"] ? "https://image.tmdb.org/t/p/w500#{item["poster_path"]}" : nil,
      genres: item["genre_ids"]&.join(","),
      original_language: item["original_language"],
      adult: item["adult"] || false,
      status: item["release_date"].present? && item["release_date"] > Date.current.to_s ? "upcoming" : "released",
      metadata: item.except("title", "name", "overview", "release_date", "first_air_date", "poster_path", "genre_ids")
    )

    catalog.save! if catalog.changed?
  end
end
```

- [ ] **Passo 4b: CollectIgdbCatalogJob**
  - Arquivo: `app/jobs/collect_igdb_catalog_job.rb`
  - O que fazer: Mesmo padrão. Chamar `IgdbClient.fetch_popular_games`. Iterar, `find_or_initialize_by(source: "igdb", external_id:)`. Extrair cover URL, genres. Sleep 0.5s entre saves (rate limit mais agressivo).

```ruby
# frozen_string_literal: true

class CollectIgdbCatalogJob < ApplicationJob
  queue_as :default

  def perform
    data = ScrapingServices::IgdbClient.fetch_popular_games
    return unless data.is_a?(Array)

    data.each { |item| save_catalog(item) }
    Rails.logger.info "[CollectIgdbCatalogJob] Coleta IGDB concluída: #{data.size} jogos"
  rescue StandardError => e
    Rails.logger.error "[CollectIgdbCatalogJob] Erro: #{e.message}"
  end

  private

  def save_catalog(item)
    catalog = ExternalCatalog.find_or_initialize_by(source: "igdb", external_id: item["id"].to_s)
    return if catalog.updated_at && catalog.updated_at > 24.hours.ago

    catalog.assign_attributes(
      title: item["name"],
      media_type: "game",
      description: item["summary"],
      release_date: item["first_release_date"] ? Time.at(item["first_release_date"]).to_date : nil,
      popularity: item["rating"],
      vote_average: item["rating"].to_f > 0 ? item["rating"] : nil,
      vote_count: item["rating_count"].to_i > 0 ? item["rating_count"] : nil,
      poster_url: item.dig("cover", "url"),
      genres: item["genres"]&.map { |g| g["name"] }&.join(","),
      status: item["status"] == 0 ? "released" : "upcoming",
      metadata: item.except("name", "summary", "first_release_date", "rating", "rating_count", "cover", "genres")
    )

    catalog.save! if catalog.changed?
  end
end
```

- [ ] **Passo 4c: CollectAnilistCatalogJob**
  - Arquivo: `app/jobs/collect_anilist_catalog_job.rb`
  - O que fazer: Mesmo padrão. Chamar `AnilistClient.fetch_trending_anime`. Iterar `data["data"]["Page"]["media"]`. `find_or_initialize_by(source: "anilist", external_id:)`. Sleep 0.7s.

```ruby
# frozen_string_literal: true

class CollectAnilistCatalogJob < ApplicationJob
  queue_as :default

  def perform
    data = ScrapingServices::AnilistClient.fetch_trending_anime
    media_list = data&.dig("data", "Page", "media")
    return unless media_list.is_a?(Array)

    media_list.each { |item| save_catalog(item) }
    Rails.logger.info "[CollectAnilistCatalogJob] Coleta Anilist concluída: #{media_list.size} animes"
  rescue StandardError => e
    Rails.logger.error "[CollectAnilistCatalogJob] Erro: #{e.message}"
  end

  private

  def save_catalog(item)
    catalog = ExternalCatalog.find_or_initialize_by(source: "anilist", external_id: item["id"].to_s)
    return if catalog.updated_at && catalog.updated_at > 24.hours.ago

    start_date = item["startDate"]
    release_date = if start_date&.dig("year")
                     Date.new(start_date["year"], start_date["month"] || 1, start_date["day"] || 1)
                   end

    score = item["averageScore"]
    pop = item["popularity"]

    catalog.assign_attributes(
      title: item.dig("title", "english") || item.dig("title", "romaji"),
      media_type: "anime",
      description: item["description"]&.gsub(/<[^>]+>/, "")&.strip,
      release_date: release_date,
      popularity: pop,
      vote_average: score ? (score.to_f / 10.0) : nil,
      vote_count: pop,
      poster_url: item.dig("coverImage", "large"),
      genres: item["genres"]&.join(","),
      status: item["status"]&.downcase,
      original_language: "ja",
      metadata: item.except("title", "description", "startDate", "averageScore", "popularity", "coverImage", "genres")
    )

    catalog.save! if catalog.changed?
  end
end
```

- [ ] **Passo 4d: CollectEventsRssJob**
  - Arquivo: `app/jobs/collect_events_rss_job.rb`
  - O que fazer: Chamar `EventsRssParser.fetch_events`. Iterar, `find_or_initialize_by(source_url:)`. Dedup: skip se `updated_at < 12h.ago`.

```ruby
# frozen_string_literal: true

class CollectEventsRssJob < ApplicationJob
  queue_as :default

  def perform
    items = ScrapingServices::EventsRssParser.fetch_events

    items.each do |item|
      event = Event.find_or_initialize_by(source_url: item[:source_url])
      next if event.updated_at && event.updated_at > 12.hours.ago

      event.assign_attributes(
        title: item[:title],
        description: item[:description],
        source: "rss",
        start_date: item[:start_date],
        event_type: item[:event_type]
      )

      event.save! if event.changed?
    end

    Rails.logger.info "[CollectEventsRssJob] #{items.size} eventos processados"
  rescue StandardError => e
    Rails.logger.error "[CollectEventsRssJob] Erro: #{e.message}"
  end
end
```

---

### Passo 5: Recurring Schedule

- [ ] **Passo 5: Atualizar `config/recurring.yml`**
  - Arquivo: `config/recurring.yml`
  - O que fazer: Adicionar schedules após a entrada existente de `discovery_job`:

```yaml
  collect_tmdb_catalog_job:
    class: CollectTmdbCatalogJob
    queue: default
    schedule: at 4am every monday
  collect_igdb_catalog_job:
    class: CollectIgdbCatalogJob
    queue: default
    schedule: at 4am every tuesday
  collect_anilist_catalog_job:
    class: CollectAnilistCatalogJob
    queue: default
    schedule: at 4am every wednesday
  collect_events_rss_job:
    class: CollectEventsRssJob
    queue: default
    schedule: every day at 7am
```

---

### Passo 6: Factories

- [ ] **Passo 6a: Factory `external_catalog`**
  - Arquivo: `test/factories/external_catalog.rb`
  - O que fazer:

```ruby
FactoryBot.define do
  factory :external_catalog do
    source { %w[tmdb igdb anilist].sample }
    external_id { Faker::Number.number(digits: 6).to_s }
    title { Faker::Movie.title }
    media_type { %w[movie tv game anime].sample }
    description { Faker::Lorem.paragraph }
    release_date { Faker::Date.between(from: 1.year.ago, to: 1.year.from_now) }
    popularity { Faker::Number.between(from: 1.0, to: 100.0) }
    vote_average { Faker::Number.between(from: 1.0, to: 10.0) }
    vote_count { Faker::Number.between(from: 10, to: 10_000) }
    poster_url { Faker::Internet.url(path: "/poster.jpg") }
    genres { %w[Action Comedy Drama].sample(2).join(",") }
    metadata { {} }
    original_language { %w[en ja pt].sample }
    adult { false }
    status { %w[upcoming released airing].sample }

    trait :tmdb do
      source { "tmdb" }
      media_type { %w[movie tv].sample }
    end

    trait :igdb do
      source { "igdb" }
      media_type { "game" }
    end

    trait :anilist do
      source { "anilist" }
      media_type { "anime" }
    end

    trait :with_nil_metrics do
      popularity { nil }
      vote_average { nil }
      vote_count { nil }
    end
  end
end
```

- [ ] **Passo 6b: Factory `event`**
  - Arquivo: `test/factories/event.rb`
  - O que fazer:

```ruby
FactoryBot.define do
  factory :event do
    title { Faker::Lorem.words(number: 3).join(" ").titleize }
    description { Faker::Lorem.paragraph }
    source { "rss" }
    source_url { Faker::Internet.url }
    location { %w[São-Paulo São-Bernardo Rio-de-Janeiro].sample }
    start_date { Faker::Date.forward(days: 90) }
    end_date { Faker::Date.forward(days: 95) }
    event_type { %w[bgs ccxp anime_friends other].sample }
    image_url { Faker::Internet.url(path: "/event.jpg") }
    organizer { Faker::Company.name }

    trait :bgs do
      event_type { "bgs" }
      title { "Brasil Game Show #{Date.current.year}" }
    end

    trait :ccxp do
      event_type { "ccxp" }
      title { "CCXP #{Date.current.year}" }
    end

    trait :upcoming do
      start_date { Faker::Date.forward(days: 60) }
      end_date { Faker::Date.forward(days: 65) }
    end

    trait :past do
      start_date { Faker::Date.backward(days: 30) }
      end_date { Faker::Date.backward(days: 28) }
    end
  end
end
```

---

### Passo 7: Tests — Models

- [ ] **Passo 7a: Test `external_catalog_test.rb`**
  - Arquivo: `test/models/external_catalog_test.rb`
  - O que fazer: Testar validações (source presence, inclusion, uniqueness scoped, external_id presence, title presence). Testar scopes (by_source, by_media_type, upcoming, popular). Testar `with_nil_metrics` trait aceita nil.

- [ ] **Passo 7b: Test `event_test.rb`**
  - Arquivo: `test/models/event_test.rb`
  - O que fazer: Testar validações (title presence, source_url uniqueness, source/event_type inclusion). Testar scopes (upcoming, by_type, by_location, recent).

---

### Passo 8: Tests — HTTP Clients

- [ ] **Passo 8a: Test `tmdb_client_test.rb`**
  - Arquivo: `test/scraping/tmdb_client_test.rb`
  - O que fazer: WebMock stub para `api.themoviedb.org`. Testar `fetch_upcoming_movies` retorna parsed JSON. Testar HTTP 401 retorna nil. Testar timeout retorna nil. ENV stub com `ENV.stubs(:fetch).with('TMDB_API_KEY').returns('test_key')`.

- [ ] **Passo 8b: Test `igdb_client_test.rb`**
  - Arquivo: `test/scraping/igdb_client_test.rb`
  - O que fazer: WebMock stub para `api.igdb.com`. Testar POST com query APICALYPSE. Testar headers Client-ID e Authorization. Testar erro HTTP retorna nil.

- [ ] **Passo 8c: Test `anilist_client_test.rb`**
  - Arquivo: `test/scraping/anilist_client_test.rb`
  - O que fazer: WebMock stub para `graphql.anilist.co`. Testar POST com body GraphQL JSON. Testar response parsing. Testar erro HTTP retorna nil.

- [ ] **Passo 8d: Test `events_rss_parser_test.rb`**
  - Arquivo: `test/scraping/events_rss_parser_test.rb`
  - O que fazer: WebMock stub com fixture XML de RSS. Testar `fetch_events` retorna array normalizado. Testar XML malformado retorna []. Testar HTTP error retorna [].

---

### Passo 9: Tests — Jobs

- [ ] **Passo 9a: Test `collect_tmdb_catalog_job_test.rb`**
  - Arquivo: `test/jobs/collect_tmdb_catalog_job_test.rb`
  - O que fazer: Stub `TmdbClient` com mocha. Verificar `find_or_initialize_by` chamado. Verificar idempotência (não duplica). Testar erro em client não quebra job.

- [ ] **Passo 9b: Test `collect_igdb_catalog_job_test.rb`**
  - Arquivo: `test/jobs/collect_igdb_catalog_job_test.rb`
  - O que fazer: Mesmo padrão do 9a, stub `IgdbClient`.

- [ ] **Passo 9c: Test `collect_anilist_catalog_job_test.rb`**
  - Arquivo: `test/jobs/collect_anilist_catalog_job_test.rb`
  - O que fazer: Mesmo padrão do 9a, stub `AnilistClient`.

- [ ] **Passo 9d: Test `collect_events_rss_job_test.rb`**
  - Arquivo: `test/jobs/collect_events_rss_job_test.rb`
  - O que fazer: Stub `EventsRssParser`. Verificar `find_or_initialize_by(source_url:)`. Verificar dedup window 12h.

---

### Passo 10: CONTEXT.md Updates

- [ ] **Passo 10a: Update `app/models/CONTEXT.md`**
  - Arquivo: `app/models/CONTEXT.md`
  - O que fazer: Adicionar `ExternalCatalog` e `Event` à tabela de models existente.

- [ ] **Passo 10b: Update `app/jobs/CONTEXT.md`**
  - Arquivo: `app/jobs/CONTEXT.md`
  - O que fazer: Adicionar os 4 novos jobs à tabela de jobs.

- [ ] **Passo 10c: Update `lib/scraping/CONTEXT.md`**
  - Arquivo: `lib/scraping/CONTEXT.md`
  - O que fazer: Adicionar os 4 novos services à tabela de services.

---

## Perguntas

- [ ] **P1: IGDB OAuth2 — Tokens.** O PRD recomenda env vars (`IGDB_ACCESS_TOKEN`, `IGDB_CLIENT_ID`). Tokens IGDB expiram a 60 dias. Quem/como vai renovar? Precisa de um job de refresh ou documentação manual?
- [ ] **P2: Dedup cross-source.** Mesmo conteúdo (ex: One Piece) existe em Anilist e TMDB. Quer registros separados por `source` ou algum mecanismo de fusão? Atualmente: separados por `source + external_id`.
- [ ] **P3: Event type inference.** O `EventsRssParser` atualmente mapeia todos os feeds como `event_type: "other"`. Quer lógica de inferência baseada no título (ex: "BGS" → `bgs`, "CCXP" → `ccxp`)?
- [ ] **P4: Queue `:background`.** O PRD menciona criar queue `:background` para jobs pesados. Usar `:default` por simplicidade ou criar nova queue?

---

## Validação

- [ ] `docker-compose -f docker/docker-compose.yml run --rm test` passa (0 failures, 0 errors)
- [ ] `ruby -cw` sem warnings em cada arquivo `.rb` criado/modificado
- [ ] `docker-compose -f docker/docker-compose.yml exec app bin/rails db:migrate:status` mostra migrations como "up"
- [ ] Nenhum hardcoded secret — `TMDB_API_KEY`, `IGDB_CLIENT_ID`, `IGDB_ACCESS_TOKEN` via ENV
- [ ] Factories em `test/factories/` existem para `external_catalog` e `event`
- [ ] Testes em `test/models/`, `test/scraping/`, `test/jobs/` espelham a estrutura de `app/` e `lib/`
