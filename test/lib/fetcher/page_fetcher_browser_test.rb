# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../../lib/fetcher/page_fetcher"
# A sonda `PageFetcher.alive?` delega para `BrowserCookies.probe` (laudo r3 B5 /
# v2 B3): sem isto, este arquivo (que só puxa page_fetcher) teria NameError no
# caminho da sonda e a reescreveria como falha — falsificando os resultados.
require_relative "../../../lib/fetcher/browser_cookies"

# Defeitos do segundo nível (escalada para o Chrome), com guarda para cada um.
#
# A escalada é engolida por um `rescue` no ExtractService e vira degradação
# silenciosa — então "não levantou exceção" não prova nada aqui. Cada teste
# abaixo verifica o RECEPTOR da chamada ou o efeito observável.
class Fetcher::PageFetcherBrowserTest < ActiveSupport::TestCase
  # ── Dublês ────────────────────────────────────────────────────────────────
  # FakePage NÃO define `evaluate_on_new_document` de propósito: se o código
  # voltar a chamá-lo na página, o teste morre com NoMethodError — que é
  # exatamente o defeito que passou despercebido em produção.
  class FakeResponse
    def initialize(status:, content_type:)
      @status = status
      @headers = { "Content-Type" => content_type }
    end
    attr_reader :status, :headers
  end

  class FakeNetwork
    def initialize(response) = @response = response
    def wait_for_idle(**_opts) = nil
    attr_reader :response
  end

  class FakePage
    attr_reader :visited, :closed, :timeout_during_goto
    attr_accessor :timeout

    def initialize(body_text: "conteúdo renderizado por javascript", status: 200,
                   content_type: "text/html", document_remote_ip: nil)
      @body_text = body_text
      @network = FakeNetwork.new(FakeResponse.new(status: status, content_type: content_type))
      @visited = []
      @closed = false
      @document_remote_ip = document_remote_ip
      @listeners = {}
      @timeout = 12
      @timeout_during_goto = nil
    end

    def go_to(url)
      @visited << url
      @timeout_during_goto = @timeout
      # O Ferrum emite Network.responseReceived do documento durante o go_to;
      # o dublê emite na mesma hora para o assinante do RebindingGuard pegar.
      return unless @document_remote_ip

      Array(@listeners["Network.responseReceived"]).each do |blk|
        blk.call("type" => "Document",
                 "response" => { "url" => url, "remoteIPAddress" => @document_remote_ip })
      end
    end

    def on(event, &block)
      (@listeners[event] ||= []) << block
      @listeners[event].size - 1
    end

    def off(event, id)
      @listeners[event]&.delete_at(id)
      true
    end

    def body = "<html><body>#{@body_text}</body></html>"
    def title = "Título Renderizado"
    def current_url = @visited.last
    def close = (@closed = true)
    attr_reader :network

    def evaluate(js)
      return { "text" => @body_text, "html" => "<p>#{@body_text}</p>" } if js.include?("Readability")
      return @body_text.length if js.include?("innerText.length")

      @body_text
    end
  end

  class FakeContext
    attr_reader :page, :disposed

    def initialize(page)
      @page = page
      @disposed = false
    end

    def create_page = @page
    def dispose = (@disposed = true)
  end

  class FakeContexts
    attr_reader :last_options, :reset_called, :contexts

    def initialize(context)
      @context = context
      @last_options = nil
      @reset_called = false
      @contexts = context ? { "ctx1" => context } : {}
    end

    def create(**options)
      @last_options = options
      @context
    end

    def reset
      @reset_called = true
      @contexts.each_value { |c| c.dispose if c.respond_to?(:dispose) }
      true
    end

    def size
      @contexts.size
    end
  end

  class FakeBrowser
    attr_reader :contexts, :injected, :version_calls, :reset_called, :quit_called, :call_order

    def initialize(context: nil, version_error: nil)
      @contexts = FakeContexts.new(context) if context
      @injected = []
      @version_error = version_error
      @version_calls = 0
      @reset_called = false
      @quit_called = false
      @call_order = []
    end

    def evaluate_on_new_document(source) = @injected << source

    def version
      @version_calls += 1
      raise @version_error if @version_error

      "HeadlessChrome/131.0.0.0"
    end

    # A sonda `alive?` delega para `BrowserCookies.probe` (laudo r3 B5 / v2 B3),
    # que roda `version` + o comando de storage (`browser.command`) na RAIZ, SEM
    # `browserContextId` (a chave devolve -32602: medicao-C-vias-producao.txt).
    # Sem `command` no dublê, a sonda daria NoMethodError e devolveria `false` —
    # descartando o browser vivo à toa e falsificando os testes de
    # reaproveitamento. Modelamos o caminho NOVO para o browser ser considerado
    # vivo.
    def command(_cmd, **_params)
      { "cookies" => [] }
    end

    def default_context
      @default_context ||= Struct.new(:id).new("ctx_default")
    end

    def reset
      @reset_called = true
      @call_order << :reset
      @contexts&.reset
      true
    end

    def quit
      @quit_called = true
      @call_order << :quit
      true
    end
  end

  setup do
    Rails.cache.clear
    Fetcher::SsrfGuard.stubs(:resolve_all).returns(["8.8.8.8"])
    Fetcher::PageFetcher.stubs(:hard_domains).returns([])
    Fetcher::PageFetcher.instance_variable_set(:@browser, nil)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, nil)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_dirty, false)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
  end

  teardown do
    Fetcher::PageFetcher.instance_variable_set(:@browser, nil)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, nil)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_dirty, false)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Thread.current[:page_fetcher_holds_browser] = nil
  end

  # ── DEFEITO 1: método chamado no objeto errado ────────────────────────────

  test "evaluate_on_new_document é método de Ferrum::Browser, não de Ferrum::Page" do
    assert Ferrum::Browser.method_defined?(:evaluate_on_new_document),
           "o receptor correto perdeu o método — reveja build_browser contra o fonte do ferrum"
    assert_not Ferrum::Page.method_defined?(:evaluate_on_new_document),
               "ferrum passou a expor o método na Page: reavalie onde injetar o stealth"
  end

  test "build_browser injeta o STEALTH_JS no browser recém-construído" do
    fake = FakeBrowser.new
    FerumConfig.stubs(:browser_options).returns({})
    Ferrum::Browser.stubs(:new).returns(fake)

    built = Fetcher::PageFetcher.send(:build_browser)

    assert_same fake, built
    assert_equal [Fetcher::PageFetcher::STEALTH_JS], fake.injected,
                 "o stealth não chegou ao browser — toda página nasceria sem ele"
  end

  test "o render NÃO chama evaluate_on_new_document na página" do
    page = FakePage.new
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    # FakePage não implementa o método: se o código o chamar, isto levanta
    # NoMethodError — o mesmo erro visto nos logs de produção.
    payload = fetcher.call("https://exemplo.test/pagina")

    assert_equal "Título Renderizado", payload[:title]
    assert_includes payload[:content], "renderizado por javascript"
    assert_equal ["https://exemplo.test/pagina"], page.visited
  end

  test "escalada completa sobrevive ao render: conteúdo chega ao ExtractService" do
    page = FakePage.new(body_text: "dados que só existem depois do javascript " * 20)
    browser = FakeBrowser.new(context: FakeContext.new(page))

    Fetcher::PageFetcher.any_instance.stubs(:wait_for_body_stabilize)
    Fetcher::PageFetcher.stubs(:browser).returns(browser)

    # estático magro força a escalada
    stub_request(:get, "https://spa.test/")
      .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>",
                 headers: { "Content-Type" => "text/html" })

    result = Fetcher::ExtractService.call("https://spa.test/")

    assert_nil result[:error], result.inspect
    assert_equal "chrome", result[:engine]
    assert result[:rendered]
    assert_includes result[:content], "depois do javascript"
  end

  # ── DEFEITO 2: browser em cache não se cura ───────────────────────────────

  test "browser em cache com sessão morta é descartado e reconstruído" do
    dead = FakeBrowser.new(version_error: Ferrum::DeadBrowserError.new("ws fechado"))
    fresh = FakeBrowser.new

    Fetcher::PageFetcher.instance_variable_set(:@browser, dead)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.expects(:build_browser).once.returns(fresh)

    assert_same fresh, Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser },
                "o browser morto foi devolvido do cache — é o que envenena a escalada por 24h"
    assert_equal 1, dead.version_calls
  end

  test "browser vivo é reaproveitado, sem reconstruir" do
    live = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, live)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.expects(:build_browser).never

    assert_same live, Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser }
    assert_same live, Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser }
    assert_equal 2, live.version_calls, "a sonda tem que rodar a cada uso"
  end

  test "sonda pendurada não bloqueia além do próprio timeout" do
    hung = FakeBrowser.new
    hung.define_singleton_method(:version) { sleep 30 }

    started = Time.current
    assert_not Fetcher::PageFetcher.send(:alive?, hung)
    elapsed = Time.current - started

    assert_operator elapsed, :<, Fetcher::PageFetcher::BROWSER_PROBE_TIMEOUT + 1,
                    "a sonda herdou o timeout de 30s do client do ferrum"
  end

  test "browser expirado por idade continua sendo descartado" do
    old = FakeBrowser.new
    fresh = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, old)
    Fetcher::PageFetcher.instance_variable_set(
      :@browser_started_at, Time.current - Fetcher::PageFetcher::BROWSER_MAX_AGE - 60
    )
    Fetcher::PageFetcher.expects(:build_browser).once.returns(fresh)

    assert_same fresh, Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser }
  end

  test "sessão que morre durante o render dispara uma retentativa com browser novo" do
    page = FakePage.new
    good = FakeBrowser.new(context: FakeContext.new(page))

    fetcher = Fetcher::PageFetcher.new
    rendered = { title: "ok", final_url: "https://x.test/", readability_text: "texto suficiente " * 40,
                 readability_html: "", body_text: "texto", html: "", status: 200 }

    fetcher.expects(:render_via_ferrum).twice
           .raises(Ferrum::DeadBrowserError).then.returns(rendered)
    Fetcher::PageFetcher.expects(:reset_browser!).once

    payload = fetcher.call("https://x.test/")

    assert_equal "ok", payload[:title]
  end

  test "render timeout descarta o browser para a próxima chamada não herdar a sessão" do
    fetcher = Fetcher::PageFetcher.new
    # Timeout::Error levantado DENTRO do bloco de render é o caminho real do
    # travamento de 25s medido em produção.
    Fetcher::PageFetcher.stubs(:browser).raises(Timeout::Error)
    Fetcher::PageFetcher.expects(:reset_browser!).at_least_once

    assert_raises(Fetcher::PageFetcher::RenderTimeout) { fetcher.call("https://lento.test/") }
  end

  test "Ferrum::TimeoutError no go_to com body vazio vira RenderTimeout e nao sobe cru" do
    page = FakePage.new(body_text: "")
    page.stubs(:go_to).raises(Ferrum::TimeoutError)
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })

    assert_raises(Fetcher::PageFetcher::RenderTimeout) do
      fetcher.call("https://timeout.test/")
    end
  end

  test "GOTO_TIMEOUT e aplicado durante go_to e restaurado depois" do
    page = FakePage.new(body_text: "conteúdo válido")
    page.timeout = 12
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })

    payload = fetcher.call("https://timeout-test.test/")

    assert_equal Fetcher::PageFetcher::GOTO_TIMEOUT, page.timeout_during_goto
    assert_equal 12, page.timeout
    assert_equal "Título Renderizado", payload[:title]
  end

  test "go_to soft com body presente prossegue para extracao sem RenderTimeout" do
    page = FakePage.new(body_text: "texto presente no body antes do timeout de load")
    page.stubs(:go_to).raises(Ferrum::TimeoutError)
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })

    payload = fetcher.call("https://soft-goto.test/")

    assert_includes payload[:content], "texto presente no body"
  end

  test "idle e stabilize nao comecam sem budget suficiente" do
    page = FakePage.new(body_text: "texto com pouco budget")
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })

    # Simula relógio com 0.4s de budget restante
    fetcher.expects(:wait_for_idle_soft).with(page, budget: 0.4).once
    fetcher.expects(:wait_for_body_stabilize).with(page, budget: 0.4).once

    page.network.expects(:wait_for_idle).never
    Kernel.expects(:sleep).never

    fetcher.send(:wait_for_idle_soft, page, budget: 0.4)
    fetcher.send(:wait_for_body_stabilize, page, budget: 0.4)
  end

  test "reset_browser! com holder real em voo adia; sem holder real (chamador ainda sem browser) descarta na hora (Sol r2)" do
    quit_called = false
    fake_browser = FakeBrowser.new
    fake_browser.define_singleton_method(:quit) { quit_called = true }
    Fetcher::PageFetcher.instance_variable_set(:@browser, fake_browser)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)

    # Caso 1 — outro request de fato RECEBEU a instância (received = 1):
    # o reset adia e não derruba enquanto o holder usa.
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 1)
    Fetcher::PageFetcher.track_in_flight do
      Fetcher::PageFetcher.reset_browser!
      assert_equal false, quit_called, "quit nao pode rodar enquanto holder real em voo"
    end
    assert_equal true, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                 "reset com holder real marca pending (instancia condenada)"

    # Caso 2 — chamador dentro do track mas SEM browser recebido (received = 0):
    # o descarte é IMEDIATO; um browser() subsequente recebe instância nova.
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    rebuilt = FakeBrowser.new
    rebuilt.define_singleton_method(:quit) { quit_called = true }
    Fetcher::PageFetcher.stubs(:build_browser).returns(rebuilt)
    got = nil
    Fetcher::PageFetcher.track_in_flight do
      Fetcher::PageFetcher.reset_browser!
      got = Fetcher::PageFetcher.browser
    end
    assert_same rebuilt, got,
                "browser() após reset sem holder real NÃO devolve a instância condenada"
    assert_equal false, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                 "descarte imediato limpa pending (não condena a instância nova)"
  end

  test "interleaving Sol r2: A resetou; B entra no track e recebe instância NOVA, não a condenada" do
    condemned = FakeBrowser.new
    rebuilt = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, condemned)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    Fetcher::PageFetcher.stubs(:build_browser).returns(rebuilt)

    b_entered = Queue.new
    b_can_proceed = Queue.new
    got = nil
    t_b = Thread.new do
      Fetcher::PageFetcher.track_in_flight do
        b_entered << true
        b_can_proceed.pop
        got = Fetcher::PageFetcher.browser
      end
    end
    t_b.abort_on_exception = true
    b_entered.pop # B está no track (in_flight > 0) mas ainda NÃO recebeu browser

    # A (fora do track, holders = 0): sofre timeout e reseta — descarte
    # IMEDIATO: a condenada sai do cache (pending nem persiste; o browser()
    # de B reconstruirá).
    Fetcher::PageFetcher.reset_browser!
    assert_not Fetcher::PageFetcher.instance_variable_get(:@browser).equal?(condemned),
               "instância condenada não permanece no cache"

    # B chama browser(): NÃO pode receber a condenada.
    b_can_proceed << true
    t_b.join
    assert_same rebuilt, got,
                "B recebeu instância nova (a condenada foi descartada antes da entrega)"
    assert_equal false, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                 "pending é consumido pelo descarte da condenada"
  end

  # ── DEFEITO 3: DNS rebinding no caminho Chrome ──────────────────────────
  # O SsrfGuard valida que TODOS os IPs do host são públicos, mas o Chrome
  # re-resolve o hostname sozinho no go_to. O `remoteIPAddress` do documento
  # não pode ter vindo de IP privado/loopback/metadata — mas também não precisa
  # ser o `ips.first`: CDN multi-registro e dual-stack (A+AAAA) fazem o Chrome
  # conectar em QUALQUER IP público do conjunto. O cheque é `ip_blocked?`, não
  # igualdade com o primeiro IP.

  test "documento que veio de IP privado (10.x) levanta SsrfGuard::Blocked, mesmo com IP público no conjunto" do
    page = FakePage.new(body_text: "dados", document_remote_ip: "10.0.0.1")
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    erro = assert_raises(Fetcher::SsrfGuard::Blocked) do
      fetcher.call("https://spa.test/")
    end

    assert_match(/rebinding/i, erro.message)
    assert_match(/10\.0\.0\.1/, erro.message)
  end

  test "documento que veio de loopback (127.0.0.1) levanta SsrfGuard::Blocked mesmo com outro IP público no conjunto" do
    # validação aprovou um conjunto todo público; o Chrome conectou em
    # loopback — rebinding de verdade, tem que bloquear.
    Fetcher::SsrfGuard.stubs(:resolve_all).returns(["8.8.8.8", "1.1.1.1"])
    page = FakePage.new(body_text: "dados", document_remote_ip: "127.0.0.1")
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    erro = assert_raises(Fetcher::SsrfGuard::Blocked) do
      fetcher.call("https://spa.test/")
    end

    assert_match(/127\.0\.0\.1/, erro.message)
  end

  test "documento que veio de IP público do conjunto (não o primeiro) passa — CDN/dual-stack" do
    # O bug da 1a rodada: exigia igualdade com ips.first e derrubava
    # youtube.com/reddit.com, que têm múltiplos registros A/AAAA.
    Fetcher::SsrfGuard.stubs(:resolve_all).returns(["8.8.8.8", "1.1.1.1"])
    page = FakePage.new(body_text: "dados renderizados " * 40, document_remote_ip: "1.1.1.1")
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    payload = fetcher.call("https://spa.test/")

    assert_equal "Título Renderizado", payload[:title]
    assert_includes payload[:content], "dados renderizados"
  end

  test "documento que veio de AAAA público do conjunto passa — dual-stack" do
    Fetcher::SsrfGuard.stubs(:resolve_all).returns(["8.8.8.8", "2606:2800:220:1:248:1893:25c8:1946"])
    page = FakePage.new(body_text: "dados renderizados " * 40, document_remote_ip: "2606:2800:220:1:248:1893:25c8:1946")
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    payload = fetcher.call("https://spa.test/")

    assert_equal "Título Renderizado", payload[:title]
    assert_includes payload[:content], "dados renderizados"
  end

  test "documento que veio do IP validado passa" do
    page = FakePage.new(body_text: "dados renderizados " * 40, document_remote_ip: "8.8.8.8")
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    payload = fetcher.call("https://spa.test/")

    assert_equal "Título Renderizado", payload[:title]
    assert_includes payload[:content], "dados renderizados"
  end

  test "sem remoteIPAddress no CDP o caminho segue (fail-open com log), não derruba" do
    page = FakePage.new(body_text: "conteúdo renderizado " * 40) # document_remote_ip nil
    browser = FakeBrowser.new(context: FakeContext.new(page))
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log)
    Rails.logger.level = Logger::WARN
    begin
      payload = fetcher.call("https://spa.test/")
    ensure
      Rails.logger = original_logger
    end

    assert_equal "Título Renderizado", payload[:title]
    # Contrato canônico (unificado com a PR #136): fail-open SILENCIOSO quando
    # o IP não chega (assert_document_ip! sai cedo com nil — sem log). O que
    # importa: não derruba e o conteúdo segue.
    refute_match(/rebinding/, log.string)
  end

  # ── FASE 1: ITENS 1 a 6 ───────────────────────────────────────────────────

  test "create_page levanta NoSuchTargetError: context.dispose é chamado no ensure (Item 1)" do
    fake_context = FakeContext.new(nil)
    fake_context.define_singleton_method(:create_page) do
      raise Ferrum::NoSuchTargetError, "target disappeared"
    end
    browser = FakeBrowser.new(context: fake_context)
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })

    assert_raises(Fetcher::PageFetcher::RenderTimeout) do
      fetcher.call("https://broken-target.test/")
    end

    assert_equal true, fake_context.disposed, "contexto deve ser descartado mesmo se create_page falhar"
  end

  test "Timeout::Error na criacao da pagina descarta o contexto (Item 1)" do
    fake_context = FakeContext.new(nil)
    fake_context.define_singleton_method(:create_page) do
      raise Timeout::Error, "timeout creating page"
    end
    browser = FakeBrowser.new(context: fake_context)
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })

    assert_raises(Fetcher::PageFetcher::RenderTimeout) do
      fetcher.call("https://timeout-target.test/")
    end

    assert_equal true, fake_context.disposed, "contexto deve ser descartado no timeout de create_page"
  end

  test "discard_locked! fecha o WS local (quit) SEM reset/dispose no browser (HOTFIX B2)" do
    # Laudo v2 do perito (B2): @browser.reset acionava Target.disposeBrowserContext
    # sobre contextos GLOBAIS do Chrome compartilhado app+jobs+discord-bot —
    # o descarte derrubava render em voo do vizinho. O caminho de descarte só
    # fecha o WS local (safe_quit). Se reset/dispose voltarem a rodar aqui, o
    # dublê explodindo prova na hora (as chamadas também ficam em call_order).
    fake_context = FakeContext.new(FakePage.new)
    fake_browser = FakeBrowser.new(context: fake_context)
    fake_browser.define_singleton_method(:reset) do
      @call_order << :reset
      @reset_called = true
      raise StandardError, "reset rodou no caminho de descarte — proibido (HOTFIX B2)"
    end
    fake_context.define_singleton_method(:dispose) do
      @disposed = true
      raise StandardError, "contexto foi descartado no caminho de descarte — proibido (HOTFIX B2)"
    end

    # Estado do descarte imediato: received == 0, instância condenada em cache.
    Fetcher::PageFetcher.instance_variable_set(:@browser, fake_browser)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)

    Fetcher::PageFetcher.send(:discard_locked!)

    # O WS local foi fechado (safe_quit → browser.quit):
    assert_equal true, fake_browser.quit_called,
                 "safe_quit continua fechando o WS local no descarte"
    # E reset/disposeBrowserContext NUNCA:
    assert_equal false, fake_browser.reset_called,
                 "reset não pode rodar no caminho de descarte (laudo v2, item B2)"
    assert_equal false, fake_context.disposed,
                 "contexto não pode ser descartado no caminho de descarte (vizinho)"
    assert_equal %i[quit], fake_browser.call_order,
                 "a única ação de descarte é o quit"
    # A instância condenada sai limpa do cache: o próximo uso reconstrói.
    assert_nil Fetcher::PageFetcher.instance_variable_get(:@browser)
    assert_nil Fetcher::PageFetcher.instance_variable_get(:@browser_started_at)
    assert_equal 0, Fetcher::PageFetcher.instance_variable_get(:@pages_since_start)

    # Esmagar "o próximo uso reconstrói": cache limpo → build_browser roda.
    rebuilt = FakeBrowser.new
    Fetcher::PageFetcher.expects(:build_browser).once.returns(rebuilt)
    got = Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser }
    assert_same rebuilt, got,
                "o próximo uso reconstrói a instância (cache limpo após o descarte)"
  end

  test "contexts.create recebe disposeOnDetach: true (Item 3)" do
    page = FakePage.new
    fake_context = FakeContext.new(page)
    browser = FakeBrowser.new(context: fake_context)
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    fetcher.call("https://detach-test.test/")

    assert_equal({ disposeOnDetach: true }, browser.contexts.last_options,
                 "contexts.create deve passar disposeOnDetach: true")
  end

  test "BROWSER_MAX_PAGES renders recicla browser mesmo com idade recente (Item 5)" do
    live_browser = FakeBrowser.new
    fresh_browser = FakeBrowser.new

    Fetcher::PageFetcher.instance_variable_set(:@browser, live_browser)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.instance_variable_set(
      :@pages_since_start,
      Fetcher::PageFetcher::BROWSER_MAX_PAGES
    )

    Fetcher::PageFetcher.expects(:build_browser).once.returns(fresh_browser)

    assert_same fresh_browser, Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser },
                "browser deve ser reciclado quando pages_since_start >= BROWSER_MAX_PAGES"
  end

  test "falha ao fechar pagina ou descartar contexto marca browser_dirty e proximo browser reconstroi (Item 4)" do
    page = FakePage.new
    page.define_singleton_method(:close) { raise StandardError, "erro fechando pagina" }
    fake_context = FakeContext.new(page)
    browser = FakeBrowser.new(context: fake_context)
    fetcher = Fetcher::PageFetcher.new(browser_factory: -> { browser })
    fetcher.stubs(:wait_for_body_stabilize)

    # Executa com o browser factory
    fetcher.call("https://dirty-test.test/")

    assert_equal true, Fetcher::PageFetcher.browser_dirty?, "falha no close/dispose deve marcar browser_dirty"

    # Agora verifica que PageFetcher.browser reconhece browser_dirty e descarta a instância atual
    stale_browser = FakeBrowser.new
    rebuilt_browser = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, stale_browser)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.expects(:build_browser).once.returns(rebuilt_browser)

    assert_same rebuilt_browser, Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser }
    assert_equal false, Fetcher::PageFetcher.browser_dirty?
  end

  test "semaforo MAX_INFLIGHT_PAGES limita concorrencia e o segundo espera (Item 6)" do
    active_count = 0
    max_active = 0
    mutex = Mutex.new

    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(context: FakeContext.new(FakePage.new)))
    Fetcher::PageFetcher.any_instance.stubs(:wait_for_body_stabilize)

    # Simula render rodando com tempo controlado
    threads = Array.new(4) do
      Thread.new do
        Fetcher::PageFetcher.track_in_flight do
          mutex.synchronize do
            active_count += 1
            max_active = [max_active, active_count].max
          end
          sleep 0.05
          mutex.synchronize do
            active_count -= 1
          end
        end
      end
    end

    threads.each(&:join)

    assert_operator max_active, :<=, Fetcher::PageFetcher::MAX_INFLIGHT_PAGES
    assert_operator max_active, :>=, 1
  end

  test "browser.reset descarta contextos abertos da colecao (Item 2)" do
    ctx1 = FakeContext.new(FakePage.new)
    ctx2 = FakeContext.new(FakePage.new)
    fake_contexts = FakeContexts.new(nil)
    fake_contexts.contexts["c1"] = ctx1
    fake_contexts.contexts["c2"] = ctx2

    fake_browser = FakeBrowser.new
    fake_browser.instance_variable_set(:@contexts, fake_contexts)

    fake_browser.reset

    assert_equal true, ctx1.disposed
    assert_equal true, ctx2.disposed
  end

  # ── CRITICAL (grok): browser() nao derruba o browser em uso por render in-flight ─
  test "browser() nao chama reset+quit com render in-flight: apenas marca pending_discard (overlap via BROWSER_MAX_PAGES)" do
    live_browser = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, live_browser)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)

    # Marca como expirado por pagina (BROWSER_MAX_PAGES) para forçar o caminho de descarte
    Fetcher::PageFetcher.instance_variable_set(
      :@pages_since_start, Fetcher::PageFetcher::BROWSER_MAX_PAGES
    )

    # Ordem de produção (Sol r1): OUTRO request já recebeu a instância e está em
    # voo (@browser_received = 1 simulando-o). O chamador atual chama browser()
    # dentro do track: deve receber a MESMA instância (não derrubar em uso) e o
    # descarte fica pendente até o ÚLTIMO holder soltar (fix v2: @browser_received).
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 1)

    result = nil
    Fetcher::PageFetcher.track_in_flight do
      result = Fetcher::PageFetcher.browser
      assert_same live_browser, result,
                  "browser() devolveu uma instância nova em vez do browser em uso"
      assert_equal true, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                   "pending_discard deve ser marcado, mas browser não deve ser derrubado"
      assert_equal false, live_browser.reset_called,
                   "reset NÃO pode ser chamado enquanto há holder real em voo"
      assert_equal false, live_browser.quit_called,
                   "quit NÃO pode ser chamado enquanto há holder real em voo"
    end

    # Ao sair, o chamador soltou a SUA referência, mas o holder simulado continua
    # (received = 1): o descarte NÃO dispara ainda.
    assert_equal false, live_browser.reset_called,
                 "reset não pode rodar enquanto resta holder (received > 0)"
    assert_equal false, live_browser.quit_called,
                 "quit não pode rodar enquanto resta holder (received > 0)"

    # Último holder solta: o pending_discard dispara o descarte.
    Fetcher::PageFetcher.stubs(:build_browser).returns(FakeBrowser.new)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser }
    assert_equal false, live_browser.reset_called,
                 "reset NÃO roda no descarte (HOTFIX B2: contextos globais atingem vizinhos); quem fecha o WS local é o quit"
    assert_equal true, live_browser.quit_called,
                 "quit deve rodar após o último holder soltar"
    assert_equal false, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                 "pending_discard deve ser limpo após o descarte"
  end

  test "browser() nao derruba browser dirty com render in-flight: apenas marca pending_discard (overlap via dirty path)" do
    live_browser = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, live_browser)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Fetcher::PageFetcher.instance_variable_set(:@browser_dirty, true)
    # Ordem de produção: OUTRO request já recebeu a instância e está em voo.
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 1)

    result = nil
    Fetcher::PageFetcher.track_in_flight do
      result = Fetcher::PageFetcher.browser
      assert_same live_browser, result,
                  "browser() devolveu instância nova em vez do browser dirty em uso"
      assert_equal true, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                   "pending_discard deve ser marcado para o browser dirty"
      assert_equal false, live_browser.reset_called,
                   "reset NÃO pode rodar enquanto há holder real em voo"
      assert_equal false, live_browser.quit_called,
                   "quit NÃO pode rodar enquanto há holder real em voo"
    end

    assert_equal false, live_browser.reset_called,
                 "reset não pode rodar enquanto resta holder (received > 0)"
    assert_equal false, live_browser.quit_called,
                 "quit não pode rodar enquanto resta holder (received > 0)"

    Fetcher::PageFetcher.stubs(:build_browser).returns(FakeBrowser.new)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    Fetcher::PageFetcher.track_in_flight { Fetcher::PageFetcher.browser }
    assert_equal false, live_browser.reset_called,
                 "reset NÃO roda no descarte (HOTFIX B2: contextos globais atingem vizinhos); quem fecha o WS local é o quit"
    assert_equal true, live_browser.quit_called,
                 "quit deve rodar após o último holder soltar"
    assert_equal false, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                 "pending_discard deve ser limpo após o descarte"
  end

  test "browser() com browser_dirty e in_flight <= 1 descarta e reconstroi antes de devolver (Blocker dirty fix)" do
    live_browser = FakeBrowser.new
    rebuilt_browser = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, live_browser)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Fetcher::PageFetcher.instance_variable_set(:@browser_dirty, true)

    Fetcher::PageFetcher.expects(:build_browser).once.returns(rebuilt_browser)

    result = nil
    Fetcher::PageFetcher.track_in_flight do
      result = Fetcher::PageFetcher.browser
      assert_same rebuilt_browser, result,
                  "browser() deve devolver nova instância reconstruída quando dirty e in_flight <= 1"
      assert_equal false, Fetcher::PageFetcher.browser_dirty?,
                   "browser_dirty deve ser limpo após rebuild"
      assert_equal false, live_browser.reset_called,
                   "reset NÃO roda no descarte do browser dirty (HOTFIX B2); o quit fecha o WS local"
      assert_equal true, live_browser.quit_called,
                   "quit deve rodar no browser dirty anterior"
    end
  end


  test "duas threads reais concorrentes em track_in_flight respeitam semaforo e limpam pending_discard apenas na saida da ultima" do
    live_browser = FakeBrowser.new
    Fetcher::PageFetcher.instance_variable_set(:@browser, live_browser)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, Time.current)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Fetcher::PageFetcher.instance_variable_set(:@browser_dirty, false)

    t1_inside = Queue.new
    t2_inside = Queue.new
    t1_resume = Queue.new
    t2_resume = Queue.new

    max_in_flight_observed = 0
    obs_mutex= Mutex.new

    t1 = Thread.new do
      Fetcher::PageFetcher.track_in_flight do
        Fetcher::PageFetcher.browser # ordem de produção: obtém a instância
        obs_mutex.synchronize do
          current = Fetcher::PageFetcher.instance_variable_get(:@in_flight)
          max_in_flight_observed = [max_in_flight_observed, current].max
        end
        t1_inside << true
        t1_resume.pop
      end
    end

    t2 = Thread.new do
      Fetcher::PageFetcher.track_in_flight do
        Fetcher::PageFetcher.browser # ordem de produção: obtém a instância
