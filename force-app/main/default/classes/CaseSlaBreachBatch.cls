/**
 * Procura casos abertos que estouraram o SLA, marca SLA_Breached__c e escala os que
 * ainda nao estavam escalados. Ao final grava um resumo da rodada em SLA_Run__c.
 *
 * Estoura o SLA quem esta aberto, ainda nao foi marcado e: passou do prazo de
 * resolucao, ou passou do prazo de resposta sem ninguem ter respondido.
 *
 * Escalar muda o Status, e o resto vem das etapas anteriores: o Flow sobe nivel e
 * prioridade e manda para a fila de escalonamento, o trigger recalcula prazos e
 * audita, e o webhook avisa o sistema externo.
 */
public with sharing class CaseSlaBreachBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Um execute so pode enfileirar 1 job (limite do contexto assincrono) e o webhook
    // cria 1 job por bloco de CHUNK_SIZE casos: lote maior que isso estoura o limite.
    public static final Integer SCOPE_SIZE = CaseWebhookService.CHUNK_SIZE;

    private static final String STATUS_ESCALATED = 'Escalated';

    private Integer flagged = 0;
    private Integer escalated = 0;
    private Integer failures = 0;
    private String errorSample;

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime now = System.now();
        return Database.getQueryLocator([
            SELECT Id, Status
            FROM Case
            WHERE IsClosed = false
              AND SLA_Breached__c = false
              AND (
                  Resolution_Due_At__c < :now
                  OR (Response_Due_At__c < :now AND First_Response_At__c = null)
              )
        ]);
    }

    public void execute(Database.BatchableContext context, List<Case> scope) {
        Set<Id> toEscalate = new Set<Id>();
        for (Case c : scope) {
            c.SLA_Breached__c = true;
            if (c.Status != STATUS_ESCALATED) {
                c.Status = STATUS_ESCALATED;
                toEscalate.add(c.Id);
            }
        }

        List<Database.SaveResult> results = Database.update(scope, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                flagged++;
                if (toEscalate.contains(scope[i].Id)) {
                    escalated++;
                }
            } else {
                failures++;
                if (errorSample == null) {
                    errorSample = results[i].getErrors()[0].getMessage();
                }
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        // Rodada que nao achou nada nao gera registro: a cada 15 minutos seriam 96 linhas vazias por dia.
        if (flagged == 0 && failures == 0) {
            return;
        }
        insert new SLA_Run__c(
            Cases_Flagged__c = flagged,
            Cases_Escalated__c = escalated,
            Failures__c = failures,
            Error_Sample__c = errorSample == null ? null : errorSample.abbreviate(255)
        );
    }
}
