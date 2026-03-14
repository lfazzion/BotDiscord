# Chrome WebSocket Connector
# 
# This script handles the Host header bypass required for Ferrum to connect
# to Chrome running in a Docker container.
#
# See: Requisitos_Projeto_Data_Mining.md:57-60
# See: Documentations/docker_chrome_setup.md

require 'net/http'

module ChromeWSConnector
  CHROME_HOST = ENV.fetch('CHROME_HOST', 'chrome')
  CHROME_PORT = ENV.fetch('CHROME_PORT', '9222').to_i

  def self.fetch_ws_url
    uri = URI("http://#{CHROME_HOST}:#{CHROME_PORT}/json/version")

    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri)
    request["Host"] = "localhost"

    response = http.request(request)
    data = JSON.parse(response.body)

    ws_url = data["webSocketDebuggerUrl"]
    ws_url&.gsub(/127\.0\.0\.1|localhost/, CHROME_HOST)
  end
end
