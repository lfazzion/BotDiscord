# frozen_string_literal: true

require "test_helper"

class RedditBlockedPageTest < ActiveSupport::TestCase
  test "Fetcher::Channels::Reddit.blocked_reddit_page? retorna true para texto bloqueado e false para texto normal" do
    blocked_text = "whoa there, pardner! Your request has been blocked due to a network policy"
    normal_text = "Here are the search results for something interesting"

    assert_equal true, Fetcher::Channels::Reddit.blocked_reddit_page?(blocked_text)
    assert_equal false, Fetcher::Channels::Reddit.blocked_reddit_page?(normal_text)
  end

  test "REDDIT_USER_AGENT e determinístico de Chrome/Windows sem HeadlessChrome" do
    ua = Fetcher::BrowserSession::REDDIT_USER_AGENT
    esperado = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "\
               "AppleWebKit/537.36 (KHTML, like Gecko) "\
               "Chrome/131.0.0.0 Safari/537.36"

    assert_match(/Chrome\/131/, ua)
    assert_equal esperado, ua,
                 "UA do Reddit deve ser o Chrome 131 Windows determinístico"
  end

  test "REDDIT_PLATFORM é Win32 coerente com o UA" do
    assert_equal "Win32", Fetcher::BrowserSession::REDDIT_PLATFORM
  end

  test "REDDIT_HOSTS casa com subdomínios do reddit e rejeita youtube/x" do
    regex = Fetcher::BrowserSession::REDDIT_HOSTS

    # Casos que DEVEM casar
    assert regex.match?("old.reddit.com"),  "old.reddit.com deve casar"
    assert regex.match?("www.reddit.com"),  "www.reddit.com deve casar"
    assert regex.match?("reddit.com"),      "reddit.com (domínio raiz) deve casar"
    assert regex.match?("br.reddit.com"),   "subdomínio br.reddit.com deve casar"

    # Casos que NÃO devem casar
    refute regex.match?("youtube.com"),     "youtube.com não deve casar"
    refute regex.match?("x.com"),           "x.com não deve casar"
    refute regex.match?("notreddit.com"),   "notreddit.com não deve casar"

    # Casos adversariais: hosts que CONTÊM "reddit.com" como substring
    # mas não são o domínio reddit. O regex usa \z (fim de string), então
    # estes são seguros — mas o teste cimenta o contrato contra regressão.
    refute regex.match?("reddit.com.evil.com"),   "subdomínio .evil.com não deve casar com reddit.com"
    refute regex.match?("www.reddit.com.br"),     ".com.br não é .com — não casa"
    refute regex.match?("evilreddit.com"),        "nome enganoso não é subdomínio reddit"
  end
end
