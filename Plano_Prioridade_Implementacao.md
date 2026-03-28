# Plano de Prioridade de Implementa��o: Sistema de Data Mining para Influencers

## ?? Fase 1: Funda��o do Sistema e Ambiente Dockerizado (Prioridade P0)
*O objetivo aqui � ter o "esqueleto" funcional e tolerante a arquiteturas hostis isoladas (Host Header).*

1.  **Setup Limpo do Rails 8.1 Headless:**
    *   Gerar scaffolding da app em modo `--minimal` (Sem sprockets, ActionView e lixos HTML).
    *   Setup r�gido das gems de fila/cache nativo local: **Solid Queue** (jobs ass�ncronos) e **Solid Cache**.
    *   Ativar obrigat�riamente banco remoto/local em **SQLite3** e transacionar o config para modo **WAL** (Write-Ahead Logging) via initializers para aguentar concorr�ncia extrema de jobs de IO.
2.  **Infraestrutura Docker & O "Host Header Bypass":**
    *   Montar o pipeline `docker-compose.yml` dividindo em workers macro: `app`, `jobs`, `chrome` (imagem chromedp/headless-shell).
    *   **CR�TICO:** Implementar rotina customizada em Ruby para a aloca��o de websockets: bater no `/json/version` da porta `9222` da rede injetando manualmente o `req["Host"] = "localhost"` bypassing os logs socat, coletar o ws string sujo, dar replace de host local para host do compose network, e plugar direto dentro dos construtores do headless gem (Ferrum).
3.  **Core Domain - Blindagem Natural:**
    *   Migrates Nucleares: `SocialProfile`, `SocialPost`, `ProfileSnapshot`.
    *   Cria��o de tipos restritivos SQL: As colunas estat�sticas de likes, views NUNCA devem ter set \`default: 0\`. Nullity safety � mandat�ria no racioc�nio base para ferramentas LLM interpretarem gaps e ban limitations de APIs externas corretamente (`nil` !== `0`).
    *   Sinergizar Idempot�ncia pesada utilizando limites de throttle: `SNAPSHOT_DEDUP_WINDOW` de 1 a 2 horas via cache key e calls defensivos na aloca��o via `.find_or_initialize_by(platform_post_id)` para isolar replica��o desnecess�ria por falhas do scraper repetidas.

## ?? Fase 2: Motor de Coleta H�brida Militar (Prioridade P1)
*A coleta em 2026 exige t�ticas de evas�o contra bloqueios duros via TLS Fingerprints e Chromium Developer Tool protocols.*

1.  **Coletores Resilientes Inteligentes (Sem Browsers):**
    *   O bypass base que nunca cai (Regra Reuters): Utilize agregadores RSS (`https://news.google.com/rss/search?q=when:24h+allinurl:site.com`) parseados via REXML nativo do Ruby, isentando voc� integralmente de desafios Bot e Captcha vindos do Cloudflare/Data Dome frente a scraping de portais nerds do cen�rio global de cultura.
    *   Acoplar chamadas limpas execut�veis via subshell a bin�rios otimizados abertos, ex: `yt-dlp` varrendo IDs de canais Youtube da cena.
2.  **Stealth Scrapers Customizados p/ SPAs Inevit�veis:**
    *   Ao focar em sites vitrificados pelas big-techs (ex: Instagram / X), as inst�ncias do Ferrum com header sujo natural ir�o banir blocos IP. Acople microservicos (via scripts em Python chamados ou local service via socket) consumindo APIs stealth como o **Nodriver** (intera��o em SPAS sem depend�ncia do problem�tico `Runtime.enable` root CDP) ou navegadores anti-detec��o como **Camoufox**.
    *   Injete Spoofing de alto n�vel nas rest calls diretas que o Rails far� externalizando tr�fego de API, abra�ando wraps em Ruby tipo o `curl-impersonate` (ou em python `curl_cffi`) for�ando fingerprints de JA3/HTTP2/TLS como se todo packet ruby adviesse de um user-agent purista em Firefox ou Safari macOC legitimo.
    *   (Futuro) Prepare t�nel e configs prontas para integra��o de Proxies residenciais de alta estamiria Mobile (roteando pacotes 4G p/ bypasses IP).
3.  **Rate limits Handling - Engula Quietamente:**
    *   O Rescue nativo dos workers Rails tem que identificar HTTP `RateLimit` e `403`. **NUNCA** deixe o framework rodar retries cl�ssicos em exponencias em janelas curtas para proxies, ou ele aniquilar� a confiabilidade do proxy-pool. Deu erro: rescue em sil�ncio, aborte erro como warning de logger local, e insira job schedule com offset de atraso alt�ssimo (a partir de 6 horas est�ticas). 

