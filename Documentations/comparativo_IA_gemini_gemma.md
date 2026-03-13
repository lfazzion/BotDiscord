# Comparativo Técnico & Limites de API (Google AI Studio - 2026)

Com base nas restrições reais da API extraídas do painel de limites atuais da plataforma, a arquitetura deve ser desenhada milimetricamente para respeitar os gargalos críticos cruzados de TPM (Tokens per Minute), RPM (Requests per Minute) e RPD (Requests per Day).

## 📊 Tabela de Limites Estritos (Google AI Studio)

| Característica | Gemini 3.1 Flash Lite | Gemma 3 27B |
| :--- | :--- | :--- |
| **RPM** (Requests/Minuto)| **15 RPM** | **30 RPM** |
| **TPM** (Tokens/Minuto) | **250.000 TPM** | **15.000 TPM** |
| **RPD** (Requests/Dia) | **500 RPD** | **14.400 RPD** |
| **Ponto Forte** | Alta capacidade de Ingestão de Tokens por minuto/minutos isolados | Alto volume diário de chamadas e respostas rápidas |
| **Gargalo Principal** | RPD baixo (acaba rápido se usado em um chat ativo) | TPM muito reduzido (estoura se houver 1 arquivo grande ou histórico longo) |

## 🎯 Estratégia Híbrida Direcionada aos Limites

A estratégia Multi-Model agora não é apenas uma escolha de precisão, mas de **sobrevivência aos Rate Limits do Tier Gratuito/Padrão**:

### 1. Gemini 3.1 Flash Lite: O Minerador de Lotes (Batching)
Apesar da janela teórica gigantesca, estamos limitados a **250K TPM** e estrangulados em **500 RPD**.
- **Uso Estrito:** Deve ser acionado **exclusivamente pelos Background Jobs (Solid Queue)** para limpar HTML cru ou processar matrizes de dados da raspagem do web scraping.
- **Atenção (Batching):** Como temos apenas 500 requests por dia e 15 por minuto, NÃO pode processar os dados um a um. Os jobs devem agrupar (batching) o máximo de metadados raspados até somarem próximo a `200.000` tokens, enviar em um único request pesado para classificação/análise e dormir um minuto para limpar a janela de cota de TPM.

### 2. Gemma 3 27B: O Cérebro Conversacional
Possui incríveis **14.400 RPD** (permitindo conversas ilimitadas na prática) e **30 RPM**, mas sofre em um limite severo de **15.000 TPM**.
- **Uso Crítico:** É o motor exclusivo do Chatbot no Discord. Pode ser chamado o dia inteiro.
- **Implementação (Tool Calling Enxuto):** O limite de 15K TPM significa que os JSONs passados nas ferramentas de banco de dados (Tool Calling) devem ser rigorosamente filtrados. Retorne apenas as 5-10 linhas mais cruciais das tabelas para evitar estourar o limite de Tokens por Minuto se a influencer fizer múltiplas perguntas seguidas.
