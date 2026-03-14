# Contexto: app/services

Este diretório contém a lógica de negócios e orquestração do BotDiscord.

## Regras Críticas para IA
1. **Localização Exclusiva de Lógica**: A lógica de domínio e negócios **DEVE** residir aqui em `app/services/`. NUNCA coloque lógicas complexas em Controllers ou Models.
2. **Nomenclatura Padrão**: Sempre utilize o sufixo `Service` para classes neste diretório (ex: `InfluencerProfileService`).
3. **Padrão de Criação**: Os serviços devem servir como orquestradores que utilizam models e outros serviços subjacentes para completar um fluxo de trabalho (ex: `TwitterCollectJob` chamaria um `TwitterCollectService`).
