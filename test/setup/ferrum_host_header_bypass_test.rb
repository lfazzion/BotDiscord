require "test_helper"
require "webmock"

class FerrumHostHeaderBypassTest < ActiveSupport::TestCase
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

  test "ferrum initializer should exist" do
    assert File.exist?(Rails.root.join("config", "initializers", "ferrum.rb"))
  end

  test "FerumConfig module should be defined" do
    assert defined?(FerumConfig)
  end

  test "FerumConfig should use CHROME_HOST from env" do
    assert_equal @chrome_host, FerumConfig::CHROME_HOST
    assert_equal @chrome_port, FerumConfig::CHROME_PORT
  end

  test "discover_stealth_ws_url should inject Host: localhost header" do
    mock_response = {
      "webSocketDebuggerUrl" => "ws://127.0.0.1:9222/devtools/browser/abc123"
    }.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    ws_url = FerumConfig.discover_stealth_ws_url

    assert_includes ws_url, "ws://"
    assert_includes ws_url, "/devtools/browser/"
    assert_includes ws_url, "chrome"
  end

  test "discover_stealth_ws_url should replace localhost with CHROME_HOST" do
    mock_response = {
      "webSocketDebuggerUrl" => "ws://localhost:9222/devtools/browser/abc123"
    }.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    ws_url = FerumConfig.discover_stealth_ws_url

    assert_includes ws_url, "ws://chrome"
    assert_not_includes ws_url, "localhost"
  end

  test "discover_stealth_ws_url should raise on non-200 response" do
    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 503)

    assert_raises(RuntimeError) { FerumConfig.discover_stealth_ws_url }
  end

  test "discover_stealth_ws_url should raise when no WS URL in response" do
    mock_response = {}.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    assert_raises(RuntimeError) { FerumConfig.discover_stealth_ws_url }
  end

  test "browser_options should include stealth ws_url and headless" do
    mock_response = {
      "webSocketDebuggerUrl" => "ws://127.0.0.1:9222/devtools/browser/abc123"
    }.to_json

    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    options = FerumConfig.browser_options

    assert options.key?(:ws_url)
    assert_equal true, options[:headless]
    assert options[:timeout] > 0
  end

  test "browser_options fallback should work when Chrome unavailable" do
    stub_request(:get, "http://#{@chrome_host}:#{@chrome_port}/json/version")
      .with(headers: { "Host" => "localhost" })
      .to_timeout

    options = FerumConfig.browser_options

    assert_kind_of Hash, options
    assert_equal true, options[:headless]
  end
end
