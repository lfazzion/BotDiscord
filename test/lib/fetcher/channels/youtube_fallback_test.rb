# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "open3"
require_relative "../../../../lib/fetcher/channels/youtube"

class Fetcher::Channels::YoutubeFallbackTest < ActiveSupport::TestCase
  EVENTS = {
    "events" => [
      { "segs" => [{ "utf8" => "transcricao em portugues valida" }] }
    ]
  }.freeze

  INFO = {
    "id" => "video123", "title" => "Video Teste", "channel" => "Canal Teste",
    "subtitles"=> {}, "automatic_captions" => {}
  }.freeze

  test "reporta versao do yt-dlp no ambiente de teste" do
    out, = Open3.capture2("yt-dlp", "--version") rescue ["not found"]
    puts "yt-dlp version inside testctl: #{out.to_s.strip}"
    assert true
  end

  # (a) restrito GREEN: apenas pt-BR.json3 com conteudo valido
  test "caso (a) restrito GREEN: seleciona pt-BR.json3 com sucesso" do
    Dir.mktmpdir("fallback_a") do |dir|
      File.write(File.join(dir, "video123.pt-BR.json3"), JSON.generate(EVENTS))
      result = Fetcher::Channels::Youtube.build_from(dir: dir, url: "https://www.youtube.com/watch?v=video123", info: INFO)

      assert_equal "transcricao em portugues valida", result[:content]
      assert_equal "pt-BR", result[:metadata]["lang"]
    end
  end

  # (b) set-all com stub aa vazio + pt-BR valida -> content pt-BR
  test "caso (b) set-all com stub aa vazio + pt-BR valida elege pt-BR" do
    Dir.mktmpdir("fallback_b") do |dir|
      File.write(File.join(dir, "video123.aa.vtt"), "WEBVTT\n\n")
      File.write(File.join(dir, "video123.en-GB.vtt"), "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nEnglish auto text")
      File.write(File.join(dir, "video123.ja.vtt"), "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nJapanese text")
      File.write(File.join(dir, "video123.es.srt"), "1\n00:00:00,000 --> 00:00:05,000\nSpanish text")
      File.write(File.join(dir, "video123.pt-BR.json3"), JSON.generate(EVENTS))

      result = Fetcher::Channels::Youtube.build_from(dir: dir, url: "https://www.youtube.com/watch?v=video123", info: INFO)

assert_equal "transcricao em portugues valida", result[:content]
      assert_equal "pt-BR", result[:metadata]["lang"]
    end
  end

  # (c) dir vazio -> NoTranscript
  test "caso (c) dir vazio levanta NoTranscript" do
    Dir.mktmpdir("fallback_c") do |dir|
      assert_raises(Fetcher::Channels::Youtube::NoTranscript) do
        Fetcher::Channels::Youtube.build_from(dir: dir, url: "https://www.youtube.com/watch?v=video123", info: INFO)
      end
    end
  end

  # (d) todas vazias -> NoTranscript
  test "caso (d) todas as faixas vazias levanta NoTranscript" do
Dir.mktmpdir("fallback_d") do |dir|
      File.write(File.join(dir, "video123.aa.vtt"), "WEBVTT\n\n")
      File.write(File.join(dir, "video123.pt-BR.json3"), JSON.generate({ "events" => [] }))
      File.write(File.join(dir, "video123.es.srt"), "")

      assert_raises(Fetcher::Channels::Youtube::NoTranscript) do
        Fetcher::Channels::Youtube.build_from(dir: dir, url: "https://www.youtube.com/watch?v=video123", info: INFO)
      end
    end
  end

  # (e) manual es vence auto aa
  test "caso (e) manual es vence auto aa" do
    Dir.mktmpdir("fallback_e") do |dir|
      info = INFO.merge(
        "subtitles" => { "es" =>[{}] },
        "automatic_captions" => { "aa" => [{}] }
      )
      File.write(File.join(dir, "video123.aa.vtt"), "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nAfaraf auto text")
      File.write(File.join(dir, "video123.es.srt"), "1\n00:00:00,000 --> 00:00:05,000\nSpanish manual text")

      result = Fetcher::Channels::Youtube.build_from(dir: dir, url: "https://www.youtube.com/watch?v=video123", info: info)

