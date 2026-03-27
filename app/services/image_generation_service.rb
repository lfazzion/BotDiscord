# frozen_string_literal: true

class ImageGenerationService
  def self.generate(prompt:, size: "1024x1024")
    return nil if ENV["ENABLE_IMAGE_GENERATION"] != "true"

    Rails.logger.info "[ImageGenerationService] Gerando imagem com prompt: #{prompt[0..50]}..."

    image = RubyLLM.paint(prompt, model: "imagen-3.0-generate-002", size: size)

    {
      url: image.url,
      base64: image.base64,
      mime_type: image.mime_type
    }
  rescue StandardError => e
    Rails.logger.error "[ImageGenerationService] Erro ao gerar imagem: #{e.message}"
    raise
  end
end
