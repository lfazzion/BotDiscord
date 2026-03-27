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


## 🧱 Fase 7: Hardening Real de Produção e Sobrevivência Operacional (Prioridade P2)
*Quando o sistema entra em uso contínuo, não basta funcionar; ele precisa falhar sem colapsar, se recuperar sem duplicar e sinalizar sem esconder a causa raiz.*

1.  **Restore de Backup Validado de Verdade:**
    *   Backup sem restore testado é placebo operacional. Toda rotina de cópia do SQLite/WAL precisa ter verificação periódica em ambiente isolado.
    *   O restore deve provar três coisas: o banco sobe, as tabelas centrais (`SocialProfile`, `SocialPost`, `ProfileSnapshot`) permanecem consistentes e a aplicação consegue consultar e enfileirar jobs após recuperação.
    *   Falhou restore? O alerta deve ser tratado como incidente crítico mesmo que o backup tenha “sido gerado”.

2.  **Idempotência Blindada nos Workers Críticos:**
    *   Revisar cada job de coleta, snapshot, classificação e discovery para garantir tolerância total a retry, duplicidade de agendamento e corrida entre workers.
    *   Nenhum retry pode gerar:
        * snapshots duplicados
        * posts replicados
        * chamadas LLM redundantes
        * reclassificação inconsistente do mesmo alvo
    *   Toda operação crítica deve nascer de chaves naturais rígidas + janela de deduplicação bem definida.

3.  **Fila de Quarentena / Dead Letter Controlada:**
    *   Jobs que excederem tentativas ou quebrarem por erro persistente não podem sumir em logs.
    *   Criar fluxo de quarentena com payload mínimo auditável:
        * classe do job
        * plataforma/fonte
        * identificador do profile/post
        * etapa da falha
        * motivo resumido
        * timestamp
    *   Isso precisa permitir replay manual posterior sem editar banco na mão.

4.  **Health Checks de Dependência, Não Só de Processo:**
    *   O `/up` do Rails não basta como semáforo operacional. O sistema pode responder HTTP 200 e estar morto funcionalmente.
    *   Validar separadamente:
        * banco SQLite em WAL
        * fila e workers ativos
        * chrome/headless disponível
        * acesso mínimo às integrações externas
        * provider LLM acessível
    *   Se qualquer dependência crítica estiver degradada, o health geral deve refletir isso.

5.  **Feature Flags para Degradação Elegante:**
    *   Todo coletor frágil, caro ou instável precisa ser desligável sem deploy.
    *   Flags mínimas sugeridas:
        * `rss_enabled`
        * `stealth_enabled`
        * `llm_discovery_enabled`
        * `multimodal_enabled`
        * `proactive_digest_enabled`
    *   Em incidente, o sistema precisa perder capacidade parcial — nunca a plataforma inteira.

6.  **Ledger de Bloqueios e Rate Limits por Fonte:**
    *   Não basta logar 403/429. É preciso memória operacional por provider.
    *   Registrar por origem:
        * número de falhas recentes
        * última ocorrência
        * cooldown sugerido
        * tipo de coletor afetado
        * status atual (`ok`, `cooldown`, `blocked`)
    *   Isso impede insistência burra sobre fonte degradada e melhora decisões futuras do scheduler.

7.  **Runbooks de Incidente e Recuperação Curta:**
    *   Documentar o passo a passo mínimo para os cenários mais prováveis:
        * chrome/headless indisponível
        * proxy/residencial degradado
        * provider LLM fora
        * banco bloqueado
        * crescimento anormal da fila
        * restore emergencial
    *   Produção madura não depende de memória pessoal do dev que escreveu tudo.

## 🧪 Fase 8: Qualidade Sistêmica, Testabilidade e Critérios de Confiança (Prioridade P2)
*Sem provas de comportamento, o sistema parece inteligente até o primeiro desvio real de fonte, layout ou modelo externo.*

1.  **Testes de Fluxos Críticos ponta a ponta:**
    *   Priorizar testes de comportamento real sobre unit tests decorativos.
    *   Cobrir no mínimo:
        * ingestão/coleta
        * deduplicação
        * snapshots
        * classificação LLM
        * fallback sem browser
        * fallback sem LLM
        * resposta do tool calling
    *   O objetivo é provar que o encadeamento inteiro não quebra quando uma parte degrada.

2.  **Fixtures Reais de HTML, JSON e RSS:**
    *   Salvar exemplos reais das fontes externas para testar parse local sem depender do site online.
    *   Isso protege contra regressões silenciosas quando o scraper muda ou quando o layout externo é alterado.
    *   Fixtures devem cobrir:
        * resposta limpa
        * resposta parcial
        * resposta quebrada
        * campos faltando
        * rate-limit/ban page quando aplicável

