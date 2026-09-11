# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/fetcher/browser_cookies"
require_relative "../../../lib/fetcher/page_fetcher"

# CURA (TDD) da sessão de target CDP — laudo r5 (via FINAL, após a medição C).
#
# A leitura de cookies é a chamada RAIZ `Storage.getCookies`, SEM `sessionId` e
# SEM `browserContextId`. O jar do perfil é o IMPLÍCITO e se lê OMITINDO o
# parâmetro. O par RED/GREEN é rodado pelo maestro via testctl; estes testes
# modelam a API NOVA e, salvo onde declarado, FALHAM no código ANTES do patch:
#
#   (a) a sonda `alive?` usa a MESMA via da leitura (comando CDP da raiz), sem a
#       página default — pre-patch ela só rodava `version` e nunca o comando de
#       Storage;
#   (b) a leitura roda na RAIZ, sem `browserContextId` e NUNCA no contexto do
#       fetch (`disposeOnDetach: true`) — pre-patch era `browser.cookies.all`, e
#       o dublê da página default EXPLODE se for tocado;
#   (c) a marca de instância condenada (`browser_condemned?` / @pending_discard)
#       NÃO dispara reset do browser compartilhado — pre-patch não existe
#       `browser_condemned?` e `for` reconstruía mesmo condenada;
#   (d) o predicado "sessão morta" continua ESTREITO (não captura JS/Node nem
#       sanitização de cookie) — trava de regressão, não discriminador.
#
# MEDIÇÃO EM CHROME REAL, imagem de produção (laudo r5; evidência
# /tmp/revisao-b1/evidencia/medicao-C-vias-producao.txt), que os dublês modelam:
#
#   Storage.getCookies (raiz, SEM id)              => OK {"cookies"=>[]}   (C:8)
#   Storage.getCookies com o id do CDP             => CDP -32602           (C:9)
#   Storage.getCookies com id nil / ""             => CDP -32602           (C:15)
#   Network.getAllCookies (raiz)                   => CDP -32601           (C:14)
#   browser.cookies.all (página default)           => CDP -32001           (C:11)
#   default_context.create_page                    => CDP -32602           (C:12)
#   contexts.create + create_page                  => OK, jar ISOLADO      (C:13)
#
# `default_context.id` é nil no ferrum 0.18 da imagem; o `defaultBrowserContextId`
# que o `Target.getBrowserContexts` publica EXISTE mas ESTE comando o RECUSA. Os
# dois dublês abaixo recusam QUALQUER `browserContextId` com -32602 — é o que
# acusa a volta ao caminho antigo. Nada de rede, Chrome real ou sleep.
class Fetcher::CuraSessaoCdpTest < ActiveSupport::TestCase
  # Códigos CDP como o Chrome real os devolve (medicao-C-vias-producao.txt).
  CTX_DO_FERRUM = "ctx_default"                       # id que o Ferrum inventaria
  CTX_DO_CDP    = "83E8EFF3922BA9E9B8F391F77FDD08AA"  # id que o CDP publica

  class PaginaDefaultExcecao < StandardError; end
  class FallbackDePaginaExcecao < StandardError; end

  # Helper de erro CDP acessível TANTO ao corpo dos testes quanto aos dublês
  # aninhados (um método privado da instância de teste não vale dentro deles).
  class CdpErro
    def self.montar(msg, codigo)
      Ferrum::BrowserError.new("message" => msg, "code" => codigo)
    end
  end

  def erro_cdp(msg, code)
    CdpErro.montar(msg, code)
  end

  # ── Dublês no formato do Ferrum raiz (browser.rb / context.rb / client.rb) ──
  # `command` no Browser vai ao Client raiz (browser.rb:38), SEM sessionId.
  class EspiaoBase
    attr_reader :calls

    def initialize
      @calls = []
    end

    def storage_calls
      @calls.select { |c| c[0] == :command && c[1] == "Storage.getCookies" }
    end

    def contextos_consultados
      @calls.select { |c| c[0] == :command && c[1] == "Target.getBrowserContexts" }
    end
  end

  # Espia `cookies.all` na página default: chamado = defeito (origem do -32001).
  class CookiesSpy
    attr_reader :all_calls

    def initialize
      @all_calls = 0
    end

    def all
      @all_calls += 1
      raise PaginaDefaultExcecao.new(
        "a leitura/sonda passou pela página default (browser.cookies.all) — vetado pelo laudo r5: é a origem do -32001"
      )
    end
  end

  # Contexto do Ferrum. `id` é o `browserContextId` quando existe; `create_page` é
  # o fallback de página — INEXECUTÁVEL nesta imagem (create_page do ferrum 0.18
  # devolve CDP -32602, C:12): o dublê levanta se o código voltar a usá-lo.
  class EspiaoContext
    attr_reader :id, :pages_criadas

    def initialize(id)
      @id = id
      @pages_criadas = 0
    end

    def create_page
      @pages_criadas += 1
      raise FallbackDePaginaExcecao.new(
        "o fallback de página é INEXECUTÁVEL nesta imagem (medido CDP -32602, C:12) — laudo r5 B2"
      )
    end
  end

  # Coleção de contextos do fetch (disposeOnDetach). Rastreia `create`: a leitura
  # de cookies NÃO pode tocar nela (contexto do fetch = jar vazio e descartável).
  class EspiaoContexts
    attr_reader :creates

    def initialize
      @creates = 0
    end

    def create(**)
      @creates += 1
      EspiaoContext.new("ctx_fetch")
    end
  end

  # Browser raiz no formato do Ferrum que a API NOVA consome.
  #
  # MODELO DE PRODUÇÃO: `Storage.getCookies` só responde quando NÃO recebe
  # `browserContextId` (C:8). Qualquer parâmetro presente — nil, "" ou o id que o
  # CDP publica — devolve CDP -32602, como o Chrome real (C:9, C:15).
  class EspiaoBrowser < EspiaoBase
    attr_reader :default_context, :contexts, :cookies_spy

    def initialize(cookies: [], command_error: nil, success_error: nil,
                   default_ctx_id: CTX_DO_FERRUM)
      super()
      @cookies = cookies
      @command_error = command_error
      # Erro que SÓ aparece na chamada da raiz (sem id) — o dublê da
      # discriminação: a leitura problemática tem de cair no mesmo erro.
      @success_error = success_error
      @default_context = EspiaoContext.new(default_ctx_id)
      @contexts = EspiaoContexts.new
      @cookies_spy = CookiesSpy.new
    end

    def version
      @calls << [:version, nil]
      "HeadlessChrome/147.0.7727.102"
    end

    def command(cmd, **params)
      @calls << [:command, cmd, params]
      raise @command_error if @command_error

      case cmd
      when "Storage.getCookies"
        # Comando real ACEITA o parâmetro e o RECUSA com -32602: é a medição C:9
        # (id do CDP) e C:15 (id do Ferrum/nil/vazio).
        raise parametros_invalidos(params) if params.key?(:browserContextId)

        raise @success_error if @success_error

        { "cookies" => @cookies }
      when "Network.getAllCookies"
        # Medido -32601 na raiz (C:14) — a via antiga está morta neste Chrome.
        raise erro_cdp("'Network.getAllCookies' wasn't found", -32601)
      when "Target.getBrowserContexts"
        # O id existe, mas NÃO serve para a leitura (C:6-7 x C:9).
        { "browserContextIds" => [], "defaultBrowserContextId" => CTX_DO_CDP }
      else
        raise "comando inesperado: #{cmd}"
      end
    end

    def cookies = @cookies_spy

    private

    def parametros_invalidos(params)
      id = params[:browserContextId]
      mensagem = id.nil? || id.to_s.empty? ? "Invalid parameters" : "Failed to find browser context for id #{id}"
      CdpErro.montar(mensagem, -32602)
    end
  end

  # Dublê do CONTROLE INVERTIDO (b2): omite propositalmente a recusa por
  # `browserContextId` e só falha na chamada SEM id. Se o código voltar a mandar
  # o id, este dublê responde OK COM cookies — mas a asserção `refute_includes
  # keys` acusa a chave e `assert_empty lidos` acusa a leitura que só "funciona"
  # porque errou primeiro (o comportamento REPROVADO do B1).
  class EspiaoBrowserDiscriminacao < EspiaoBrowser
    def initialize(cookies: [], erro_sem_id:, **opts)
      super(cookies: cookies, **opts)
      @erro_sem_id = erro_sem_id
    end

    def command(cmd, **params)
      @calls << [:command, cmd, params]
      case cmd
      when "Storage.getCookies"
        if params.key?(:browserContextId)
          { "cookies" => @cookies }
        else
          raise @erro_sem_id
        end
      when "Target.getBrowserContexts"
        { "browserContextIds" => [], "defaultBrowserContextId" => CTX_DO_CDP }
      else
        raise "comando inesperado: #{cmd}"
      end
    end
  end

  # Estado de classe do PageFetcher isolado como nos testes irmãos
  # (page_fetcher_browser_test.rb / browser_cookies_test.rb).
  setup do
    Fetcher::PageFetcher.instance_variable_set(:@browser, nil)
    Fetcher::PageFetcher.instance_variable_set(:@browser_started_at, nil)
    Fetcher::PageFetcher.instance_variable_set(:@pages_since_start, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_dirty, false)
    Fetcher::PageFetcher.instance_variable_set(:@in_flight, 0)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
  end

  teardown do
    Fetcher::PageFetcher.unstub(:browser)
  end

  def com_browser(browser)
    Fetcher::PageFetcher.stubs(:browser).returns(browser)
    browser
  end

  # ──────────────────────────────────────────────────────────────────────────
  # (a) A sonda alive? usa a MESMA via da leitura — comando CDP na RAIZ, sem
  #     browserContextId — e NÃO toca a página default. Pre-patch, alive? só
  #     rodava `version` e nunca o comando de Storage, então `refute_empty
  #     storage_calls` falha nesse código.
  # ──────────────────────────────────────────────────────────────────────────
  test "(a) alive?: version ok + Storage.getCookies raiz SEM browserContextId devolve true, e a sonda NUNCA passa pela pagina default" do
    espiao = EspiaoBrowser.new(cookies: [cdo_sido_do_default])

    assert_equal true, Fetcher::PageFetcher.alive?(espiao)

    assert_equal 1, espiao.storage_calls.size,
                 "a sonda tem de usar a MESMA chamada da leitura (laudo r5 item 2) — " \
                 "o probe antigo só rodava version e ficava apontando para o caminho instável"
    assert_not espiao.storage_calls.last[2].key?(:browserContextId),
               "a sonda NÃO pode mandar browserContextId: em produção o id do CDP (e o " \
               "nil do Ferrum) são RECUSADOS com -32602 (medicao-C:9,15)"
    assert_empty espiao.contextos_consultados,
                 "nada de Target.getBrowserContexts no caminho quente (laudo r5 item 1) — " \
                 "o id que ele publica não alimenta Storage.getCookies"
    assert_equal 0, espiao.cookies_spy.all_calls,
                 "a sonda NÃO pode passar pela página default (origem do -32001): browser.cookies.all nunca é chamada"
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
                    "version roda ANTES do comando (probe dual do laudo: WS vivo → jar da raiz)"
    assert_equal 0, espiao.cookies_spy.all_calls,
                 "a sonda não usa a pagina default"
  end

  # ──────────────────────────────────────────────────────────────────────────
  # (b) A leitura roda na RAIZ, SEM browserContextId, e NUNCA no contexto do
  #     fetch (o que nasce com disposeOnDetach: true e morre com a sessão).
  #     Pre-patch, for() usava browser.cookies.all — o dublê explode
  #     (PaginaDefaultExcecao) e for() devolve [] — as asserções de nomes/cookie
  #     falham nesse código.
  # ──────────────────────────────────────────────────────────────────────────
  test "(b) for() lê o jar pela raiz e filtra dominio, sem tocar a pagina default" do
    espiao = com_browser(EspiaoBrowser.new(cookies: [
                                             cdo_sido_do_default,
                                             { "name" => "sessionid", "value" => "xyz", "domain" => ".reddit.com", "path" => "/" }
                                           ]))

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "só o cookie do dominio alvo (mesmo filtro de antes da migração)"
    assert_equal "abc", lidos.first["value"]
    assert_equal ".youtube.com", lidos.first["domain"]
    assert_equal 0, espiao.cookies_spy.all_calls,
                 "o caminho principal NÃO usa browser.cookies.all (a pagina default)"
  end

  test "(b) for() chama Storage.getCookies SEM a chave browserContextId, nunca com o id do CDP nem o do Ferrum" do
    espiao = com_browser(EspiaoBrowser.new(cookies: [cdo_sido_do_default], default_ctx_id: CTX_DO_FERRUM))

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "a leitura da raiz não leva parâmetro nenhum: o jar é o IMPLÍCITO (medicao-C:8)"
    storage = espiao.storage_calls.last
    refute_nil storage, "a leitura tem de ser um comando CDP no cliente raiz"
    assert_not storage[2].key?(:browserContextId),
               "a leitura tem de OMITIR browserContextId — com o id do CDP o Chrome responde " \
               "-32602 (medicao-C:9) e com o do Ferrum/nil também (C:15); quem trava essa " \
               "chave é que trava o defeito reprovado no laudo r5"
    refute_equal CTX_DO_CDP, storage[2][:browserContextId],
                 "o id do contexto padrão do CDP NÃO alimenta Storage.getCookies (medido -32602)"
    refute_equal espiao.default_context.id, storage[2][:browserContextId],
                 "não mire o default_context.id do Ferrum (#{espiao.default_context.id}): no ferrum " \
                 "de produção esse campo é nil e o Chrome recusa o parâmetro"
    assert_empty espiao.contextos_consultados,
                 "nada de Target.getBrowserContexts no caminho quente (laudo r5 item 1)"
    assert_equal 0, espiao.contexts.creates,
                 "for() não pode criar/reaproveitar contexto de fetch (disposeOnDetach: true)"
  end

  test "(b) o dublê recusa QUALQUER browserContextId: mandá-lo é a via REPROVADA do B1" do
    espiao = EspiaoBrowser.new(cookies: [cdo_sido_do_default])

    assert_raises(Ferrum::BrowserError) { espiao.command("Storage.getCookies", browserContextId: CTX_DO_CDP) }
    assert_raises(Ferrum::BrowserError) { espiao.command("Storage.getCookies", browserContextId: CTX_DO_FERRUM) }
    assert_raises(Ferrum::BrowserError) { espiao.command("Storage.getCookies", browserContextId: nil) }
    assert_equal({ "cookies" => [cdo_sido_do_default] }, espiao.command("Storage.getCookies"))
  end

  test "(b) a leitura não passa pelo Network.getAllCookies (medido -32601 na raiz)" do
    espiao = com_browser(EspiaoBrowser.new(cookies: [cdo_sido_do_default]))

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] }
    assert_empty espiao.calls.select { |c| c[0] == :command && c[1] == "Network.getAllCookies" },
                 "Network.getAllCookies está morto neste Chrome (medicao-C:14): a via é Storage.getCookies"
  end

  test "(b) sem id mas com jar vazio NÃO é erro: devolve [] legítimo" do
    espiao = com_browser(EspiaoBrowser.new(cookies: []))

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "{\"cookies\"=>[]} na chamada sem id é o jar implícito VAZIO em repouso (medicao-C:8), " \
                 "não falha da via — quem decide é o SessionCookies, que cai no jar do banco"
  end

  test "(b4) for() com o erro que só aparece na chamada SEM id: [] SEM retry (não-condenada)" do
    erro = erro_cdp("Storage.getCookies recusou a chamada da raiz", -32602)
    espiao = com_browser(EspiaoBrowserDiscriminacao.new(cookies: [cdo_sido_do_default], erro_sem_id: erro))
    Fetcher::PageFetcher.expects(:reset_browser!).never

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "-32602 é log + [] (laudo r5 §4): o browser vive, o contexto é que não atende — não reconstrói"
    assert_equal 1, espiao.storage_calls.size,
                 "-32602 não gera 2ª leitura: sem id para degradar (laudo r5 §4)"
  end

  # ── DISCRIMINAÇÃO da inversão: se o código voltar a mandar browserContextId ──
  # O dublê abaixo, de propósito, RESPONDE OK a quem manda id (cenário
  # generoso) e só falha na chamada da raiz — assim a leitura só "funciona" se
  # errar primeiro. A chave no comando é o que acusa.
  test "REGRESSÃO: com id o dublê responde OK e a asserção da CHAVE ausente acusa a inversão" do
    espiao = com_browser(EspiaoBrowserDiscriminacao.new(
                           cookies: [cdo_sido_do_default],
                           erro_sem_id: erro_cdp("'Storage.getCookies' wasn't found", -32601)
                         ))

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_empty lidos,
                 "a chamada da raiz FALHA (erro_sem_id): se este array vier com cookies, " \
                 "a leitura leu por uma chamada COM id — que é a inversão reprovada pelo laudo r5"
    assert_not espiao.storage_calls.last[2].key?(:browserContextId),
               "INVERSÃO: o comando saiu com browserContextId — é o caminho REPROVADO (B1): " \
               "obriga um -32602 antes de ler e trava o id falso no código e nos testes"
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
    zumbi = EspiaoBrowser.new(command_error: Ferrum::DeadBrowserError.new("message" => "ws fechado"))
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, true)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 1)
    Fetcher::PageFetcher.stubs(:browser).returns(zumbi)
    Fetcher::PageFetcher.expects(:reset_browser!).never

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "na instância condenada a 2ª leitura cairia num objeto morrendo — " \
                 "devolve [] e deixa o descarte rodar na saida do ultimo holder"
    assert_equal 1, zumbi.storage_calls.size,
                 "sem retry na condenada: UMA leitura e para"
  ensure
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
  end

  test "NÃO condenada + sessão morta: for() reconstrói UMA vez e a 2ª leitura já sai lida" do
    zumbi = EspiaoBrowser.new(command_error: Ferrum::DeadBrowserError.new("message" => "ws fechado"))
    saudavel = EspiaoBrowser.new(cookies: [cdo_sido_do_default])
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    # 1ª chamada pega o zumbi; após o reset (received == 0 → descarte imediato),
    # a 2ª volta já no browser saudável.
    Fetcher::PageFetcher.stubs(:browser).returns(zumbi, saudavel)
    Fetcher::PageFetcher.expects(:reset_browser!).once

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "o retry acontece APENAS quando a instância não está condenada"
    assert_equal 1, zumbi.storage_calls.size, "a instância morta leva UMA leitura"
    assert_equal 1, saudavel.storage_calls.size,
                 "o retry é 1×: a 2ª leitura sai na instância reconstruída"
    refute saudavel.storage_calls.last[2].key?(:browserContextId),
           "o retry também sai sem browserContextId"
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

  # Um cookie do jar implícito, no formato que o CDP devolve em response["cookies"].
  def cdo_sido_do_default
    { "name" => "SID", "value" => "abc", "domain" => ".youtube.com", "path" => "/" }
  end
end
