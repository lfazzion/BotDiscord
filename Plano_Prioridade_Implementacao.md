# Plano de Prioridade de Implementação: Sistema de Data Mining para Influencers

## 🚀 Fase 1: Fundação do Sistema e Ambiente Dockerizado (Prioridade P0)
*O objetivo aqui é ter o "esqueleto" funcional e tolerante a arquiteturas hostis isoladas (Host Header).*

1.  **Setup Limpo do Rails 8.1 Headless:**
    *   Gerar scaffolding da app em modo `--minimal` (Sem sprockets, ActionView e lixos HTML).
    *   Setup rígido das gems de fila/cache nativo local: **Solid Queue** (jobs assíncronos) e **Solid Cache**.
    *   Ativar obrigatóriamente banco remoto/local em **SQLite3** e transacionar o config para modo **WAL** (Write-Ahead Logging) via initializers para aguentar concorrência extrema de jobs de IO.
2.  **Infraestrutura Docker & O "Host Header Bypass":**
    *   Montar o pipeline `docker-compose.yml` dividindo em workers macro: `app`, `jobs`, `chrome` (imagem chromedp/headless-shell).
    *   **CRÍTICO:** Implementar rotina customizada em Ruby para a alocação de websockets: bater no `/json/version` da porta `9222` da rede injetando manualmente o `req["Host"] = "localhost"` bypassing os logs socat, coletar o ws string sujo, dar replace de host local para host do compose network, e plugar direto dentro dos construtores do headless gem (Ferrum).
3.  **Core Domain - Blindagem Natural:**
    *   Migrates Nucleares: `SocialProfile`, `SocialPost`, `ProfileSnapshot`.
    *   Criação de tipos restritivos SQL: As colunas estatísticas de likes, views NUNCA devem ter set \`default: 0\`. Nullity safety é mandatória no raciocínio base para ferramentas LLM interpretarem gaps e ban limitations de APIs externas corretamente (`nil` !== `0`).
    *   Sinergizar Idempotência pesada utilizando limites de throttle: `SNAPSHOT_DEDUP_WINDOW` de 1 a 2 horas via cache key e calls defensivos na alocação via `.find_or_initialize_by(platform_post_id)` para isolar replicação desnecessária por falhas do scraper repetidas.

## 📡 Fase 2: Motor de Coleta Híbrida Militar (Prioridade P1)
*A coleta em 2026 exige táticas de evasão contra bloqueios duros via TLS Fingerprints e Chromium Developer Tool protocols.*

1.  **Coletores Resilientes Inteligentes (Sem Browsers):**
    *   O bypass base que nunca cai (Regra Reuters): Utilize agregadores RSS (`https://news.google.com/rss/search?q=when:24h+allinurl:site.com`) parseados via REXML nativo do Ruby, isentando você integralmente de desafios Bot e Captcha vindos do Cloudflare/Data Dome frente a scraping de portais nerds do cenário global de cultura.
    *   Acoplar chamadas limpas executáveis via subshell a binários otimizados abertos, ex: `yt-dlp` varrendo IDs de canais Youtube da cena.
2.  **Stealth Scrapers Customizados p/ SPAs Inevitáveis:**
    *   Ao focar em sites vitrificados pelas big-techs (ex: Instagram / X), as instâncias do Ferrum com header sujo natural irão banir blocos IP. Acople microservicos (via scripts em Python chamados ou local service via socket) consumindo APIs stealth como o **Nodriver** (interação em SPAS sem dependência do problemático `Runtime.enable` root CDP) ou navegadores anti-detecção como **Camoufox**.
    *   Injete Spoofing de alto nível nas rest calls diretas que o Rails fará externalizando tráfego de API, abraçando wraps em Ruby tipo o `curl-impersonate` (ou em python `curl_cffi`) forçando fingerprints de JA3/HTTP2/TLS como se todo packet ruby adviesse de um user-agent purista em Firefox ou Safari macOC legitimo.
    *   (Futuro) Prepare túnel e configs prontas para integração de Proxies residenciais de alta estamiria Mobile (roteando pacotes 4G p/ bypasses IP).
3.  **Rate limits Handling - Engula Quietamente:**
    *   O Rescue nativo dos workers Rails tem que identificar HTTP `RateLimit` e `403`. **NUNCA** deixe o framework rodar retries clássicos em exponencias em janelas curtas para proxies, ou ele aniquilará a confiabilidade do proxy-pool. Deu erro: rescue em silêncio, aborte erro como warning de logger local, e insira job schedule com offset de atraso altíssimo (a partir de 6 horas estáticas). 

## 🧠 Fase 3: O Cérebro Inteligente - Multi LLM (Prioridade P1)
*Montando a capacidade orgânica de avaliação do sistema.*

1.  **Orquestrador de IA de Ponta:**
    *   Criar módulo Router que fará proxy e escolhas transacionais de qual LLM usar para otimização do projeto.
    *   Bifurcação padrão: **Gemini 3.1 Flash Lite** isolado em background workers que demandem alta captação de tokens de mining ou Discovery; **Gemma 3 27B / Claude 3.5 via OpenRouter** na linha da frente para Chat dinâmicos sem tempo de espera. 