3.  **Testes de Contrato para Integrações Externas:**
    *   Qualquer provider externo que entregue estrutura esperada precisa ter contrato mínimo verificado.
    *   Inclui:
        * LLM structured outputs
        * TMDB / IGDB / Anilist
        * RSS parsers
        * yt-dlp outputs
        * módulos stealth
    *   Mudou shape de retorno? O sistema precisa acusar antes da produção ficar semanticamente errada.

4.  **Validação de Modo Degradado:**
    *   O sistema precisa ter testes específicos provando que continua útil sem partes não essenciais.
    *   Exemplos:
        * sem LLM → coleta e persistência continuam
        * sem browser stealth → RSS/coletores simples continuam
        * sem multimodal → chatbot e análises textuais continuam
    *   Falhar bonito é uma feature de arquitetura, não um acidente.

5.  **Smoke Tests Pós-Deploy:**
    *   Todo deploy deve ser seguido por validações automáticas mínimas:
        * leitura do banco
        * enqueue e execução de job simples
        * acesso ao serviço headless
        * consulta básica do bot/chat
        * leitura de uma configuração/feature flag
    *   Deploy “verde” não significa sistema operacionalmente pronto.

6.  **Teste de Concorrência Leve com SQLite WAL:**
    *   O uso real vai concentrar IO, snapshots, jobs e classificações em paralelo.
    *   Validar lock contention, tempo médio de job, throughput mínimo e comportamento sob fila crescente.
    *   Se WAL começar a estrangular em cenário plausível, isso precisa aparecer antes do uso real.

7.  **Critérios de Aceite por Fase Operacional:**
    *   Formalizar um checklist objetivo para considerar a plataforma confiável:
        * coleta persiste sem duplicar
        * snapshots respeitam janela de dedup
        * tool calling não explode query
        * fallback degradado funciona
        * backups restauram
        * alertas são acionáveis
    *   Sem isso, “implementado” vira apenas percepção subjetiva.

## 🔐 Fase 9: Segurança Operacional, Governança e Controle de Superfície (Prioridade P2)
*Quanto mais autonomia o sistema ganha, maior o risco de custo explosivo, vazamento de contexto e ações além do permitido.*

1.  **Gestão Rígida de Segredos e Credenciais:**
    *   Tokens de providers, chaves LLM, cookies de sessão e credenciais de proxies nunca devem residir em código, fixtures ou logs.
    *   Centralizar leitura via environment/config segura com política explícita de rotação.
    *   Toda credencial crítica precisa ter dono, origem e estratégia de troca documentados.

2.  **Sanitização Obrigatória de Logs:**
    *   Log útil não pode virar vazamento.
    *   É proibido expor:
        * tokens
        * cookies
        * headers sensíveis
        * prompt completo com dados privados
        * payload integral de autenticação
    *   Os logs devem mostrar contexto suficiente para debug sem expor material reaproveitável.

3.  **Controle de Acesso por Tool e Classe de Ação:**
    *   Nem toda ferramenta do chatbot deve ficar disponível em qualquer contexto.
    *   Separar permissões por categoria:
        * leitura
        * análise
        * descoberta automatizada
        * ações administrativas
        * rotinas caras/multimodais
    *   Quanto mais poderosa a tool, maior o gate de execução.

4.  **Rate Limits Internos e Controle de Custo:**
    *   O risco não é só bloqueio externo; é custo interno explodindo por tool calling descontrolado ou loops de automação.
    *   Limitar por:
        * usuário/canal
        * job recorrente
        * número de chamadas LLM
        * volume de outputs multimodais
    *   Toda rotina cara precisa de clamp e budget operacional.

5.  **Versionamento de Prompts, Schemas e Ferramentas:**
    *   Prompt sistêmico, contrato de tool e output estruturado não podem mudar “soltos”.
    *   Versionar:
        * prompts base
        * schemas de retorno
        * regras do roteador LLM
        * classificadores de discovery
    *   Isso permite rollback sem adivinhação quando um ajuste piora a qualidade.

6.  **Auditoria de Ações Automatizadas Sensíveis:**
    *   Toda ação importante disparada por automação ou LLM deve deixar trilha:
        * qual rotina executou
        * qual entrada motivou
        * qual ferramenta foi chamada
        * qual resultado saiu
        * qual versão de prompt/modelo estava ativa
    *   Sem trilha, não existe governança real de autonomia.

7.  **Escopo Seguro de Execução do Chatbot:**
    *   O bot precisa ser desenhado para consultar e sugerir com liberdade, mas agir com restrição.
    *   Operações destrutivas, caras ou com efeito sistêmico devem exigir:
        * confirmação explícita
        * role/contexto apropriado
        * ou bloqueio total fora de ambiente administrativo
    *   Chatbot útil não pode virar operador irrestrito por acidente.

