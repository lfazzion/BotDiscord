# BotDiscord — Sistema de Data Mining para Influencers

Este projeto é um sistema completo de coleta de dados, análise de influencers e chatbot com integração ao Discord, construí­do utilizando Ruby on Rails 8 em modo headless.

A motivação inicial é simples: Acompanhar métricas de vários perfis (próprios e de concorrentes) sem perder horas fazendo isso manualmente. O que começou como um script simples evoluiu para um sistema robusto com mais de 25 jobs agendados, scraping automatizado com Chrome headless e um bot de Discord que responde perguntas sobre os dados coletados usando LLMs.

## Arquitetura do Sistema

O projeto segue uma arquitetura modular onde cada responsabilidade está bem isolada. O backend utiliza Rails 8 em modo headless (sem ActionView/Sprockets), servindo apenas API JSON. A escolha pelo Rails foi feita pela produtividade que o framework oferece em termos de ORM, migrations, jobs assíncronos e estrutura de pastas organizada.

Para o banco de dados, utilizei SQLite3 em modo WAL (Write-Ahead Logging). Embora muitos considerem SQLite inadequado para produção, ele funciona muito bem para aplicações de escala média e elimina a necessidade de manter um servidor de banco de dados separado. O modo WAL permite leituras concurrentes enquanto outras conexões escrevem, e o banco é servido via bind mount em Docker para garantir persistência.

A fila de processamento utiliza Solid Queue (implementação de filas em Ruby baseada em SQLite), e o cache utiliza Solid Cache (cache baseado em arquivos ou SQLite). Para aplicações que não precisam de escala massiva, essa combinação elimina dependências externas como Redis.

### Stack Tecnológico

| Componente | Tecnologia |
|------------|------------|
| Framework | Rails 8.1 (headless, sem sprockets/actionview) |
| Banco de Dados | SQLite3 (modo WAL) |
| Fila/Cache | Solid Queue + Solid Cache |
| Bot | discordrb |
| Scraping | Ferrum + Chrome headless + Python (Nodriver/Camoufox) |
| LLM | RubyLLM + OpenRouter / Gemini 3.1 Flash Lite / Gemma 3 27B |
| Docker | docker-compose (app, jobs, chrome) |
| Testes | Minitest |

## Técnicas de Web Scraping

Um dos maiores desafios do projeto é coletar dados de sites que implementam proteções cada vez mais sofisticadas. Em 2016, fazer scraping era trivial — bastava uma requisição HTTP simples com um User-Agent decente. Hoje, metade dos sites retorna "Are you a robot?" e a outra metade renderiza todo o conteúdo em JavaScript do lado do cliente.

### Os Quatro Obstáculos

O sistema enfrenta quatro desafios principais ao fazer scraping na web moderna:

O primeiro obstáculo são as SPAs (Single Page Applications) que renderizam conteúdo exclusivamente no cliente. Não existe HTML no response do servidor — tudo vem via JavaScript. Para isso, utilizo Ferrum, uma biblioteca Ruby que controla o Chrome headless via DevTools Protocol. O Chrome executa o JavaScript e retorna o DOM pronto.

O segundo obstáculo é a detecção de bots. Sites implementam algoritmos que analisam comportamento de navegação, headers, timing entre requisições e padrões de mouse/teclado. A solução envolve randomizar delays, usar proxies residenciais e configurar headers realistas.

O terceiro obstáculo são os CDPs (Customer Data Platforms) de anti-bot como DataDome. Esses serviços usam o Chrome DevTools Protocol para detectar automação. A técnica do "Host Header Bypass" permite enganar essas proteções fingindo que a requisição vem de um domínio diferente.

O quarto obstáculo são sites que mudam sua estrutura HTML diariamente para dificultar parsing. Isso exige pipelines de descoberta que detectam mudanças automaticamente e se adaptam sem intervenção humana.

### Stack de Scraping

O sistema utiliza múltiplas abordagens dependiendo da dificuldade do alvo:

Ferrum com Chrome headless é a abordagem principal para sites com JavaScript. O Chrome roda em um container Docker separado, e o Ruby se conecta via WebSocket. Essa configuração permite escalar horizontalmente adicionando mais containers de Chrome.

Para sites com proteções avançadas, utilizo Python com bibliotecas como Nodriver (selenium webdriver manager) e Camoufox (Firefox headless com configurações de stealth). A integração entre Ruby e Python acontece via jobs assíncronos que passam dados entre os serviços.

## Design de Dados e Regras de Negócio

### Nulo versus Zero

Uma decisão de design crítica foi nunca usar `default: 0` em colunas numéricas que representam métricas sociais (likes, views, followers). Quando uma API bloqueia ou rate-limit acontece, o correto é salvar `nil`, nunca `0`.

