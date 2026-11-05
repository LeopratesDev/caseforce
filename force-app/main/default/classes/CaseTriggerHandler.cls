/**
 * Ponto unico de entrada do CaseTrigger. Nao tem regra de negocio: so decide
 * quais servicos rodam em cada operacao, e em que ordem.
 */
public with sharing class CaseTriggerHandler {

    public static void run() {
        List<Case> cases = (List<Case>) Trigger.new;
        Map<Id, Case> oldCases = (Map<Id, Case>) Trigger.oldMap;

        switch on Trigger.operationType {
            when BEFORE_INSERT {
                CaseSlaService.setDueDates(cases, oldCases);
                CaseRoutingService.routeByCategory(cases, oldCases);
            }
            when BEFORE_UPDATE {
                // Primeira resposta antes dos prazos: o prazo de resposta so
                // e recalculado enquanto ainda nao houve resposta.
                CaseSlaService.markFirstResponse(cases, oldCases);
                CaseSlaService.setDueDates(cases, oldCases);
                CaseRoutingService.routeByCategory(cases, oldCases);
            }
            when AFTER_UPDATE {
                CaseAuditService.recordChanges(cases, oldCases);
            }
        }
    }
}