## 📊 Fase 10: Qualidade de Dados, Auditoria Semântica e Reprocessamento Inteligente (Prioridade P3)
*Não basta coletar muito. O valor real do sistema nasce quando o dado continua confiável, explicável e reaproveitável mesmo após falhas, mudanças externas e classificações imperfeitas do LLM.*

1.  **Data Quality Checks Automáticos:**
    *   Criar rotinas periódicas para varrer inconsistências silenciosas no banco, antes que elas contaminem o chatbot, os digests e as decisões da Influencer.
    *   Detectar automaticamente:
        * picos absurdos ou quedas improváveis em likes/views
        * snapshots fora de ordem temporal
        * posts duplicados por falha de scraper ou retry
        * campos críticos ausentes em excesso
        * perfis “ativos” sem coleta recente
    *   O objetivo é tratar dado estranho como sinal operacional — não como verdade absoluta.

2.  **Flags de Confiabilidade por Registro:**
    *   Nem toda linha persistida deve carregar o mesmo peso interpretativo para o sistema.
    *   Adicionar sinalização objetiva por registro/snapshot/post, com estados como:
        * `trusted`
        * `partial`
        * `source_degraded`
        * `llm_inferred`
        * `needs_review`
    *   Isso permite que o bot, os classificadores e os relatórios saibam quando um dado é sólido, quando é aproximado e quando deve ser tratado com cautela.

3.  **Auditoria das Classificações e Inferências de LLM:**
    *   Toda classificação relevante feita por modelo precisa deixar trilha suficiente para inspeção posterior.
    *   Persistir pelo menos:
        * entrada resumida enviada ao modelo
        * saída estruturada recebida
        * versão do prompt
        * modelo utilizado
        * timestamp da inferência
    *   Sem isso, o sistema perde a capacidade de explicar por que um profile virou `CONCORRENTE`, `PATROCINADOR_PROSPECTO` ou `IGNORAR`.

4.  **Reprocessamento Seletivo e Cirúrgico:**
    *   Falhas ou melhorias futuras não devem obrigar rerun global do pipeline inteiro.
    *   Permitir reprocessar isoladamente:
        * um profile específico
        * um post específico
        * uma fonte/plataforma
        * uma janela temporal
        * uma etapa semântica (ex: somente classificação LLM)
    *   Isso reduz custo, evita duplicidade e acelera correção de incidentes localizados.

5.  **Reconciliação entre Fontes e Verdade Provável:**
    *   Quando múltiplas rotas de coleta produzirem dados diferentes para o mesmo alvo, o sistema não pode simplesmente sobrescrever silenciosamente.
    *   Criar lógica de reconciliação leve baseada em:
        * precedência de fonte
        * recência do snapshot
        * consistência histórica do perfil/post
        * presença de degradação conhecida na origem
    *   Divergência precisa virar decisão explícita, não ruído escondido.

6.  **Janela de Validade Semântica dos Dados:**
    *   Nem todo dado continua útil pelo mesmo tempo.
    *   Definir TTL lógico por classe de informação:
        * métricas de post → alta volatilidade
        * bios e links → média volatilidade
        * classificação de perfil → requer reavaliação periódica
        * eventos externos/agendas → expiração por data
    *   O chatbot precisa preferir dado recente quando a natureza do campo exigir isso.

7.  **Camada de Revisão para Casos Ambíguos:**
    *   Algumas saídas não devem entrar como verdade automática.
    *   Sempre que houver baixa confiança, conflito entre fontes ou structured output incompleto, marcar o item para revisão posterior em vez de consolidar como sinal definitivo.
    *   Melhor um registro pendente do que uma certeza falsa alimentando análise futura.

8.  **Métricas de Qualidade do Próprio Sistema:**
    *   Além de monitorar infra, medir a qualidade da inteligência produzida.
    *   Acompanhar indicadores como:
        * taxa de registros degradados
        * volume de inferências LLM contraditórias
        * percentual de posts/perfis reprocessados
        * quantidade de gaps por fonte
        * taxa de confiança por classificador
    *   Isso transforma qualidade de dados em superfície visível de operação, e não em problema descoberto tarde demais.

9.  **Preparação para Evolução de Schema Sem Perda Semântica:**
    *   O modelo do domínio vai evoluir. Quando novos campos, flags ou tipos surgirem, o banco e os pipelines não podem apagar nuance histórica.
    *   Toda mudança futura em schema deve preservar:
        * distinção entre `nil` e zero
        * origem do dado
        * qualidade/confiabilidade associada
        * compatibilidade com snapshots antigos
    *   Evoluir schema sem destruir semântica é parte central da longevidade do sistema.

