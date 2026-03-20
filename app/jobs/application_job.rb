# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # ── Rate-Limit / Anti-Scraping: Silent Rescue ───────────────────────────────
  #
  # Quando um scraper detectar bloqueio (DataDome, 403, 429, Captcha),
  # deve levantar `ScrapingServices::RateLimitError`.
  #
  # A reschedule é feita com backoff de 6 horas para evitar re-tentativas em
  # loop que esgotariam o pool de proxies.
  # `retry_job` é usado (não `raise`) para não queimar a fila do Solid Queue.
  rescue_from 'ScrapingServices::RateLimitError' do |exception|
    retry_after = if exception.respond_to?(:retry_after)
                    exception.retry_after
                  else
                    6.hours
                  end

    Rails.logger.warn "[#{self.class.name}] Rate-limit detectado: #{exception.message}. " \
                      "Reagendando para +#{(retry_after / 3600).round}h."
    retry_job wait: retry_after
  end

  # ── Erros Transitórios Genéricos ────────────────────────────────────────────
  # Retry padrão do Active Job (exponential backoff) para erros não de rate-limit.
  # Desabilitado por padrão — subclasses podem habilitar seletivamente.
  # discard_on ActiveJob::DeserializationError
end
