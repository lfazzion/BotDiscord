# Requisitos e Brainstorming: Sistema de Data Mining para Influencers

## 1. Visão Geral da Arquitetura
O sistema é um **Rails 8 Headless**, focado em processamento de fundo e integração com APIs.

- **Stack Técnica:**
  - **Framework:** Rails 8.1 (Solid Queue para jobs, Solid Cache).
  - **Banco de Dados:** SQLite3 em produção (WAL mode) via bind mount no Docker.
  - **Interface:** Chatbot Discord (`discordrb`). Sem interface web (apenas health check `/up`).
  - **Automação/Scraping:** `Ferrum` (Ruby) + Headless Chrome (`chromedp/headless-shell`).
  - **AI/LLM:** `RubyLLM` integrado via OpenRouter (Claude 3.5 Sonnet, Grok).

---

## 2. Componentes Principais

### A. Coleta e Scraping (Back-end)
- **Fontes:** Instagram, YouTube, X (Twitter).
- **Estratégia:** 
  - Uso do **Apify** como fonte primária (API paga) para maior confiabilidade.
  - Scraping local via Ferrum/Chrome como fallback.
- **Idempotência:** Todo job deve ser capaz de rodar múltiplas vezes sem duplicar dados (`find_or_initialize_by`).
- **Snapshot Dedup Window:** Ignorar novas coletas de métricas (followers/likes) se o último snapshot foi há menos de 1 hora.

### B. O Oracle (Contexto Externo)
Dados puros não são úteis sem o "porquê".
- **Tracking de Eventos:** CCXP, Anime Friends, BGS. Datas, locais e mudanças bruscas.
- **Lançamentos:** TMDB (filmes/séries), IGDB (jogos/Twitch), AniList (animes).
- **Datas Comemorativas:** Feriados brasileiros e aniversários de franquias.
- **News:** Scraping de RSS e X/Twitter a cada 6 horas.

### C. Discovery Pipeline (Mineração de Novos Perfis)
- Busca autônoma por novos criadores e marcas.
- **Lógica:** Analisar menções em posts, comentários com alto engajamento e links em bios/Linktree de perfis já rastreados.
- **Validação:** LLM avalia se o candidato é concorrente, patrocinador ou irrelevante antes de iniciar o tracking automático.

---

## 3. Interface e Experiência do Usuário (Chatbot)
- **Discord como UI:** Facilita o acesso rápido onde a usuária já está.
- **Digests Diários (9h da manhã):**
  - **Segunda:** Performance semanal.
  - **Terça:** Radar de concorrentes.
  - **Quarta:** Playbook de conteúdo/tendências.
  - **Quinta:** Oportunidades de marcas/pricing.
  - **Sexta:** Planejamento da próxima semana.
- **Tool Calling:** O LLM tem acesso a 40+ ferramentas Ruby que consultam o banco e retornam dados estruturados (Hashes/Arrays).

---

## 4. Dicas e "Pulos do Gato" (Destaques Técnicos)

### Host Header Bypass (Docker Chrome)
O container `headless-shell` rejeita conexões que não sejam `localhost`.
- **Truque:** Forjar o header `Host: localhost` no request inicial em `/json/version` para obter a URL do WebSocket e então reescrever o IP para o nome do serviço no Docker Compose.

### Nil vs Zero
- **Conceito:** `nil` = dado não disponível; `0` = dado confirmado como zero.
- **Importância:** Se tratar `nil` como `0`, o LLM tirará conclusões erradas (ex: "ninguém compartilha seus posts" quando na verdade a API apenas não retorna essa métrica).

### Prompt Management
- Todos os prompts em arquivos **YAML**.
- Uso de **Includes/Snippets** (ex: `null_vs_zero.yml`, `never_invent.yml`) para evitar inconsistências entre diferentes comandos do bot.

### Gestão de Erros de Scraping
- Erros de rede/banco: Retry com backoff polinomial.
- **BlockedError/RateLimitError:** Devem ser "engolidos" silenciosamente. Retentar imediatamente só piora o bloqueio; é melhor esperar o próximo ciclo agendado.

### Clamping e Normalização
- O LLM costuma errar parâmetros (ex: pedir `limit: 100` num limite de `50`).
- **Solução:** Aplicar clamping silencioso (`[[val.to_i, 1].max, 50].min`) em todas as ferramentas.

---

## 5. Manutenção e Produção
- **Jobs Agendados (25+):** Distribuídos durante a madrugada para evitar sobrecarga.
- **Time Management:** Injetar sempre o `current_datetime` no prompt para evitar alucinações de datas relativas ("amanhã").
- **Backup:** Simples `cp` dos arquivos `.db` do SQLite, por estar em WAL mode e bind mount.

---

## 6. Alternativas Gratuitas para Desenvolvimento Inicial

Para iniciar o projeto sem custos de API, recomenda-se substituir os serviços pagos pelas seguintes alternativas:

### A. Alternativas ao Apify (Scraping)
O Apify é robusto, mas pago. Para o início:
- **YouTube:** Usar a biblioteca `yt-dlp` (gratuita e open-source) para extrair metadados e informações de vídeos.
- **Instagram:**
  - `instaloader` (Python): Excelente para baixar posts, perfis e metadados sem custo.
  - `instagrapi` (Python): Permite simular a API privada do Instagram (usar com cautela para evitar bans).
- **X (Twitter):**
  - `snscrape`: Embora instável recentemente, ainda é uma opção para busca histórica sem API key.
  - **RapidAPI:** Existem scrapers de Twitter com tier gratuito (ex: 50-100 requests/mês) que podem servir de base.
- **Scraping Customizado:** Manter o uso do `Ferrum` + `Headless Chrome` (já gratuito) como o artigo sugere.

### B. Alternativas ao OpenRouter/LLMs Pagos
- **Google Gemini API:** Atualmente oferece um tier gratuito generoso (ex: Gemini 1.5 Flash com 15 RPM e 1 milhão de tokens por minuto).
- **Groq:** Oferece acesso gratuito a modelos como Llama 3 e Mistral com latência baixíssima (ideal para o chatbot responder rápido).
- **Mistral AI:** Possui um tier "La Plateforme" com limites razoáveis para testes.
- **Ollama:** Se tiver hardware local, permite rodar Llama 3 ou Mistral localmente, eliminando custos e limites de rede.

### C. Dados de Cultura Geek (APIs com Free Tier)
- **Filmes/Séries:** [TMDB API](https://www.themoviedb.org/documentation/api) - Gratuito para uso não comercial.
- **Games:** [IGDB API](https://api-docs.igdb.com/) - Gratuito (requer conta de desenvolvedor Twitch).
- **Animes:** [AniList API](https://anilist.gitbook.io/anilist-apiv2-docs/) - Gratuito via GraphQL.
- **Notícias:** Utilizar feeds **RSS** diretamente de portais como Jovem Nerd, Omelete e IGN, que são gratuitos por natureza.

### D. Infraestrutura
- **SQLite + Docker Compose:** Já são 100% gratuitos e rodam localmente ou em uma VPS barata (ex: Oracle Cloud Free Tier).