obs_mutex.synchronize do
          current = Fetcher::PageFetcher.instance_variable_get(:@in_flight)
          max_in_flight_observed = [max_in_flight_observed, current].max
        end
        t2_inside << true
        t2_resume.pop
      end
    end

    t1.abort_on_exception = true
    t2.abort_on_exception = true

    # Barreira determinística: aguarda ambas as threads entrarem no bloco track_in_flight
    t1_inside.pop
    t2_inside.pop

    assert_equal 2, Fetcher::PageFetcher.instance_variable_get(:@in_flight),
                 "duas threads devem estar em voo concorrentemente"
    assert_equal 2, max_in_flight_observed

    # As duas JÁ OBTIVERAM a instância (browser() dentro do track): received
    # derivado, não manual.
    assert_equal 2, Fetcher::PageFetcher.instance_variable_get(:@browser_received),
                 "as duas threads obtiveram a instância (ordem de produção)"
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, true)

    # Libera thread 1 para sair
    t1_resume << true
    t1.join
    # pos-t1: resta a t2 segurando a instância — pending NÃO pode limpar ainda.
    assert_equal true, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                 "pending_discard NÃO pode ser limpo enquanto resta 1 thread em voo"
    assert_equal false, live_browser.quit_called,
                 "browser NAO pode sofrer quit enquanto houver thread em voo"

    assert_equal 1, Fetcher::PageFetcher.instance_variable_get(:@in_flight),
                 "in_flight deve decrementar para 1 após saída da primeira thread"
