# Documentação: Rails 8.1 - O Ecossistema Solid e Otimizações

## 🌍 Visão Geral da Mudança de Paradigma
A fundação de todo o projeto descansa na filosofia Omakase do Rails 8 ("The One Person Framework"). Rejeitamos Redis e instâncias ativas externas. O backend é 100% suportado por RDMBS (`SQLite`).

Através das joias da coroa (Solid Queue, Solid Cache e Solid Cable), a infraestrutura cai para literalmente 1 container dinâmico de App e o Host de Arquivos.

## 📦 Solid Cache (Persistência em Disco)
O ActiveSupport Cache não morará na RAM, residirá no SQLite.
- **Vantagem em 2026:** Discos NVMe em VPS baratas possuem velocidades de leitura absurdas, eclipsando a necessidade estrita de Redis para projetos que não são de ultra-alta-frequência.
- O cache será utilizado para salvar o `SNAPSHOT_DEDUP_WINDOW` de métricas de Influencers por horas, salvando requests ao Scraper.

## 🗄️ Solid Queue (Background Jobs no SQLite)

O Solid Queue abraça o motor relacional. Porém, o SQLite embute limitações de paralelismo extremo.
- **O Problema de 2026 (Concurrency Locks):** Quando vários workers Solid Queue tentam inserir logs de scrapes simultâneos no mesmo arquivo de fila, você invariavelmente atingirá avisos de exceção `SQLite3::BusyException: database is locked`. Rails 8 traz um retry adapter interno, mas precisamos de blindagem arquitetônica extra.
- **A Solução "Database Sharding":** É OBRIGATÓRIO isolar fisicamente o arquivo do banco de dados da Queue e do Cache para caminhos absolutos distintos do seu banco principal de Profiles do Bot limitando o travamento do Kernel.

### Setup Mandatório (Sharding SQLite) no `database.yml`

```yaml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
  # A fila Solid Queue Roda em um arquivo SQLite separado!
  queue:
    adapter: sqlite3
    database: storage/production_queue.sqlite3
    migrations_paths: db/queue_migrate
  # O Cache também mora fora do banco matriz
  cache:
    adapter: sqlite3
    database: storage/production_cache.sqlite3
    migrations_paths: db/cache_migrate
```

### Acoplamento Específico

Nos environments de config (`config/environments/production.rb`), mapear explicitamente a segregação de banco para o Solid Queue:

```ruby
config.solid_queue.connects_to = { database: { writing: :queue } }
config.active_job.queue_adapter = :solid_queue
config.solid_cache.connects_to = { database: { writing: :cache } }
config.cache_store = :solid_cache_store
```

> [!WARNING]
> Sem essa separação nos initializers, o seu banco produtivo transacional `primary` tentará disputar os headers WAL com os Inserts temporários pesados dos background workers no mesmo microsegundo, colapsando a base de dados. Menos é mais, mas arquivos DB isolados são essenciais.
