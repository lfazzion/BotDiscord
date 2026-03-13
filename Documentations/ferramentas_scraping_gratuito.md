# Documentação: Ferramentas de Scraping Gratuito

Para evitar custos iniciais com Apify, utilizaremos ferramentas open-source via CLI e wrappers em Python/Ruby.

## 📺 YouTube: yt-dlp
A ferramenta mais robusta para extrair metadados do YouTube.
- **Instalação:** `apk add yt-dlp` (no Docker).
- **Uso no Rails:** Executar via `Open3` ou `system`.
- **Comando Exemplo (JSON de metadados):**
  ```bash
  yt-dlp --print jsson --skip-download "VIDEO_URL"
  ```

## 📸 Instagram: Instaloader & Instagrapi
- **Instaloader:** Melhor para coleta de metadados públicos e download de posts sem login pesado.
- **Instagrapi:** Biblioteca Python que simula a App oficial. Útil para métricas mais profundas.
- **Estratégia:** Criar um pequeno script Python que o Rails chama via `Open3`.

## 🐦 X (Twitter): snscrape & RapidAPI Free
- **snscrape:** Útil para histórico, embora possa requerer proxys se o volume for alto.
- **RapidAPI:** Usar o Tier Gratuito (ex: "X/Twitter Scraper") para 50-100 requisições/mês como reforço.

## ⚙️ Integração com Rails (O Wrapper)
```ruby
# app/services/free_scraper.rb
class FreeScraper
  def self.youtube_metadata(url)
    stdout, stderr, status = Open3.capture3("yt-dlp", "--dump-json", "--skip-download", url)
    return JSON.parse(stdout) if status.success?
    raise "Erro no yt-dlp: #{stderr}"
  end
end
```

> [!CAUTION]
> Ao usar ferramentas gratuitas/locais, o risco de **Banimento de IP** é real. Use limites agressivos e, se possível, proxys rotativos ou VPN.
