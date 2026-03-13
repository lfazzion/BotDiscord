# Documentação: Ferramentas de Scraping Integradas (2026)

Em 2026, plataformas sociais possuem escudos behaviorais baseados em IA. A ingenuidade de rodar bibliotecas gratuitas com IPs de datacenter resulta em shadowbans imediatos.

Abaixo estão as especificações rigorosas para usar ferramentas open-source.

## 📺 YouTube: yt-dlp (O Padrão Ouro Resiliente)
O YouTube implementou chaves rotativas de assinaturas em JS ("SABR streaming").
- **Evasão e Dependências:** Você **deve** ter uma runtime JavaScript instalada na máquina do container (Recomenda-se o `Deno` ao invés do Node por ser mais leve). O `yt-dlp` em 2026 precisa invocar JS localmente para decriptar as signatures de vídeos protegidos contra bots.
- **Cookies & Spoofing:** NUNCA bata na API anonimamente em excesso. Extraia cookies reais de uma sessão de navegador via plugin e passe o arquivo para o CLI: `--cookies cookies.txt`.
- **Delays & Proxies:** Incorpore pausas obrigatórias usando `--sleep-interval 5 --sleep-requests 2` para parecer navegação manual, e amarre IPs de web-unlockers: `--proxy "http://user:pass@roaming.proxy.net"`.
- **Uso no Rails (Wrappers Seguros):**
  ```ruby
  # Extração puramente de JSON Metadados sem baixar vídeo
  stdout, stderr, status = Open3.capture3(
    "yt-dlp", "--dump-json", "--skip-download", 
    "--sleep-requests", "3", "--cookies", "storage/yt_cookie.txt", url
  )
  ```

## 📸 Instagram: Instaloader & Restrições (Perigo Alto)
O Instagram bloqueia agresivamente. O uso do `Instaloader` requer malícia técnica:
- **Rate Limitings Customizados:** O Instaloader possui rate-limits passados. Sobrescreva-os localmente exigindo pausas absolutas entre perfis coletados.
- **Sessão Mimetizada (Obrigatório):** Tentar fazer raspagem longa deslogado redirecionará para telas de Log-in infinitas. Você deve usar a flag `--login` via **imports de Cookies de Sessão** (NUNCA faça login via username e senha no script, isso alerta os monitores headless da Meta).
- **Sem Concorrência:** NUNCA abra o app do Instagram no celular da mesma conta de sessão enquanto o scraper estiver rodando na madrugada. Isso lança flags de "Dispositivo Múltiplo Suspeito".

## 🐦 X (Twitter / Alternativas)
Ferramentas não-oficiais como `snscrape` costumam quebrar quinzenalmente.
- O plano A de estabilidade é rotear requests de menções via APIs de agregadores baratos de mercado como RapidAPI em tiers free (50 requisições).
- Como Fallback absoluto, utilizar microserviços em `Nodriver` com redes móveis para varrer a SPA.

> [!CAUTION]
> **A Regra de Ouro do Ban:** Scripts burros tentam novamente quando recebem 403 Forbidden. Scripts inteligentes salvam o erro e dão yield em 12 horas. Insistir no Scraping em caso de bloqueio aniquilará permanentemente a conta Cookie exportada.