## ?? Fase 3: O C�rebro Inteligente - Multi LLM (Prioridade P1)
*Montando a capacidade org�nica de avalia��o do sistema.*

1.  **Orquestrador de IA de Ponta:**
    *   Criar m�dulo Router que far� proxy e escolhas transacionais de qual LLM usar para otimiza��o do projeto.
    *   Bifurca��o padr�o: **Gemini 3.1 Flash Lite** isolado em background workers que demandem alta capta��o de tokens de mining ou Discovery; **Gemma 3 27B / Claude 3.5 via OpenRouter** na linha da frente para Chat din�micos sem tempo de espera. 
2.  **Reposit�rio YAML Estrutural (Prompts System):**
    *   Puxar todo prompt em plain text das sub-classes e subir para layouts em `config/prompts/`.
    *   Incluir macros em `ERB` cru ou Liquid para embutir fragmentos compartilhados (regra do Never Invent, do Null vs Zero) em conjunto com a inje��o fatal�stica de timestamp string `<current_datetime: Time.Current>` nos base-systems, matando alucina��es de agenda que modelos pre-treinados costumam carregar.
3.  **Pipeline Aut�nomo de Tracking e Discovery:**
    *   Background Job de ca�a de dados focado em descer a �rvore social da Influencer. Ler array de men��es textuais `@` publicadas e coment�rios hiper-rankados da �ltima quinzena.
    *   Coletou handles potenciais? Envie a URL de profile + bios/posts para LLM Classificat�rio formatar em array fixo: enum DB [`CONCORRENTE`, `PATROCINADOR_PROSPECTO`, `IGNORAR`].

## ??? Fase 4: O Oracle e Sensibilidade de Mercado (Prioridade P2)
*O banco de dados nativo sabe do micro. O Oracle � o radar de contexto macro do planeta terra que o LLM precisa enxergar.*

1.  **Datalake Externo:**
    *   Rotinas schedulers semanais que coletam cat�logos limpos abertos: TMDB para datas de Cinema e S�ries ocidentais, IGDB para video-games do nicho Gamer Twitcher, e API do Anilist em calls simples em GraphQL para animes de temporada.
2.  **Aggregator de Agenda:**
    *   Scraping RSS cont�nuo de pautas (Regra Reuters) centralizando datas flutuantes de eventos nerds globais e nacionais massivos do Brasil (BGS, Anime Friends, CCXP) populando tabelas de Eventos Base.

## ?? Fase 5: UI Aut�noma e Chatbot Tool Caller (Prioridade P2)
*Acesso universal sem pain�is de BI via linguagem natural de humano em 2026.*

1.  **Discord Bot Base:**
    *   Adicionar gem `discordrb`. Focar em setup resiliente com flags visuais no frontend (typing delay "processando..." "Puxando banco...").
2.  **O M�dulo de Ferramentas / Tool Calling Profissional (Core Business):**
    *   Integrar APIs de controle tipo `RubyLLM` (com compatibilidade MCP / tools definition strict).
    *   Escrever mais de 40+ comandos em classes isoladas.
    *   **Regras Cr�ticas no C�digo LLM Tool:**
        *   Cada classe Ferramenta retorna **somente Hashes/Arrays** puros. Zero formata��o estetica string base, force a IA a mastigar os dados matematicos via raw json.
        *   **Clamping (Clamp Silencioso):** Em m�todos ruby injete limites r�gidos for�ados com `Math.min/max`: ex `[ [{param[:limit].to_i}, 1].max, 50].min` assegurando que se o LLM alucinar offsets impossiveis pedindo 10 mil posts, ele s� quebre no cap definido (50) ao inves de sobrecarregar o ActiveRecord no Host.
        *   N�o use inst�ncias de `raise X.exception()`. Todas as queries falhas, accounts faltantes e empty arrays devem sair do def como `{status: error, reason: "Dados ausentes"}`. Devolva cordialmente erros internos empacotados pro contexto reflex�vel local da IA rodar o fallback l�gico iterativo sobre ela mesma perfeitamente.
3.  **Provis�o Ativa Di�ria - O "The Flow" Digests:**
    *   A automa��o da rotina e sa�de mental da Influencer n�o depende dela perguntar, depende do bot mandar reports proativos em blocos da semana (Via jobs com delays cron). (Ex: Segunda-Desempenho Semanal. Sexta-Idea��o Base futura). 

## ??? Fase 6: Lapida��o e Opera��o Segura (Prioridade P3)

1.  **Monitoramento B�sico e Vis�o Macro:**
    *   Ativa��o da rota simples `/up` (Built-in do Rails 8). Tratamento em console log stream de falhas nos nodes dos workers de proxy.
