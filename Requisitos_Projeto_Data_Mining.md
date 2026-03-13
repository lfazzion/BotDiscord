# Requisitos e Brainstorming: Sistema de Data Mining para Influencers

## 1. Visão Geral da Arquitetura
O sistema é um **Rails 8 Headless**, focado em processamento de fundo e integração com APIs, projetado para ser resiliente às restrições modernas de web scraping de 2026 (ataques à CDP, DataDome, Cloudflare).

- **Stack Técnica:**
  - **Framework:** Rails 8.1 (Solid Queue para jobs, Solid Cache).
  - **Banco de Dados:** SQLite3 em produção (WAL mode) via bind mount no Docker.
  - **Interface:** Chatbot Discord (`discordrb`). Sem interface web (apenas health check `/up`).
  - **Automação/Scraping:** Uma combinação híbrida de `Ferrum` (Ruby) + Headless Chrome (`chromedp/headless-shell`), com integrações externas/microsserviços em Python (ex: `Nodriver` ou `Camoufox`) para contornar proteções avançadas onde o CDP padrão é detectado.
  - **AI/LLM:** Interface principal via gems modernas como `RubyLLM` ou `llm.rb` integradas ao OpenRouter, Gemini 3.1 Flash Lite e Gemma 3 27B.

---

## 2. Componentes Principais

### A. Coleta e Scraping (Back-end) - O Cenário de Defesa em 2026
Em 2026, web scraping convencional de SPAs falha em sistemas como DataDome, Cloudflare Turnstile e PerimeterX devido a verificações rigorosas de CDP (Chrome DevTools Protocol) e análises de TLS Fingerprinting.

- **Estratégia de Scraping Resiliente:**
  - **A "Regra Reuters" (Nunca raspe se puder evitar):** Anti-bots verificam CDP (ex: via bloqueio de `Runtime.enable`). Ao invés de lutar contra o DataDome de portais de notícias ou grandes sites, consuma dados de fontes abertas paralelas. Utilize o **Google News RSS** (`https://news.google.com/rss/search?q=when:24h+allinurl:site.com`). É imune a detectores, sem JS, rápido e altamente estável.
  - **Stealth Browsers para SPAs Irredutíveis:** O Chrome headless padrão será inevitavelmente detectado pelo `navigator.webdriver`. Utilize soluções modernas: **Nodriver** (interação sem CDP cru), **Camoufox** (build modificado anti-detecção), ou **SeleniumBase UC Mode**. Esses exigirão scripts sidecar em Python orquestrados pelo Ruby.
  - **Spoofing de TLS/HTTP/2:** Anti-bots analisam o handshake TLS (JA3/JA4 fingerprints). O `Net::HTTP` nativo do Ruby acusa que você é um bot. Se precisar fazer chamadas simples, utilize wrappers como o `curl-impersonate` para espelhar fingerprints de navegadores reais sem abrir um browser inteiro.
  - **Redes Móveis (Proxies):** IP reputation é rei. Datacenters (AWS, DigitalOcean) disparam Turnstiles na hora. Para tráfego contínuo nas redes das influenciadoras, use proxies residenciais ou 4G/5G mobile proxies, mantendo `sticky sessions` para simular navegação contínua de um humano real. O tráfego precisa ter timeouts aleatórios assemelhando-se a comportamento humano.

- **Idempotência no DB:** Todo job em backend deve aceitar rodar repetidas vezes com métodos de safe guard (ex: `find_or_initialize_by(platform_post_id)`) no Rails para não inflar métricas indevidamente em caso de falha transitória do worker.
- **Snapshot Dedup Window:** Ignorar tentativas de atualizar métricas orgânicas (followers/likes) em janelas de menos de 1 hora.

### B. O Oracle (Contexto Externo)
Dados isolados ("postou sobre anime X") são inúteis sem o hiper-contexto: por que aquele assunto hypou hoje? O "Oracle" preenche esse gap de contexto base do LLM.
- **Rastreador de Eventos:** Database local de eventos geeks (CCXP, Anime Friends, BGS) e suas contagens regressivas/relevância anual.
- **Rastreador de Lançamentos:** Consultar via jobs o TMDB (Filmes/Séries em Free-tier), IGDB API via Twitch Developer, e AniList (GraphQL livre).
- **Rastreador de News Diárias:** Ingestion do Google News RSS mencionado acima. Nenhuma barreira anti-bot enfrentada.

### C. Discovery Pipeline (Mineração Autônoma de Novos Perfis)
- O sistema varre comentários de alta interação, menções nos posts e perfis citados nas Bios/Linktrees da influenciadora.
- Ao encontrar um novo handle, emite um Prompt Assíncrono para o LLM pedindo classificação. O modelo lê o escopo e decide salvar o candidato no banco como: `concorrente`, `patrocinador_prospecto`, ou `irrelevante`.

---

## 3. Interface e Experiência do Usuário

- **Chatbot Discord (Voice of God):** Um bot integrado para facilitar entrada de quem não é técnica de dados. Esqueça gráficos e UI, é sobre perguntas em texto natural respondidas com base científica. ("O que devo gravar para YouTube esta semana baseada no TikTok concorrente?").
- **Digest Diários Inativos (Push-based):**
  - O sistema envia resumos madrugadas adentro (Programados por CRON no Solid Queue):
    - Segunda: Relatório da Semana que Passou
    - Terça: Check-up de Concorrentes Diretos
    - Quarta: Ideações criativas (O Playbook)
    - Quinta: Pitch para agências de publicidade baseado em eventos futuros
    - Sexta: Plano Estrutural
