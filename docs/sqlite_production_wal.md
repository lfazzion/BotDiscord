# Documentação: SQLite 3 em Produção (A Renascença)

O Rails 8 elevou o SQLite de um ambiente sandbox para um banco de dados de produção extremamente competente para workloads Single-Node de baixo a médio Write.

## 🚀 WAL e Otimizações de Concorrência

Não faça deploy em produção sem assegurar os Pragmas corretos. O Rails 8 injeta pragmas de inicialização automáticos localizados no hash do `database.yml`, removendo a necessidade de gambiarras manuais no boot:

```yaml
production:
  adapter: sqlite3
  database: storage/production.sqlite3
  pool: 5
  timeout: 5000 # Critical: Permite que operações aguardem 5s antes de erro de Lock.
  pragmas:
    journal_mode: wal # Leitores não bloqueiam escritores.
    synchronous: normal # Sem chamadas excessivas ao OS filesystem.
    mmap_size: 134217728 # ~128MB de RAM alocada para mapeamento estático e caching velozes.
    cache_size: 10000 
```

**ALERTA:** Ao interagir via terminal Rails C ou visualizar os arquivos, você notará os adjacentes `-wal` e `-shm`. A exclusão manual desses logs residuais corrompe irredutivelmente o banco principal recém formatado.

## 🛡️ Disaster Recovery em Tempo Real (2026): O Padrão Litestream

Cópias manuais (Cronjobs varrendo `cp storage/base.db`) geram pontos mortos de backup. Para o bot Discord, adote o **Litestream**.

### Como o Litestream resolve o SQLite Cloud
Apesar da grande atualização de 2025 focar minimização de espaço e recuperação acelerada via Leases (evitando empilhamento em nós temporários), o conceito central é atemporal: O serviço roda em paralelo no Host escutando ativamente as transições WAL.
Acordos de Restore caem para poucos "segundos" de gap de tempo. Toda inserção, deleção de métrica e novo post mineirado ecoa instantaneamente via socket de cópia para buckets S3 (Cloudflare R2, ou Amazon).

### Implementação Simplificada
A gema `litestream_rails` abraça essa arquitetura nativamente, enxertando no `Procfile` de boot o processo background contínuo e habilitando web-dashboards segurados por senhas para análise da saúde da replicação de blocos em produções enxutas nativamente no Rails 8.

> [!TIP]
> **O Gatilho da Escalabilidade:** Sua base de conhecimento permanecerá no SQLite blindado com Litestream indefinidamente enquanto possuir infraestrutura **Single-Node** rodando no mesmo hardware/container de disco persistente. 
> Se por acréscimos volumosos este Bot for expandido para múltiplos servidores de backend paralelos lidando com as coletas da rede social na Web, abandone o SQLite e refatore imediatamente para pools de Postgres.