2.  **Auto-Healing Reports:**
    *   Workers que disparam alertas num Channel admin do Discord na exata hora em que um container de scrapping Camoufox / parser base reportar descompasso violento na quebra de nodes DOM (Sites que viraram o Front-end e baniram a hierarquia de Classes CSS temporariamente do Web Scraper Base).
3.  **Cadeia Multimidia Opcional:**
    *   Testes isolados em chamadas Gemini Imagen 3/DALL-E criando assets bases, gerando imagens inspiracionais de thumbs e moodboards a partir das descri��es analisadas do concorrente p/ agregar nos Digests p/ influenciadora.
4.  **A Backup Simples de Um Banco Simples:**
    *   Jobs shell que invocam `cp` nas pastilhas absolutas `/data/*.sqlite3` copiando p/ volumes protegidos cloud. (Garantia por rodar WAL em modo de c�pia resilientes live). Mantenha `credentials.yml.enc` e a master.key trancadas num gerenciador de secrets � parte da m�quina rodando.

---

## ?? Observa��es Retroativas � Fase 2 (P�s-Implementa��o)

*Adi��es identificadas ap�s revis�o de alinhamento. Fase j� conclu�da � itens servem como refer�ncia para futuras melhorias no motor de coleta.*

1.  **Seletores Estruturais nos Scrapers:**
    *   NUNCA hardcoded CSS selectors (`a.mdc-basic-feed-item`). Identifique artigos e perfis por propriedades estruturais que sobrevivem a redesigns: agrupamento de links por classe CSS, comprimento m�dio de slug das URLs do grupo, e tamanhos descritivos de t�tulos vs links de navega��o. Seletor quebrou? O scraper degrada, n�o morre.
2.  **Graceful Degradation em Cascata:**
    *   Se o scraper falhou (bloqueio, timeout, DOM quebrado), caia em cascata: (1) tentar `og:description` / OpenGraph metadata via HTTP simples; (2) extrair t�tulo da URL; (3) registrar como gap no banco com flag `source_degraded: true` para o LLM saber que aquele dado tem qualidade reduzida.
3.  **Stealth Patches no Ferrum (Anti-Bot Detection):**
    *   Injetar JS anti-detec��o via CDP `Page.addScriptToEvaluateOnNewDocument` ANTES de qualquer script da p�gina: falsificar `navigator.webdriver = false`, patchar `navigator.plugins`, spoofar WebGL renderer ("NVIDIA GeForce GTX 1080"), e ativar flag `--disable-blink-features=AutomationControlled`.

## ?? Observa��es P�s-Implementa��o � Fase 6 (Verifica��es Obrigat�rias)

1. **Calibrar limiares do AlertThrottler existente** ? implementado (AlertThrottler: max 10/hora via Solid Cache, gate `ALERT_THROTTLE_ENABLED`):
   * Ajustar limiares operacionais reais para evitar flood no Discord admin.
   * Alertas devem sinalizar problema real, n�o spam operacional.
   * Validar se 10/hora � o teto correto para o volume de jobs do sistema.

2. **Implementar escalonamento de incidentes recorrentes** ?? parcial (ScrapingFailureAlertJob existe, mas sem escalonamento):
   * Se o sistema s� alerta e reexecuta, mas nunca marca incidente recorrente, a falha vira d�vida invis�vel.
   * Necess�rio: ap�s N ocorr�ncias do mesmo tipo/janela, escalar para alerta de severidade cr�tica (ex: canal separado, men��o a role admin).

3. **Validar restore do backup existente** ?? parcial (SqliteBackupJob + bin/backup j� fazem backup WAL-safe com reten��o 7 dias):
   * O gap real N�O � o backup � � o restore.
   * Criar script `bin/restore` que execute restore em ambiente isolado e valide: banco sobe, tabelas centrais consistentes, jobs enfileiram.
   * Agendar teste peri�dico de restore (ex: mensal).

4. **Testar falha simulada dos containers de coleta** ? n�o testado:
   * Derrubar manualmente o container `chrome` / scraper e validar:
     * se o sistema detecta
     * se alerta corretamente
     * se os jobs pendentes n�o corrompem estado
     * se a retomada ocorre sem duplicidade

5. **Padronizar logs com contexto m�nimo �til** ?? parcial (s� existe prefixo `[ClassName]`):
   * Todo erro operacional precisa indicar pelo menos:
     * job/classe
     * plataforma/fonte
     * profile/post/evento afetado
     * tipo de falha
   * Implementar helper de log estruturado (ex: `log_context(:error, job: self.class, platform:, profile_id:, error:)`).

6. **Or�ar custos de rotinas opcionais** ? parcial (ImageGenerationService j� tem gate `ENABLE_IMAGE_GENERATION`):
   * A cadeia multim�dia opcional precisa ter guarda de custo e execu��o controlada.
   * Adicionar budget di�rio acumulado via Solid Cache (ex: `MAX_DAILY_IMAGE_COST_USD`) para impedir gera��o autom�tica em massa.