## 🚀 Fase 11: Deploy, Publicação e Ambiente Real de Execução (Prioridade P2)
*Um sistema não está realmente pronto quando apenas roda localmente; ele precisa subir com previsibilidade, degradar com segurança, reiniciar sem perder contexto e caber numa estratégia de custo viável.*

1.  **Definir Topologia de Deploy Real:**
    *   Formalizar como os componentes serão publicados fora do ambiente local.
    *   Separar claramente:
        * aplicação Rails principal
        * workers/jobs assíncronos
        * browser/headless quando necessário
        * banco/persistência
        * redis/fila, se aplicável
    *   O deploy precisa refletir a arquitetura de verdade, não apenas “um container que sobe tudo”.

2.  **Escolher Estratégia de Hospedagem por Perfil de Carga:**
    *   Antes de publicar, classificar o sistema em termos de execução real:
        * bot HTTP sob demanda
        * worker contínuo
        * scheduler/cron recorrente
        * tarefas pesadas com browser
        * rotinas LLM com custo variável
    *   Isso evita escolher plataforma “free” que parece suficiente, mas quebra no primeiro uso contínuo.

3.  **Pesquisar e Validar Opções de Deploy Free para Hospedar o Bot:**
    *   Incluir uma investigação prática comparando provedores gratuitos ou com camada gratuita viável para hobby/MVP.
    *   Avaliar pelo menos:
        * suporte a processo contínuo
        * suporte a web service + worker
        * possibilidade de cron/scheduler
        * persistência/local disk
        * cold start / scale-to-zero
        * limites de RAM/CPU
        * necessidade de cartão/crédito
    *   A decisão não deve ser baseada só em “tem free tier”, mas em compatibilidade com o comportamento real do bot.

4.  **Documentar Provedores Candidatos e Restrições Reais:**
    *   Registrar prós, contras e bloqueios de cada opção analisada.
    *   Observações iniciais importantes:
        * **Render**: possui free para web services, mas não é solução ideal quando você depende de cron pago ou workers contínuos fora da camada free. :contentReference[oaicite:1]{index=1}
        * **Railway**: é prática para deploy rápido, mas hoje não é um “free tier permanente” simples; começa com trial/créditos e depois entra em custo. :contentReference[oaicite:2]{index=2}
        * **Koyeb**: hoje oferece uma Free Instance com 512MB RAM, 0.1 vCPU e 2GB SSD; pode servir para MVP, mas o scale-to-zero após 1 hora sem tráfego precisa ser considerado se o bot exigir processo sempre ativo. :contentReference[oaicite:3]{index=3}
    *   O plano deve deixar claro qual opção é “boa para MVP/teste” e qual é “boa para operação contínua”.

5.  **Empacotamento Reprodutível com Docker:**
    *   Garantir que a aplicação possa ser subida de forma consistente fora do dev machine.
    *   Criar imagem reprodutível com:
        * dependencies explícitas
        * variáveis de ambiente bem definidas
        * entrypoints separados por papel (`web`, `worker`, `scheduler`)
    *   Deploy confiável começa por build confiável.

6.  **Configuração Segura de Ambientes:**
    *   Separar claramente dev / staging / production.
    *   Toda variável crítica deve ser configurável sem alteração de código:
        * segredos
        * endpoints externos
        * flags operacionais
        * limites de custo
        * chaves de providers
    *   O ambiente publicado não pode depender de defaults implícitos do desenvolvimento local.

7.  **Estratégia de Persistência e Volumes:**
    *   Se houver uso de SQLite, arquivos, cache local ou artefatos temporários, isso precisa ser compatível com o host escolhido.
    *   Validar:
        * disco efêmero vs persistente
        * comportamento após restart/redeploy
        * backup compatível com o ambiente
        * impacto de múltiplas instâncias sobre arquivos locais
    *   Nem todo host free é amigável a persistência local.

8.  **Deploy Inicial com Smoke Test de Publicação:**
    *   Após o primeiro deploy, executar checklist mínimo:
        * aplicação sobe
        * worker executa
        * fila/processamento funciona
        * healthcheck responde
        * bot consegue responder ao fluxo mais básico
        * logs aparecem no ambiente remoto
    *   “Deploy concluído” não significa “sistema utilizável”.

9.  **Estratégia de Rollback e Rebuild Rápido:**
    *   Toda publicação precisa ter caminho simples de reversão.
    *   Documentar:
        * como voltar para versão anterior
        * como redeployar build limpo
        * como validar se o problema está no código ou no ambiente
    *   Operação madura inclui recuperação rápida, não só entrega.

10. **Critério de Saída da Fase 11:**
    *   A fase só deve ser considerada concluída quando existir:
        * pelo menos um ambiente remoto funcional
        * documentação da escolha de hosting
        * entendimento explícito dos limites do plano free escolhido
        * checklist de deploy e rollback
        * prova de que o bot sobe e executa o fluxo principal fora do ambiente local