assert_equal true, Fetcher::PageFetcher.instance_variable_get(:@pending_discard),
                 "pending_discard NÃO pode ser limpo enquanto resta 1 thread em voo"
    assert_equal false, live_browser.quit_called,
                 "browser NÃO pode sofrer quit enquanto houver thread em voo"

    # Libera thread 2 para sair
    t2_resume << true
    t2.join

assert_equal 0, Fetcher::PageFetcher.instance_variable_get(:@in_flight),
                 "in_flight deve chegar a 0 após saída da segunda thread"
    assert_equal true, live_browser.quit_called,
"browser deve sofrer quit na saída da última thread com pending_discard"
  end

  # A leitura de cookies deixou de passar pela página default do Ferrum
  # (`browser.cookies.all`): hoje é comando CDP no cliente raiz
  # (`Storage.getCookies` na RAIZ, SEM `browserContextId` — mandar a chave é
  # -32602: medicao-C-vias-producao.txt). O
  # invariante que este teste protege NÃO mudou e continua sendo o ponto (Sol r1
  # item 3): a leitura de cookies não pode correr fora de `track_in_flight` — com
  # browser compartilhado e `MAX_INFLIGHT_PAGES`, o descarte/`quit` pode acontecer
  # no meio de uma leitura em uso. O que estava desatualizado era o observador: o
  # dublê só modelava `cookies.all`, então o espião nunca disparava no caminho
  # novo e o contador ficava em 0 (LACUNA 2 da lane A3).
  test "BrowserCookies.for e load! executam a leitura CDP/set envolvidos em track_in_flight (Sol r1 item 3)" do
    fake_cookies_manager = Object.new
    in_flight_during_leitura = nil
    in_flight_during_set = nil

    # O caminho NOVO da leitura: comando no cliente raiz. É AQUI que o
    # invariante tem de valer agora — o espião acompanha a chamada real do
    # código, não a assinatura antiga.
    fake_cookies_manager.define_singleton_method(:all) do
      raise "a leitura principal NÃO pode passar por browser.cookies.all (página default) — " \
            "o caminho novo é Storage.getCookies no cliente raiz SEM browserContextId"
    end

    fake_cookies_manager.define_singleton_method(:set) do |**_opts|
      in_flight_during_set = Fetcher::PageFetcher.instance_variable_get(:@in_flight)
      true
    end

    fake_browser = Object.new
    fake_browser.define_singleton_method(:cookies) { fake_cookies_manager }
    fake_browser.define_singleton_method(:default_context) { @default_context ||= Struct.new(:id).new("ctx_default") }
    fake_browser.define_singleton_method(:command) do |_cmd, **_params|
      in_flight_during_leitura = Fetcher::PageFetcher.instance_variable_get(:@in_flight)
      { "cookies" => [{ "name" => "auth", "value" => "tok123", "domain" => "youtube.com", "path" => "/" }] }
    end

    Fetcher::PageFetcher.stubs(:browser).returns(fake_browser)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)

    cookies = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal 1, cookies.size
    assert_equal "auth", cookies.first["name"]
    assert_operator in_flight_during_leitura, :>, 0,
                    "a leitura (Storage.getCookies) deve rodar dentro de track_in_flight (in_flight > 0)"
    assert_equal 0, Fetcher::PageFetcher.instance_variable_get(:@in_flight),
                 "in_flight deve retornar a 0 após BrowserCookies.for"

    in_flight_during_leitura = nil
    resultado = Fetcher::BrowserCookies.load!([{ "name" => "auth", "value" => "tok123",
                                                 "domain" => "youtube.com", "path" => "/" }])

    assert_equal 1, resultado[:postos]
    assert_operator in_flight_during_set, :>, 0,
                    "cookies.set deve rodar dentro de track_in_flight (in_flight > 0)"
    assert_equal 0, Fetcher::PageFetcher.instance_variable_get(:@in_flight),
                 "in_flight deve retornar a 0 após load!"
  ensure
    Fetcher::PageFetcher.unstub(:browser)
  end

end
