# Contexto: app/jobs

Este diretório contém os jobs executados em background pelo Solid Queue.

## Regras Críticas para IA
1. **Assincronicidade e Fila**: O projeto utiliza Solid Queue. Jobs devem ser projetados para rodar de forma assíncrona.
2. **Nomenclatura Padrão**: Sempre utilize o sufixo `Job` (ex: `TwitterCollectJob`).
3. **Idempotência Obrigatória**: Jobs devem ser idempotentes. Use `find_or_initialize_by(platform_post_id)` ou mecanismos similares para evitar duplicações caso um job rode mais de uma vez.
4. **Tratamento de Rate Limits**:
   - Identifique comportamentos como HTTP `RateLimit`, erro `403` ou Captchas.
   - **NUNCA** tente um retry imediato. Cancele/silencie o erro e **agende o job novamente com backoff de 6 a 12 horas**.
5. **Snapshot Dedup Window**: Na coleta de métricas, ignore salvamentos caso a janela de tempo desde a última coleta seja menor que 1 a 2 horas.
