# Documentação: Rails 8.1 - Solid Queue & Solid Cache

## 🌍 Visão Geral
O Rails 8.1 promove uma arquitetura "database-backed", eliminando a necessidade de Redis para a maioria das aplicações. Isso é feito através do **Solid Queue** (jobs) e **Solid Cache** (cache).

## 📥 Solid Queue
Substituto do Sidekiq/Resque que utiliza o banco de dados como backend.
- **Vantagem:** Sem dependências externas. Transacional (o job só é criado se a transaction do banco commitar).
- **Configuração no Rails 8:** Já vem por padrão em novos apps.
- **Comando para iniciar:** `bundle exec rake solid_queue:start`.
- **Destaque:** Suporta `concurrency_controls` e `scheduled_jobs`. No SQLite, funciona melhor em apps de médio porte.

## 💾 Solid Cache
Utiliza o banco de dados para armazenar o cache do ActiveSupport.
- **Vantagem:** Cache muito maior (limitado pelo disco, não pela RAM).
- **Estratégia:** Utiliza FIFO (First-In, First-Out) para expiração.
- **Performance:** Levemente mais lento que Redis em RAM, mas ideal para dados que não caberiam na memória.

## 🛠️ Configuração Recomendada (SQLite Sharding)
Para evitar contenção e garantir performance "zero-latency", use bancos de dados separados.

### 1. `config/database.yml`
```yaml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
  queue:
    adapter: sqlite3
    database: storage/production_queue.sqlite3
    migrations_paths: db/queue_migrate
  cache:
    adapter: sqlite3
    database: storage/production_cache.sqlite3
    migrations_paths: db/cache_migrate
```

### 2. Comandos de Inicialização
Para garantir que as tabelas de suporte existam nos bancos separados:
```bash
# Instala as migrações nos caminhos específicos
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install

# Roda as migrações (o Rails 8 detecta os caminhos definidos no database.yml)
bin/rails db:prepare
```

### 3. Configurar Background Job
No `config/environments/production.rb`:
```ruby
config.active_job.queue_adapter = :solid_queue
config.cache_store = :solid_cache_store
```

> [!TIP]
> O uso de `migrations_paths` no SQLite é o segredo para manter os esquemas de jobs e cache isolados do seu schema principal.
