# Documentação: SQLite 3 em Produção (WAL Mode)

## ⚡ Por que SQLite no Rails 8?
No Rails 8, o SQLite é considerado um cidadão de primeira classe para produção em servidores únicos.

## 🚀 WAL (Write-Ahead Logging)
O modo WAL permite que múltiplos leitores e um escritor operem simultaneamente sem se bloquearem.
- **Ativação:** O Rails 7+ já ativa por padrão em novos projetos.
- **Configuração Manual:** `PRAGMA journal_mode=WAL;`.
- **Arquivos Gerados:** Verá arquivos `-wal` e `-shm` na pasta `storage/`. **Não os delete.**

## 🔧 Otimizações Críticas
1.  **Busy Timeout:** Aumentar o tempo de espera antes de dar erro de "Database is locked".
    ```ruby
    # config/database.yml
    production:
      adapter: sqlite3
      database: storage/production.sqlite3
      timeout: 5000 # 5 segundos
    ```
2.  **Synchronous = Normal:** Melhora performance de escrita reduzindo chamadas `fsync` caras.
    ```sql
    PRAGMA synchronous = NORMAL;
    ```
3.  **STRICT Tables:** O SQLite 3.37+ suporta tabelas com tipos rígidos, o que o aproxima do comportamento do Postgres.

## 📦 Backups com Litestream
Para produção real, use o **Litestream**. Ele faz streaming das mudanças do arquivo WAL diretamente para um bucket S3 (AWS, Cloudflare R2, etc).

> [!IMPORTANT]
> O SQLite em produção é ideal para **single-node**. Se precisar escalar horizontalmente (múltiplos servidores de app), mude para Postgres.
