# Contexto: lib/scraping

Este diretório lida com coleta de dados e scraping (Ferrum + Chrome headless).

## Arquitetura de Scraping

```
app (Ruby) ──WebSocket──> docker-chrome (Chrome headless)
                                   │
                              Ferrum/CDP
                                   │
                        :9222 (DevTools Protocol)
```

## Regras Críticas de Scraping para IA
1. **Container Chrome**: O scrape roda usando Ferrum conectando ao container `docker-chrome` (chromedp/headless-shell).
2. **Variáveis de Ambiente**: `CHROME_HOST=chrome` e `CHROME_PORT=9222` são passadas via docker-compose.
3. **Host Header Bypass**: É **OBRIGATÓRIO** substituir o header `Host` para `localhost` ao conectar no `/json/version`. Isso contorna a rejeição do Chrome 120+ a headers de origin.
4. **Identificação de Bloqueios**: Captchas, Cloudflare loops ou 403 Forbidden devem retornar `nil` e agendar retry em 6-12 horas.
