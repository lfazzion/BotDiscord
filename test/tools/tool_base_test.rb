# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/tools/tool_base'

class ToolBaseTest < ActiveSupport::TestCase
  class DummyTool < ToolBase
    description 'Tool de teste'

    def run(value: nil)
      success({ value: value })
    end
  end

  test 'clamp limita valor ao mínimo' do
    tool = DummyTool.new
    result = tool.send(:clamp, 0, 1, 50)
    assert_equal 1, result
  end

  test 'clamp limita valor ao máximo' do
    tool = DummyTool.new
    result = tool.send(:clamp, 100, 1, 50)
    assert_equal 50, result
  end

  test 'clamp mantém valor dentro do range' do
    tool = DummyTool.new
    result = tool.send(:clamp, 25, 1, 50)
    assert_equal 25, result
  end

  test 'clamp converte nil para 0 e limita ao mínimo' do
    tool = DummyTool.new
    result = tool.send(:clamp, nil, 1, 50)
    assert_equal 1, result
  end

  test 'success retorna hash com status success' do
    tool = DummyTool.new
    result = tool.send(:success, { foo: 'bar' })
    assert_equal :success, result[:status]
    assert_equal({ foo: 'bar' }, result[:data])
  end

  test 'error retorna hash com status error' do
    tool = DummyTool.new
    result = tool.send(:error, 'falhou')
    assert_equal :error, result[:status]
    assert_equal 'falhou', result[:reason]
  end

  test 'logging é chamado ao executar tool' do
    tool = DummyTool.new
    Rails.logger.expects(:info).at_least_once
    tool.execute(value: 'test')
  end
end
