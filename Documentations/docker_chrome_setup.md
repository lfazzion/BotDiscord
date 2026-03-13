# Documentação: Docker & Headless Chrome Bypass

## 🏗️ Estrutura do Docker Compose
A arquitetura sugerida utiliza 4 serviços principais num único `docker-compose.yml`.

## 📦 Dockerfile (Ruby 3.4/Alpine)
Recomendado usar multi-stage builds para reduzir o tamanho da imagem.
- **Base:** `ruby:3.4-alpine` ou `ruby:3.4-slim`.
- **Dependências:** `build-base`, `sqlite-dev`, `gcompat`, `curl`.

## 🌐 Chrome Headless (Bypass & Connection)
No Docker, o Ruby precisa se conectar ao WebSocket do Chrome.

### Implementação da Ferrum
```ruby
# config/initializers/ferrum.rb
require "ferrum"

# Helper para descobrir a URL do WebSocket (Bypass Host Header)
def discover_chrome_ws(url = "http://chrome:9222")
  uri = URI.parse("#{url}/json/version")
  http = Net::HTTP.new(uri.hostname, uri.port)
  request = Net::HTTP::Get.new(uri)
  request["Host"] = "localhost" # 👈 ESSENCIAL
  
  response = http.request(request)
  ws_url = JSON.parse(response.body)["webSocketDebuggerUrl"]
  
  # Troca 127.0.0.1 pelo nome do serviço no docker
  ws_url.gsub("127.0.0.1", uri.hostname)
end

# Uso no Scraper
browser = Ferrum::Browser.new(
  url: discover_chrome_ws,
  browser_options: { "no-sandbox": nil, "disable-setuid-sandbox": nil },
  timeout: 30
)
```

## 🛠️ docker-compose.yml (Skeleton)
```yaml
services:
  app:
    build: .
    volumes: ["./storage:/rails/storage"]
    depends_on: [chrome]
  
  chrome:
    image: chromedp/headless-shell:stable
    shm_size: '1gb'
    ports: ["9222:9222"]

  jobs:
    build: .
    command: bundle exec rake solid_queue:start
    volumes: ["./storage:/rails/storage"]
```

> [!WARNING]
> Sem o bypass do Host Header, o Ruby receberá `Connection Refused` ao tentar falar com o container do Chrome via rede interna do Docker.
