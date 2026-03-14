# syntax=docker/dockerfile:1

# ── Build Stage ──────────────────────────────────────────────────────────────
FROM ruby:3.4-slim AS build

# Dependências bare-metal — sem Node.js/Sprockets (app é Headless Zero HTML)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libsqlite3-dev \
      curl \
      git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /rails

# Instala gems antes de copiar o código (cache layer)
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test && \
    bundle exec bootsnap precompile --gemfile

# Copia o restante da aplicação
COPY . .

# Pre-compila bootsnap para inicialização mais rápida
RUN bundle exec bootsnap precompile app/ lib/

# ── Runtime Stage ─────────────────────────────────────────────────────────────
FROM ruby:3.4-slim AS runtime

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libsqlite3-0 \
      curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /rails

# Copia gems e código compilado do build stage
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Diretório de banco persistido via bind mount em produção
RUN mkdir -p storage

# Não rodar como root
RUN useradd -m -s /bin/bash rails && chown -R rails:rails /rails
USER rails

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
