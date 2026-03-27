# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/services/image_generation_service'

class ImageGenerationServiceTest < ActiveSupport::TestCase
  class MockImage
    attr_reader :url, :base64, :mime_type

    def initialize(url:, base64:, mime_type:)
      @url = url
      @base64 = base64
      @mime_type = mime_type
    end
  end

  test 'generate retorna nil quando desabilitado' do
    ENV['ENABLE_IMAGE_GENERATION'] = nil

    result = ImageGenerationService.generate(prompt: "test")

    assert_nil result
  end

  test 'generate retorna nil quando ENABLE não é true' do
    ENV['ENABLE_IMAGE_GENERATION'] = "false"

    result = ImageGenerationService.generate(prompt: "test")

    assert_nil result
  end

  test 'generate chama RubyLLM.paint quando habilitado' do
    ENV['ENABLE_IMAGE_GENERATION'] = "true"

    img = MockImage.new(url: "http://example.com/img.png", base64: "abc123", mime_type: "image/png")
    RubyLLM.stubs(:paint).returns(img)

    result = ImageGenerationService.generate(prompt: "A sunset")

    assert_equal "http://example.com/img.png", result[:url]
    assert_equal "abc123", result[:base64]
    assert_equal "image/png", result[:mime_type]

    ENV['ENABLE_IMAGE_GENERATION'] = nil
  end

  test 'generate passa size customizado' do
    ENV['ENABLE_IMAGE_GENERATION'] = "true"

    img = MockImage.new(url: "http://example.com/img.png", base64: "abc", mime_type: "image/jpeg")
    RubyLLM.expects(:paint).with("A cat", model: "imagen-3.0-generate-002", size: "512x512").returns(img)

    result = ImageGenerationService.generate(prompt: "A cat", size: "512x512")

    assert_equal "http://example.com/img.png", result[:url]

    ENV['ENABLE_IMAGE_GENERATION'] = nil
  end

  test 'generate loga e re-raise em caso de erro' do
    ENV['ENABLE_IMAGE_GENERATION'] = "true"

    RubyLLM.stubs(:paint).raises(StandardError.new("API error"))

    assert_raises StandardError do
      ImageGenerationService.generate(prompt: "A dog")
    end

    ENV['ENABLE_IMAGE_GENERATION'] = nil
  end
end
