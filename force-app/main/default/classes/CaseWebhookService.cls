/**
 * Avisa um sistema externo (webhook) quando um caso e escalado. O destino vem do
 * Named Credential CaseForce_Webhook, entao URL e autenticacao ficam fora do codigo.
 *
 * O payload leva so identificacao e andamento do caso, sem assunto nem descricao:
 * texto livre do cliente nao sai da org. O resultado de cada envio vira uma linha
 * em Case_Audit__c (campo "Webhook"), para a falha nao passar em silencio.
 */
public with sharing class CaseWebhookService implements Queueable, Database.AllowsCallouts {

    private static final String ENDPOINT = 'callout:CaseForce_Webhook/post';
    private static final String STATUS_ESCALATED = 'Escalated';
    private static final String AUDIT_FIELD = 'Webhook';
    // Limite de 100 chamadas HTTP por transacao: um job por bloco de casos.
    @TestVisible private static final Integer CHUNK_SIZE = 100;
    private static final Integer TIMEOUT_MS = 10000;

    // Os testes do restante do projeto escalam casos o tempo todo e nao devem chamar a rede.
    @TestVisible private static Boolean enabledInTests = false;

    private final List<Id> caseIds;

    public CaseWebhookService(List<Id> caseIds) {
        this.caseIds = caseIds;
    }

    /** Chamado no after update: enfileira so os casos que acabaram de virar Escalated. */
    public static void enqueueEscalations(List<Case> cases, Map<Id, Case> oldCases) {
        if (Test.isRunningTest() && !enabledInTests) {
            return;
        }

        List<Id> escalated = new List<Id>();
        for (Case c : cases) {
            if (c.Status == STATUS_ESCALATED && oldCases.get(c.Id).Status != STATUS_ESCALATED) {
                escalated.add(c.Id);
            }
        }

        for (Integer start = 0; start < escalated.size(); start += CHUNK_SIZE) {
            Integer finish = Math.min(start + CHUNK_SIZE, escalated.size());
            System.enqueueJob(new CaseWebhookService(slice(escalated, start, finish)));
        }
    }

    public void execute(QueueableContext context) {
        List<Case_Audit__c> results = new List<Case_Audit__c>();

        for (Case c : [
            SELECT Id, CaseNumber, Priority, Category__c, Escalation_Level__c, Owner.Name, Resolution_Due_At__c
            FROM Case
            WHERE Id IN :caseIds
        ]) {
            results.add(deliver(c));
        }

        // DML so depois de todas as chamadas HTTP: o Salesforce nao permite o contrario.
        insert results;
    }

    private Case_Audit__c deliver(Case c) {
        String outcome;
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(ENDPOINT);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(TIMEOUT_MS);
            request.setBody(JSON.serialize(payload(c)));

            HttpResponse response = new Http().send(request);
            outcome = 'HTTP ' + response.getStatusCode();
        } catch (Exception e) {
            outcome = 'Erro: ' + e.getMessage();
        }

        return new Case_Audit__c(
            Case__c = c.Id,
            Field_Name__c = AUDIT_FIELD,
            New_Value__c = outcome.abbreviate(255),
            Changed_By__c = UserInfo.getUserId()
        );
    }

    private static Map<String, Object> payload(Case c) {
        return new Map<String, Object>{
            'event' => 'case.escalated',
            'caseNumber' => c.CaseNumber,
            'priority' => c.Priority,
            'category' => c.Category__c,
            'escalationLevel' => c.Escalation_Level__c == null ? 0 : c.Escalation_Level__c.intValue(),
            'queue' => c.Owner.Name,
            'resolutionDueAt' => c.Resolution_Due_At__c
        };
    }

    private static List<Id> slice(List<Id> source, Integer start, Integer finish) {
        List<Id> part = new List<Id>();
        for (Integer i = start; i < finish; i++) {
            part.add(source[i]);
        }
        return part;
    }
}