## ?? Fase 7: Hardening Real de Produ��o e Sobreviv�ncia Operacional (Prioridade P2)
*Quando o sistema entra em uso cont�nuo, n�o basta funcionar; ele precisa falhar sem colapsar, se recuperar sem duplicar e sinalizar sem esconder a causa raiz.*

1.  **Restore de Backup Validado de Verdade** ? n�o implementado:
    *   Backup sem restore testado � placebo operacional. Toda rotina de c�pia do SQLite/WAL precisa ter verifica��o peri�dica em ambiente isolado.
    *   Criar `bin/restore` que: copia backup para path isolado, inicia Rails em modo read-only, executa queries de valida��o nas tabelas centrais (`SocialProfile`, `SocialPost`, `ProfileSnapshot`), e tenta enfileirar job simples.
    *   Falhou restore? O alerta deve ser tratado como incidente cr�tico mesmo que o backup tenha "sido gerado".

2.  **Idempot�ncia Blindada nos Workers Cr�ticos** ?? parcial (ProfileSnapshot tem dedup 2h, jobs usam find_or_initialize_by):
    *   Auditar CADA UM dos 16 jobs de coleta, snapshot, classifica��o e discovery � n�o assumir que todos s�o idempotentes.
    *   Nenhum retry pode gerar:
        * snapshots duplicados
        * posts replicados
        * chamadas LLM redundantes
        * reclassifica��o inconsistente do mesmo alvo
    *   Toda opera��o cr�tica deve nascer de chaves naturais r�gidas + janela de deduplica��o bem definida.

3.  **Fila de Quarentena / Dead Letter Controlada** ?? parcial (Solid Queue tem `failed_jobs`, mas sem quarentena audit�vel):
    *   Jobs que excederem tentativas ou quebrarem por erro persistente n�o podem sumir em logs.
    *   Criar tabela `quarantined_jobs` com payload m�nimo audit�vel:
        * classe do job
        * plataforma/fonte
        * identificador do profile/post
        * etapa da falha
        * motivo resumido
        * timestamp
    *   Isso precisa permitir replay manual posterior (job rake `quarantine:replay[id]`) sem editar banco na m�o.

4.  **Health Checks de Depend�ncia, N�o S� de Processo** ?? parcial (/health s� faz SELECT 1):
    *   O `/up` do Rails e o `/health` atual n�o bastam como sem�foro operacional. O sistema pode responder HTTP 200 e estar morto funcionalmente.
    *   Expandir `HealthController` para validar separadamente:
        * banco SQLite em WAL mode
        * fila Solid Queue com workers ativos
        * chrome/headless dispon�vel (GET `http://chrome:9222/json/version`)
        * provider LLM acess�vel (ping de quota)
    *   Retornar status degradado (HTTP 207) se qualquer depend�ncia cr�tica falhar, e cr�tico (HTTP 503) se m�ltiplas falharem.

5.  **Feature Flags para Degrada��o Elegante** ? n�o implementado (s� 2 ENV gates soltos):
    *   Implementar sistema de feature flags usando Solid Cache como backend (evita depend�ncia extra).
    *   Criar m�dulo `FeatureFlags` com m�todo `.enabled?(:flag_name)` que l� de Solid Cache com fallback para ENV.
    *   Flags m�nimas:
        * `rss_enabled`
        * `stealth_enabled`
        * `llm_discovery_enabled`
        * `multimodal_enabled`
        * `proactive_digest_enabled`
    *   Interface de admin: rake task `feature:enable[flag]` / `feature:disable[flag]` + status no `/health`.
    *   Em incidente, o sistema precisa perder capacidade parcial � nunca a plataforma inteira.

6.  **Ledger de Bloqueios e Rate Limits por Fonte** ?? parcial (rate_limit_handler.rb existe, sem persist�ncia):
    *   N�o basta logar 403/429. � preciso mem�ria operacional persistente por provider.
    *   Criar tabela `source_health_ledger` com colunas: `source_name`, `failure_count`, `last_failure_at`, `cooldown_until`, `collector_type`, `status` (enum: `ok` / `cooldown` / `blocked`).
    *   Jobs de coleta devem consultar o ledger ANTES de executar � se `status = blocked`, pular com log.
    *   Isso impede insist�ncia burra sobre fonte degradada e melhora decis�es futuras do scheduler.

7.  **Runbooks de Incidente e Recupera��o Curta** ? n�o implementado:
    *   Criar `docs/runbooks/` com passo a passo m�nimo para os cen�rios mais prov�veis:
        * chrome/headless indispon�vel
        * proxy/residencial degradado
        * provider LLM fora
        * banco bloqueado (WAL lock)
        * crescimento anormal da fila
        * restore emergencial
    *   Produ��o madura n�o depende de mem�ria pessoal do dev que escreveu tudo.

