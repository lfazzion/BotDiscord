# Plano de Prioridade de Implementação: Sistema de Data Mining para Influencers

## 🚀 Fase 1: Fundação e Ambiente (Prioridade P0)
*O objetivo aqui é ter o "esqueleto" funcional e o ambiente de desenvolvimento isolado.*

1.  **Setup do Rails 8.1 Headless:**
    *   Gerar o projeto com `--minimal` (sem ActionVew, sem sprockets, etc).
    *   Configurar **Solid Queue** (jobs) e **Solid Cache**.
    *   Habilitar **SQLite3** em modo **WAL** para suportar concorrência.
2.  **Conteinerização (Docker Compose):**
    *   Serviço `app` (Rails).
    *   Serviço `jobs` (Worker do Solid Queue).
    *   Serviço `chrome` (`chromedp/headless-shell`).
3.  **Core Domain Models:**
    *   Modelos base: `SocialProfile`, `SocialPost`, `ProfileSnapshot`.
    *   Implementar a lógica de **Idempotência**:
        *   `find_or_initialize_by(platform_post_id)` para evitar duplicatas.
        *   `SNAPSHOT_DEDUP_WINDOW = 1.hour` para limitar coletas excessivas.

## 📡 Fase 2: Motor de Coleta Gratuito (Prioridade P1)
*Implementar a captação de dados brutos sem custos de API.*

1.  **Ferramentas Locais de Scraping:**
    *   Integrar **yt-dlp** para metadados de YouTube.
    *   Integrar **Instaloader** (via script Python) para Instagram.
    *   Usar **snscrape** ou **RapidAPI Free** para X (Twitter).
2.  **Scraping Customizado (Ferrum):**
    *   Utilizar Ferrum + Headless Chrome para sites que não possuem wrappers específicos.
    *   Manter o `discover_ws_url` para bypass de Host Header.
3.  **Resiliência e Normalização:**
    *   Lógica de `find_or_initialize_by` e `SNAPSHOT_DEDUP_WINDOW` obrigatórios para evitar re-processamento caro em ferramentas limitadas por IP.
    *   Normalização rigorosa de `Nil vs Zero`.

## 🧠 Fase 3: O Cérebro - IA Gratuita (Prioridade P1)
*IA de ponta sem custo mensal.*

1.  **Setup Gemini 1.5 Flash (Free Tier):**
    *   Configurar API Key do Google AI Studio.
    *   Implementar cliente generativo para extração de insights e classificação.
2.  **Gestão de Prompts (YAML System):**
    *   Criar diretório `config/prompts/`.
    *   Implementar sistema de snippets reutilizáveis (ex: `nil_vs_zero.yml`, `market_context.yml`).
3.  **Discovery Pipeline:**
    *   Job para minerar novos perfis baseados em menções e comentários.
    *   Uso do LLM para classificação prévia (concorrente, marca, irrelevante).
4.  **Scoring e Classificação:**
    *   Implementar lógica de cálculo de posts: `viral`, `acima da média`, `flop`.

## 🏛️ Fase 4: O Oracle - Contexto Externo (Prioridade P2)
*Dar ao sistema a capacidade de entender o mundo fora das redes.*

1.  **APIs de Cultura Geek:**
    *   Integrar **TMDB** (Filmes/Séries), **IGDB** (Games), **AniList** (Animes).
2.  **News Tracker:**
    *   Scraper de RSS para portais de notícias.
3.  **Event Tracker:**
    *   Base de dados de convenções (CCXP, BGS, Anime Friends) com datas e relevância.

## 💬 Fase 5: Interface e Chatbot (Prioridade P2)
*Como o usuário consome a informação.*

1.  **Chatbot Discord (`discordrb`):**
    *   Implementar o bot como interface principal.
2.  **Tool Calling (O Grande Diferencial):**
    *   Desenvolver 40+ ferramentas Ruby que permitem ao LLM consultar o SQLite.
    *   Implementar **Clamping** nas ferramentas (ex: `limit` máximo de 50) para evitar estouro de contexto.
3.  **Digests Diários (The Flow):**
    *   **Segunda:** Performance semanal.
    *   **Terça:** Radar de concorrentes.
    *   **Quarta:** Tendências/Conteúdo.
    *   **Quinta:** Marcas e Pricing.
    *   **Sexta:** Planejamento.

## 🛠️ Fase 6: Refinamento e Operação (Prioridade P3)
*Manutenção e visualização.*

1.  **Monitoramento:**
    *   Dashboard simples de Health Check (`/up`).
    *   Logs detalhados de jobs falhos.
2.  **Geração de Imagens:**
    *   Integração com Gemini/DALL-E para gerar artes de posts sugeridos.
3.  **Backup e Segurança:**
    *   Scripts de backup (`cp`) do SQLite.
    *   Gestão de secrets (Rails Credentials).

---

> [!IMPORTANT]
> **Dica de Ouro:** Não comece pela arquitetura. Sente com quem vai usar e defina os problemas reais (como o `IDEA.md`). O código deve ser escravo da necessidade, não o contrário.
