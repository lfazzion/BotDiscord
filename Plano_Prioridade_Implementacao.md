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

---

## 📋 Observações Retroativas — Fase 2 (Pós-Implementação)

*Adições identificadas após revisão de alinhamento. Fase já concluída — itens servem como referência para futuras melhorias no motor de coleta.*

1.  **Seletores Estruturais nos Scrapers:**
    *   NUNCA hardcoded CSS selectors (`a.mdc-basic-feed-item`). Identifique artigos e perfis por propriedades estruturais que sobrevivem a redesigns: agrupamento de links por classe CSS, comprimento médio de slug das URLs do grupo, e tamanhos descritivos de títulos vs links de navegação. Seletor quebrou? O scraper degrada, não morre.
2.  **Graceful Degradation em Cascata:**
    *   Se o scraper falhou (bloqueio, timeout, DOM quebrado), caia em cascata: (1) tentar `og:description` / OpenGraph metadata via HTTP simples; (2) extrair título da URL; (3) registrar como gap no banco com flag `source_degraded: true` para o LLM saber que aquele dado tem qualidade reduzida.
3.  **Stealth Patches no Ferrum (Anti-Bot Detection):**
    *   Injetar JS anti-detecção via CDP `Page.addScriptToEvaluateOnNewDocument` ANTES de qualquer script da página: falsificar `navigator.webdriver = false`, patchar `navigator.plugins`, spoofar WebGL renderer ("NVIDIA GeForce GTX 1080"), e ativar flag `--disable-blink-features=AutomationControlled`.

## 🔍 Observações Pós-Implementação — Fase 6 (Verificações Obrigatórias)

1. **Verificar se os alertas geram ruído excessivo:**
   * Ajustar limiares para evitar flood no Discord admin.
   * Alertas devem sinalizar problema real, não spam operacional.

2. **Confirmar que o Auto-Healing não mascara falhas persistentes:**
   * Se o sistema só alerta e reexecuta, mas nunca marca incidente recorrente, a falha vira dívida invisível.
   * Necessário escalonamento após N ocorrências semelhantes.

3. **Validar integridade do fluxo de backup em banco vivo:**
   * Confirmar que a cópia em ambiente com WAL não gera arquivo inconsistente.
   * Verificar retenção, naming e limpeza de backups antigos.

4. **Testar falha simulada dos containers de coleta:**
   * Derrubar manualmente o container `chrome` / scraper e validar:
     * se o sistema detecta
     * se alerta corretamente
     * se os jobs pendentes não corrompem estado
     * se a retomada ocorre sem duplicidade

5. **Revisar logs da Fase 6 para contexto mínimo útil:**
   * Todo erro operacional precisa indicar pelo menos:
     * job/classe
     * plataforma/fonte
     * profile/post/evento afetado
     * tipo de falha
   * Sem isso, o alerta existe mas a investigação continua cega.

6. **Testar custos indiretos de rotinas opcionais:**
   * A cadeia multimídia opcional precisa ter guarda de custo e execução controlada.
   * Não permitir geração automática em massa sem budget limit ou flag explícita.


## ✅ Fase 7: Validação de Produção e Hardening Operacional (Prioridade P2)

1. **Testes de Restore do Backup (Não basta só copiar o SQLite):**
   * Todo backup gerado precisa ter restore testado periodicamente em ambiente isolado.
   * Validar se o banco restaurado sobe, se as migrations estão consistentes e se as tabelas críticas (`SocialProfile`, `SocialPost`, `ProfileSnapshot`) permanecem íntegras.
   * Backup sem teste de restauração é apenas esperança operacional.

2. **Validação de Idempotência Real dos Workers:**
   * Revisar todos os jobs de coleta, snapshot e discovery para garantir que reprocessamento por retry, timeout ou duplicidade de schedule não gere registros duplicados, snapshots inválidos ou custos redundantes de LLM.
   * Criar checklist técnico para confirmar:
     * deduplicação por janela
     * chaves de cache consistentes
     * uso seguro de `.find_or_initialize_by`
     * tolerância a corrida entre workers concorrentes