## ?? Fase 8: Qualidade Sist�mica, Testabilidade e Crit�rios de Confian�a (Prioridade P2)
*Sem provas de comportamento, o sistema parece inteligente at� o primeiro desvio real de fonte, layout ou modelo externo.*

1.  **Testes de Fluxos Criticos ponta a ponta** ?? parcial (~394 tests existem, majoritariamente unit com mocks):
    *   O que existe hoje sao testes unitarios e de integracao com mocks � nao e2e.
    *   Priorizar testes de comportamento real sobre unit tests decorativos.
    *   Cobrir no minimo como testes e2e com fixtures reais:
        * ingestao/coleta ? persistencia ? consulta
        * deduplicacao com retry simultaneo
        * snapshots com janela de 2h
        * classificacao LLM com structured output
        * fallback sem browser (RSS como caminho alternativo)
        * fallback sem LLM (degradacao graciosa)
        * resposta do tool calling no chatbot
    *   O objetivo e provar que o encadeamento inteiro nao quebra quando uma parte degrada.

2.  **Fixtures Reais de HTML, JSON e RSS** ? nao implementado (ha factories, nao fixtures externas):
    *   Criar diretorio `test/fixtures/external/` com exemplos reais capturados das fontes.
    *   Salvar exemplos reais das fontes externas para testar parse local sem depender do site online.
    *   Isso protege contra regressoes silenciosas quando o scraper muda ou quando o layout externo e alterado.
    *   Fixtures devem cobrir no minimo:
        * Twitter: perfil limpo, perfil privado, rate-limit page
        * Instagram: post com midia, perfil business, ban/redirect
        * RSS: feed valido, feed parcial, feed malformado
        * TMDB/IGDB: resposta JSON valida, campos faltando, erro 429

3.  **Testes de Contrato para Integracoes Externas** ? nao implementado:
    *   Qualquer provider externo que entregue estrutura esperada precisa ter contrato minimo verificado.
    *   Inclui:
        * LLM structured outputs (Gemini, Gemma, OpenRouter)
        * TMDB / IGDB / Anilist / RAWG
        * RSS parsers
        * yt-dlp outputs
        * modulos stealth (nodriver, camoufox)
    *   Criar testes que validem shape de retorno esperado � se o provider mudar, o teste falha antes da producao.

4.  **Validacao de Modo Degradado** ? nao implementado:
    *   O sistema precisa ter testes especificos provando que continua util sem partes nao essenciais.
    *   Exemplos:
        * sem LLM ? coleta e persistencia continuam
        * sem browser stealth ? RSS/coletores simples continuam
        * sem multimodal ? chatbot e analises textuais continuam
        * sem chrome headless ? jobs que dependem dele falham graciosamente, nao crasham
    *   Falhar bonito e uma feature de arquitetura, nao um acidente.

5.  **Smoke Tests Pos-Deploy** ? nao implementado:
    *   Criar script `bin/smoke_test` que valida pos-deploy:
        * leitura do banco
        * enqueue e execucao de job simples em modo sincrono
        * acesso ao servico headless (`http://chrome:9222/json/version`)
        * resposta basica do health endpoint
        * leitura de uma feature flag
    *   Integrar ao entrypoint do container ou como step no CI/CD.
    *   Deploy "verde" nao significa sistema operacionalmente pronto.

6.  **Teste de Concorr�ncia Leve com SQLite WAL:**
    *   O uso real vai concentrar IO, snapshots, jobs e classifica��es em paralelo.
    *   Validar lock contention, tempo m�dio de job, throughput m�nimo e comportamento sob fila crescente.
    *   Se WAL come�ar a estrangular em cen�rio plaus�vel, isso precisa aparecer antes do uso real.

7.  **Crit�rios de Aceite por Fase Operacional:**
    *   Formalizar um checklist objetivo para considerar a plataforma confi�vel:
        * coleta persiste sem duplicar
        * snapshots respeitam janela de dedup
        * tool calling n�o explode query
        * fallback degradado funciona
        * backups restauram
        * alertas s�o acion�veis
    *   Sem isso, �implementado� vira apenas percep��o subjetiva.

## ?? Fase 9: Seguran�a Operacional, Governan�a e Controle de Superf�cie (Prioridade P2)
*Quanto mais autonomia o sistema ganha, maior o risco de custo explosivo, vazamento de contexto e a��es al�m do permitido.*

1.  **Gestao Rigida de Segredos e Credenciais** ⚠️ parcial (ENV-based via .env, sem Vault/SOPS/rotacao):
    *   Tokens de providers, chaves LLM, cookies de sess�o e credenciais de proxies nunca devem residir em c�digo, fixtures ou logs.
    *   Centralizar leitura via environment/config segura com pol�tica expl�cita de rota��o.
    *   Toda credencial cr�tica precisa ter dono, origem e estrat�gia de troca documentados.

