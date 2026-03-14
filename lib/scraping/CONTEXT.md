# Contexto: lib/scraping

Este diretório lida com coleta de dados e scraping (Ferrum + chromedp/headless-shell).

## Regras Críticas de Scraping para IA
1. **Containerização Headless**: O scrape roda obrigatoriamente usando Ferrum, e comunicando via Docker em container isolado de browser (`chromedp/headless-shell`).
2. **Bypass de Docker Host Header**: Essencial para conectar o dev tools endpoint no container. É **OBRIGATÓRIO** realizar requests pro endpoint `/json/version` substituindo localmente o header host: `req["Host"] = "localhost"`. O retorno coletará uma `webSocketDebuggerUrl` cujos IPs internos precisarão ser adaptados para a network docker apropriada.
3. **Identificação de Bloqueios**: Preste atenção se a página retornar Captchas / Cloudflare loops infinitos ou 403 Forbidden. Em caso de bloqueio contínuo, reporte `nil` e desista, deixando a rotina de job retentar em 6 a 12 horas.