3. **Dead Letter / Falha Terminal de Jobs:**
   * Jobs que falharem repetidamente não devem desaparecer em silêncio.
   * Criar fluxo de marcação de falha terminal com contexto mínimo:
     * classe do job
     * profile/post alvo
     * plataforma
     * motivo da falha
     * timestamp
   * Permitir reprocessamento manual posterior.

4. **Rate Limit Ledger por Fonte Externa:**
   * Criar rastreio persistente dos bloqueios por provider/site/API.
   * Registrar:
     * quantidade de 403 / 429
     * última ocorrência
     * cooldown sugerido
     * tipo de coletor afetado (RSS, HTTP, stealth, yt-dlp)
   * Isso evita insistência cega em fontes degradadas e melhora a orquestração futura.

5. **Feature Flags para Coletores Sensíveis:**
   * Todo coletor mais instável ou stealth deve poder ser desligado sem deploy.
   * Flags por fonte, plataforma ou estratégia:
     * `rss_enabled`
     * `stealth_browser_enabled`
     * `llm_discovery_enabled`
     * `image_generation_enabled`
   * Em incidente, o sistema degrada com controle em vez de cair inteiro.

6. **Health Checks por Dependência Crítica:**
   * Não limitar observabilidade ao `/up`.
   * Criar verificações separadas para:
     * banco SQLite em modo WAL
     * fila de jobs
     * container headless/chrome
     * conectividade externa mínima
     * disponibilidade do provedor LLM
   * O sistema pode estar “up” e ainda assim inutilizável.

7. **Runbooks de Incidente:**
   * Documentar passo a passo para os incidentes mais prováveis:
     * Chrome/headless indisponível
     * bloqueio massivo por anti-bot
     * falha no provider LLM
     * crescimento anormal da fila
     * banco SQLite bloqueado
     * restore de emergência
   * O objetivo é reduzir improviso em produção.

## 🧪 Fase 8: Qualidade, Testes e Critérios de Confiabilidade (Prioridade P2)

1. **Suite de Testes para Fluxos Críticos:**
   * Cobrir:
     * coleta e parsing
     * deduplicação
     * snapshots
     * classificação LLM
     * fallback degradado
     * tool calling
   * Priorizar testes de comportamento, não só unitários isolados.

2. **Testes de Contrato para Integrações Externas:**
   * Toda integração com LLM, RSS, GraphQL, yt-dlp ou navegador stealth precisa ter contrato mínimo esperado.
   * Mudou formato de retorno? O teste acusa antes da produção quebrar silenciosamente.

3. **Fixtures Reais de HTML/JSON para Scrapers:**
   * Salvar exemplos reais de páginas e respostas para testar parser sem depender do site estar online.
   * Isso acelera debug e protege contra regressões.

4. **Smoke Tests de Produção Pós-Deploy:**
   * Após deploy, executar checks mínimos automatizados:
     * enqueue de job
     * leitura do banco
     * conexão com headless
     * execução de um coletor simples
     * resposta básica do bot/chat
   * Deploy bem-sucedido não significa sistema funcional.

5. **Teste de Carga Leve em Concorrência:**
   * Validar comportamento com múltiplos jobs simultâneos usando SQLite WAL.
   * Medir:
     * lock contention
     * tempo médio de job
     * saturação do worker
     * crescimento de fila

## 🔐 Fase 9: Segurança Operacional e Governança (Prioridade P2)

1. **Segredos e Rotação Segura:**
   * Garantir que tokens de APIs, chaves LLM e credenciais externas estejam fora do código e com política clara de rotação.

2. **Sanitização de Logs:**
   * Nunca registrar:
     * tokens
     * cookies
     * prompts completos com dados sensíveis
     * payloads integrais de autenticação
   * Logs devem ser úteis sem vazar material crítico.

3. **Rate Limits Internos por Usuário/Canal/Ferramenta:**
   * O bot e o módulo de tools precisam limitar abuso operacional e chamadas excessivas que explodam custo de banco ou LLM.

4. **Permissões por Ferramenta no Tool Calling:**
   * Nem todo comando deve ficar exposto em qualquer contexto.
   * Separar tools:
     * leitura
     * análise
     * ação administrativa
     * rotinas caras

5. **Versionamento de Prompts e Ferramentas:**
   * Sempre que alterar prompt estrutural, schema de tool ou regras do roteador LLM, registrar versão.
   * Facilita rollback sem adivinhação.