2.  **Sanitizacao Obrigatoria de Logs** 🔴 PRIORIDADE ALTA (risco real de vazamento de tokens em logs):
    *   Log �til n�o pode virar vazamento.
    *   � proibido expor:
        * tokens
        * cookies
        * headers sens�veis
        * prompt completo com dados privados
        * payload integral de autentica��o
    *   Os logs devem mostrar contexto suficiente para debug sem expor material reaproveit�vel.

3.  **Controle de Acesso por Tool e Classe de Acao** ❌ nao implementado (ChatSessionManager carrega 16 tools sem permissao):
    *   Nem toda ferramenta do chatbot deve ficar dispon�vel em qualquer contexto.
    *   Separar permiss�es por categoria:
        * leitura
        * an�lise
        * descoberta automatizada
        * a��es administrativas
        * rotinas caras/multimodais
    *   Quanto mais poderosa a tool, maior o gate de execucao.
    *   Implementar middleware de permissao por tool category: read (livre), analysis (canal autorizado), admin (role admin), expensive (confirmacao + budget check).

4.  **Rate Limits Internos e Controle de Custo ⚠️ parcial (LLM tem quota tracking, mas sem limites por usuario/canal):**
    *   O risco n�o � s� bloqueio externo; � custo interno explodindo por tool calling descontrolado ou loops de automa��o.
    *   Limitar por:
        * usu�rio/canal
        * job recorrente
        * n�mero de chamadas LLM
        * volume de outputs multimodais
    *   Toda rotina cara precisa de clamp e budget operacional.

5.  **Versionamento de Prompts, Schemas e Ferramentas ⚠️ parcial (YAML versionado via git, sem versionamento semantico):**
    *   Prompt sist�mico, contrato de tool e output estruturado n�o podem mudar �soltos�.
    *   Versionar:
        * prompts base
        * schemas de retorno
        * regras do roteador LLM
        * classificadores de discovery
    *   Isso permite rollback sem adivinha��o quando um ajuste piora a qualidade.

6.  **Auditoria de Acoes Automatizadas Sensíveis** ❌ nao implementado:
    *   Toda a��o importante disparada por automa��o ou LLM deve deixar trilha:
        * qual rotina executou
        * qual entrada motivou
        * qual ferramenta foi chamada
        * qual resultado saiu
        * qual vers�o de prompt/modelo estava ativa
    *   Sem trilha, nao existe governanca real de autonomia.
    *   Criar tabela audit_logs com colunas: tool_name, input_summary (truncado), output_summary, model_version, user_id, channel_id, timestamp.

7.  **Escopo Seguro de Execucao do Chatbot** ❌ nao implementado (sem confirmacao explicita para operacoes destrutivas):
    *   O bot precisa ser desenhado para consultar e sugerir com liberdade, mas agir com restri��o.
    *   Opera��es destrutivas, caras ou com efeito sist�mico devem exigir:
        * confirma��o expl�cita
        * role/contexto apropriado
        * ou bloqueio total fora de ambiente administrativo
    *   Chatbot �til n�o pode virar operador irrestrito por acidente.

## ?? Fase 10: Qualidade de Dados, Auditoria Semantica e Reprocessamento Inteligente (Prioridade P3) — ⚠️ NENHUM ITEM IMPLEMENTADO (planejamento puro)
*N�o basta coletar muito. O valor real do sistema nasce quando o dado continua confi�vel, explic�vel e reaproveit�vel mesmo ap�s falhas, mudan�as externas e classifica��es imperfeitas do LLM.*

1.  **Data Quality Checks Autom�ticos:**
    *   Criar rotinas peri�dicas para varrer inconsist�ncias silenciosas no banco, antes que elas contaminem o chatbot, os digests e as decis�es da Influencer.
    *   Detectar automaticamente:
        * picos absurdos ou quedas improv�veis em likes/views
        * snapshots fora de ordem temporal
        * posts duplicados por falha de scraper ou retry
        * campos cr�ticos ausentes em excesso
        * perfis �ativos� sem coleta recente
    *   O objetivo � tratar dado estranho como sinal operacional � n�o como verdade absoluta.

2.  **Flags de Confiabilidade por Registro:**
    *   Nem toda linha persistida deve carregar o mesmo peso interpretativo para o sistema.
    *   Adicionar sinaliza��o objetiva por registro/snapshot/post, com estados como:
        * `trusted`
        * `partial`
        * `source_degraded`
        * `llm_inferred`
        * `needs_review`
    *   Isso permite que o bot, os classificadores e os relatorios saibam quando um dado � s�lido, quando � aproximado e quando deve ser tratado com cautela.
    *   Implementacao concreta: adicionar coluna data_quality (enum) em profile_snapshots e social_posts.