- **LLM Tool Calling API:** A "alma" da magia. Integração com um orquestrador forte onde o Discord envia a query à IA, que seleciona entre 40+ ferramentas Ruby (classes que efetuam queries locais) para formatar e entregar a resposta em tempo real.

---

## 4. Dicas e Arquitetura de Ponta (O que um Agente de Software deve Garantir)

### 4.1. O Truque Cíclico: Host Header Bypass (Docker Chrome)
O container `chromedp/headless-shell` é usado isoladamente. Ele sobe atrás de um proxy `socat` na porta 9222 que recusa bloqueantemente um Header HTTP `Host` que não seja estritamente um IP ou `localhost`.
- **Implementação Crucial:** Antes de dar `.new` no Ferrum, você precisa fazer um request isolado da biblioteca padrão HTTP do Ruby para a rota `/json/version` no container de Chrome forjando explicitamente: `req["Host"] = "localhost"`.
- Analise a key `webSocketDebuggerUrl` do JSON de retorno (ela voltará apontando local pro container: `ws://127.0.0.1:9222/...`). Capture essa URI, troque `127.0.0.1` pelo host do compose interno da sua rede Docker (ex: `chrome`) e passe a WSS completa na instância de setup do Ferrum. Esta gambiarra salva projetos de baterem de frente em Error Connections.

### 4.2. Segurança e Boas Práticas do LLM Tool Calling (2026)
- **Não Retorne Formatações de Texto:** As Tools devem fazer consultas ORM no banco e devolver Hashes ou Arrays em JSON bem formados com dados brutos. O Modelo LLM possui excelência nativa em "pretty print" para conversa natural; pare de usar `to_s` hardcoded nas ferramentas.
- **Clamping Obbligatório:** LLMs erram escopos. Se sua Tool tem um offset limite de 50 posts, nunca deixe o parametro vindo cru do LLM rodar. Intercepte e limpe via `amount = [[argument_llm.to_i, 1].max, 50].min`.
- **Zero Exceções (Safe Response):** Se a tool falhar (ex: perfis nulos na Base), NUNCA dê um `.raise`. O backtrace derruba o fluxo do Agente LLM. No bloco `.execute` de cada ferramenta retorne uma flag amigável tipo `{success: false, message: "A query retornou vazio. Informe o usuário de forma amigável."}`. Isso forçará o mecanismo Chain-of-Thought (Raciocínio) do LLM a se adaptar, ao invés de crashar a ponte Ruby/API do Discord.
- **Tipagem Declarativa:** Exija parâmetros estritamente documentados via DSL das gemas `RubyLLM` (ex. `param :user, type: :string, desc: 'Handle obrigatorio', required: true`).

### 4.3. Nil vs Zero: O Caos Matemático da Análise de Dados
- Se a API bloqueou, omitiu por rate limit, ou se a conta do insta não expõe dislikes: Você salva como **NULL** (`nil`) no SQLite3.
- NUNCA submeta zeros como bypass padrão em views/likes do banco. `0` causa um colapso lógico do raciocínio LLM, sinalizando que a influencer gerou 0% de engajamento, alterando todo os alertas prospectivos do projeto e gerando pânico alucinado para a usuária.
- As Tools que varrem isso no DB devem purgar/filtrar `.compact` nestes campos antes de servir a média ao modelo.

### 4.4. Controle de Inconsistências de Tempo Prompts de YAML
- Organismo: Prompts salvos externamente na árvore Rails em `config/prompts/`. Uso de snippets re-utilizáveis para restrições globais como YAML extensions.
- Injection do Relógio: LLMs são desconexos da Matrix de tempo atual. Seus prompts base OBRIGATORIAMENTE têm que concatenar dinamicamente o campo absolutista `<current_datetime: <%= Time.current.in_time_zone("America/Sao_Paulo").to_s %>>`. Sem isto, "busque evento na quarta que vem" quebrará o banco.

### 4.5. Silenciamento de Block/Errors no Scraper
- Erro 403 / Captchas / Ban por Rate-Limit (Frequentemente causados pelo Turnstile em excesso). O pior erro que um agente programador pode escrever é um loop persistente para re-tentativas imediatas no Catch do Worker.
- Rescue total, logger limpo e descarte do job com `set backoff` futuro para pelo menos 6h-12h para a frente para "limpar a reputação" de cooldown dos Proxies residenciais em uso.

---

## 5. Custo Zero Para Kick-Start de Desenvolvimento

Se optar por iniciar sem alugar Scraper APIs e Servidores Dedicados:
- **Para Evitar APIs caras:**
  - YouTube Data via sub-process em background de `yt-dlp` que roda binários em Go livres de bloqueio contínuio.
  - Instagram via `instaloader` modularizado isolado. O X/Twitter por portais de espelho ou feeds nitter.
- **Models API Limit:** Usufruir extensos Free-Tier do Gemini 3.1 Flash Lite. Testes com Llama 3 via `Groq` API para latências impossivelmente rápidas gratuitas nas respostas diárias e `Ollama` para varrer processamento sem rate limit na nuvem durante o job de Data Discovery em batch do banco.
- Tudo coberto pela infra de Docker-Compose/SQLite Wal em VPS Oracle Cloud free-tier por exemplo para MVP primário limitador de custos ao criador e testador.
