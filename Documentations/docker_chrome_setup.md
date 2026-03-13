# Documentação: Docker & Evasão Avançada de Headless Chrome (2026)

Em 2026, simplesmente plugar o `Ferrum` a um container remoto via portas dockerizadas comuns atrairá 100% de detecção de provedores como Cloudflare Turnstile, DataDome, PerimeterX, etc. Os sistemas Anti-Bot atuais não analisam apenas o DOM, analisam assinaturas **TLS (JA3)**, vazamentos WebGL e a **mera presença de bindings do protocolo de desenvolvedor (CDP - Chrome DevTools Protocol)**, especialmente o evento `Runtime.enable`.

A arquitetura abaixa detalha como estruturar os containers isolando o core Ruby dos engines sujos de scraping.

## 🏗️ Estrutura do Docker Compose (O Cofre de Raspagem)

A aplicação usa serviços divididos. O core do Rails NUNCA varre a web sozinho (pois a Net::HTTP expõe fingerprints de bots Ruby gritantes). 

### 1. O "Host Header Bypass" (Sempre Necessário para containers Internos)

Para interagir com bibliotecas Headless puras (sem sidecars) hospedadas em `chromedp/headless-shell`:
Quando você conecta na porta local `9222`, o proxy socat interno do container exige rigorosamente que a origem não seja cross-domain spoof. Se você o chamar via rede interna do docker `http://chrome:9222`, o `Host` chega quebrado e a conexão dá Refused.

```ruby
# Implementação vital para injetar no config/initializers/ferrum.rb
require "ferrum"

def discover_stealth_ws_url(service_alias = "http://chrome:9222")
  uri = URI.parse("#{service_alias}/json/version")
  http = Net::HTTP.new(uri.hostname, uri.port)
  
  req = Net::HTTP::Get.new(uri)
  req["Host"] = "localhost" # 👈 A MÁGICA: Bypassa o filtro do socat
  
  res = http.request(req)
  ws_url = JSON.parse(res.body)["webSocketDebuggerUrl"]
  
  # O Chrome devolve 127.0.0.1 ignorando a rede isolada. Mapeamos de volta:
  ws_url.gsub("127.0.0.1", uri.hostname)
end
```

### 2. Sidecars de Evasão Extrema (Estratégia 2026)

Para SPAs blindadas no nível Enterprise (DataDome), Ferrum puro enviando `Runtime.enable` pela conexão descrita acima **irá falhar e renderizar captchas instransponíveis**. 

Você precisará acoplar sidecars de automação fortificados como serviços no Compose:

1. **Nodriver (Node/Python wrapper):** Uma lib moderna de automação em Python desenhada estritamente para não expor as flags CDP tradicionais para o Chrome. O Rails invoca jobs que despacham comandos para um micro-app python portando Nodriver, salvando a saída HTML/JSON no SQLite via API interna.
2. **Camoufox:** Utilizar uma imagem com o browser Camoufox (um fork do Firefox imune a verificadores estritos que caçam assinaturas do Chromium) em vez do Chromium vanilla.

### 3. Esqueleto do docker-compose.yml (Architecture Base)
```yaml
services:
  app:
    build: .
    volumes: ["./storage:/rails/storage"]
    depends_on: [jobs, proxy_rotator] # App só reage, não raspa diretamente

  jobs:
    build: .
    command: bundle exec rake solid_queue:start
    volumes: ["./storage:/rails/storage"]

  # A Sandbox do ChromeDriver Padrão (Vulnerável em SPAs densas, uso para alvos fracos)
  chrome:
    image: chromedp/headless-shell:stable
    shm_size: '2gb' # Impede crashs de out of memory no kernel em abas simultaneas
    ports: ["9222:9222"]

  # Micro-serviço Python portando Nodriver / curl_cffi para sites com DataDome
  stealth_scraper:
    build: ./scrapers/stealth
    environment:
      - DATABASE_URL=sqlite3:///rails/storage/production.sqlite3
```

> [!CAUTION]
> Ao configurar Ferum para testes básicos via CDP, utilize browser_options supressoras de sinaleiros básicos: `{"disable-blink-features" => "AutomationControlled"}` e injete extensões customizadas (user-agents robustos). Nunca se aproxime das grandes redes sem Fingerprint rotacional TLS.
