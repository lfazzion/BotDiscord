## Objetivo
Implementar a Fase 4 do Plano de Prioridade: "O Oracle e Sensibilidade de Mercado" — um datalake externo com catálogos de entretenimento (filmes/séries via TMDB, jogos via IGDB, animes via Anilist) e um agregador de agenda RSS para eventos nerd brasileiros (BGS, Anime Friends, CCXP), alimentando o contexto macro que o LLM precisa para análises de mercado.

## Arquivos Relevantes
| Arquivo | Relevância | Motivo |
|---------|------------|--------|
| `app/models/external_catalog.rb` | alta | Novo model para armazenar itens de catálogo (filmes, jogos, animes) |
| `app/models/event.rb` | alta | Novo model para eventos nerd (BGS, CCXP, Anime Friends) |
| `app/jobs/collect_tmdb_catalog_job.rb` | alta | Job semanal para coleta TMDB |
| `app/jobs/collect_igdb_catalog_job.rb` | alta | Job semanal para coleta IGDB |
| `app/jobs/collect_anilist_catalog_job.rb` | alta | Job semanal para coleta Anilist GraphQL |
| `app/jobs/collect_events_rss_job.rb` | alta | Job contínuo para RSS de eventos |
| `lib/scraping/services/tmdb_client.rb` | alta | Cliente HTTP para API TMDB v3 |
| `lib/scraping/services/igdb_client.rb` | alta | Cliente HTTP para API IGDB v4 |
| `lib/scraping/services/anilist_client.rb` | alta | Cliente GraphQL para Anilist API v2 |
| `lib/scraping/services/events_rss_parser.rb` | alta | Parser RSS especializado em eventos |
| `db/migrate/TIMESTAMP_create_external_catalogs.rb` | alta | Migration para tabela de catálogos |
| `db/migrate/TIMESTAMP_create_events.rb` | alta | Migration para tabela de eventos |
| `config/recurring.yml` | alta | Adicionar jobs semanais ao scheduler |
| `test/models/external_catalog_test.rb` | média | Testes do novo model |
| `test/models/event_test.rb` | média | Testes do novo model |
| `test/jobs/collect_tmdb_catalog_job_test.rb` | média | Testes dos jobs |
| `test/jobs/collect_igdb_catalog_job_test.rb` | média | Testes dos jobs |
| `test/jobs/collect_anilist_catalog_job_test.rb` | média | Testes dos jobs |
| `test/jobs/collect_events_rss_job_test.rb` | média | Testes dos jobs |
| `test/scraping/tmdb_client_test.rb` | média | Testes dos clientes HTTP |
| `test/scraping/igdb_client_test.rb` | média | Testes dos clientes HTTP |
| `test/scraping/anilist_client_test.rb` | média | Testes dos clientes HTTP |
| `test/scraping/events_rss_parser_test.rb` | média | Testes dos parsers |
| `test/factories/external_catalog.rb` | média | Factory para testes |
| `test/factories/event.rb` | média | Factory para testes |
| `app/models/CONTEXT.md` | baixa | Atualizar com novos models |
| `app/jobs/CONTEXT.md` | baixa | Atualizar com novos jobs |
| `lib/scraping/CONTEXT.md` | baixa | Atualizar com novos services |

## Padrões Encontrados no Codebase

### Padrão de Job Idempotente (RssCollectJob)
`app/jobs/rss_collect_job.rb:6-28`
```ruby
def perform(query, days: 1)
  articles = ScrapingServices::RssParserService.parse_google_news(query: query, days: days)
  articles.each do |article|
    news = NewsArticle.find_or_initialize_by(link: article[:link])
    news.assign_attributes(...)
    news.save! if news.changed?
  end
  RssCollectJob.set(wait: 1.hour).perform_later(query, days: days)
rescue StandardError => e
  Rails.logger.error "[RssCollectJob] Erro ao coletar RSS '#{query}': #{e.message}"
  RssCollectJob.set(wait: 6.hours).perform_later(query, days: days)
end
```

### Padrão de Model com Validação de Unicidade
`app/models/news_article.rb:5-9`
```ruby
validates :link, presence: true, uniqueness: true
scope :recent, ->(days = 7) { where('pub_date >= ?', days.days.ago) }
scope :by_source, ->(source) { where(source: source) }
```

