# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/fetcher/browser_cookies"

class Fetcher::BrowserCookiesTest < ActiveSupport::TestCase
  # Dublê no formato do Ferrum: `cookies.all` devolve hash nome => Cookie, e o
  # Cookie responde a name/value/domain/path (ferrum-0.17.2 cookies.rb:49).
  Cookie = Struct.new(:name, :value, :domain, :path)

  class FakeCookies
    def initialize(lista) = @lista = lista
    def all = @lista.to_h { |c| [c.name, c] }
  end

  # A leitura de cookies é a chamada RAIZ do CDP (`Storage.getCookies`), SEM
  # `browserContextId` e SEM a página default (laudo r5). O jar que interessa é o
  # IMPLÍCITO do perfil e só se lê OMITINDO o parâmetro: `default_context.id` é
  # nil no ferrum 0.18 e o id que o `Target.getBrowserContexts` publica é
  # RECUSADO com -32602 (medicao-C-vias-producao.txt:9,15). O dublê modela a API
  # NOVA: `command` devolve os cookies em formato CDP (hash) e IGNORA os params.
  class FakeBrowser
    attr_reader :cookies

    def initialize(lista) = @cookies = FakeCookies.new(lista)

    def command(_cmd, **_params)
      { "cookies" => @cookies.all.values.map do |c|
          { "name" => c.name, "value" => c.value, "domain" => c.domain, "path" => c.path }
        end }
    end

    def default_context
      @default_context ||= Struct.new(:id).new("ctx_default")
    end
  end

  def com_browser(lista)
    Fetcher::PageFetcher.stubs(:browser).returns(FakeBrowser.new(lista))
  end

  test "pega os cookies do dominio e ignora os de outros" do
    com_browser([
                  Cookie.new("SID", "abc", ".youtube.com", "/"),
                  Cookie.new("sessionid", "xyz", ".reddit.com", "/"),
                  Cookie.new("LOGIN_INFO", "def", "www.youtube.com", "/")
                ])

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal %w[SID LOGIN_INFO], lidos.map { |c| c["name"] }
    assert_equal "abc", lidos.first["value"]
    assert_equal ".youtube.com", lidos.first["domain"]
  end

  test "subdominio do alvo conta como o mesmo dominio" do
    com_browser([Cookie.new("SID", "abc", ".www.youtube.com", "/")])

    assert_equal 1, Fetcher::BrowserCookies.for("youtube.com").size
  end

  test "dominio que apenas termina parecido nao casa" do
    com_browser([Cookie.new("X", "1", ".naoyoutube.com", "/")])

    assert_empty Fetcher::BrowserCookies.for("youtube.com")
  end

  test "path vazio vira barra" do
    com_browser([Cookie.new("SID", "abc", ".youtube.com", "")])

    assert_equal "/", Fetcher::BrowserCookies.for("youtube.com").first["path"]
  end

  test "browser indisponivel devolve lista vazia, nunca excecao" do
    Fetcher::PageFetcher.stubs(:browser).raises(StandardError, "sem chrome")

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "o canal ainda pode cair no jar; derrubar a chamada tiraria essa chance"
  end

  class Espiao
    attr_reader :postos

    def initialize = @postos = []
    def all = @postos.to_h { |k| [k[:name], Cookie.new(k[:name], k[:value], k[:domain], k[:path])] }
    def set(**kwargs) = @postos << kwargs
  end

  class BrowserEspiao
    attr_reader :cookies

    def initialize = @cookies = Espiao.new

    # `load!` grava via `cookies.set` e confirma lendo de volta — a leitura é a
    # chamada RAIZ (`command` SEM `browserContextId`). Devolve os cookies
    # postados no formato CDP (hash), como o `Storage.getCookies` faria.
    def command(_cmd, **_params)
      { "cookies" => @cookies.postos.map do |c|
          { "name" => c[:name], "value" => c[:value].to_s, "domain" => c[:domain], "path" => c[:path] }
        end }
    end

    def default_context
      @default_context ||= Struct.new(:id).new("ctx_default")
    end
  end

  def com_espiao
    espiao = BrowserEspiao.new
    Fetcher::PageFetcher.stubs(:browser).returns(espiao)
    espiao
  end

  # Sem `expires` o cookie vira de SESSAO e o Chrome o descarta ao reiniciar.
  test "load! traduz expirationDate para expires" do
    espiao = com_espiao
    Fetcher::BrowserCookies.load!([{ "name" => "SID", "value" => "v", "domain" => ".youtube.com",
                                     "path" => "/", "expirationDate" => 2_000_000_000.5 }])

    assert_equal 2_000_000_000, espiao.cookies.postos.first[:expires]
  end

  test "load! traduz os nomes de sameSite do Cookie-Editor para os do CDP" do
    espiao = com_espiao
    Fetcher::BrowserCookies.load!([
                                   { "name" => "a", "value" => "1", "domain" => ".x.test", "sameSite" => "no_restriction" },
                                   { "name" => "b", "value" => "1", "domain" => ".x.test", "sameSite" => "lax" },
                                   { "name" => "c", "value" => "1", "domain" => ".x.test", "sameSite" => nil }
                                 ])
    postos = espiao.cookies.postos

    assert_equal "None", postos[0][:samesite]
    assert_equal "Lax", postos[1][:samesite]
    assert_not postos[2].key?(:samesite), "sameSite ausente nao pode virar valor inventado"
  end

  test "load! confirma lendo de volta e ignora entrada sem nome" do
    com_espiao
    resultado = Fetcher::BrowserCookies.load!([
                                                { "name" => "SID", "value" => "v", "domain" => ".youtube.com" },
                                                { "name" => "", "value" => "x", "domain" => ".youtube.com" }
                                              ])

    assert_equal({ postos: 1, confirmados: 1 }, resultado)
  end

  # A sessão do target CDP morre ("Session with given id not found") — sinal
  # ESTREITO: só ele (e DEAD_SESSION_ERRORS) reconstrói o browser. O erro é um
  # Ferrum::BrowserError no construtor HASH real (errors.rb:88-94).
  class ZumbiBrowser
    ZUMBI_ERROR = Ferrum::BrowserError.new("message" => "Session with given id not found.")

    def cookies = self

    def all
      raise ZUMBI_ERROR
    end

    def command(_cmd, **_params)
      raise ZUMBI_ERROR
    end

    def default_context
      @default_context ||= Struct.new(:id).new("ctx_default")
    end
  end

  test "(i) cookies.for reconstrói o browser e retenta quando a sessão CDP morre (sinal estreito)" do
    saudavel = FakeBrowser.new([Cookie.new("SID", "abc", ".youtube.com", "/")])
    # 1ª chamada (dentro do track) pega o zumbi e levanta; a 2ª volta já no browser saudável.
    Fetcher::PageFetcher.stubs(:browser).returns(ZumbiBrowser.new, saudavel)
    Fetcher::PageFetcher.expects(:reset_browser!).once

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "a 2ª tentativa deve devolver o cookie lido no browser reconstruído"
  end

  test "(ii) cookies.for com a sessão morta nas duas vezes devolve [], nunca exceção" do
    Fetcher::PageFetcher.stubs(:browser).returns(ZumbiBrowser.new, ZumbiBrowser.new)
    Fetcher::PageFetcher.expects(:reset_browser!).once # só a 1ª retentativa reseta

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "o contrato 'nunca exceção' é mantido: a 2ª falha loga e devolve []"
  end

  test "(iv) erro CDP que não é o sinal estreito NÃO reconstrói o browser" do
    # "Sanitizing cookie failed" e os erros de JS caem no pai BrowserError mas
    # NÃO no sinal — reconstruir aqui condenaria a instância compartilhada
    # (MAX_INFLIGHT). `.raises` (não `.returns`): é o browser quem levanta.
    Fetcher::PageFetcher.stubs(:browser)
                       .raises(Ferrum::BrowserError.new("message" => "Sanitizing cookie failed"))
    Fetcher::PageFetcher.expects(:reset_browser!).never

    assert_empty Fetcher::BrowserCookies.for("youtube.com")
  end

  test "(iv) JavaScriptError NÃO reconstrói o browser" do
    js = Ferrum::JavaScriptError.new("exception" => { "className" => "TypeError",
                                                       "description" => "cannot read property of undefined" })
    Fetcher::PageFetcher.stubs(:browser).raises(js)
    Fetcher::PageFetcher.expects(:reset_browser!).never

    assert_empty Fetcher::BrowserCookies.for("youtube.com")
  end
end
