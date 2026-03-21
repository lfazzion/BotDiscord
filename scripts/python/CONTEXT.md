# Contexto: scripts/python

Scripts Python para scraping alternativo quando Ferrum/Chrome falha ou é bloqueado.

## Scripts Existentes

| Script | Engine | Uso |
|--------|--------|-----|
| `nodriver_twitter.py` | nodriver | Scraping de Twitter/X |
| `nodriver_instagram.py` | nodriver | Scraping de Instagram |
| `camoufox_scrape.py` | camoufox | Scraping com fingerprint realista |
| `curl_impersonate.py` | curl-impersonate | Requisições HTTP com fingerprint de browser |

## Regras Críticas para IA

1. **Execução via Ruby bridge**: Nunca chamar `python` diretamente. Usar `PythonBridge::NodriverRunner` ou `PythonBridge::CamoufoxService` em `lib/scraping/python_bridge/`
2. **Saída JSON**: Todo script deve retornar JSON no stdout (parseável pelo Ruby)
3. **Erros em stderr**: Logs de erro vão para stderr, nunca misturar com JSON de saída
4. **Variáveis de ambiente**: URLs e configs vêm via env vars (não hardcoded)
5. **Requirements**: `requirements.txt` na raiz do projeto. Instalar com `pip install -r requirements.txt` no container Python
 6. **Timeout**: Scripts devem ter timeout implícito (o Ruby bridge mata o processo após timeout)

## Cross-References

- Scraping: `lib/scraping/CONTEXT.md` — Ruby bridge que executa estes scripts
- Docker: `docker/CONTEXT.md` — `Dockerfile.python` que instala as dependências