assert_equal "Spanish manual text", result[:content]
      assert_equal "es", result[:metadata]["lang"]
assert_equal false, result[:metadata]["auto_generated"]
    end
  end

  # ── Novos testes: boundar download de legendas (429) e passes limitados ─────
  test "all nunca de primeira: passe 1 usa lista curta preferida e nao chama all se ha legendas" do
    Dir.mktmpdir("fallback_p1") do |dir|
      chamadas_langs = []
      Fetcher::Channels::Youtube.stubs(:download_subs).with do |d, _cookie, _url, langs,_timeout|
        chamadas_langs << langs
        File.write(File.join(d, "video123.pt-BR.json3"), JSON.generate(EVENTS))
        INFO
      end

      info = Fetcher::Channels::Youtube.send(:run, "https://www.youtube.com/watch?v=video123", dir, "/fake/cookie")

      assert_equal "pt-BR,pt,en,en-US,en-GB,en-orig,es,fr,de,it,ja", chamadas_langs.first
      refute_equal "all", chamadas_langs.first
      assert_equal 1, chamadas_langs.size
      assert_equal "video123", info["id"]
    end
  end

  test "tolerancia por faixa: 429 em uma faixa com outras validas nao aborta e elege legenda valida" do
    Dir.mktmpdir("fallback_429") do |dir|
      Fetcher::Channels::Youtube.stubs(:download_subs).with do |d, _cookie, _url, _langs, _timeout|
        File.write(File.join(d, "video123.pt-BR.json3"), JSON.generate(EVENTS))
        raise Fetcher::Channels::Youtube::YtdlpError.new(1, "Unable to download video subtitles for ab: HTTP Error 429 Too Many Requests")
      end

      info = Fetcher::Channels::Youtube.send(:run, "https://www.youtube.com/watch?v=video123", dir, "/fake/cookie")
      result = Fetcher::Channels::Youtube.build_from(dir: dir, url: "https://www.youtube.com/watch?v=video123", info: info)

      assert_equal "transcricao em portugues valida", result[:content]
      assert_equal "pt-BR", result[:metadata]["lang"]
end
  end

  test "passe 2 estendido com all chamado quando passe 1 e vazio" do
    Dir.mktmpdir("fallback_p2") do |dir|
      chamadas_langs = []
      Fetcher::Channels::Youtube.stubs(:download_subs).with do |d, _cookie, _url, langs, _timeout|
        chamadas_langs << langs
        if langs == "all"
          File.write(File.join(d, "video123.ja.vtt"), "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nJapanese text")
        end
        INFO
      end

      info = Fetcher::Channels::Youtube.send(:run, "https://www.youtube.com/watch?v=video123", dir, "/fake/cookie")
      result = Fetcher::Channels::Youtube.build_from(dir:dir, url: "https://www.youtube.com/watch?v=video123", info: info)

      assert_equal 2, chamadas_langs.size
      assert_equal "all", chamadas_langs[1]
      assert_equal "Japanese text", result[:content]
      assert_equal "ja", result[:metadata]["lang"]
    end
  end

  test "YtdlpError propagado quando nada foi baixado no disco" do
    Dir.mktmpdir("fallback_nada") do |dir|
      Fetcher::Channels::Youtube.stubs(:download_subs).raises(
        Fetcher::Channels::Youtube::YtdlpError.new(1, "Unable to download video subtitles for ab: HTTP Error 429 Too Many Requests")
      )

      assert_raises(Fetcher::Channels::Youtube::YtdlpError) do
        Fetcher::Channels::Youtube.send(:run, "https://www.youtube.com/watch?v=video123", dir, "/fake/cookie")
      end
    end
  end
end
