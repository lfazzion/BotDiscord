# frozen_string_literal: true

# Tools em app/tools/ são ignorados pelo Zeitwerk (múltiplas classes por arquivo).
# Carregar explicitamente aqui para que estejam disponíveis em runtime.

Rails.application.config.after_initialize do
  tool_dir = Rails.root.join("app/tools")

  # tool_base deve carregar primeiro (base class)
  require tool_dir.join("tool_base.rb").to_s

  Dir[tool_dir.join("*.rb").to_s].sort.each do |f|
    require f unless f.end_with?("tool_base.rb")
  end
end
