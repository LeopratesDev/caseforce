# CaseForce

Central de atendimento sobre **Salesforce Service Cloud**: casos roteados automaticamente para filas, SLA por prioridade, trilha de auditoria e integração com API externa.

> **Status:** em desenvolvimento. Etapa 1 (estrutura e modelo de dados) **implantada em uma Developer Edition org** e conferida por consulta.

## Por que este projeto existe

Antes de programar, trabalhei do outro lado do chamado: SAC e suporte técnico. Já construí esse domínio em Node/NestJS no [helpdesk-api](https://github.com/LeopratesDev/helpdesk-api). O CaseForce refaz o problema na plataforma que muitas empresas usam de fato, com as ferramentas dela: Apex, Flow, LWC e metadados versionados.

## Roteiro

| # | Etapa | Entrega | Status |
|---|---|---|---|
| 1 | Estrutura SFDX e modelo de dados | Campos de Case, `Case_Audit__c`, Custom Metadata (SLA e roteamento), filas, permission sets | implantada |
| 2 | Apex Trigger | Roteamento por categoria, cálculo de prazos, auditoria, validação de fechamento; testes com mais de 75% | |
| 3 | Flow | Escalonamento de casos | |
| 4 | LWC | Painel de tickets com filtros e edição inline | |
| 5 | Integração | Callout com Named Credentials e endpoint `@RestResource` | |
| 6 | Batch Apex | Marca SLA estourado e gera resumo, agendado | |
| 7 | CI e acabamento | GitHub Actions rodando testes, prints e resumo | |

O modelo de dados, com diagrama e as decisões, está em [docs/data-model.md](docs/data-model.md).

## Estrutura

```
force-app/main/default/
  objects/            Case (campos), Case_Audit__c, SLA_Policy__mdt, Category_Routing__mdt
  customMetadata/     valores de SLA e de roteamento
  queues/             filas por categoria
  permissionsets/     CaseForce_Agent, CaseForce_Manager
  classes/ triggers/ flows/ lwc/   (preenchidos nas próximas etapas)
config/               definição de scratch org
docs/                 documentação
```

## Como rodar

Pré-requisitos: Salesforce CLI (`sf`), VS Code com as Salesforce Extensions e uma Developer Edition org.

```bash
sf org login web --alias caseforce
sf project deploy start --source-dir force-app --target-org caseforce
sf org assign permset --name CaseForce_Manager --target-org caseforce
```