### Padrão de HTTP Client (RssParserService)
`lib/scraping/services/rss_parser_service.rb:24-44`
```ruby
def fetch_feed(url)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 15
  request = Net::HTTP::Get.new(uri)
  request['User-Agent'] = 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
  response = http.request(request)
  return response.body if response.is_a?(Net::HTTPSuccess)
  nil
end
```

### Padrão de Recurring Tasks (Solid Queue)
`config/recurring.yml:12-19`
```yaml
production:
  discovery_job:
    class: DiscoveryJob
    queue: default
    schedule: at 3am every tuesday and friday
```

### Padrão de Service Stateless
`app/services/ai_router.rb:6-62`
```ruby
class AiRouter
  class << self
    def complete(prompt, context: :interactive, tools: [])
      # ...
    end
  end
end
```

## Documentação Externa

### APIs Gratuitas para Coleta
| API | Documentação | Rate Limit | Free Tier | Notas |
|-----|--------------|------------|-----------|-------|
| **TMDB v3** | https://developer.themoviedb.org/reference/movie-upcoming-list | 40 req/10s | Unlimited | Requer API key (gratuita). Endpoints: `/movie/upcoming`, `/tv/on_the_air`, `/discover/movie` |
| **IGDB v4** | https://api-docs.igdb.com/ | ~4 req/1s | Unlimited com Twitch OAuth | Requer Twitch Client ID + Access Token. Query language próprio. Endpoint: `https://api.igdb.com/v4/games` |
| **Anilist v2** | https://anilist.gitbook.io/anilist-apiv2-docs/ | 90 req/min | Unlimited | GraphQL em `https://graphql.anilist.co`. Não requer API key para queries públicas |
| **TVmaze** | https://www.tvmaze.com/api | 20 req/10s | Unlimited | Alternativa para TV shows, sem API key |

### RSS Feeds para Eventos Nerd
| Fonte | URL | Tipo |
|-------|-----|------|
| Anime News Network | `https://www.animenewsnetwork.com/news.xml` | Notícias anime |
| Crunchyroll | `https://www.crunchyroll.com/rss/new-episodes` | Novos episódios |
| Google News RSS | `https://news.google.com/rss/search?q=BGS+2026+OR+Anime+Friends+2026+OR+CCXP+2026` | Notícias de eventos |

### Referências Técnicas
- **TMDB API Tutorial 2026**: https://www.youtube.com/watch?v=-AVvVpzNVnI
- **IGDB API Introduction**: https://publicapis.io/igdb-com-api
- **Anilist GraphQL Playground**: https://anilist.co/graphiql
- **Free Movie APIs Comparison 2026**: https://hypereal.tech/a/free-movie-apis

## Constraints

### Stack Atual
| Constraint | Impacto |
|------------|---------|
| **SQLite WAL** | Banco único com 3 conexões (primary, queue, cache). Novas tabelas vão no `primary`. Sem foreign keys entre tabelas de catálogo e social_profiles (são domínios independentes). |
| **Solid Queue** | Jobs semanais via `config/recurring.yml`. Sem Redis/Sidekiq. Usar `queue_as :default` ou criar queue `:background` para jobs pesados. |
| **Docker** | Todos os comandos via `docker-compose -f docker/docker-compose.yml`. Bind mount em `storage/`. |
| **Headless Rails** | Sem ActionView. API-only. Não criar controllers/views para esta fase. |
| **Ruby ~> 4.0** | Usar syntax moderna. `frozen_string_literal: true` obrigatório. |
| **HTTP Clients** | Usar `Net::HTTP` nativo para APIs simples (TMDB, Anilist). `Typhoeus` já está no Gemfile para fallback. Não adicionar novas gems sem necessidade. |
| **GraphQL** | Anilist usa GraphQL. Usar `Net::HTTP` com POST + JSON body (sem gem GraphQL). |
| **Logging** | Prefixo `[ClassName]` em todos os logs. |
| **Null vs Zero** | Métricas de popularidade/rating devem ser `nil` em falha, nunca `0`. |
| **Idempotência** | Usar `find_or_initialize_by` com chaves únicas (external_id + source). |
| **Dedup Window** | Catálogos: atualização semanal (ignorar se última coleta < 24h). Eventos: atualização diária (ignorar se última coleta < 12h). |

### APIs Externas
| API | Auth | Limite | Risco |
|-----|------|--------|-------|
| TMDB | API Key (header `Authorization: Bearer`) | 40 req/10s | Key pode ser revogada. Usar env var `TMDB_API_KEY`. |
| IGDB | Twitch OAuth2 (Client ID + Access Token) | ~4 req/1s | Token expira a cada 60 dias. Implementar refresh automático. |
| Anilist | Nenhuma (pública) | 90 req/min | Rate limit por IP. Backoff de 60s em 429. |

