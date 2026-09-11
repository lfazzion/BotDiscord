# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/fetcher/browser_cookies"
require_relative "../../../lib/fetcher/page_fetcher"

# CURA (TDD) da sessão de target CDP — laudo r3 B5 / v2 B3.
#
# O par RED/GREEN é rodado pelo maestro via testctl. Estes testes modelam a API
# NOVA (leitura pelo cliente raiz `Storage.getCookies` com `browserContextId` do
# `default_context`, SEM a página default) e, salvo onde declarado, FALHAM no
# código ANTES do patch:
#
#   (a) a sonda `alive?` usa a MESMA via da leitura (comando CDP), sem a página
#       default — pre-patch ela só rodava `version` e nunca o comando de
#       Storage;
#   (b) a leitura de cookies roda no `default_context` (browserContextId do
#       contexto padrão do Ferrum), NUNCA no contexto do fetch
#       (`disposeOnDetach: true`) — pre-patch era `browser.cookies.all`, e o
#       dublê da página default EXPLODE se for tocado;
#   (c) a marca de instância condenada (`browser_condemned?` / @pending_discard)
#       NÃO dispara reset do browser compartilhado — pre-patch não existe
#       `browser_condemned?` e `for` reconstruía mesmo condenada;
#   (d) o predicado "sessão morta" continua ESTREITO (não captura JS/Node nem
#       sanitização de cookie) — trava de regressão, não discriminador.
#
# Nada de rede, Chrome real ou sleep: tudo com dublês.
class Fetcher::CuraSessaoCdpTest < ActiveSupport::TestCase
  # ── Dublês no formato do Ferrum raiz (browser.rb / context.rb / client.rb) ──
  # `command` no Browser vai ao Client raiz (browser.rb:38), SEM sessionId.
  # `default_context` é o contexto CRIADO pelo Ferrum (Context#id, EV §4).

  # Cookie do jar lido pela página (fallback) — responde a name/value/domain/path.
  FerrumCookie = Struct.new(:name, :value, :domain, :path)

  # A página default é o caminho VETADO (laudo r3, origem do -32001): se a
  # leitura ou a sonda voltarem a `browser.cookies.all`, o dublê EXPLODE.
  class PaginaDefaultExcecao < StandardError; end

  # Espia `cookies.all` na página: chamado = defeito. `raise_error` injeta o
  # erro de sessão morta (zumbi) no caminho LEGADO — assim, no código ANTES do
  # patch, a mesma instância "zumbi" leva a leitura (que era `cookies.all`) a
  # morrer por sessão CDP, e os testes (c) discriminam RED/GREEN.
  class CookiesSpy
    attr_reader :all_calls

    def initialize(raise_error: nil)
      @raise_error = raise_error
      @all_calls = 0
    end

    def all
      @all_calls += 1
      raise @raise_error || PaginaDefaultExcecao.new(
        "a leitura/sonda passou pela pagina default (browser.cookies.all) — vetado pelo laudo r3 (origem do -32001)"
      )
    end
  end

  # Página nova criada no MESMO default_context (fallback -32601). `close` é
  # rastreada: o fallback TEM de fechar no ensure.
  class EspiaoPage
    attr_reader :closed, :cookies

    def initialize(cookie_map = {})
      @cookie_map = cookie_map
      @closed = false
      @cookies = EspiaoPageCookies.new(cookie_map)
    end

    def close
      @closed = true
    end
  end

  class EspiaoPageCookies
    def initialize(cookie_map = {})
      @cookie_map = cookie_map
    end

    def all
      @cookie_map
    end
  end

  # Contexto do Ferrum. `id` é o `browserContextId` do CDP; `create_page` é o
  # fallback de página nova no MESMO contexto (nunca `new_context`).
  class EspiaoContext
    attr_reader :id, :pages_criadas, :last_page

    def initialize(id, fallback_cookies: {})
      @id = id
      @fallback_cookies = fallback_cookies
      @pages_criadas = 0
      @last_page = nil
    end

    def create_page
      @pages_criadas += 1
      @last_page = EspiaoPage.new(@fallback_cookies)
      @last_page
    end
  end

  # Coleção de contextos do fetch (disposeOnDetach). Rastreia `create`: a leitura
  # de cookies NÃO pode tocar nela — só o default_context.
  class EspiaoContexts
    attr_reader :creates, :last_options

    def initialize
      @creates = 0
      @last_options = nil
    end

    def create(**options)
      @creates += 1
      @last_options = options
      EspiaoContext.new("ctx_fetch")
    end
  end

  # Browser raiz no formato do Ferrum que a API NOVA consome.
  class EspiaoBrowser
    attr_reader :calls, :default_context, :contexts, :cookies_spy

    def initialize(cookies: [], command_result: nil, command_error: nil,
                   default_ctx_id: "ctx_default", fallback_cookies: {}, spy_error: nil)
      @calls = []
      @command_result = command_result || { "cookies" => cookies }
      @command_error = command_error
      @default_context = EspiaoContext.new(default_ctx_id, fallback_cookies: fallback_cookies)
      @contexts = EspiaoContexts.new
      # `spy_error`: o erro que a leitura LEGADA (`cookies.all`) levanta no
      # código ANTES do patch — o mesmo erro de sessão da `command_error`, para
      # o zumbi existir do lado antigo e os testes (c) discriminarem.
      @cookies_spy = CookiesSpy.new(raise_error: spy_error)
    end

    def version
      @calls << [:version, nil]
      "HeadlessChrome/147.0.7727.102"
    end

    def command(cmd, **params)
      @calls << [:command, cmd, params]
      raise @command_error if @command_error

      @command_result
    end

    def cookies
      @cookies_spy
    end
  end

  def calls_do(espiao, verb)
    espiao.calls.select { |c| c[0] == verb }
  end

  # PageFetcher guarda estado em variáveis de classe (@in_flight, @pending_discard,
  # @browser_received, ...) — a suíte do repo o isola em setup/teardown
  # (page_fetcher_browser_test.rb); faço o mesmo para não contaminar os vizinhos.
  setup do
    Fetcher::PageFetcher.instance_variable_set(:@browser, nil)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, nil)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_dirty, false)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # (a) A sonda alive? usa a MESMA via da leitura — comando CDP no raiz, com
  #     browserContextId do default_context — e NÃO toca a página default.
  #     Pre-patch, alive? só rodava `version` e nunca o comando de Storage,
  #     então `refute_empty storage_calls` falha nesse código.
  # ──────────────────────────────────────────────────────────────────────────
  test "(a) alive?: version ok + Storage.getCookies(browserContextId:) ok devolve true, e a sonda NUNCA passa pela pagina default" do
    espiao = EspiaoBrowser.new(cookies: [cdo_sido_do_default])

    assert_equal true, Fetcher::PageFetcher.alive?(espiao)

    storage_calls = calls_do(espiao, :command).select do |(_t, cmd, params)|
      cmd == "Storage.getCookies" && params[:browserContextId] == espiao.default_context.id
    end
    refute_empty storage_calls,
                 "a sonda tem de usar a MESMA chamada da leitura (laudo r3 B5 / v2 B3) — " \
                 "o probe antigo só rodava version e ficava apontando para o caminho instável"
    assert_equal 0, espiao.cookies_spy.all_calls,
                   "a sonda NÃO pode passar pela pagina default (origem do -32001): browser.cookies.all nunca é chamada"
  end

  test "(a) alive? é probe dual: version ANTES do comando de storage, nunca pagina default" do
    espiao = EspiaoBrowser.new(cookies: [cdo_sido_do_default])

    Fetcher::PageFetcher.alive?(espiao)

    version_idx = espiao.calls.index { |c| c[0] == :version }
    storage_idx = espiao.calls.index { |c| c[0] == :command && c[1] == "Storage.getCookies" }
    refute_nil version_idx, "o probe tem de rodar version (sinal barato de WS de pé)"
    refute_nil storage_idx,
               "o probe tem de rodar o comando da leitura MESMO (laudo v2 B3) — " \
               "pre-patch ele só rodava version e ficava apontando para o caminho instável"
    assert_operator version_idx, :<, storage_idx,
                   "version roda ANTES do comando (probe dual do laudo: WS vivo → jar do contexto)"
    assert_equal 0, espiao.cookies_spy.all_calls,
                  "a sonda não usa a pagina default"
  end

  # ──────────────────────────────────────────────────────────────────────────
  # (b) A leitura de cookies roda no default_context (browserContextId do
  #     contexto padrão do Ferrum), NUNCA no contexto do fetch (o que nasce
  #     com disposeOnDetach: true e morre com a sessão). Pre-patch, for()
  #     usava browser.cookies.all — o dublê explode (PaginaDefaultExcecao)
  #     e for() devolve [] — as asserções de nomes/cookie falham nesse código.
  # ──────────────────────────────────────────────────────────────────────────
  test "(b) for() lê o jar do default_context e filtra dominio, sem tocar pagina default" do
    espiao = EspiaoBrowser.new(cookies: [
                                 cdo_sido_do_default,
                                 { "name" => "sessionid", "value" => "xyz", "domain" => ".reddit.com", "path" => "/" }
                               ])
    Fetcher::PageFetcher.stubs(:browser).returns(espiao)

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "só o cookie do dominio alvo (mesmo filtro de antes da migração)"
    assert_equal "abc", lidos.first["value"]
    assert_equal 0, espiao.cookies_spy.all_calls,
                   "o caminho principal NÃO usa browser.cookies.all (a pagina default)"
  end

  test "(b) for() envia o browserContextId do default_context, nunca o contexto do fetch" do
    espiao = EspiaoBrowser.new(cookies: [cdo_sido_do_default])
    Fetcher::PageFetcher.stubs(:browser).returns(espiao)

    Fetcher::BrowserCookies.for("youtube.com")

    storage = calls_do(espiao, :command).find { |(_t, cmd, _p)| cmd == "Storage.getCookies" }
    refute_nil storage, "a leitura tem de ser um comando CDP no cliente raiz"
    assert_equal espiao.default_context.id, storage.last[:browserContextId],
                 "a leitura tem de mirar o default_context (jar de render), não o contexto do fetch"
    assert_equal 0, espiao.contexts.creates,
                 "for() não pode criar/reaproveitar contexto de fetch (disposeOnDetach: true)"
  end

  test "(b) fallback -32601 cria pagina nova no MESMO default_context, lê e fecha no ensure" do
    comando_inexistente = Ferrum::BrowserError.new("message" => "'Storage.getCookies' wasn't found", "code" => -32601)
    espiao = EspiaoBrowser.new(command_error: comando_inexistente,
                               fallback_cookies: { "SID" => FerrumCookie.new("SID", "abc", ".youtube.com", "/") })
    Fetcher::PageFetcher.stubs(:browser).returns(espiao)

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] }
    assert_equal 1, espiao.default_context.pages_criadas,
                   "o fallback -32601 cria a pagina no MESMO default_context (nunca new_context)"
    assert espiao.default_context.last_page.closed,
           "a pagina de fallback tem de ser fechada no ensure (sem leak de target)"
    assert_equal 0, espiao.contexts.creates,
                 "o fallback NAO abre um contexto de fetch (disposeOnDetach)"
  end

  # ──────────────────────────────────────────────────────────────────────────
  # (c) A marca de instância condenada não dispara reset do browser
  #     compartilhado. Pre-patch não existe browser_condemned?, e for()
  #     reconstruía (reset_browser!) mesmo condenada — `expects(never)`
  #     falha nesse código.
  # ──────────────────────────────────────────────────────────────────────────
  test "(c) browser_condemned? espelha @pending_discard" do
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, true)
    assert_equal true, Fetcher::PageFetcher.browser_condemned?,
                   "instância condenada (Sol r2) deve ser reportada — o retry de for() não pode cair nela"
  ensure
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
  end

  test "(c) instância condenada + sessão morta (received == 1): for() NÃO reseta e devolve []" do
    # T3 real: um holder de fato segura a instância (received == 1). O descarte
    # fica ADIADO na saída do último holder (page_fetcher.rb:156-158: só roda
    # discard_locked! quando @browser_received == 0), então @pending_discard
    # sobrevive ao ensure do track_in_flight — e é isso que `for` deve respeitar.
    zumbi = EspiaoBrowser.new(command_error: Ferrum::DeadBrowserError.new("message" => "ws fechado"),
                              spy_error: Ferrum::DeadBrowserError.new("message" => "ws fechado"))
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, true)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 1)
    Fetcher::PageFetcher.stubs(:browser).returns(zumbi)
    Fetcher::PageFetcher.expects(:reset_browser!).never

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "na instância condenada a 2ª leitura cairia num objeto morrendo — " \
                 "devolve [] e deixa o descarte rodar na saida do ultimo holder"
  ensure
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
  end

  test "NÃO condenada + sessão morta: for() reconstrói UMA vez e a 2ª leitura já sai lida" do
    zumbi = EspiaoBrowser.new(command_error: Ferrum::DeadBrowserError.new("message" => "ws fechado"),
                              spy_error: Ferrum::DeadBrowserError.new("message" => "ws fechado"))
    saudavel = EspiaoBrowser.new(cookies: [cdo_sido_do_default])
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    # 1ª chamada pega o zumbi; após o reset (received == 0 → descarte imediato),
    # a 2ª volta já no browser saudável.
    Fetcher::PageFetcher.stubs(:browser).returns(zumbi, saudavel)
    Fetcher::PageFetcher.expects(:reset_browser!).once

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "o retry acontece APENAS quando a instância não está condenada"
  end

  # ──────────────────────────────────────────────────────────────────────────
  # (d) O predicado "sessão morta" continua ESTREITO — trava de regressão
  #     (comportamento pré-existente, que o patch não pode alargar). Não é o
  #     que diferencia RED/GREEN, mas impede regressão futura do sinal.
  # ──────────────────────────────────────────────────────────────────────────
  test "(d) erro de JavaScript nao é sessão morta" do
    js = Ferrum::JavaScriptError.new("exception" => { "className" => "TypeError",
                                                       "description" => "cannot read property of undefined" })
    assert_not Fetcher::PageFetcher.sessao_morta?(js)
  end

  test "(d) falha de sanitizacao de cookie nao é sessão morta" do
    assert_not Fetcher::PageFetcher.sessao_morta?(Ferrum::BrowserError.new("message" => "Sanitizing cookie failed"))
  end

  test "(d) node morto (NodeNotFoundError) nao é sessão morta" do
    assert_not Fetcher::PageFetcher.sessao_morta?(Ferrum::NodeNotFoundError.new("message" => "No node with given id found"))
  end

  test "(d) o sinal ESTREITO continua reconhecendo sessão CDP morta" do
    assert Fetcher::PageFetcher.sessao_morta?(Ferrum::DeadBrowserError.new)
    assert Fetcher::PageFetcher.sessao_morta?(Ferrum::BrowserError.new("message" => "Session with given id not found"))
  end

  private

  # Um cookie do jar de render, no formato que o CDP devolve em response["cookies"].
  def cdo_sido_do_default
    { "name" => "SID", "value" => "abc", "domain" => ".youtube.com", "path" => "/" }
  end
end
