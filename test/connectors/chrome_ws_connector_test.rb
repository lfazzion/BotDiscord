require "test_helper"
require "webmock"
require_relative "../../lib/chrome_ws_connector"

class ChromeWSConnectorTest < ActiveSupport::TestCase
  setup do
    @chrome_host = "chrome"
    @chrome_port = 9222
    ENV["CHROME_HOST"] = @chrome_host
    ENV["CHROME_PORT"] = @chrome_port.to_s
  end

  teardown do
    ENV.delete("CHROME_HOST")
    ENV.delete("CHROME_PORT")
  end

  test "should fetch WebSocket URL successfully" do
    mock_response = {
      "webSocketDebuggerUrl" => "ws://127.0.0.1:9222/devtools/browser/abc123"
    }.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    ws_url = ChromeWSConnector.fetch_ws_url

    assert_includes ws_url, "ws://"
    assert_includes ws_url, "/devtools/browser/"
  end

  test "should replace localhost with chrome host" do
    mock_response = {
      "webSocketDebuggerUrl" => "ws://localhost:9222/devtools/browser/abc123"
    }.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    ws_url = ChromeWSConnector.fetch_ws_url

    assert_includes ws_url, "ws://chrome"
    assert_not_includes ws_url, "localhost"
  end

  test "should replace 127.0.0.1 with chrome host" do
    mock_response = {
      "webSocketDebuggerUrl" => "ws://127.0.0.1:9222/devtools/browser/abc123"
    }.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    ws_url = ChromeWSConnector.fetch_ws_url

    assert_includes ws_url, "ws://chrome"
    assert_not_includes ws_url, "127.0.0.1"
  end

  test "should use default env values when not set" do
    ENV.delete("CHROME_HOST")
    ENV.delete("CHROME_PORT")

    assert_equal "chrome", ChromeWSConnector.chrome_host
    assert_equal 9222, ChromeWSConnector.chrome_port
  end

  test "should raise error when response is not 200" do
    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 503, body: "Service Unavailable")

    assert_raises(ChromeWSConnector::Error) do
      ChromeWSConnector.fetch_ws_url
    end
  end

  test "should raise error when no WebSocket URL in response" do
    mock_response = {}.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    assert_raises(ChromeWSConnector::Error) do
      ChromeWSConnector.fetch_ws_url
    end
  end

  test "replace_host should correctly replace localhost" do
    url = "ws://localhost:9222/devtools/browser/abc"
    result = ChromeWSConnector.replace_host(url)

    assert_equal "ws://chrome:9222/devtools/browser/abc", result
  end

  test "replace_host should correctly replace 127.0.0.1" do
    url = "ws://127.0.0.1:9222/devtools/browser/abc"
    result = ChromeWSConnector.replace_host(url)

    assert_equal "ws://chrome:9222/devtools/browser/abc", result
  end
end
