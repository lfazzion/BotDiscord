#!/usr/bin/env ruby
# frozen_string_literal: true

# Prova da correção do Reddit: instrumentação + UA override.
# Uso: dentro do container de teste:
#   rails runner test/scripts/prova_reddit.rb
#
# Saída esperada com sucesso:
#   PROVA_STATUS=success PROVA_COUNT=N (> 0)
#   + linhas [Fetcher::BrowserSession:diag] mostrando a instrumentação

require_relative "../../config/environment"

Rails.logger.level = Logger::INFO

resultado = PlatformSearchTool.new.execute(platform: "reddit", query: "brasil", limit: 5)

puts "PROVA_STATUS=#{resultado[:status]}"
puts "PROVA_COUNT=#{resultado.dig(:data, :count) || 0}"
puts "PROVA_PLATFORM=#{resultado.dig(:data, :platform)}"

if resultado[:status] == :success
  resultados = resultado.dig(:data, :results) || []
  resultados.each_with_index do |item, i|
    puts "  [#{i + 1}] #{item['title']} | #{item['url']} | score=#{item['score']}"
  end
  puts "VEREDITO=OK"
else
  razao = resultado[:reason] || resultado.dig(:data, :error)
  puts "PROVA_ERRO=#{razao}"
  puts "VEREDITO=FALHA"
  exit 1
end
