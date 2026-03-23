# Contexto: lib/scraping

Coleta de dados e scraping (Ferrum + Chrome headless + Python bridge).

## Arquitetura

```
app (Ruby) ──WebSocket──> docker-chrome (Chrome headless)
                                   │
                              Ferrum/CDP
                                   │
                        :9222 (DevTools Protocol)
```

## Estrutura

| Diretório | Descrição |
|-----------|-----------|
| `scrapers/` | Scrapers baseados em Ferrum (twitter, instagram) |
| `services/` | Serviços HTTP (stealth client, RSS, YouTube, TMDB, IGDB, Anilist) |
| `python_bridge/` | Ponte Ruby→Python (nodriver, camoufox, curl-impersonate) |

## Regras Críticas de Scraping para IA

1. **Chrome container**: Ferrum conecta ao `docker-chrome` (chromedp/headless-shell) na rede interna
2. **Host Header Bypass**: OBRIGATÓRIO substituir header `Host` para `localhost` em `/json/version`
3. **Bloqueios → backoff**: Ver regra cross-cutting #4 no AGENTS.md
4. **Ensure close**: Ver regra cross-cutting #5 no AGENTS.md
5. **Python bridge**: Scripts Python em `scripts/python/`, executados via Ruby bridge — nunca chamar `python` diretamente

## Cross-References

- Jobs: `app/jobs/CONTEXT.md` — jobs que disparam scraping
- Scripts: `scripts/python/CONTEXT.md` — scripts Python executados pelo bridge
- Docker: `docker/CONTEXT.md` — configuração do container Chrome
