# Contexto: docker/

Esta pasta contém toda a infraestrutura de containers do projeto.

## Arquivos

| Arquivo | Descrição |
|---|---|
| `Dockerfile` | Build multi-stage da imagem Rails (build + runtime) |
| `docker-compose.yml` | Orquestração dos 3 serviços: `app`, `jobs`, `chrome` |

---

## Como Usar

**Rodar a partir da raiz do projeto (obrigatório):**

```bash
# Subir todos os serviços
docker-compose -f docker/docker-compose.yml up -d

# Ver logs
docker-compose -f docker/docker-compose.yml logs -f

# Parar
docker-compose -f docker/docker-compose.yml down
```

---

## Arquitetura dos Serviços

```
┌─────────────┐    ┌─────────────┐    ┌──────────────────────────┐
│     app     │    │    jobs     │    │          chrome          │
│  Puma :3000 │    │ Solid Queue │    │ headless-shell:stable    │
│             │    │             │    │ :9222 (WebSocket CDP)    │
└──────┬──────┘    └──────┬──────┘    └────────────┬─────────────┘
       │                  │                        │
       └──────────────────┴──────── network:internal ──────────────┘
                          │
                   ../storage/ (bind mount)
                   └── production.sqlite3 (único arquivo, 3 conexões)
```

---

## Regras Críticas para IA

### 1. Paths são relativos à raiz do projeto
- O `docker-compose.yml` usa `context: ..` para apontar para a raiz.
- O `dockerfile: docker/Dockerfile` é relativo ao context (a raiz).
- Volumes usam `../storage` (relativo ao arquivo compose em `docker/`).
- **SEMPRE rodar docker-compose a partir da raiz** com `-f docker/docker-compose.yml`.

### 2. Chrome e Host Header Bypass
- O container `chrome` expõe o CDP na porta `9222` dentro da rede `internal`.
- O `FerumConfig` em `config/initializers/ferrum.rb` injeta `Host: localhost` no GET `/json/version` para contornar a rejeição do Chrome 120+ ao header de origin.
- A variável `CHROME_HOST=chrome` é passada pelo compose e consumida pelo initializer.

### 3. Shared Memory do Chrome
- `shm_size: '2gb'` é **obrigatório** no serviço `chrome`.
- Sem ele, o Chrome 120+ em modo headless vaza memória durante renderização pesada (Ferrum/CDP).

### 4. SQLite e Bind Mount
- O diretório `storage/` na raiz é montado em `/rails/storage` tanto no `app` quanto no `jobs`.
- **Único arquivo SQLite** (`production.sqlite3`) com 3 conexões separadas (primary, queue, cache).
- Migrations de queue em `db/queue_migrate/`, cache em `db/cache_migrate/`.
- App container roda migrations automaticamente via `bin/entrypoint` na inicialização.
- **NUNCA** usar Docker volume nomeado para os bancos — use bind mount para garantir acesso direto.

### 5. Entrypoints
- `bin/entrypoint` (app): Roda migrations → inicia Puma
- `bin/entrypoint-jobs` (jobs): Inicia Solid Queue supervisor via `bin/jobs start`
- Não use comando `supervisor` diretamente — use `bin/jobs start`

### 6. Imagem
- Base: `ruby:3.4-slim`
- Sem Node.js (projeto Headless Zero HTML — nada de Sprockets/ActionView).
- Build stage tem `build-essential` + `libsqlite3-dev`; runtime stage tem apenas `libsqlite3-0`.
