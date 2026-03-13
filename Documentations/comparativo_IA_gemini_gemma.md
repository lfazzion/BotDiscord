# Comparativo Técnico: Gemini 3.1 Flash Lite vs. Gemma 3 27B

Para o projeto de Data Mining, a escolha do LLM deve equilibrar capacidade de processamento (Tokens) e frequência de uso (Requisições).

## 📊 Tabela de Limites Reais (Google AI Studio)

| Característica | Gemini 3.1 Flash Lite | Gemma 3 27B |
| :--- | :--- | :--- |
| **RPM** (Requests/Min) | 15 | **30** |
| **TPM** (Tokens/Min) | **250.000** | 15.000 |
| **RPD** (Requests/Day) | 500 | **14.400** |
| **Context Window** | 1.000.000 tokens | 128.000 tokens |

## 🎯 Estratégia Híbrida: O Melhor dos Dois Mundos

Decidimos não escolher apenas um, mas utilizar ambos de forma inteligente para maximizar o Tier Gratuito.

### 1. Gemini 3.1 Flash Lite: O Minerador de Profundidade
Utilizado para tarefas que exigem "luz forte" sobre muitos dados simultâneos.
- **Uso:** Processamento de Lotes (Batch Mining) de 50+ posts.
- **Vantagem:** Com 250K TPM, ele "engole" o histórico da semana em segundos.
- **Gestão:** Limitado a 500 chamadas/dia, por isso deve ser usado apenas por Jobs agendados (Solid Queue).

### 2. Gemma 3 27B: O Atendente de Chat e Fallback
Utilizado para tarefas de "alta frequência" e resposta rápida.
- **Uso:** Interação direta no Discord (Chatbot) e classificação individual de posts novos.
- **Vantagem:** Com 14.4K RPD, o bot nunca ficará "mudo" por falta de cota diária.
- **Fallback:** Caso o Gemini esgote as 500 requisições diárias, o sistema redireciona tarefas críticas para o Gemma (mesmo que leve mais tempo devido ao TPM menor).

## 🛠️ Próximos Passos
- Implementar um `AiRouter` no Rails para decidir qual modelo usar baseado na tarefa.
- Configurar o Gemma 3 27B no `GemmaClient` com foco no chatbot.

> [!TIP]
> Essa arquitetura garante que o sistema seja **resiliente**: inteligente para minerar (Gemini) e infatigável para conversar (Gemma).
