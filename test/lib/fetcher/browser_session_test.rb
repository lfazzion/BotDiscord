# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/fetcher/browser_session"

class Fetcher::BrowserSessionTest < ActiveSupport::TestCase
  # `Ferrum::Cookies#set` é `def set(options)` — UM hash POSICIONAL, não keywords
  # (ferrum-0.17.2/lib/ferrum/cookies.rb:118). O dublê copia a assinatura real:
  # um dublê com `set(**kwargs)` aceitaria chamadas que o Ferrum recusaria.
  class FakeCookies
    # Modela o contrato real de `Ferrum::Cookies`, incluindo `all` (usado por
    # `persist_rotation`). Antes o `rescue StandardError` engolia o
    # NoMethodError de `all` ausente; com o rescue estreitado (ACHADO B) o fake
    # precisa implementar o método de verdade.
    FakeCookie = Struct.new(:name, :value, :domain, :path)
    attr_reader :postos

    def initialize
      @postos = []
    end

    def set(options)
      @postos << options
      true
    end

    def all
      @postos.each_with_object({}) do |opts, acc|
        nome = (opts[:name] || opts["name"]).to_s
        path_val = (opts[:path] || opts["path"]).to_s
        path_val = "/" if path_val.empty?

        acc[nome] = FakeCookie.new(
          (opts[:name] || opts["name"]).to_s,
          (opts[:value] || opts["value"]).to_s,
          (opts[:domain] || opts["domain"]).to_s,
          path_val
        )
      end
    end
  end

  class FakePage
    attr_reader :cookies, :visitado, :fechada, :commands, :timeout_during_goto
    attr_accessor :timeout, :body_text

    def initialize(document_remote_ip: nil, body_text: "conteúdo inicial")
      @cookies = FakeCookies.new
      @fechada = false
      @document_remote_ip = document_remote_ip
      @listeners = {}
      @commands = []
      @command_result = true
      @timeout = 12
      @timeout_during_goto = nil
      @body_text = body_text
    end

    attr_accessor :command_result

    def evaluate(js)
      return @body_text if js.to_s.include?("innerText")
      nil
    end

    def command(name, params = {})
      @commands << [name, params]
      @command_result
    end

    def go_to(url)
      @visitado = url
      @timeout_during_goto = @timeout
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

    def current_url = @visitado
    def close = @fechada = true
  end

  class FakeContext
    attr_reader :page, :descartado

    def initialize(page)
      @page = page
      @descartado = false
    end

    def create_page = @page
    def dispose = @descartado = true
  end

  class FakeContexts
    attr_reader :last_options
    def initialize(context)
      @context = context
      @last_options = nil
    end
    def create(**options)
      @last_options = options
      @context
    end
  end

  class FakeBrowser
    attr_reader :contexts

    def initialize(context) = @contexts = FakeContexts.new(context)
  end

  setup do
    @page = FakePage.new
    @context = FakeContext.new(@page)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(@context))
    # O `with_page` valida a URL com o SsrfGuard antes de gastar browser —
    # sem o stub, isto resolveria DNS de verdade no ambiente de teste.
    Fetcher::SsrfGuard.stubs(:resolve_all).returns(["93.184.216.34"])
    Fetcher::CookieJar.store!(
      domain: "youtube.com",
      cookies: [{ "name" => "SID", "value" => "abc", "domain" => ".youtube.com", "path" => "/" }],
      expires_at: 7.days.from_now
    )
  end

  test "injeta o cookie ANTES de navegar" do
    ordem = []
    @page.cookies.stubs(:set).with { |**_| ordem << :cookie; true }
    @page.stubs(:go_to).with { |_| ordem << :navegou; true }

    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }

    assert_equal %i[cookie navegou], ordem
  end

  test "passa nome, valor, dominio e path para o CDP" do
    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }

    posto = @page.cookies.postos.first
    assert_equal "SID", posto[:name]
    assert_equal "abc", posto[:value]
    assert_equal ".youtube.com", posto[:domain]
    assert_equal "/", posto[:path]
  end

  test "devolve o valor do bloco" do
    assert_equal 42, Fetcher::BrowserSession.with_page("https://www.youtube.com/x") { |_p| 42 }
  end

  test "sem sessao viva levanta Expired e nao navega" do
    assert_raises(Fetcher::CookieJar::Expired) do
      Fetcher::BrowserSession.with_page("https://reddit.com/r/x") { |_p| :nunca }
    end

    assert_nil @page.visitado
  end

  test "fecha a pagina e descarta o contexto mesmo quando o bloco levanta" do
    assert_raises(RuntimeError) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/x") { |_p| raise "erro do bloco" }
    end

    assert @page.fechada
    assert @context.descartado
  end

  test "URL privada é recusada antes de gastar browser (invariante enforced)" do
    Fetcher::SsrfGuard.stubs(:resolve_all).with("192.168.1.10").returns(["192.168.1.10"])

    erro = assert_raises(Fetcher::SsrfGuard::Blocked) do
      Fetcher::BrowserSession.with_page("http://192.168.1.10/admin") { |_p| :nunca }
    end

    assert_match(/privado|interno/i, erro.message)
    assert_nil @page.visitado
  end

  test "documento que veio de IP privado levanta Blocked (DNS rebinding)" do
    @page = FakePage.new(document_remote_ip: "10.0.0.1")
    @context = FakeContext.new(@page)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(@context))

    erro = assert_raises(Fetcher::SsrfGuard::Blocked) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end

    assert_match(/rebinding/i, erro.message)
  end

  test "documento que veio de loopback (127.0.0.1) levanta Blocked mesmo com outro IP público no conjunto" do
    Fetcher::SsrfGuard.stubs(:resolve_all).returns(["93.184.216.34", "1.1.1.1"])
    @page = FakePage.new(document_remote_ip: "127.0.0.1")
    @context = FakeContext.new(@page)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(@context))

    erro = assert_raises(Fetcher::SsrfGuard::Blocked) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end

    assert_match(/127\.0\.0\.1/, erro.message)
  end

  test "documento que veio de IP público do conjunto (não o primeiro) passa — CDN/dual-stack" do
    Fetcher::SsrfGuard.stubs(:resolve_all).returns(["93.184.216.34", "1.1.1.1"])
    @page = FakePage.new(document_remote_ip: "1.1.1.1")
    @context = FakeContext.new(@page)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(@context))

    assert_equal :ok, Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
  end

  test "documento que veio do IP validado passa" do
    @page = FakePage.new(document_remote_ip: "93.184.216.34")
    @context = FakeContext.new(@page)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(@context))

    assert_equal :ok, Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
  end

  test "inject_cookies pula cookies fora da allowlist e nao chama set no Ferrum" do
    misturados = [
      { "name" => "reddit_session", "value" => "ok", "domain" => ".reddit.com", "path" => "/" },
      { "name" => "__Secure-YNID", "value" => "bad", "domain" => ".youtube.com", "path" => "/" }
    ]
    Fetcher::SessionCookies.stubs(:for).with("old.reddit.com").returns([misturados, :jar])

    @page.cookies.expects(:set).with(has_entry(name: "reddit_session")).once
    @page.cookies.expects(:set).with(has_entry(name: "__Secure-YNID")).never

    Fetcher::BrowserSession.with_page("https://old.reddit.com/r/test") { |_p| :ok }
  end

  test "inject_cookies passa secure: true para cookies __Secure-*" do
    sec_cookie = { "name" => "__Secure-3PSID", "value" => "sec_val", "domain" => ".youtube.com", "path" => "/" }
    Fetcher::SessionCookies.stubs(:for).with("www.youtube.com").returns([[sec_cookie], :jar])

    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }

    posto = @page.cookies.postos.find { |c| c[:name] == "__Secure-3PSID" }
    assert_not_nil posto
    assert_equal true, posto[:secure]
  end

  test "inject_cookies envia Network.setCookie via CDP com url, secure e path / sem domain para cookies __Host-*" do
    host_cookie = { "name" => "__Host-SID", "value" => "host_val", "domain" => "youtube.com", "path" => "/" }
    Fetcher::SessionCookies.stubs(:for).with("www.youtube.com").returns([[host_cookie], :jar])

    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }

    cmd = @page.commands.find { |c, p| c == "Network.setCookie" && p[:name] == "__Host-SID" }
    assert_not_nil cmd
    _name, params = cmd
    assert_equal "host_val", params[:value]
    assert_equal "https://www.youtube.com/", params[:url]
    assert_equal true, params[:secure]
    assert_equal "/", params[:path]
    assert_not_includes params.keys, :domain
    assert_not_includes params.keys, "domain"
  end

  test "persist_rotation solicita renovação de expires_at por sete dias" do
    sid_cookie = Struct.new(:name, :value, :domain, :path).new(
      "SID", "abc", ".youtube.com", "/"
    )
    @page.cookies.stubs(:all).returns({ "SID" => sid_cookie })

    # Teste REAL (sem stub de refresh_for!): o stub mascara o ArgumentError
    # quando a assinatura não aceita expires_at: (achado P1 do sol, 13/08).
    # O setup já criou o registro (domain "youtube.com", 7 dias) — encurta
    # expires_at para provar que a rotação REALMENTE estende.
    jar_record = BrowserSessionCookie.find_by(domain: "youtube.com")
    assert_not_nil jar_record, "setup deve ter criado o registro do jar"
    jar_record.update!(expires_at: 1.day.from_now)

    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }

    jar_record.reload
    parsed = JSON.parse(jar_record.payload)
    assert_equal "abc", parsed.first["value"], "payload deve ser persistido de volta"
    assert_operator jar_record.expires_at, :>, 6.days.from_now,
                    "rotacao deve estender expires_at para ~7 dias"
    assert_operator jar_record.expires_at, :<=, 8.days.from_now
  end

  # ACHADO A (13/08, P2): o retorno de Network.setCookie era ignorado. O CDP
  # responde `{ "success": false, "errorText": "..." }` sem lançar exceção, então
  # o cookie __Host- podia falhar silenciosamente e a sessão seguir anônima.
  test "inject_cookies levanta quando Network.setCookie do CDP responde success: false" do
    host_cookie = { "name" => "__Host-SID", "value" => "host_val", "domain" => "youtube.com", "path" => "/" }
    Fetcher::SessionCookies.stubs(:for).with("www.youtube.com").returns([[host_cookie], :jar])

    # FakePage cujo command simula o CDP recusando o cookie (success:false, sem exceção)
    @page = FakePage.new
    @page.command_result = { "success" => false, "errorText" => "Bloqueado pelo Chrome" }
    @page.cookies.stubs(:all).returns({})
    @context = FakeContext.new(@page)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(@context))

    erro = assert_raises(RuntimeError) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end
    assert_match(/success.*false|falha|setCookie|recusou/i, erro.message)
  end

  # ACHADO B (13/08, P2): o `rescue StandardError` engolia erros de programação
  # (era o bug original desta PR). Um NoMethodError na rotação deve propagar.
  test "persist_rotation deixa erro de programação (NoMethodError) propagar em vez de engolir" do
    sid = Struct.new(:name, :value, :domain, :path).new("SID", "abc", ".youtube.com", "/")
    @page.cookies.stubs(:all).returns({ "SID" => sid })
    Fetcher::CookieJar.stubs(:refresh_for!).raises(NoMethodError, "bug de programacao na rotacao")

    assert_raises(NoMethodError) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end
  end

  # Rodada 2 (sol 13/08): o bug original desta PR ERA um ArgumentError de
  # assinatura (refresh_for! sem expires_at:) — mantê-lo no rescue recriaria
  # o mascaramento. ArgumentError deve propagar como erro de programação.
  test "persist_rotation deixa ArgumentError (assinatura/contrato) propagar em vez de engolir" do
    sid = Struct.new(:name, :value, :domain, :path).new("SID", "abc", ".youtube.com", "/")
    @page.cookies.stubs(:all).returns({ "SID" => sid })
    Fetcher::CookieJar.stubs(:refresh_for!).raises(ArgumentError, "wrong number of arguments")

    assert_raises(ArgumentError) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end
  end

  # Regressão do ACHADO B: erro operacional esperado (JSON::GeneratorError da
  # serialização) continua engolido e logado, para não derrubar o fetch da página.
  test "persist_rotation ainda engole e loga erro operacional esperado (JSON::GeneratorError)" do
    sid = Struct.new(:name, :value, :domain, :path).new("SID", "abc", ".youtube.com", "/")
    @page.cookies.stubs(:all).returns({ "SID" => sid })
    Fetcher::CookieJar.stubs(:refresh_for!).raises(JSON::GeneratorError, "valor não serializável")
    log_capturado = ""
    Rails.logger.stubs(:warn).with { |msg| log_capturado += msg.to_s }

    assert_nothing_raised do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end
    assert_match(/rotação não persistida/, log_capturado)
  end

  test "create_page com target nil que levanta NoMethodError build_page vira BrowserSession::RenderTimeout" do
    broken_context = Object.new
    def broken_context.create_page
      raise NoMethodError, "undefined method `build_page' for nil:NilClass"
    end
    def broken_context.dispose; end

    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(broken_context))

    assert_raises(Fetcher::BrowserSession::RenderTimeout) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end
  end

  test "BrowserSession mapeia Ferrum::TimeoutError no go_to com body vazio para RenderTimeout e fecha pagina e contexto" do
    @page.body_text = ""
    @page.stubs(:go_to).raises(Ferrum::TimeoutError)

    assert_raises(Fetcher::BrowserSession::RenderTimeout) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end
    assert @page.fechada
    assert @context.descartado
  end

  test "BrowserSession go_to soft com body presente prossegue para o bloco sem RenderTimeout" do
    @page.body_text = "conteúdo presente no body"
    @page.stubs(:go_to).raises(Ferrum::TimeoutError)

    res = Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :bloco_executado }
    assert_equal :bloco_executado, res
  end

  # (iii) do laudo — a queda de 35s medida. O `Timeout::Error` (stdlib) que sai
  # do `go_to` NÃO é pego pelo rescue interno (só `Ferrum::TimeoutError` e
  # `Ferrum::PendingConnectionsError`), sobe até o rescue de timeout do método,
  # que agora chama `reset_browser!` antes de propagar `RenderTimeout`. Sem
  # este teste o patch ficaria verde e o zumbi continuaria travando a sessão.
  test "(iii) timeout no go_to chama reset_browser! e propaga RenderTimeout" do
    @page.stubs(:go_to).raises(Timeout::Error, "excedeu o tempo de render")
    Fetcher::PageFetcher.expects(:reset_browser!).once

    assert_raises(Fetcher::BrowserSession::RenderTimeout) do
      Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
    end
  end

  test "BrowserSession entrega remaining deadline durante execucao do bloco e limpa no ensure" do
    remaining_durante_bloco = nil
    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") do |_p|
      remaining_durante_bloco = Fetcher::BrowserSession.remaining
    end

    assert_operator remaining_durante_bloco, :>, 0
    assert_operator remaining_durante_bloco, :<=, Fetcher::BrowserSession::OVERALL_TIMEOUT
    assert_equal Float::INFINITY, Fetcher::BrowserSession.remaining
  end

  test "BrowserSession contexts.create recebe disposeOnDetach: true (Item 3)" do
    fake_contexts = FakeContexts.new(@context)
    fake_browser = FakeBrowser.new(nil)
    fake_browser.instance_variable_set(:@contexts, fake_contexts)
    Fetcher::PageFetcher.stubs(:browser).returns(fake_browser)

    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }

    assert_equal({ disposeOnDetach: true }, fake_contexts.last_options,
                 "BrowserSession deve passar disposeOnDetach: true para contexts.create")
  end

  test "BrowserSession falha no dispose_quietly marca PageFetcher como dirty (Item 4)" do
    @context.define_singleton_method(:dispose) { raise StandardError, "erro no dispose" }

    Fetcher::PageFetcher.expects(:mark_dirty!).at_least_once

    Fetcher::BrowserSession.with_page("https://www.youtube.com/watch?v=x") { |_p| :ok }
  end

  # Causa raiz do bloqueio do Reddit: o Chrome do app é chromedp/headless-shell e
  # anuncia o UA `HeadlessChrome/1xx`, que o Reddit bloqueia ("whoa there,
  # pardner ... blocked due to a network policy"). A correção é injetar um UA de
  # navegador real via `Network.setUserAgentOverride` por-página, ANTES do
  # `go_to` — o override por-página não toca o perfil persistente do Chrome e
  # precisa valer já na primeira requisição.
  #
  # Achado 2 (perito r2): `Network.enable` é emitido PELO FERRUM em
  # `prepare_page` sem argumentos ANTES do go_to — re-emitir com
  # maxTotalBufferSize:0 desligaria o buffer de corpo (quem chama page.body
  # recebe nil). Por isso NÃO emitimos Network.enable aqui; só o
  # setUserAgentOverride, via chamada CRUA ao CDP.
  #
  # Achado 3 (perito r2): `platform: "Win32"` fixo contra o UA sorteado
  # (3 de 4 UAs não-Windows) dava fingerprint incoerente e prova
  # não-determinística. Agora o Reddit usa UM UA determinístico de Chrome/Windows
  # com platform coerente — ver REDDIT_USER_AGENT/REDDIT_PLATFORM.
  test "with_page injeta user-agent determinístico de Chrome/Windows antes do go_to" do
    Fetcher::SessionCookies.stubs(:for).with("old.reddit.com").returns([[], :jar])

    ja_tinha_override_no_go_to = nil
    @page.stubs(:go_to).with do |_url|
      ja_tinha_override_no_go_to = @page.commands.any? { |name, _| name == "Network.setUserAgentOverride" }
      true
    end

    Fetcher::BrowserSession.with_page("https://old.reddit.com/r/x") { |_p| :ok }

    assert ja_tinha_override_no_go_to,
           "override do UA deve estar emitido ANTES do go_to (valer já na 1a requisição)"
    cmd_ovr = @page.commands.find { |name, _| name == "Network.setUserAgentOverride" }
    refute_nil cmd_ovr, "deve chamar Network.setUserAgentOverride"
    _name, params_ovr = cmd_ovr
    assert_equal Fetcher::BrowserSession::REDDIT_USER_AGENT, params_ovr[:userAgent],
                 "deve usar o UA determinístico de Chrome/Windows (não sorteio)"
    refute_match(/Headless/i, params_ovr[:userAgent])
    assert_match(/Windows/i, params_ovr[:userAgent], "UA deve ser de Windows")
    assert_equal Fetcher::BrowserSession::REDDIT_PLATFORM, params_ovr[:platform],
                 "platform deve ser coerente com o UA (Win32)"
    assert_includes params_ovr[:acceptLanguage].to_s, "pt-BR",
                    "deve incluir acceptLanguage pt-BR no override"

    # Achado 2: NÃO deve re-emitir Network.enable (o Ferrum já o faz em
    # prepare_page com buffers de corpo intactos).
    refute @page.commands.any? { |name, _| name == "Network.enable" },
           "NÃO deve emitir Network.enable (Ferrum já emite; re-emitir com buffers zerados quebraria page.body)"
  end

  # Achado 2 (perito r2): o UA override em outros hosts NÃO deve tocar o Reddit
  # — e hosts não-Reddit nem devem emitir setUserAgentOverride (comportamento de
  # YouTube/X preservado).
  # I2 do laudo r6: o goto_limit especial do Reddit (15s) vs geral (20s) deve
  # estar coberto por teste. O duble FakePage capta timeout_during_goto na
  # chamada a go_to.
  test "goto_limit do Reddit e 15s e o de hosts comuns e PageFetcher::GOTO_TIMEOUT" do
    Fetcher::SessionCookies.stubs(:for).with("old.reddit.com").returns([[], :jar])

    Fetcher::BrowserSession.with_page("https://old.reddit.com/r/x") { |_p| :ok }

    assert_equal 15, @page.timeout_during_goto,
                 "Reddit deve usar goto_limit de 15s"

    @page2 = FakePage.new
    @context2 = FakeContext.new(@page2)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(@context2))
    Fetcher::SessionCookies.stubs(:for).with("x.com").returns([[], :jar])

    Fetcher::BrowserSession.with_page("https://x.com/someuser") { |_p| :ok }

    assert_equal Fetcher::PageFetcher::GOTO_TIMEOUT, @page2.timeout_during_goto,
                 "host comum deve usar goto_limit de #{Fetcher::PageFetcher::GOTO_TIMEOUT}s"
  end

  test "with_page nao emite setUserAgentOverride para host nao-reddit" do
    Fetcher::SessionCookies.stubs(:for).with("x.com").returns([[], :jar])

    Fetcher::BrowserSession.with_page("https://x.com/someuser") { |_p| :ok }

    refute @page.commands.any? { |name, _| name == "Network.setUserAgentOverride" },
           "UA override é SÓ do Reddit — não pode vazar para YouTube/X"
  end
end
