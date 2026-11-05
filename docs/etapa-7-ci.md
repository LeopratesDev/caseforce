# Etapa 7: CI e acabamento

O CI roda a cada push na `main` e a cada pull request, em três jobs independentes. Dois funcionam sem nenhum segredo; o terceiro (testes Apex) precisa de uma org e fica desligado até alguém conectar uma.

| Job | O que faz | Precisa de segredo? |
|---|---|---|
| **Metadados** | Roda `scripts/check_metadata.py`: XML e JSON válidos, todo `.cls` e `.trigger` com seu `-meta.xml`, `apiVersion` igual ao do `sfdx-project.json`, classe de teste com `@IsTest` e nenhuma credencial no código | Não |
| **Testes do LWC (Jest)** | `npm ci` e `npm run test:unit:coverage` | Não |
| **Testes Apex (validação na org)** | Compila e roda todos os testes numa org, **sem gravar nada nela** | **Sim**: `SFDX_AUTH_URL` |

## Por que o Apex não vem ligado

Testar Apex exige uma org, e conectar o GitHub a ela significa guardar uma credencial como segredo do repositório. Isso dá ao GitHub acesso à sua org, então é uma decisão do dono dela, não algo para eu criar por conta própria. O job existe, está escrito, e **se o segredo não existir ele termina verde com um aviso**, sem quebrar o CI.

**Importante:** esse job **nunca foi executado de verdade**, porque o segredo ainda não existe. Ele segue a documentação do Salesforce CLI, mas está sem prova. Na primeira vez que você ligá-lo, esteja pronto para ajustá-lo.

### Como ligar

1. Gere a URL de autenticação da org (não a cole em lugar nenhum além do passo 2):

   ```bash
   sf org display --target-org caseforce --verbose --json
   ```

   Procure o campo `sfdxAuthUrl` na saída. Ele começa com `force://` e **equivale a uma senha da sua org**.

2. No GitHub: **Settings, Secrets and variables, Actions, New repository secret**. Nome: `SFDX_AUTH_URL`. Valor: o `sfdxAuthUrl`.

3. Abra ou atualize um pull request. O job passa a rodar `sf project deploy validate --test-level RunLocalTests`.

### Cuidados

- **Use uma org de desenvolvimento**, nunca uma de produção. O `validate` não grava metadados, mas roda os testes dentro dela.
- Em pull requests vindos de **forks** o GitHub não entrega segredos: o job roda, o segredo chega vazio e ele termina pulado. É o que se quer.
- Quem puder editar o workflow ou abrir PR no repositório consegue, em tese, usar o segredo. Em repositório público, restrinja quem pode fazer isso.
- O `scripts/check_metadata.py` **bloqueia o commit de uma URL `force://`** no código, justamente para o segredo nunca ir parar no repositório por engano.
- Se o segredo vazar, revogue o acesso em **Setup, Connected Apps OAuth Usage, Salesforce CLI**.

## O verificador de metadados

`scripts/check_metadata.py` pega a classe de erro que só apareceria num deploy, de graça e em segundos. Antes de confiar nele, plantei defeitos numa cópia mínima e conferi que ele os acha:

| Defeito plantado | Pego? |
|---|---|
| XML quebrado | sim |
| JSON quebrado | sim |
| Classe sem o `-meta.xml` | sim |
| `apiVersion` diferente do projeto | sim |
| Classe de teste sem `@IsTest` | sim |
| URL de autenticação `force://` no código | sim |

## Outras mudanças desta etapa

- **README final**, com print do painel, diagrama de como as peças se encaixam, números medidos e a lista de limitações.
- **`.gitattributes`** com fim de linha LF, para os arquivos não mudarem de aparência entre Windows e Linux (o Windows convertia tudo para CRLF a cada operação do Git).
- **Badge de CI** no README.

## Limitações

- O job de Apex nunca rodou (veja acima).
- O CI não mede cobertura mínima nem falha por cobertura baixa; só falha se um teste falhar.
- Não há análise estática de Apex (PMD) nem formatação automática (Prettier).
- Não há `LICENSE` no repositório: é decisão sua escolher uma.