## Riscos / Pontos de Atenção

### Críticos
1. **IGDB OAuth2 Complexity**: IGDB requer autenticação Twitch OAuth2. O access token expira a cada 60 dias. Precisa implementar fluxo de refresh token ou documentar renovação manual.
2. **Rate Limits Diferentes**: Cada API tem limites diferentes (TMDB: 40/10s, IGDB: 4/s, Anilist: 90/min). Jobs semanais devem respeitar esses limites com delays entre requests.
3. **Schema Heterogêneo**: TMDB, IGDB e Anilist retornam estruturas JSON completamente diferentes. O model `ExternalCatalog` precisa ser flexível o suficiente para armazenar dados normalizados de todas as fontes.
4. **Eventos RSS Voláteis**: Eventos brasileiros (BGS, CCXP) podem não ter RSS oficial. Pode ser necessário scraping de sites ou usar Google News RSS como proxy.

### Regras do Projeto
5. **Nunca retry em 403/429/captcha**: Se uma API retornar 429, backoff de 6+ horas (regra cross-cutting #4 do AGENTS.md).
6. **Métricas nil vs 0**: Campos como `popularity`, `vote_average` do TMDB devem ser `nil` se não disponíveis, nunca `0`.
7. **Ensure close**: Se usar conexões HTTP persistentes, garantir fechamento em `ensure` blocks.
8. **Timestamp injection**: Se prompts LLM usarem dados de catálogo, injetar `<current_datetime: Time.current>`.

### Edge Cases
9. **Dados Duplicados**: Mesmo conteúdo pode existir em múltiplas fontes (ex: anime existe no Anilist e TMDB). Decidir se são registros separados ou se precisam de dedup cross-source.
10. **Dados Incompletos**: APIs podem retornar campos nulos. Model deve aceitar `nil` em campos opcionais.
11. **Mudanças de Schema**: APIs externas podem mudar sem aviso. Implementar graceful degradation (log warning, não crash).
12. **Timezone**: Datas de eventos podem estar em timezone diferentes. Normalizar para UTC no banco.

## Decisões a Tomar

### Arquitetura
1. **Um model ou três?** Criar um `ExternalCatalog` genérico com campo `source` (tmdb/igdb/anilist) OU criar `Movie`, `Game`, `Anime` separados?
   - **Prós do genérico**: Menos tabelas, query unificada para LLM.
   - **Prós do separado**: Schema específico por domínio, validações diferentes.
   - **Recomendação**: Um model genérico com `metadata:json` para dados específicos da fonte.

2. **Eventos: model separado ou parte de ExternalCatalog?**
   - Eventos têm natureza diferente (datas, localização) vs catálogos (títulos, ratings).
   - **Recomendação**: Model `Event` separado.

3. **Jobs semanais: um job por API ou job orquestrador único?**
   - Jobs separados permitem retry independente e debugging mais fácil.
   - **Recomendação**: Um job por API (`CollectTmdbCatalogJob`, `CollectIgdbCatalogJob`, `CollectAnilistCatalogJob`).

### Integração
4. **IGDB OAuth: como armazenar tokens?**
   - Opção A: Variáveis de ambiente (`IGDB_ACCESS_TOKEN`, `IGDB_CLIENT_ID`).
   - Opção B: Tabela `api_credentials` no banco.
   - **Recomendação**: Env vars por simplicidade (seguindo padrão do projeto).

5. **Eventos RSS: quais feeds monitorar?**
   - Google News RSS para "BGS 2026", "Anime Friends 2026", "CCXP 2026"?
   - RSS específicos de sites de eventos?
   - **Recomendação**: Começar com Google News RSS (já temos padrão no `RssCollectJob`).

6. **Frequência de atualização:**
   - Catálogos (filmes/jogos/animes): semanal (dados mudam pouco).
   - Eventos: diária (datas podem ser anunciadas a qualquer momento).
   - **Recomendação**: Adicionar ao `recurring.yml` com schedule apropriado.

### Testes
7. **Como testar chamadas a APIs externas?**
   - Usar WebMock para stubs HTTP (já configurado no `test_helper.rb`).
   - Criar fixtures JSON com respostas reais das APIs.
   - **Recomendação**: Seguir padrão existente de `test/scraping/`.
