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
  # A leitura é a chamada RAIZ do CDP (`Storage.getCookies`), SEM `sessionId` e
  # SEM `browserContextId`: o jar do perfil é o IMPLÍCITO, e ele é lido OMITINDO
  # o parâmetro. Também NÃO passa pela página default do Ferrum
  # (`browser.cookies.all`): era ela o -32001 de produção, porque a página tem
  # sessionId e a sessão CDP morta a leva junto.
  #
  # MEDIÇÃO EM CHROME REAL, imagem de produção (laudo r5; evidência em
  # /tmp/revisao-b1/evidencia/medicao-C-vias-producao.txt):
  #
  #   Storage.getCookies (raiz, sem id)     → OK {"cookies"=>[]}   (C:8)
  #   Storage.getCookies com id do CDP      → CDP -32602           (C:9)
  #   Storage.getCookies com id nil/vazio   → CDP -32602           (C:15)
  #   Target.getBrowserContexts             → publica o id do padrão,
  #                                           que este comando RECUSA (C:6-7)
  #   Network.getAllCookies (raiz)          → CDP -32601           (C:14)
  #   browser.cookies.all (página default)  → CDP -32001           (C:11)
  #   default_context.create_page           → CDP -32602           (C:12)
  #   contexts.create + create_page         → OK, mas jar ISOLADO e vazio (C:13)
  #
  # `browser.default_context.id` é nil no ferrum 0.18 da imagem (o Ferrum só
  # preenche `id` em contexto que ele MESMO cria), e o `defaultBrowserContextId`
  # que o CDP publica existe mas é RECUSADO por este comando. Nenhum dos dois
  # alimenta a leitura: quem a faz funcionar é a AUSÊNCIA do parâmetro.
  #
  # `{"cookies"=>[]}` na chamada sem id é o jar implícito VAZIO em repouso (o
  # headless-shell não persiste cookie em disco — comentário de 04/08), não falha
  # da via: nesse caso o `SessionCookies` cai no `CookieJar`.
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

    # Comando CDP que lê o jar implícito do Chrome — MESMO texto usado na sonda de
    # vida (`PageFetcher.alive?` delega para `probe`, que usa `comando_storage`;
    # laudo v2 B3: se a leitura mudou, a sonda muda junto — senão o probe
    # apontaria para o caminho instável e reconstruiria à toa).
    STORAGE_GET_COOKIES = "Storage.getCookies"

    # Taxonomia dos códigos CDP que esta leitura encontra, com o tratamento dado
    # pelo `rescue` de `for` (evidência: medicao-C-vias-producao.txt):
    #
    #   -32601  comando inexistente neste Chrome   → log; []
    #           NÃO existe fallback de página: `default_context.create_page` é
    #           INEXECUTÁVEL nesta imagem (medido -32602, C:12) e
    #           `contexts.create` leria um jar ISOLADO e vazio (C:13). Chrome
    #           futuro sem o comando cai no jar do banco, igual a "Chrome
    #           indisponível".
    #   -32602  contexto recusado pelo CDP         → log; []
    #           A leitura já sai sem `browserContextId`, então não há id para
    #           degradar — não há 2ª chamada por causa dele.
    #   -32001  "Session with given id not found" → sessão morta: 1 retry se a
    #           instância NÃO está condenada; senão [].
    #   resto                                      → log; []
    #
    # Quem separa "-32001/sessão morta" de "resto" é o predicado ESTREITO
    # `PageFetcher.sessao_morta?` — nenhum número é decidido no código aqui.
    CDP_COMANDO_INEXISTENTE = -32601
    CDP_CONTEXTO_INVALIDO   = -32602

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
            ler_da_raiz(PageFetcher.browser, alvo)
          end
        rescue StandardError => e
          if PageFetcher.sessao_morta?(e) && !PageFetcher.browser_condemned? && tentativa < 1
            tentativa += 1
            Rails.logger.warn "[Fetcher::BrowserCookies] sessão do Chrome morta (#{descrever_erro(e)}: #{e.message}) — reconstruindo browser e tentando de novo"
            PageFetcher.reset_browser!
            retry
          end
          # Todo o resto (inclui -32601 e -32602: o browser vive, o comando/contexto
          # é que não atende) loga e devolve [] — SEM condenar o browser, SEM 2ª
          # leitura na condenada.
          Rails.logger.warn "[Fetcher::BrowserCookies] sessão do Chrome indisponível (#{descrever_erro(e)}: #{e.message})"
          []
        end
      end

      # Sonda de vida da sessão — usada por `PageFetcher.alive?` sobre a
      # instância JÁ EM CACHE: em `PageFetcher.browser`, o `alive?` só roda
      # dentro do `if @browser && (expired? || !alive?(@browser) || ...)`.
      # NÃO existe sonda pós-build: a instância recém-criada vem de
      # `build_browser` sem sonda alguma (`@browser ||= begin ... build_browser
      # end`), então um browser recém-criado morto só seria percebido na
      # chamada SEGUINTE de `browser`, via `alive?`.
      #
      # A sonda é `version` + a MESMA chamada da leitura (`comando_storage`, raiz
      # e sem parâmetro nenhum), NUNCA a página default — era ela que produzia o
      # -32001. Sucesso, INCLUSIVE com o jar vazio (`{"cookies"=>[]}`), é `true`:
      # jar vazio em repouso é estado legítimo, não sessão morta. O timeout é o
      # `BROWSER_PROBE_TIMEOUT` (2s), porque o client do ferrum está configurado
      # com `timeout: 30` (config/initializers/ferrum.rb) e uma sessão pendurada
      # bloquearia 30s aqui.
      #
      # Qualquer Timeout/StandardError devolve false: sonda falsa descarta a
      # instância em cache, que é o caminho de cura do H2 (pós-hotfix B2 é
      # barato: só o WS local morre).
      def probe(browser)
        Timeout.timeout(PageFetcher::BROWSER_PROBE_TIMEOUT) do
          browser.version
          comando_storage(browser)
        end
        true
      rescue Timeout::Error, StandardError => e
        Rails.logger.warn "[Fetcher::BrowserCookies] browser não respondeu à sonda (#{descrever_erro(e)}) — descartando"
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

      # A leitura propriamente dita: o comando da raiz e o filtro de domínio
      # dentro de `["cookies"]`. `alvo == nil` (sonda) dispensa o filtro: a sonda
      # só quer saber se a chamada responde, não quais cookies vêm.
      def ler_da_raiz(browser, alvo)
        resposta = comando_storage(browser)
        Array(resposta && resposta["cookies"]).filter_map do |cookie|
          construir_cookie(cookie, alvo)
        end
      end

      # O comando CDP da leitura — MESMO texto e MESMA forma usados pela sonda
      # (`probe`).
      #
      # RAIZ: sem página, sem `sessionId` e SEM `browserContextId`. Este último
      # NÃO é detalhe de estilo: `Storage.getCookies` ACEITA o parâmetro e o
      # RECUSA com -32602 tanto com o id do Ferrum (`browser.default_context.id`,
      # nil na imagem) quanto com o `defaultBrowserContextId` que o CDP publica
      # (medido em Chrome real: medicao-C-vias-producao.txt:9,15). O jar que
      # interessa é o IMPLÍCITO do perfil, e a única forma medida de lê-lo é
      # omitindo o parâmetro (C:8).
      #
      # Por isso não há consulta a `Target.getBrowserContexts` no caminho quente:
      # o id que ele publica não serve para esta chamada.
      def comando_storage(browser)
        browser.command(STORAGE_GET_COOKIES)
      end

      # O MESMO filtro de domínio de sempre (`matches?` + os quatro campos, path
      # vazio vira "/"). `cookie` é o hash do CDP — a única forma que a leitura da
      # raiz devolve.
      def construir_cookie(cookie, alvo)
        dominio = cookie["domain"]
        return nil if alvo && !matches?(dominio, alvo)

        {
          "name"   => cookie["name"].to_s,
          "value"  => cookie["value"].to_s,
          "domain" => dominio.to_s,
          "path"   => cookie["path"].to_s.presence || "/"
        }
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

      # Classifica o erro para o LOG (o código CDP é o que diz qual via falhou).
      # Nada aqui decide o fluxo: quem decide é `PageFetcher.sessao_morta?`.
      def descrever_erro(erro)
        codigo = erro.code if erro.respond_to?(:code)
        codigo ? "#{erro.class} code=#{codigo}" : erro.class.to_s
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
