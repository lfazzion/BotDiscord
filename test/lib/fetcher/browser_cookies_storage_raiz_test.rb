# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/fetcher/page_fetcher"
require_relative "../../../lib/fetcher/browser_cookies"

# VIA FINAL — a leitura de cookies é a chamada RAIZ do CDP.
#
# Este arquivo substitui `browser_cookies_contexto_padrao_test.rb`, escrito para
# a PISTA FALSA (o id do contexto padrão alimentaria `Storage.getCookies`). O
# laudo r5 reprovou aquela via: o B1 só "funcionava" porque, depois de um -32602
# inevitável, caía na chamada que é a única OK — o que travava o id falso no
# código e nos testes.
#
# MEDIÇÃO EM CHROME REAL, imagem de produção (ferrum 0.18.0, chromedp/headless-shell),
# evidência em /tmp/revisao-b1/evidencia/medicao-C-vias-producao.txt:
#
#   Storage.getCookies (raiz, SEM id)       => OK {"cookies"=>[]}   (C:8)
#   Storage.getCookies com o id do CDP      => CDP -32602           (C:9)
#   Storage.getCookies com id nil / ""      => CDP -32602           (C:15)
#   Network.getAllCookies (raiz)            => CDP -32601           (C:14)
#   browser.cookies.all (página default)    => CDP -32001           (C:11)
#   default_context.create_page             => CDP -32602           (C:12)
#   Target.getBrowserContexts               => publica defaultBrowserContextId
#                                              que ESTE comando RECUSA (C:6-7 x C:9)
#
# `default_context.id` é nil no ferrum 0.18 desta imagem: o Ferrum só preenche
# `id` em contextos que ele PRÓPRIO cria. O `defaultBrowserContextId` do CDP
# existe, mas o `Storage.getCookies` o recusa. O jar que interessa é o IMPLÍCITO
# do perfil, e a forma medida de lê-lo é OMITINDO o parâmetro.
#
# Os dublês abaixo modelam ESSA medição: QUALQUER chamada que traga
# `browserContextId` responde -32602; sem a chave responde `{"cookies"=>[...]}`.
# Mandar id levantando o MESMO erro de produção é o que acusa a volta ao caminho
# antigo.
class Fetcher::BrowserCookiesStorageRaizTest < ActiveSupport::TestCase
  # Ids: o do CDP (contexto padrão) e um "id do Ferrum" que NÃO é o do CDP —
  # este último só serve para provar que a leitura não voltou a mirar o objeto do
  # Ferrum nem o id publicado pelo CDP.
  CTX_DO_CDP    = "83E8EFF3922BA9E9B8F391F77FDD08AA"
  CTX_DO_FERRUM = "id_que_o_ferrum_inventou"
  ERRO_PARAMETROS  = -32602
  ERRO_INEXISTENTE = -32601

  COOKIE_YOUTUBE = { "name" => "SID", "value" => "abc",
                     "domain" => ".youtube.com", "path" => "/" }.freeze
  COOKIE_REDDIT = { "name" => "sessionid", "value" => "xyz",
                    "domain" => ".reddit.com", "path" => "/" }.freeze

  # ── Dublê no formato do ferrum 0.18 de produção ─────────────────────────────
  # `command` vai ao cliente raiz (browser.rb:38). `default_context` devolve um
  # Context cujo `id` é nil — como em produção — e cujo `create_page` EXPLODE: o
  # fallback de página é inexecutável nesta imagem (medido -32602, C:12) e o
  # laudo r5 B2 manda apagá-lo.
  class BrowserDeProducao
    attr_reader :comandos, :pages_criadas

    def initialize(default_ctx_id: nil, cookies: [], erro_por_chamada: {},
                   comando_inexistente: false, erro_version: nil, erro_sucesso: nil)
      @default_ctx_id = default_ctx_id
      @cookies = cookies
      @comandos = []
      @pages_criadas = 0
      # Erro por assinatura da chamada: :com_id (a chave veio) e :sem_id.
      @erro_por_chamada = erro_por_chamada
      @comando_inexistente = comando_inexistente
      @erro_version = erro_version
      @erro_sucesso = erro_sucesso
    end

    def version
      raise @erro_version if @erro_version

      "HeadlessChrome/147.0.7727.102"
    end

    def default_context
      @default_context ||= begin
        duble = self
        Struct.new(:id) do
          define_method(:create_page) do
            duble.pages_criadas_incrementa!
            raise "o fallback de página é INEXECUTÁVEL nesta imagem (medido -32602, C:12) — laudo r5 B2"
          end
        end.new(@default_ctx_id)
      end
    end

    def pages_criadas_incrementa!
      @pages_criadas += 1
    end

    def command(cmd, **params)
      @comandos << { cmd: cmd, params: params }
      case cmd
      when "Target.getBrowserContexts"
        # O id existe, mas o comando de leitura o recusa (C:6-7 x C:9).
        { "browserContextIds" => [], "defaultBrowserContextId" => CTX_DO_CDP }
      when "Network.getAllCookies"
        # Medido -32601 na raiz (C:14): a via antiga está morta neste Chrome.
        raise cdp("'Network.getAllCookies' wasn't found", ERRO_INEXISTENTE)
      when "Storage.getCookies"
        return recusa(params) if params.key?(:browserContextId)

        raise cdp("'Storage.getCookies' wasn't found", ERRO_INEXISTENTE) if @comando_inexistente

        raise @erro_sucesso if @erro_sucesso

        { "cookies" => @cookies }
      else
        raise "comando inesperado: #{cmd}"
      end
    end

    def storage_calls = @comandos.select { |c| c[:cmd] == "Storage.getCookies" }
    def contextos_consultados = @comandos.select { |c| c[:cmd] == "Target.getBrowserContexts" }

    private

    # PRODUÇÃO: o comando ACEITA o parâmetro e o RECUSA — nil/vazio devolve
    # "Invalid parameters" (C:15), um id que o Chrome não reconhece devolve
    # "Failed to find browser context for id X" (C:9). Os dois são -32602.
    def recusa(params)
      id = params[:browserContextId]
      mensagem = id.nil? || id.to_s.empty? ? "Invalid parameters" : "Failed to find browser context for id #{id}"
      raise cdp(mensagem, ERRO_PARAMETROS)
    end

    # Erro injetado por assinatura (o controle discriminador usa os dois lados).
    def erro_para(params)
      @erro_por_chamada[params.key?(:browserContextId) ? :com_id : :sem_id]
    end

    def cdp(mensagem, codigo)
      Ferrum::BrowserError.new("message" => mensagem, "code" => codigo)
    end
  end

  # Estado de classe do PageFetcher isolado como nos testes irmãos
  # (page_fetcher_browser_test.rb / cura_sessao_cdp_test.rb).
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

  # ── (a) leitura com cookies, pela raiz ────────────────────────────────────
  test "(a) default_context.id nil: a leitura acha os cookies pela chamada da raiz, SEM id" do
    b = com_browser(BrowserDeProducao.new(cookies: [COOKIE_YOUTUBE, COOKIE_REDDIT]))

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "a leitura sem id é a via medida OK (C:8): tem de achar o jar implícito"
    assert_equal "abc", lidos.first["value"]
    assert_equal ".youtube.com", lidos.first["domain"]
  end

  test "(a) Storage.getCookies é chamado SEM a chave :browserContextId" do
    b = com_browser(BrowserDeProducao.new(cookies: [COOKIE_YOUTUBE]))

    Fetcher::BrowserCookies.for("youtube.com")

    assert_equal 1, b.storage_calls.size, "uma chamada, e uma só: sem id para degradar"
    assert_not b.storage_calls.last[:params].key?(:browserContextId),
               "a leitura tem de OMITIR o parâmetro — mandá-lo é o defeito REPROVADO pelo " \
               "laudo r5 (com id do CDP: -32602, C:9; com o do Ferrum/nil: -32602, C:15)"
    assert_equal 0, b.pages_criadas, "o fallback de página foi apagado (inexecutável: C:12)"
  end

  test "(a) sem Target.getBrowserContexts no caminho quente" do
    b = com_browser(BrowserDeProducao.new(cookies: [COOKIE_YOUTUBE]))

    Fetcher::BrowserCookies.for("youtube.com")

    assert_empty b.contextos_consultados,
                 "Target.getBrowserContexts publica o id que o Storage.getCookies RECUSA (C:9): " \
                 "consultá-lo no caminho quente é a pista falsa do B1"
  end

  test "(a) leitura vazia é [] legítimo, não erro" do
    b = com_browser(BrowserDeProducao.new(cookies: []))

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "{\"cookies\"=>[]} na chamada sem id é o jar implícito VAZIO em repouso (C:8)"
    assert_not b.storage_calls.last[:params].key?(:browserContextId)
  end

  # ── (b) controle invertido: nenhuma leitura leva browserContextId ─────────
  test "(b) controle invertido: nenhuma forma de leitura leva browserContextId (nem nil)" do
    b = com_browser(BrowserDeProducao.new(cookies: [COOKIE_YOUTUBE]))

    Fetcher::BrowserCookies.for("youtube.com")

    com_id = b.storage_calls.select { |c| c[:params].key?(:browserContextId) }
    assert_empty com_id,
                 "em produção o id do Ferrum é nil e o do CDP é recusado: mandar browserContextId " \
                 "é o CDP -32602 'Invalid parameters' / 'Failed to find browser context' que " \
                 "desligava a leitura (C:9, C:15)"
  end

  test "(b) controle invertido: com o id do Ferrum divergente, a leitura segue sem parâmetro" do
    # O Ferrum deixa `id` nil em produção; aqui ele é um id DIFERENTE do que o CDP
    # devolve. Se alguém voltar a `browser.default_context.id`, a asserção acusa.
    b = com_browser(BrowserDeProducao.new(default_ctx_id: CTX_DO_FERRUM, cookies: [COOKIE_YOUTUBE]))

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] }
    assert_not b.storage_calls.last[:params].key?(:browserContextId),
               "a leitura mirou o id do Ferrum (#{CTX_DO_FERRUM}) — é o defeito B1 de volta"
  end

  # ── (c) erros CDP → [] com log, sem rebuild indevido ──────────────────────
  test "(c) -32601 → [] e log, sem fallback de página" do
    b = com_browser(BrowserDeProducao.new(comando_inexistente: true))
    Fetcher::PageFetcher.expects(:reset_browser!).never
    Rails.logger.expects(:warn).at_least_once

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "-32601 é log + [] (laudo r5 §3): Chrome sem o comando cai no jar do banco, " \
                 "igual a 'Chrome indisponível'"
    assert_equal 0, b.pages_criadas,
                 "o fallback de página do -32601 foi APAGADO — medido inexecutável (C:12)"
  end

  test "(c) -32602 → [] e log, sem retry e sem degradação" do
    # Dublê do pior caso: até a chamada da raiz é recusada. Não há id para
    # degradar, então não pode haver 2ª chamada.
    b = com_browser(BrowserDeProducao.new(erro_sucesso: Ferrum::BrowserError.new(
      "message" => "Invalid parameters", "code" => ERRO_PARAMETROS
    )))
    Fetcher::PageFetcher.expects(:reset_browser!).never
    Rails.logger.expects(:warn).at_least_once

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "-32602 é log + [] (laudo r5 §4): o browser vive, o contexto é que não atende"
    assert_equal 1, b.storage_calls.size,
                 "-32602 não gera 2ª leitura: o id falso que exigia retry não existe mais"
  end

  test "(c) -32001 (sessão morta) → 1 retry quando não condenado" do
    zumbi = BrowserDeProducao.new(erro_sucesso: Ferrum::BrowserError.new(
      "message" => "Session with given id not found", "code" => -32001
    ))
    saudavel = BrowserDeProducao.new(cookies: [COOKIE_YOUTUBE])
    # 1ª chamada pega o zumbi; após o reset, a 2ª já sai no browser saudável.
    Fetcher::PageFetcher.stubs(:browser).returns(zumbi, saudavel)
    Fetcher::PageFetcher.expects(:reset_browser!).once

    lidos = Fetcher::BrowserCookies.for("youtube.com")

    assert_equal ["SID"], lidos.map { |c| c["name"] },
                 "o retry da sessão morta cobre DeadBrowserError / WS morto (laudo r5 §4)"
    assert_equal 1, zumbi.storage_calls.size, "o zumbi leva UMA leitura"
    assert_equal 1, saudavel.storage_calls.size, "o retry é 1×, não um laço"
  end

  test "(c) retry não é infinito: morta nas duas vezes → [] nunca exceção" do
    zumbi = BrowserDeProducao.new(erro_sucesso: Ferrum::BrowserError.new(
      "message" => "Session with given id not found", "code" => -32001
    ))
    zumbi2 = BrowserDeProducao.new(erro_sucesso: Ferrum::BrowserError.new(
      "message" => "Session with given id not found", "code" => -32001
    ))
    Fetcher::PageFetcher.stubs(:browser).returns(zumbi, zumbi2)
    Fetcher::PageFetcher.expects(:reset_browser!).once # só a 1ª retentativa reseta

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "o contrato 'nunca exceção' é mantido: a 2ª falha loga e devolve []"
    assert_equal 1, zumbi.storage_calls.size
    assert_equal 1, zumbi2.storage_calls.size, "cada instância leva UMA leitura: o retry para em 1"
  end

  test "(c) condenada + sessão morta: [] SEM retry e SEM reset" do
    zumbi = BrowserDeProducao.new(erro_sucesso: Ferrum::BrowserError.new(
      "message" => "Session with given id not found", "code" => -32001
    ))
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, true)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 1)
    Fetcher::PageFetcher.stubs(:browser).returns(zumbi)
    Fetcher::PageFetcher.expects(:reset_browser!).never

    assert_empty Fetcher::BrowserCookies.for("youtube.com"),
                 "na condenada a 2ª leitura cairia num objeto morrendo — o descarte roda na " \
                 "saída do último holder"
    assert_equal 1, zumbi.storage_calls.size
  ensure
    Fetcher::PageFetcher.instance_variable_set(:@pending_discard, false)
    Fetcher::PageFetcher.instance_variable_set(:@browser_received, 0)
  end

  # ── (d) sonda ─────────────────────────────────────────────────────────────
  test "(d) probe devolve true com jar VAZIO (sessão viva, jar em repouso)" do
    b = BrowserDeProducao.new(cookies: [])

    assert_equal true, Fetcher::BrowserCookies.probe(b),
                 "{\"cookies\"=>[]} é resposta de sessão VIVA (C:8) — jar vazio em repouso " \
                 "não é sessão morta"
    assert_equal true, Fetcher::PageFetcher.alive?(b),
                 "PageFetcher.alive? é a sonda do cache: false aqui reconstrói o browser à toa"
    assert_not b.storage_calls.last[:params].key?(:browserContextId)
  end

  test "(d) probe devolve false quando o Storage estoura" do
    morto = BrowserDeProducao.new(erro_sucesso: Ferrum::DeadBrowserError.new("ws fechado"))
    assert_equal false, Fetcher::BrowserCookies.probe(morto),
                 "sessão morta na chamada da raiz tem de dar sonda falsa (o descarte da " \
                 "instância é o caminho de cura)"

    sem_version = BrowserDeProducao.new(erro_version: Ferrum::DeadBrowserError.new("ws fechado"))
    assert_equal false, Fetcher::BrowserCookies.probe(sem_version),
                 "sem o version respondendo não há sessão viva"
  end

  test "(d) probe devolve false quando o Chrome recusa o comando (-32602/-32601)" do
    recusado = BrowserDeProducao.new(erro_sucesso: Ferrum::BrowserError.new(
      "message" => "Invalid parameters", "code" => ERRO_PARAMETROS
    ))
    assert_equal false, Fetcher::BrowserCookies.probe(recusado),
                 "StandardError na sonda = false: a instância é descartada (laudo r5 item 2)"

    inexistente = BrowserDeProducao.new(comando_inexistente: true)
    assert_equal false, Fetcher::BrowserCookies.probe(inexistente),
                 "comando ausente também é sonda falsa — o cache entrega instância nova"
  end

  test "(d) a sonda mantém o Timeout (BROWSER_PROBE_TIMEOUT)" do
    b = BrowserDeProducao.new
    b.define_singleton_method(:version) { sleep 30 }

    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    resultado = Fetcher::BrowserCookies.probe(b)
    decorrido = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio

    assert_equal false, resultado
    assert_operator decorrido, :<, Fetcher::PageFetcher::BROWSER_PROBE_TIMEOUT + 1,
                    "a sonda herdou o timeout de 30s do client do ferrum"
  end

  # ── DISCRIMINAÇÃO: se alguém reintroduzir o id, qual asserção acusa ───────
  test "REGRESSÃO: reintroduzir browserContextId faz o dublê recusar com -32602 e a leitura voltar vazia" do
    b = BrowserDeProducao.new(cookies: [COOKIE_YOUTUBE])

    # A inversão crua: o comando com id, como o B1 reprovado mandava.
    assert_raises(Ferrum::BrowserError) do
      b.command("Storage.getCookies", browserContextId: CTX_DO_CDP)
    end

    # E o caminho legítimo segue funcionando sem a chave.
    assert_equal({ "cookies" => [COOKIE_YOUTUBE] }, b.command("Storage.getCookies"))
  end
end