A diferença é conceitual importante: zero é um valor válido (o post teve zero likes), enquanto nil significa "não sei" ou "não consegui coletar". Em queries que calculam médias, utilizo `.compact` para ignorar valores nulos e evitar distorções nos resultados.

### Idempotência

Todas as operações de coleta são idempotentes. Isso significa que rodar o mesmo job múltiplas vezes produz o mesmo resultado final. Isso é crucial para jobs que podem falhar por timeout ou rede instável — ao rodar novamente, não criamos duplicatas nem corrompemos dados.

Jobs de scraping verificam existência de registros antes de criar, usando combination de unique keys. Atualizações sempre verificam se houve mudança antes de persistir, evitando writes desnecessários.

## Tool Calling com LLMs

Uma das features mais interessantes é o bot que consulta o banco de dados autonomamente. Utilizando RubyLLM, o sistema configura ferramentas que a LLM pode chamar diretamente:

A LLM recebe um schema do banco de dados e pode executar queries SQL através de tools definidas em YAML. Perguntas como "qual post teve mais engajamento essa semana?" são interpretadas, convertidas em SQL, executadas, e os resultados são formatados em linguagem natural.

Essa abordagem elimina a necessidade de criar endpoints API para cada pergunta possível — a LLM constrói queries dinamicamente baseadas no que o usuário quer saber.

### Prompts Componíveis

Os prompts do sistema são definidos em arquivos YAML em vez de strings hardcoded no código. Isso permite:

Editar prompts sem mexer no código Ruby, versionar prompts via Git, testar diferentes versões de prompts em produção, e construir prompts compostos incluindo outros snippets menores.

O sistema de "Oracle" adiciona contexto que o algoritmo não vê — informações sobre tendências, eventos atuais, e dados históricos que ajudam a LLM a gerar insights mais relevantes.

## Pipeline de Descoberta

Além de coletar dados de perfis conhecidos, o sistema inclui um pipeline de descoberta que minerar perfis autonomamente. Given uma lista de perfis iniciais, ele:

Explora quem esses perfis seguem e quem os segue, identifica padrões de nicho e categorias, sugere novos perfis para monitorar, e detecta quando um perfil começa a crescer rapidamente.

Esse pipeline roda periodicamente e expande a lista de alvos automaticamente, reduzindo trabalho manual de pesquisa.

## Interface via Discord

O Discord serve como interface de administração e consumo do sistema. Ao invés de criar uma dashboard web, utilizei o próprio Discord que a usuário já usa diariamente:

Comandos de slash permitem consultar métricas, digests diários são enviados automaticamente com resumo do desempenho, alertas notificam sobre mudanças significativas, e o bot responde perguntas em linguagem natural sobre os dados.

## Jobs Agendados

O sistema possui mais de 25 jobs agendados que executam periodicamente:

Jobs de coleta rodam em diferentes frequências — alguns a cada hora, outros diariamente ou semanalmente. Jobs de limpeza removem dados antigos ou duplicados. Jobs de análise calculam métricas agregadas e detectam anomalias. Jobs de notificação enviam alerts e digests.

Cada job é independente e pode ser executado manualmente se necessário. A idempotência garante que falhas temporárias não causem problemas.

## Executando o Projeto

### Pré-requisitos

Docker e Docker Compose precisam estar instalados. O projeto utiliza três containers: app (Rails), jobs (workers), e chrome (Chrome headless para scraping).

### Comandos Principais

Iniciar todos os serviços:

```bash
docker-compose -f docker/docker-compose.yml up -d
```

Acessar o console do Rails:

```bash
bin/rails console
```

Executar os workers:

```bash
bin/rails jobs:work
```

Rodar testes:

```bash
bin/rails test
```

Listar rotas disponíveis:

```bash
bin/rails routes
```

## Lições Aprendidas

Durante o desenvolvimento, algumas lições importantes emergiram:

Começar pelo desejo do usuário, não pela arquitetura. O sistema evoluiu naturalmente a partir das necessidades reais, não de um design previa.

SQLite em produção funciona. Com o modo WAL e configuração correta de concorrência, SQLite behaves como um banco de dados moderno com todas as features necessárias.

O custo real do scraping vai além do código. Manter scrapers funcionando requer investimento contínuo em adaptar-se a mudanças nos sites alvos.

O bot como interface é mais natural para usuários não-técnicos. Ao invés de aprender uma nova ferramenta, eles usam algo que já conhecem.

Software nunca está "pronto". O sistema continua evoluindo com novas features e ajustes baseados no uso real.

## Licença

MIT License
