# Contexto: app/jobs

Jobs executados em background pelo Solid Queue.

## Jobs Existentes

| Job | Plataforma | Descrição |
|-----|-----------|-----------|
| `ScrapeTwitterJob` | Twitter | Coleta posts e métricas de perfis |
| `ScrapeInstagramJob` | Instagram | Coleta posts e métricas de perfis |
| `ScrapeYoutubeJob` | YouTube | Coleta vídeos e métricas de canais |
| `RssCollectJob` | RSS | Coleta artigos de feeds RSS |
| `DiscoveryJob` | Multi | Descobre e classifica novos perfis via grafo social |
| `CollectTmdbCatalogJob` | TMDB | Coleta filmes e séries do TMDB |
| `CollectIgdbCatalogJob` | IGDB | Coleta jogos populares do IGDB |
| `CollectAnilistCatalogJob` | Anilist | Coleta animes trending do Anilist |
| `CollectEventsRssJob` | RSS | Coleta eventos nerd via Google News RSS |

## Regras Críticas para IA

1. **Idempotência obrigatória**: Usar `find_or_initialize_by(platform_post_id)` — jobs podem rodar múltiplas vezes
2. **Nunca retry imediato em 403/429/captcha**: Backoff de 6-12 horas via `retry_job wait:`
3. **Snapshot dedup window**: Ignorar salvamento se última coleta foi há menos de 2 horas
4. **Inheritance**: Herdar de `ApplicationJob`, usar `queue_as :default`
5. **Null vs Zero**: Ver regra cross-cutting #3 no AGENTS.md
6. **Backoff**: Ver regra cross-cutting #4 no AGENTS.md
7. **Logging**: Ver regra cross-cutting #6 no AGENTS.md
8. **`posts_count` vai para `ProfileSnapshot`, nunca para `profile.update!`**: O campo `posts_count` existe na tabela `profile_snapshots`, não em `social_profiles`. Chamar `profile.update!(posts_count: ...)` levanta `ActiveModel::UnknownAttributeError`.

## Cross-References

- Models: `app/models/CONTEXT.md` — estrutura dos dados persistidos
- Services: `app/services/CONTEXT.md` — lógica de negócio chamada pelos jobs
- Scraping: `lib/scraping/CONTEXT.md` — infraestrutura de scraping
