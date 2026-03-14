FROM ruby:3.4-slim

RUN apt-get update -qq && \
    apt-get install -y build-essential libsqlite3-dev nodejs curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
