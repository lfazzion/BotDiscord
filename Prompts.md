# Workflow: Spec-Driven Development (SDD)

## 💡 Princípios Fundamentais
1. **Gestão de Contexto:** Use o comando `/clear` entre as etapas para evitar que informações inúteis "sujem" a memória do modelo.
2. **Qualidade de Input:** IAs são um multiplicador. Se você der informações ruins, receberá código ruim.
3. **Não Reinventar a Roda:** Sempre pesquise por padrões e documentações externas antes de codar.

---

## 🔄 O Fluxo de Trabalho (3 Etapas)

### 1. Pesquisa e PRD (Product Requirements Document)
O objetivo é coletar todo o contexto necessário (arquivos locais, documentação externa e padrões de implementação).

**O que fazer:**
- Peça a IA para analisar a base de código.
- Solicite a leitura de documentações externas (via MCP ou busca).
- Identifique arquivos que serão afetados.

**Exemplo de Prompt para Pesquisa:**
> "Precisamos implementar [DESCREVA A FUNCIONALIDADE]. Antes de codar, faça uma pesquisa completa:
> 1. Analise nossa base de código e identifique todos os arquivos que serão afetados ou que servem de referência.
> 2. Busque padrões de implementação similares que já usamos para mantermos a consistência.
> 3. Pesquise na internet a documentação oficial de [BIBLIOTECA/TECNOLOGIA] e busque exemplos de melhores práticas no Stack Overflow ou GitHub.
> 4. Ao final, gere um arquivo `PRD.md` contendo: objetivos, arquivos afetados, snippets de código de referência e requisitos técnicos."

---

### 2. Especificação Tática (Spec)
Após gerar o PRD, limpe o contexto e crie um plano de execução detalhado.

**Prompt para Especificação:**
> "Leia o arquivo `PRD.md` que geramos. Agora, aja como um Engenheiro de Software Sênior e crie uma especificação tática no arquivo `SPEC.md`. 
> A especificação deve listar:
> - Cada arquivo que precisa ser criado (com o caminho completo).
> - Cada arquivo que precisa ser modificado e quais linhas/funções serão alteradas.
> - Pseudocódigo ou lógica detalhada para cada mudança, garantindo que não haja repetição de componentes existentes (como botões ou layouts já criados).
> Seja extremamente específico e tático."

---

### 3. Implementação
Com a especificação pronta, limpe o contexto novamente e execute.

**Prompt para Implementação:**
> "Leia o arquivo `SPEC.md`. Implemente a funcionalidade exatamente como planejada. 
> - Siga rigorosamente os caminhos de arquivos e a lógica descrita.
> - Mantenha o código modular e evite over-engineering.
> - Se encontrar qualquer ambiguidade, me pergunte antes de prosseguir."