2.  **Repositório YAML Estrutural (Prompts System):**
    *   Puxar todo prompt em plain text das sub-classes e subir para layouts em `config/prompts/`.
    *   Incluir macros em `ERB` cru ou Liquid para embutir fragmentos compartilhados (regra do Never Invent, do Null vs Zero) em conjunto com a injeção fatalística de timestamp string `<current_datetime: Time.Current>` nos base-systems, matando alucinações de agenda que modelos pre-treinados costumam carregar.
3.  **Pipeline Autônomo de Tracking e Discovery:**
    *   Background Job de caça de dados focado em descer a árvore social da Influencer. Ler array de menções textuais `@` publicadas e comentários hiper-rankados da última quinzena.
    *   Coletou handles potenciais? Envie a URL de profile + bios/posts para LLM Classificatório formatar em array fixo: enum DB [`CONCORRENTE`, `PATROCINADOR_PROSPECTO`, `IGNORAR`].

## 🏛️ Fase 4: O Oracle e Sensibilidade de Mercado (Prioridade P2)
*O banco de dados nativo sabe do micro. O Oracle é o radar de contexto macro do planeta terra que o LLM precisa enxergar.*

1.  **Datalake Externo:**
    *   Rotinas schedulers semanais que coletam catálogos limpos abertos: TMDB para datas de Cinema e Séries ocidentais, IGDB para video-games do nicho Gamer Twitcher, e API do Anilist em calls simples em GraphQL para animes de temporada.
2.  **Aggregator de Agenda:**
    *   Scraping RSS contínuo de pautas (Regra Reuters) centralizando datas flutuantes de eventos nerds globais e nacionais massivos do Brasil (BGS, Anime Friends, CCXP) populando tabelas de Eventos Base.

## 💬 Fase 5: UI Autônoma e Chatbot Tool Caller (Prioridade P2)
*Acesso universal sem painéis de BI via linguagem natural de humano em 2026.*

1.  **Discord Bot Base:**
    *   Adicionar gem `discordrb`. Focar em setup resiliente com flags visuais no frontend (typing delay "processando..." "Puxando banco...").
2.  **O Módulo de Ferramentas / Tool Calling Profissional (Core Business):**
    *   Integrar APIs de controle tipo `RubyLLM` (com compatibilidade MCP / tools definition strict).
    *   Escrever mais de 40+ comandos em classes isoladas.
    *   **Regras Críticas no Código LLM Tool:**
        *   Cada classe Ferramenta retorna **somente Hashes/Arrays** puros. Zero formatação estetica string base, force a IA a mastigar os dados matematicos via raw json.
        *   **Clamping (Clamp Silencioso):** Em métodos ruby injete limites rígidos forçados com `Math.min/max`: ex `[ [{param[:limit].to_i}, 1].max, 50].min` assegurando que se o LLM alucinar offsets impossiveis pedindo 10 mil posts, ele só quebre no cap definido (50) ao inves de sobrecarregar o ActiveRecord no Host.
        *   Não use instâncias de `raise X.exception()`. Todas as queries falhas, accounts faltantes e empty arrays devem sair do def como `{status: error, reason: "Dados ausentes"}`. Devolva cordialmente erros internos empacotados pro contexto reflexível local da IA rodar o fallback lógico iterativo sobre ela mesma perfeitamente.
3.  **Provisão Ativa Diária - O "The Flow" Digests:**
    *   A automação da rotina e saúde mental da Influencer não depende dela perguntar, depende do bot mandar reports proativos em blocos da semana (Via jobs com delays cron). (Ex: Segunda-Desempenho Semanal. Sexta-Ideação Base futura). 

## 🛠️ Fase 6: Lapidação e Operação Segura (Prioridade P3)

1.  **Monitoramento Básico e Visão Macro:**
    *   Ativação da rota simples `/up` (Built-in do Rails 8). Tratamento em console log stream de falhas nos nodes dos workers de proxy.
2.  **Auto-Healing Reports:**
    *   Workers que disparam alertas num Channel admin do Discord na exata hora em que um container de scrapping Camoufox / parser base reportar descompasso violento na quebra de nodes DOM (Sites que viraram o Front-end e baniram a hierarquia de Classes CSS temporariamente do Web Scraper Base).
3.  **Cadeia Multimidia Opcional:**
    *   Testes isolados em chamadas Gemini Imagen 3/DALL-E criando assets bases, gerando imagens inspiracionais de thumbs e moodboards a partir das descrições analisadas do concorrente p/ agregar nos Digests p/ influenciadora.
4.  **A Backup Simples de Um Banco Simples:**
    *   Jobs shell que invocam `cp` nas pastilhas absolutas `/data/*.sqlite3` copiando p/ volumes protegidos cloud. (Garantia por rodar WAL em modo de cópia resilientes live). Mantenha `credentials.yml.enc` e a master.key trancadas num gerenciador de secrets à parte da máquina rodando.