3.  **Auditoria das Classifica��es e Infer�ncias de LLM:**
    *   Toda classifica��o relevante feita por modelo precisa deixar trilha suficiente para inspe��o posterior.
    *   Persistir pelo menos:
        * entrada resumida enviada ao modelo
        * sa�da estruturada recebida
        * vers�o do prompt
        * modelo utilizado
        * timestamp da infer�ncia
    *   Sem isso, o sistema perde a capacidade de explicar por que um profile virou `CONCORRENTE`, `PATROCINADOR_PROSPECTO` ou `IGNORAR`.

4.  **Reprocessamento Seletivo e Cir�rgico:**
    *   Falhas ou melhorias futuras n�o devem obrigar rerun global do pipeline inteiro.
    *   Permitir reprocessar isoladamente:
        * um profile espec�fico
        * um post espec�fico
        * uma fonte/plataforma
        * uma janela temporal
        * uma etapa sem�ntica (ex: somente classifica��o LLM)
    *   Isso reduz custo, evita duplicidade e acelera corre��o de incidentes localizados.

5.  **Reconcilia��o entre Fontes e Verdade Prov�vel:**
    *   Quando m�ltiplas rotas de coleta produzirem dados diferentes para o mesmo alvo, o sistema n�o pode simplesmente sobrescrever silenciosamente.
    *   Criar l�gica de reconcilia��o leve baseada em:
        * preced�ncia de fonte
        * rec�ncia do snapshot
        * consist�ncia hist�rica do perfil/post
        * presen�a de degrada��o conhecida na origem
    *   Diverg�ncia precisa virar decis�o expl�cita, n�o ru�do escondido.

6.  **Janela de Validade Sem�ntica dos Dados:**
    *   Nem todo dado continua �til pelo mesmo tempo.
    *   Definir TTL l�gico por classe de informa��o:
        * m�tricas de post ? alta volatilidade
        * bios e links ? m�dia volatilidade
        * classifica��o de perfil ? requer reavalia��o peri�dica
        * eventos externos/agendas ? expira��o por data
    *   O chatbot precisa preferir dado recente quando a natureza do campo exigir isso.

7.  **Camada de Revis�o para Casos Amb�guos:**
    *   Algumas sa�das n�o devem entrar como verdade autom�tica.
    *   Sempre que houver baixa confian�a, conflito entre fontes ou structured output incompleto, marcar o item para revis�o posterior em vez de consolidar como sinal definitivo.
    *   Melhor um registro pendente do que uma certeza falsa alimentando an�lise futura.

8.  **M�tricas de Qualidade do Pr�prio Sistema:**
    *   Al�m de monitorar infra, medir a qualidade da intelig�ncia produzida.
    *   Acompanhar indicadores como:
        * taxa de registros degradados
        * volume de infer�ncias LLM contradit�rias
        * percentual de posts/perfis reprocessados
        * quantidade de gaps por fonte
        * taxa de confian�a por classificador
    *   Isso transforma qualidade de dados em superf�cie vis�vel de opera��o, e n�o em problema descoberto tarde demais.

9.  **Prepara��o para Evolu��o de Schema Sem Perda Sem�ntica:**
    *   O modelo do dom�nio vai evoluir. Quando novos campos, flags ou tipos surgirem, o banco e os pipelines n�o podem apagar nuance hist�rica.
    *   Toda mudan�a futura em schema deve preservar:
        * distin��o entre `nil` e zero
        * origem do dado
        * qualidade/confiabilidade associada
        * compatibilidade com snapshots antigos
    *   Evoluir schema sem destruir sem�ntica � parte central da longevidade do sistema.

## ?? Fase 11: Deploy, Publica��o e Ambiente Real de Execu��o (Prioridade P2)
*Um sistema n�o est� realmente pronto quando apenas roda localmente; ele precisa subir com previsibilidade, degradar com seguran�a, reiniciar sem perder contexto e caber numa estrat�gia de custo vi�vel.*

1.  **Validar Topologia de Deploy Existente ✅ ja existe (docker-compose.yml com 6 servicos):**
    *   Formalizar como os componentes ser�o publicados fora do ambiente local.
    *   Separar claramente:
        * aplica��o Rails principal
        * workers/jobs ass�ncronos
        * browser/headless quando necess�rio
        * banco/persist�ncia
        * redis/fila, se aplic�vel
    *   O deploy precisa refletir a arquitetura de verdade, n�o apenas �um container que sobe tudo�.

