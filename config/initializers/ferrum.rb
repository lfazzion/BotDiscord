# frozen_string_literal: true

# config/initializers/ferrum.rb
#
# Resolve o problema de Host-header rejection no Chrome 120+ quando acessado
# via Docker network bridge. O Chrome expõe o debugger em 0.0.0.0:9222
# mas valida o header `Host:` — se ele não for "localhost", rejeita o WS handshake.
#
# Este initializer expõe o helper `FerumConfig.browser_options` que todos os
# scrapers devem usar ao instanciar `Ferrum::Browser`.

require "net/http"
require "json"
require "uri"

module FerumConfig
  CHROME_HOST = ENV.fetch("CHROME_HOST", "chrome")
  CHROME_PORT = ENV.fetch("CHROME_PORT", "9222").to_i

  # Varre o endpoint HTTP do Chrome (/json/version) injetando `Host: localhost`
  # para burlar a validação de security-origin do Chrome 120+.
  # Retorna a URL WebSocket correta com hostname substituído pelo IP do container.
  #
  # @return [String] WebSocket debugger URL com host resolvido
  # @raise [RuntimeError] se o Chrome não responder ou não retornar ws URL
  def self.discover_stealth_ws_url
    uri = URI("http://#{CHROME_HOST}:#{CHROME_PORT}/json/version")

    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 5) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Host"] = "localhost"   # <- bypass da validação de origin do Chrome 120+
      http.request(req)
    end

    raise "Chrome não respondeu (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

    payload      = JSON.parse(response.body)
    raw_ws_url   = payload["webSocketDebuggerUrl"]

    raise "webSocketDebuggerUrl ausente na resposta do Chrome" if raw_ws_url.nil?

    # Substitui o hostname retornado pelo Chrome (pode ser o nome interno do
    # container ou 127.0.0.1) pelo CHROME_HOST configurado — necessário porque
    # em rede Docker o Ruby não resolve "localhost" para o container correto.
    ws_uri          = URI(raw_ws_url)
    ws_uri.host     = CHROME_HOST
    ws_uri.port     = CHROME_PORT

    ws_uri.to_s
  end

  # Opções padrão para instanciar Ferrum::Browser.
  # Uso: Ferrum::Browser.new(**FerumConfig.browser_options)
  def self.browser_options
    {
      ws_url:  discover_stealth_ws_url,
      timeout: 30,
      process_timeout: 30,
      headless: true
    }
  rescue => e
    Rails.logger.error "[FerumConfig] Falha ao resolver WS URL do Chrome: #{e.message}"
    # Fallback: deixa o Ferrum tentar conectar diretamente (ambiente dev/test)
    {
      browser_path: ENV.fetch("CHROME_BIN", nil),
      timeout: 30,
      headless: true
    }.compact
  end
end
