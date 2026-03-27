# frozen_string_literal: true

require 'test_helper'

class HealthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @routes = Rails.application.routes
  end

  teardown do
    Mocha::Mockery.instance.teardown
  end

  test 'retorna 200 quando DB está ok' do
    mock_conn = mock('connection_ok')
    mock_conn.stubs(:execute).returns([])
    ActiveRecord::Base.stubs(:connection).returns(mock_conn)

    get '/health'

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
    assert_equal "ok", json["db"]
  end

  test 'retorna 503 quando DB falha' do
    mock_conn = mock('connection_error')
    mock_conn.stubs(:execute).raises(StandardError.new("DB down"))
    ActiveRecord::Base.stubs(:connection).returns(mock_conn)

    get '/health'

    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_equal "error", json["status"]
    assert_equal "error", json["db"]
  end
end
