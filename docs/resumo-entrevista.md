# CaseForce: resumo para entrevista

Uma página para consultar antes de uma conversa. Tudo aqui sai dos documentos de etapa; os números foram medidos na org, não estimados.

## Em 30 segundos

> Eu atendia chamados no SAC e no suporte técnico, então sei como uma fila sem prioridade clara dói. Construí o CaseForce em Salesforce Service Cloud: o caso é roteado para a fila certa, ganha prazos de SLA, pode ser escalado por um agente ou pelo tempo, deixa trilha de auditoria e avisa sistemas externos. Tem um painel em LWC, uma API REST de entrada, um webhook de saída e um Batch agendado. São 69 testes Apex com 97% de cobertura e 13 testes Jest. Já tinha feito o mesmo domínio em Node/NestJS, então consigo comparar as duas abordagens.

## Como as peças se encaixam

- **Um trigger no Case** que só delega a três serviços: roteamento, SLA e auditoria.
- **Um Flow before-save** sobe nível e prioridade quando o status vira `Escalated`. Roda antes do trigger, então os prazos já são recalculados com a prioridade nova.
- **Um painel LWC** que lê por Apex (`USER_MODE`) e grava por `updateRecord`, passando pelas mesmas regras do resto.
- **Uma API REST** (`@RestResource`) e **um webhook** (`Queueable` com Named Credential) para a integração.
- **Um Batch** a cada 15 minutos marca e escala casos com SLA estourado e grava o resumo da rodada.
- **Custom Metadata** guarda as metas de SLA e o roteamento: mudar uma regra não exige deploy.

## Decisões que eu sei defender

| Decisão | Por quê |
|---|---|
| Custom Metadata para SLA e roteamento | Vai no deploy, é testável, o Apex lê sem gastar consulta, e o negócio muda a meta sem código |
| Flow **before-save** para o escalonamento | Altera o próprio registro sem DML extra e roda antes do trigger |
| Validation rule para "não fechar sem resumo" | É uma fórmula; a ferramenta nativa resolve melhor do que código |
| Gravar pelo LDS (`updateRecord`) e ler por Apex | Não existe segunda via de escrita para manter; validation rule, Flow e permissões continuam valendo |
| `USER_MODE` e bind em tudo | A API e o painel só fazem o que o usuário pode; texto digitado nunca é concatenado na consulta |
| Webhook sem texto livre do cliente | Assunto e descrição podem ter dado pessoal; o payload leva só identificação e andamento |
| Resultado do webhook na auditoria | Falha de integração não pode passar em silêncio |
| Lote do Batch de 100 | Só se pode enfileirar 1 job assíncrono por `execute`, e o webhook cria 1 job por bloco de 100 casos |
| SLA calculado no Apex, sem Entitlements | Entitlements pedem configuração por conta e escondem a lógica em telas; o cálculo atual é testado e versionado |
| Usuário de integração com permission set próprio | Menor privilégio: cria e lê casos, e nada mais |

## O que deu errado (e é a melhor parte para contar)

1. **O filtro do painel não filtrava, mas os testes passavam.** O objeto de filtros chegava vazio ao Apex pelo Aura; os testes Apex chamam o método direto e não pegam isso. Achei comparando a requisição e a resposta no navegador e troquei por parâmetros simples.
2. **Meu primeiro teste da correção não valeu.** O Chrome ainda tinha o componente antigo em cache. Depois de implantar um LWC, recarrego sem cache antes de concluir.
3. **O permission set não bastava.** Um usuário só com ele não lia `Case.Subject`, porque eu liberava só os campos customizados. O teste com usuário não administrador pegou isso.
4. **Escalar pelo SLA contaria como "primeira resposta".** A regra era "sair de `New`", então o Batch registraria como respondido um caso que ninguém tocou. Mudei a regra e escrevi teste.
5. **`Owner.Name` vem nulo para fila só em teste.** Descobri com uma classe de sondagem descartável e passei a conferir o dono pelo Id; o campo ficou provado numa chamada real.
6. **O External Credential não aceita "sem autenticação".** O deploy foi recusado; usei o protocolo `Custom`.
7. **`MIXED_DML_OPERATION`** num teste que já existia, depois de mover um helper. Isolei a criação do usuário num `System.runAs`.
8. **Um `404` que não era da minha API.** O Git Bash do Windows reescrevia o caminho `/services/...` como caminho de arquivo.
9. **A coluna Assunto sumia em tela estreita.** Só percebi num print tirado em janela pequena. A primeira correção (largura mínima de 68rem com rolagem horizontal) ainda cortava o texto; medi de novo e subi para 78rem. Testei reduzindo a largura do componente, e confirmei que a tela larga não mudou.

## Números (medidos)

| | |
|---|---|
| Testes Apex | 69, todos passando em execuções seguidas |
| Cobertura Apex | 97% no total |
| Testes Jest | 13 (92% das instruções, 60% dos ramos) |
| CI | metadados e LWC verdes no GitHub; Apex pulado (veja abaixo) |

## O que eu não fiz, dito com clareza

- **O job de Apex do CI nunca rodou**, porque depende de um segredo que o dono da org ainda não criou. Está escrito, mas sem prova.
- A tabela do painel só foi testada reduzindo a largura do componente para 900 px (rola na horizontal), não num celular de verdade.
- Prazos em minutos corridos, sem horário comercial.
- API sem idempotência e webhook sem repetição de envio.
- O destino do webhook é um serviço público de demonstração.
- O repositório não tem licença.

## Perguntas que provavelmente fariam

**Por que Flow e não Apex para o escalonamento?** É uma regra simples de um objeto só. Before-save evita DML extra. Usei Apex onde precisei de lógica (roteamento, SLA, auditoria, Batch).

**Como você lida com governor limits?** Nenhuma consulta nem DML dentro de `for`; testes com 200 registros; webhook dividido em jobs de 100 por causa do limite de chamadas HTTP; lote do Batch travado em 100 por causa do limite de jobs por `execute`.

**Como você testou a integração?** Testes unitários com `HttpCalloutMock` e `RestContext`, e depois chamadas reais contra a org, que revelaram coisas que os testes não mostraram.

**O que faria com mais tempo?** Ligar o job de Apex no CI numa org de desenvolvimento, idempotência na API, repetição do webhook, horário comercial nos prazos, e testar o painel em outras larguras de tela.