2.  **Escolher Estrat�gia de Hospedagem por Perfil de Carga:**
    *   Antes de publicar, classificar o sistema em termos de execu��o real:
        * bot HTTP sob demanda
        * worker cont�nuo
        * scheduler/cron recorrente
        * tarefas pesadas com browser
        * rotinas LLM com custo vari�vel
    *   Isso evita escolher plataforma �free� que parece suficiente, mas quebra no primeiro uso cont�nuo.

3.  **Pesquisar e Validar Op��es de Deploy Free para Hospedar o Bot:**
    *   Incluir uma investiga��o pr�tica comparando provedores gratuitos ou com camada gratuita vi�vel para hobby/MVP.
    *   Avaliar pelo menos:
        * suporte a processo cont�nuo
        * suporte a web service + worker
        * possibilidade de cron/scheduler
        * persist�ncia/local disk
        * cold start / scale-to-zero
        * limites de RAM/CPU
        * necessidade de cart�o/cr�dito
    *   A decis�o n�o deve ser baseada s� em �tem free tier�, mas em compatibilidade com o comportamento real do bot.

4.  **Documentar Provedores Candidatos e Restri��es Reais:**
    *   Registrar pr�s, contras e bloqueios de cada op��o analisada.
    *   Observa��es iniciais importantes:
        * **Render**: possui free para web services, mas n�o � solu��o ideal quando voc� depende de cron pago ou workers cont�nuos fora da camada free.
        * **Railway**: � pr�tica para deploy r�pido, mas hoje n�o � um "free tier permanente" simples; come�a com trial/cr�ditos e depois entra em custo.
        * **Koyeb**: hoje oferece uma Free Instance com 512MB RAM, 0.1 vCPU e 2GB SSD; pode servir para MVP, mas o scale-to-zero ap�s 1 hora sem tr�fego precisa ser considerado se o bot exigir processo sempre ativo.
        * **Fly.io**: free tier com 3GB volume persistente (bom para SQLite), suporte a processo contínuo e cron. Boa opção para operação contínua em MVP.
        * **Oracle Cloud Free Tier**: VM Always Free com até 24GB RAM e 200GB storage. Excelente para worker contínuo, mas requer cartão e configuração manual mais complexa.
    *   O plano deve deixar claro qual op��o � �boa para MVP/teste� e qual � �boa para opera��o cont�nua�.

5.  **Empacotamento Reprodutivel com Docker ✅ ja existe (Dockerfile multi-stage com ruby:4-slim):**
    *   Garantir que a aplica��o possa ser subida de forma consistente fora do dev machine.
    *   Criar imagem reprodut�vel com:
        * dependencies expl�citas
        * vari�veis de ambiente bem definidas
        * entrypoints separados por papel (`web`, `worker`, `scheduler`)
    *   Deploy confi�vel come�a por build confi�vel.

6.  **Configura��o Segura de Ambientes:**
    *   Separar claramente dev / staging / production.
    *   Toda vari�vel cr�tica deve ser configur�vel sem altera��o de c�digo:
        * segredos
        * endpoints externos
        * flags operacionais
        * limites de custo
        * chaves de providers
    *   O ambiente publicado n�o pode depender de defaults impl�citos do desenvolvimento local.

7.  **Estrat�gia de Persist�ncia e Volumes:**
    *   Se houver uso de SQLite, arquivos, cache local ou artefatos tempor�rios, isso precisa ser compat�vel com o host escolhido.
    *   Validar:
        * disco ef�mero vs persistente
        * comportamento ap�s restart/redeploy
        * backup compat�vel com o ambiente
        * impacto de m�ltiplas inst�ncias sobre arquivos locais
    *   Nem todo host free � amig�vel a persist�ncia local.

8.  **Deploy Inicial com Smoke Test de Publica��o:**
    *   Ap�s o primeiro deploy, executar checklist m�nimo:
        * aplica��o sobe
        * worker executa
        * fila/processamento funciona
        * healthcheck responde
        * bot consegue responder ao fluxo mais b�sico
        * logs aparecem no ambiente remoto
    *   �Deploy conclu�do� n�o significa �sistema utiliz�vel�.

9.  **Estrat�gia de Rollback e Rebuild R�pido:**
    *   Toda publica��o precisa ter caminho simples de revers�o.
    *   Documentar:
        * como voltar para vers�o anterior
        * como redeployar build limpo
        * como validar se o problema est� no c�digo ou no ambiente
    *   Opera��o madura inclui recupera��o r�pida, n�o s� entrega.

10. **Crit�rio de Sa�da da Fase 11:**
    *   A fase s� deve ser considerada conclu�da quando existir:
        * pelo menos um ambiente remoto funcional
        * documenta��o da escolha de hosting
        * entendimento expl�cito dos limites do plano free escolhido
        * checklist de deploy e rollback
        * prova de que o bot sobe e executa o fluxo principal fora do ambiente local
