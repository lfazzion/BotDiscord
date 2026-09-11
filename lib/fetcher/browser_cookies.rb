# frozen_string_literal: true

require "timeout"
require_relative "page_fetcher"

module Fetcher
  # Cookies da sessão viva do Chrome, lidos pelo CDP.
  #
  # É a fonte preferida, à frente do jar no banco, porque o perfil do Chrome é
  # quem de fato conversa com a plataforma: quando o servidor manda rotacionar, é
  # ele que rotaciona, e ler dali nunca fica dessincronizado. Foi exatamente a
  # dessincronização entre uma cópia exportada e a sessão viva no navegador do
  # dono que invalidou a primeira sessão de YouTube desta construção.
  #
  # A leitura NÃO passa pela página default do Ferrum: o caminho antigo
  # (`browser.cookies.all`) operava sobre uma página com sessionId, e quando a
  # sessão CDP morre a página já vai junto — era isso que produzia o -32001 em
  # produção. O jar do `default_context` do Ferrum (o contexto CRIADO por
  # `Target.createBrowserContext`, NÃO o perfil implícito do Chrome, cujo jar é
  # sempre vazio — provado pelo probe no headless-shell real, EV §1) é lido pelo
  # cliente raiz, sem página nem sessionId (laudo r3 B5 / v2 B3, B1/B2).
  #
  # NÃO se usa o `--cookies-from-browser` do yt-dlp de propósito: aquele caminho
  # lê o SQLite do perfil, que navegadores Chromium mantêm travado enquanto rodam
  # — e o nosso roda sempre. Existe até plugin de terceiro só para destravar. Pelo
  # CDP o próprio navegador entrega os cookies em claro, sem tocar no arquivo,
  # sem depender de keyring e sem acoplar caminho de perfil.
  module BrowserCookies
    # O Cookie-Editor usa os nomes da extensão; o CDP quer os do padrão.
    SAME_SITE = {
      "no_restriction" => "None", "lax" => "Lax", "strict" => "Strict",
      "None" => "None", "Lax" => "Lax", "Strict" => "Strict"
    }.freeze

    # Comando CDP que lê o jar do contexto — MESMO texto usado na sonda de vida
    # (`PageFetcher.alive?` delega para `probe`, que usa `comando_storage`;
    # laudo v2 B3: se a leitura mudou, a sonda muda junto — senão o probe
    # apontaria para o caminho instável e reconstruía à toa).
    STORAGE_GET_COOKIES = "Storage.getCookies"

    # Códigos CDP da leitura:
    #
    # -32601 (comando inexistente): o ÚNICO caso em que a leitura cai no
    # fallback de página NOVA no MESMO default_context do Ferrum
    # (`create_page` + `page.cookies.all` + `close` no ensure) — nunca
    # `new_context`, cujo jar nasce vazio e morre com o request (laudo v2
    # item 2).
    #
    # -32602 ("Failed to find browser context for id", provado no probe,
    # EV §2): NÃO é sessão morta — o browser vive, só este contexto foi
    # despejado. É leitura indisponível: loga e segue com [] (o `rescue` de
    # `for` trata), sem condenar o browser e sem disparar o retry.
    CDP_COMANDO_INEXISTENTE = -32601

    class << self
      # Devolve [] quando não há sessão (ou nem browser) — quem decide se isso é
      # erro é o canal, que ainda pode cair no jar.
      #
      # 1 retry, e SÓ quando o sinal é ESTREITO (`sessao_morta?`) E a instância
      # não está condenada (`!browser_condemned?`, Sol r2): na condenada o
      # descarte roda na saída do último holder — a 2ª leitura cairia num objeto
      # morrendo; é o próximo `browser()` que entrega a instância nova. É a
      # ossatura T3 do patch parcial, SEM inventar estado novo: a condenação é o
      # `@pending_discard` que já existia.
      def for(domain)
        tentativa = 0
        alvo = normalize(domain)

        # Lida com o browser DENTRO do ciclo de vida (track_in_flight): sem o
        # contador, um reset/quit pode rodar entre a obtenção da referência e o
        # comando CDP — referência obtida não é posse do ciclo de vida (Sol r1,
        # item 3 do PR #148).
        begin
          PageFetcher.track_in_flight do
            browser = PageFetcher.browser
            ler_por_contexto(browser, alvo)
          end
        rescue StandardError => e
          if PageFetcher.sessao_morta?(e) && !PageFetcher.browser_condemned? && tentativa < 1
            tentativa += 1
            Rails.logger.warn "[Fetcher::BrowserCookies] sessão do Chrome morta (#{e.class}: #{e.message}) — reconstruindo browser e tentando de novo"
            PageFetcher.reset_browser!
            retry
          end
          # Sinal não-morto (inclui -32602: contexto despejado, browser vivo)
          # ou instância condenada: loga e devolve [] — SEM condenar o browser,
          # SEM 2ª leitura na condenada.
          Rails.logger.warn "[Fetcher::BrowserCookies] sessão do Chrome indisponível: #{e.class}: #{e.message}"
          []
        end
      end

      # Sonda de vida da sessão — usada por `PageFetcher.alive?` sobre a
      # instância JÁ EM CACHE: em `PageFetcher.browser`, o `alive?` só roda
      # dentro do `if @browser && (expired? || !alive?(@browser) || ...)`.
      # NÃO existe sonda pós-build: a instância recém-criada vem de
      # `build_browser` sem sonda alguma (`@browser ||= begin ... build_browser
      # end`), então um contexto recém-criado inválido só seria percebido na
      # chamada SEGUINTE de `browser`, via `alive?`.
      #
      # Critério anti-regressão (laudo r3 B5 / v2 B3): a sonda usa o MESMO
      # comando da leitura (`version` + `Storage.getCookies` com
      # browserContextId, cliente raiz) e NUNCA a página default — era ela que
      # produzia o -32001. O timeout é o `BROWSER_PROBE_TIMEOUT` (2s): o client
      # do ferrum está configurado com `timeout: 30` (config/initializers/
      # ferrum.rb), então uma sessão pendurada bloquearia 30s aqui.
      #
      # -32601 cai no mesmo fallback de página da leitura; -32602 devolve false
      # (sonda falhou → o descarte/rebuild da instância em cache é o caminho de
      # cura do H2, e pós-hotfix B2 é barato: só o WS local morre).
      def probe(browser)
        Timeout.timeout(PageFetcher::BROWSER_PROBE_TIMEOUT) do
          browser.version
          ler_por_contexto(browser, nil)
        end
        true
      rescue Timeout::Error, StandardError => e
        Rails.logger.warn "[Fetcher::BrowserCookies] browser não respondeu à sonda (#{e.class}) — descartando"
        false
      end

      # Injeta cookies no contexto PADRÃO do Chrome em execução.
      #
      # LIMITE MEDIDO EM 04/08, COM CONTROLE: o `chromedp/headless-shell` NÃO grava
      # cookie em disco, nem com `--user-data-dir`, nem após navegação real, nem
      # com parada graciosa — nenhum arquivo `Cookies` chega a existir no perfil.
      # Logo, o que se injeta aqui vive apenas enquanto o processo do Chrome viver.
      # O armazém durável continua sendo o jar (`Fetcher::CookieJar`); isto é a
      # cópia de trabalho, útil enquanto o navegador está de pé.
      #
      # Recebe o export cru do Cookie-Editor (com `expirationDate`, `secure`,
      # `httpOnly`, `sameSite`), não os quatro campos reduzidos do jar. O motivo é
      # o `expires`: cookie injetado sem prazo é cookie de SESSÃO e o Chrome o
      # descarta no próximo restart — o perfil persistiria vazio, que é
      # exatamente o problema que ele deveria resolver.
      #
      # Devolve quantos cookies do lote são lidos de volta, para a carga poder ser
      # conferida sem imprimir valor nenhum.
      #
      # FORA DO CAMINHO QUENTE — laudo r3 item 5: o grep do perito só achou
      # `load!` em testes. Mantido como estava (não é alvo desta cura).
      def load!(cookies)
        postos = Array(cookies).filter_map do |cookie|
          nome = cookie["name"].to_s
          next if nome.empty?

          PageFetcher.track_in_flight do
            PageFetcher.browser.cookies.set(**atributos(cookie))
          end
          nome
        end

        dominios = Array(cookies).filter_map { |c| c["domain"].to_s.presence }.uniq
        lidos = dominios.flat_map { |d| self.for(d) }.map { |c| c["name"] }.uniq
        { postos: postos.size, confirmados: (postos & lidos).size }
      end

      private

      # Leitura do jar do default_context do Ferrum pelo cliente raiz — o
      # caminho principal, que substituiu a leitura na página default
      # (`browser.cookies.all`, a origem do -32001). Sem página, sem sessionId:
      # o comando vai ao cliente raiz (Ferrum delega `command` => `client`).
      #
      # Fallback, SÓ se a chamada devolver -32601 (comando inexistente neste
      # Chrome): página NOVA no MESMO default_context do Ferrum
      # (`create_page` + `page.cookies.all`, fechada no ensure) — nunca
      # `new_context`. -32602 e demais: re-levantam — o `rescue` de `for`
      # trata (loga e devolve [], sem condenar o browser).
      #
      # O resultado do fallback é DEVOLVIDO, não descartado: o `-32601` é o
      # caminho de leitura alternativo, não uma falha. Re-levantar depois de ler
      # pela página jogava fora os cookies já lidos e `for` devolvia `[]` mesmo
      # com a leitura de reserva tendo funcionado (LACUNA 1 da lane A3 — as
      # quatro asserções do teste (b)3 de `cura_sessao_cdp_test.rb`).
      def ler_por_contexto(browser, alvo)
        jar_do_root(browser, alvo)
      rescue Ferrum::BrowserError => e
        raise unless e.code.to_i == CDP_COMANDO_INEXISTENTE

        Rails.logger.warn "[Fetcher::BrowserCookies] #{STORAGE_GET_COOKIES} inexistente neste Chrome (CDP -32601) — fallback: página nova no MESMO default_context do Ferrum"
        ler_via_pagina(browser, alvo)
      end

      # `browserContextId` é OBRIGATÓRIO: a chamada SEM id lê o jar implícito do
      # Chrome, que o probe provou ser sempre vazio (EV §1: 0 cookies em
      # repouso, só service_worker). O id é o do default_context CRIADO pelo
      # Ferrum (`Target.createBrowserContext`), onde o perfil de render vive
      # (laudo r3 B1/B2; EV §4: `Context#id` confirmado no ferrum-0.18.0 da
      # imagem de produção).
      def jar_do_root(browser, alvo)
        resposta = comando_storage(browser)
        Array(resposta && resposta["cookies"]).filter_map do |cookie|
          construir_cookie(cookie, alvo)
        end
      end

      # O comando CDP da leitura — MESMO texto usado na sonda (`probe`). Raiz,
      # sem página, com o browserContextId do default_context.
      def comando_storage(browser)
        browser.command(STORAGE_GET_COOKIES, browserContextId: browser.default_context.id)
      end

      # Fallback de página, só -32601: página NOVA no MESMO default_context do
      # Ferrum (não `new_context`: jar vazio + morre com o request), lida com
      # `page.cookies.all` (o MESMO filtro de domínio) e fechada no ensure.
      def ler_via_pagina(browser, alvo)
        page = browser.default_context.create_page
        begin
          page.cookies.all.each_value.filter_map do |cookie|
            construir_cookie(cookie, alvo)
          end
        ensure
          close_quietly(page)
        end
      end

      # O MESMO filtro de domínio de hoje (browser_cookies.rb:40-47 do código
      # anterior): `matches?` + os quatro campos, path vazio vira "/".
      # `cookie` pode vir dos dois lados: hash do CDP (leitura raiz, chaves
      # string) ou `Ferrum::Cookie` (objeto, fallback de página).
      # `alvo == nil` (sonda) dispensa o filtro: a sonda só quer saber se a
      # chamada responde, não quais cookies vêm.
      def construir_cookie(cookie, alvo)
        campos = cookie.is_a?(Hash) ? campos_cdp(cookie) : campos_ferrum(cookie)
        nome, valor, dominio, path = campos
        return nil if alvo && !matches?(dominio, alvo)

        {
          "name"   => nome.to_s,
          "value"  => valor.to_s,
          "domain" => dominio.to_s,
          "path"   => path.to_s.presence || "/"
        }
      end

      def campos_cdp(cookie)
        [cookie["name"], cookie["value"], cookie["domain"], cookie["path"]]
      end

      def campos_ferrum(cookie)
        [cookie.name, cookie.value, cookie.domain, cookie.path]
      end

      def close_quietly(page)
        page&.close
      rescue StandardError => e
        Rails.logger.warn "[Fetcher::BrowserCookies] falha ao fechar a página de fallback (#{e.class}: #{e.message})"
      end

      def atributos(cookie)
        base = {
          name:   cookie["name"].to_s,
          value:  cookie["value"].to_s,
          domain: cookie["domain"].to_s,
          path:   cookie["path"].to_s.presence || "/",
          secure: !cookie["secure"].nil? && cookie["secure"] != false
        }
        base[:httponly] = true if cookie["httpOnly"]
        base[:samesite] = SAME_SITE[cookie["sameSite"].to_s] if SAME_SITE.key?(cookie["sameSite"].to_s)
        # `Ferrum::Cookies#set` faz `expires.to_i` e só o usa quando positivo
        # (cookies.rb:128) — sem isto o cookie vira de sessão e morre no restart.
        base[:expires] = cookie["expirationDate"].to_i if cookie["expirationDate"].to_f.positive?
        base
      end

      # `.youtube.com`, `youtube.com` e `www.youtube.com` são a mesma sessão.
      def matches?(cookie_domain, alvo)
        atual = normalize(cookie_domain)
        atual == alvo || atual.end_with?(".#{alvo}")
      end

      def normalize(domain)
        domain.to_s.downcase.delete_prefix(".").delete_prefix("www.")
      end
    end
  end
end
