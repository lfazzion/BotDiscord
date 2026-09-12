# frozen_string_literal: true

require "test_helper"
require_relative "../../../../lib/fetcher/channels/reddit"

class Fetcher::Channels::RedditTest < ActiveSupport::TestCase
  PAYLOAD = {
    "title"     => "Por que Ruby 4.0 removeu ostruct",
    "subreddit" => "ruby",
    "author"    => "alguem",
    "score"     => 412,
    "selftext"  => "Corpo do post original.",
    "comments"  => [
      { "author" => "a", "score" => 90, "depth" => 0, "body" => "Comentario raiz." },
      { "author" => "b", "score" => 12, "depth" => 1, "body" => "Resposta." },
      { "author" => "c", "score" => 3,  "depth" => 4, "body" => "Fundo do poco." }
    ]
  }.freeze

  # Mesma forma do canal de YouTube: a lógica vive em `from_page`, público, e o
  # teste entra por lá com uma página de mentira — sem Chrome.
  class FakePage
    def initialize(json) = @json = json
    def evaluate(_js) = @json
  end

  def from_page(payload = PAYLOAD, url: "https://old.reddit.com/r/ruby/comments/abc/x/")
    Fetcher::Channels::Reddit.from_page(page: FakePage.new(JSON.generate(payload)), url: url)
  end

  test "monta post e arvore de comentarios indentada" do
    result = from_page

    assert_equal "Por que Ruby 4.0 removeu ostruct", result[:title]
    assert_equal "reddit", result[:metadata]["source"]
    assert_equal "thread", result[:metadata]["kind"]
    assert_equal "ruby", result[:metadata]["subreddit"]
    assert_equal 412, result[:metadata]["score"]
    assert_includes result[:content], "Corpo do post original."
    assert_includes result[:content], "- **a** (90): Comentario raiz."
    assert_includes result[:content], "  - **b** (12): Resposta."
  end

  test "corta abaixo de MAX_DEPTH e registra o corte" do
    result = from_page

    refute_includes result[:content], "Fundo do poco."
    assert_equal Fetcher::Channels::Reddit::MAX_DEPTH, result[:metadata]["truncated_depth"]
    assert_equal 2, result[:metadata]["num_comments"]
    assert_equal 3, result[:metadata]["comment_total"]
  end

  test "reescreve o host para old.reddit.com antes de navegar" do
    Fetcher::BrowserSession.expects(:with_page)
                           .with("https://old.reddit.com/r/ruby/comments/abc/x/")
                           .returns(nil)

    Fetcher::Channels::Reddit.call(url: "https://www.reddit.com/r/ruby/comments/abc/x/")
  end

  test "URL que nao e de post devolve nil sem abrir browser" do
    Fetcher::BrowserSession.expects(:with_page).never

    assert_nil Fetcher::Channels::Reddit.call(url: "https://www.reddit.com/r/ruby/")
    assert_nil Fetcher::Channels::Reddit.call(url: "https://www.reddit.com/user/alguem")
  end

  # O caminho de LEITURA degradava em silêncio: `from_page` devolvia nil quando
  # o EXTRACT_JS devolvia null, e o `||` do ExtractService caía no caminho
  # comum SEM erro — a casca da página virava a thread, com engine "static".
  # Agora nil vira PageFailed, erro nomeado que o serviço converte em campo.
  test "JSON invalido vindo da pagina vira erro nomeado, nao excecao crua" do
    erro = assert_raises(Fetcher::Channels::Reddit::PageFailed) do
      Fetcher::Channels::Reddit.from_page(page: FakePage.new("{nao json"),
                                          url: "https://old.reddit.com/r/x/comments/a/b/")
    end

    assert_kind_of Fetcher::Channels::Error, erro
    assert_includes erro.message, "thread"
  end

  test "JS que devolveu null na leitura vira erro nomeado, nunca nil" do
    erro = assert_raises(Fetcher::Channels::Reddit::PageFailed) do
      Fetcher::Channels::Reddit.from_page(page: FakePage.new(nil),
                                          url: "https://old.reddit.com/r/x/comments/a/b/")
    end

    assert_kind_of Fetcher::Channels::Error, erro
    assert_includes erro.message, "ilegível"
  end

  # O seletor CSS iniciado por ">" é inválido em querySelector e levanta
  # SyntaxError no navegador, matando a IIFE inteira. Tem de ser ":scope >".
  test "o JS extrator nao usa seletor iniciado por combinador" do
    js = Fetcher::Channels::Reddit::EXTRACT_JS

    refute_match(/querySelector\(\s*"\s*>/, js)
    assert_includes js, ":scope > .entry .author"
    assert_includes js, ":scope > .entry .usertext-body"
  end

  test "a URL reescrita preserva path e query" do
    Fetcher::BrowserSession.expects(:with_page)
                           .with("https://old.reddit.com/r/ruby/comments/abc/x/?sort=top")
                           .returns(nil)

    Fetcher::Channels::Reddit.call(url: "https://www.reddit.com/r/ruby/comments/abc/x/?sort=top")
  end

  # ----------------------------------------------------------------------------
  # Busca nativa (Reddit.search) — nenhum buscador web indexa permalink de
  # thread, entao descoberta so acontece por aqui.
  # ----------------------------------------------------------------------------

  SEARCH_PAYLOAD = [
    { "url" => "https://old.reddit.com/r/ruby/comments/aaa/titulo_a/", "title" => "Titulo A",
      "subreddit" => "r/ruby", "score" => 54, "comments" => 15 },
    { "url" => "https://old.reddit.com/r/rails/comments/bbb/titulo_b/", "title" => "Titulo B",
      "subreddit" => "r/rails", "score" => nil, "comments" => nil },
    { "url" => "", "title" => "sem link", "subreddit" => "r/x", "score" => 1, "comments" => 1 }
  ].freeze

  def from_search(payload = SEARCH_PAYLOAD, limit: 10)
    Fetcher::Channels::Reddit.from_search_page(page: FakePage.new(JSON.generate(payload)), limit: limit)
  end

  test "busca devolve hash de chaves string no mesmo contrato do canal de YouTube" do
    itens = from_search

    assert_equal 2, itens.size, "item sem url nao serve de resultado e e descartado"
    primeiro = itens.first
    assert_equal %w[url title subreddit score comments].sort, primeiro.keys.sort
    assert_equal "https://www.reddit.com/r/ruby/comments/aaa/titulo_a/", primeiro["url"]
    assert_equal "Titulo A", primeiro["title"]
    assert_equal "ruby", primeiro["subreddit"]
    assert_equal 54, primeiro["score"]
    assert_equal 15, primeiro["comments"]
  end

  # Regra da casa: metrica que nao deu para ler e nil. Zero significaria thread
  # sem voto nenhum, que e informacao diferente.
  test "score e comentarios desconhecidos ficam nil, nunca 0" do
    segundo = from_search[1]

    assert_nil segundo["score"]
    assert_nil segundo["comments"]
  end

  test "corta no limite pedido e no teto da classe" do
    muitos = Array.new(40) do |i|
      { "url" => "https://old.reddit.com/r/x/comments/#{i}/t/", "title" => "t#{i}",
        "subreddit" => "r/x", "score" => i + 1, "comments" => i + 1 }
    end

    assert_equal 3, from_search(muitos, limit: 3).size
    assert_equal Fetcher::Channels::Reddit::MAX_RESULTADOS, from_search(muitos, limit: 999).size
    assert_equal 1, from_search(muitos, limit: 0).size, "limite invalido nao pode virar lista vazia"
  end

  test "busca com query vazia devolve lista vazia sem abrir browser" do
    Fetcher::BrowserSession.expects(:with_page).never

    assert_equal [], Fetcher::Channels::Reddit.search(query: "   ")
  end

  test "busca navega em old.reddit.com com sort=relevance e o termo escapado" do
    Fetcher::HostRateLimiter.stubs(:exceeded?).returns(false)
    Fetcher::BrowserSession.expects(:with_page)
                           .with("https://old.reddit.com/search?q=ruby+on+rails&sort=relevance")
                           .returns([])

    Fetcher::Channels::Reddit.search(query: "ruby on rails")
  end

  # Busca em plataforma logada e onde rajada vira ban: o limitador roda ANTES de
  # abrir o browser, e estourar e erro nomeado, nunca lista vazia.
  test "limitador por host barra a busca antes de abrir o browser" do
    Fetcher::HostRateLimiter.expects(:exceeded?)
                            .with("old.reddit.com", max: Fetcher::Channels::Reddit::MAX_PER_WINDOW)
                            .returns(true)
    Fetcher::BrowserSession.expects(:with_page).never

    erro = assert_raises(Fetcher::Channels::Reddit::RateLimited) do
      Fetcher::Channels::Reddit.search(query: "ruby")
    end

    assert_includes erro.message, "old.reddit.com"
    assert Fetcher::Channels::Reddit::RateLimited < Fetcher::Channels::Error
  end

  # Medido: `.search-result-link` e o container do resultado de busca.
  # `#siteTable` e o seletor da pagina de THREAD e nao existe na busca.
  test "o JS de busca usa o seletor de resultado, nao o da pagina de thread" do
    js = Fetcher::Channels::Reddit::SEARCH_JS

    assert_includes js, ".search-result-link"
    refute_includes js, "#siteTable"
    refute_match(/querySelector\(\s*"\s*>/, js)
  end

  # Lista vazia aqui seria lida pelo modelo como "nao existe nada sobre isso".
  # Payload ilegivel nao e isso: e "nao consegui olhar". O try/catch do SEARCH_JS
  # devolve null quando um seletor muda, e o caminho de LEITURA ja trata o mesmo
  # caso como erro (from_page -> nil -> erro nomeado no ExtractService).
  test "payload ilegivel na busca vira erro nomeado, nao lista vazia" do
    erro = assert_raises(Fetcher::Channels::Reddit::SearchFailed) do
      Fetcher::Channels::Reddit.from_search_page(page: FakePage.new("{nao json"), limit: 5)
    end

    assert_kind_of Fetcher::Channels::Error, erro, "a tool faz rescue de Channels::Error"
    assert_includes erro.message, "busca"
  end

  # O ramo do catch do JS: seletor que sumiu devolve null, nao "[]".
  test "JS que devolveu null vira erro, nao zero resultados" do
    assert_raises(Fetcher::Channels::Reddit::SearchFailed) do
      Fetcher::Channels::Reddit.from_search_page(page: FakePage.new(nil), limit: 5)
    end
  end

  # E o contrario continua valendo: busca que rodou e nao achou nada e resposta,
  # nao falha.
  test "busca sem resultado nenhum continua sendo lista vazia" do
    assert_equal [], from_search([])
  end

  test "thread_comments extrai comentários estruturados com posted_at da tagline" do
    payload = {
      "title" => "Thread com timestamps",
      "subreddit" => "brasil",
      "author" => "autor1",
      "score" => 100,
      "comments" => [
        { "author" => "user1", "score" => 50, "depth" => 0, "created_at" => "2026-08-10T12:00:00+00:00", "body" => "Comentário com data." }
      ]
    }

    res = Fetcher::Channels::Reddit.from_thread_comments_page(
      page: FakePage.new(JSON.generate(payload)),
      url: "https://old.reddit.com/r/brasil/comments/xyz/t/"
    )

    assert_equal "Thread com timestamps", res["title"]
    assert_equal 1, res["comments"].size
    c = res["comments"].first
    assert_equal "user1", c["author"]
    assert_equal "2026-08-10T12:00:00+00:00", c["posted_at"]
    assert_equal "Comentário com data.", c["body"]
  end

  # A página de bloqueio do Reddit ("whoa there, pardner ... blocked due to a
  # network policy") carrega com HTTP 200 e o SEARCH_JS devolve "[]" — que o
  # parser lê como "busca sem resultado". Isso PRECISA virar SearchFailed nomeando
  # o bloqueio (e sem esperar os 35s), nunca uma lista vazia que o modelo
  # interpreta como "não existe nada sobre isso".
  class FakeBlockedPage
    def evaluate(js)
      # SEARCH_JS contém "querySelectorAll" — o evaluate do innerText
      # ("document.body ? document.body.innerText : ''") não contém.
      # NÃO usa "innerText" para discriminar: SEARCH_JS também contém
      # "innerText" (função txt(el) na linha 147 do reddit.rb).
      return "[]" if js.to_s.include?("querySelectorAll")

      "whoa there, pardner... your request has been blocked due to a network policy"
    end
  end

  test "pagina de bloqueio do Reddit vira SearchFailed com 'blocked by network policy' e nunca lista vazia" do
    erro = assert_raises(Fetcher::Channels::Reddit::SearchFailed) do
      Fetcher::Channels::Reddit.from_search_page(page: FakeBlockedPage.new, limit: 5)
    end

    assert_equal "Reddit bloqueou a leitura (politica de rede)", erro.message
  end

  # ── Achado 1 do perito (r2): caminho de LEITURA também precisa detectar
  # página de bloqueio. O EXTRACT_JS devolve um hash com title="" e comments=[]
  # na página de bloqueio — que se parece com uma thread legítima sem conteúdo.
  #
  # Fake que simula a página de bloqueio: responde com hash vazio quando o JS
  # é o EXTRACT_JS (que contém "querySelector"), e texto de bloqueio para o
  # evaluate("document.body?...") que o from_page faz para detectar bloqueio.
  # NÃO usa .include?("innerText") para discriminar — o próprio EXTRACT_JS
  # contém "innerText" (função txt(el) na linha 92 do reddit.rb).
  class FakeBlockedThreadPage < FakePage
    def initialize
      super(JSON.generate({
        "title" => "", "subreddit" => "", "author" => "",
        "score" => nil, "selftext" => "", "comments" => []
      }))
    end

    def evaluate(js)
      if js.to_s.include?("querySelector")
        @json
      else
        "whoa there, pardner... your request has been blocked due to a network policy"
      end
    end
  end

  # O caminho de LEITURA (from_page) hoje passa página de bloqueio como thread
  # legítima: o EXTRACT_JS devolve um hash vazio, build() monta um resultado com
  # title="" e 0 comentários — o modelo recebe "thread sem conteúdo" em vez de
  # erro. Precisa detectar o bloqueio e levantar PageFailed nomeando-o.
  test "from_page detecta pagina de bloqueio e levanta PageFailed nomeando o bloqueio (Achado 1)" do
    erro = assert_raises(Fetcher::Channels::Reddit::PageFailed) do
      Fetcher::Channels::Reddit.from_page(
        page: FakeBlockedThreadPage.new,
        url: "https://old.reddit.com/r/brasil/comments/xyz/t/"
      )
    end

    assert_equal "Reddit bloqueou a leitura (politica de rede)", erro.message
  end

  # Mesmo para from_thread_comments_page: o EXTRACT_JS devolve hash vazio,
  # build_thread_components monta resultado vazio — precisa detectar bloqueio.
  test "from_thread_comments_page detecta pagina de bloqueio e levanta PageFailed (Achado 1)" do
    erro = assert_raises(Fetcher::Channels::Reddit::PageFailed) do
      Fetcher::Channels::Reddit.from_thread_comments_page(
        page: FakeBlockedThreadPage.new,
        url: "https://old.reddit.com/r/brasil/comments/xyz/t/"
      )
    end

    assert_equal "Reddit bloqueou a leitura (politica de rede)", erro.message
  end

  # Thread REAL com título válido e comentários NÃO deve ser afetada pelo
  # cheque de bloqueio — regressão: um post com "" visível como título não
  # pode virar PageFailed.
  # Double discrimina por "querySelector" (EXTRACT_JS) — NÃO por
  # "innerText", porque o próprio EXTRACT_JS contém "innerText" (reddit.rb:92).
  test "thread real com titulo valido NAO e bloqueio mesmo que tenha innerText limpo (regressao)" do
    payload_real = {
      "title" => "Titulo real", "subreddit" => "ruby", "author" => "alguem",
      "score" => 100, "selftext" => "texto", "comments" => [
        { "author" => "a", "score" => 5, "depth" => 0, "body" => "comentario" }
      ]
    }
    page = FakePage.new(JSON.generate(payload_real))
    page.define_singleton_method(:evaluate) do |js|
      js.to_s.include?("querySelector") ? @json : "conteudo normal sem bloqueio"
    end

    result = Fetcher::Channels::Reddit.from_page(page: page, url: "https://old.reddit.com/r/ruby/comments/a/b/")
    assert_equal "Titulo real", result[:title]
  end

  # Hash vazio SEM marcador de bloqueio no innerText TAMBÉM levanta PageFailed:
  # o bloqueador é o blocked_hash?, a sonda de innerText só enriquece a mensagem.
  # Nunca pode cair em build() com thread vazia.
  class FakeEmptyPage
    def evaluate(js)
      js.to_s.include?("querySelector") ? JSON.generate(
        "title" => "", "subreddit" => "", "author" => "",
        "score" => nil, "selftext" => "", "comments" => []
      ) : "conteudo generico sem marcador de bloqueio"
    end
  end

  test "hash vazio sem marcador de bloqueio levanta PageFailed (nao cai em build)" do
    erro = assert_raises(Fetcher::Channels::Reddit::PageFailed) do
      Fetcher::Channels::Reddit.from_page(
        page: FakeEmptyPage.new,
        url: "https://old.reddit.com/r/brasil/comments/xyz/t/"
      )
    end
    assert_match(/ilegível|seletor/i, erro.message,
                 "deve usar a mensagem padrao (sem razao nomeada)")
  end
end
