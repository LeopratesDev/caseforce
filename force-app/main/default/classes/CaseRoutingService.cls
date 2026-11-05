/**
 * Encaminha o caso para a fila da sua categoria, conforme Category_Routing__mdt.
 * So age quando a categoria e nova ou mudou, para nao tirar o caso de quem
 * ja o assumiu.
 */
public with sharing class CaseRoutingService {

    public static void routeByCategory(List<Case> cases, Map<Id, Case> oldCases) {
        List<Case> toRoute = new List<Case>();
        Set<String> queueNames = new Set<String>();

        for (Case c : cases) {
            if (String.isBlank(c.Category__c)) {
                continue;
            }
            Case old = oldCases == null ? null : oldCases.get(c.Id);
            if (old != null && old.Category__c == c.Category__c) {
                continue;
            }
            Category_Routing__mdt rule = Category_Routing__mdt.getInstance(c.Category__c);
            if (rule != null) {
                toRoute.add(c);
                queueNames.add(rule.Queue_Developer_Name__c);
            }
        }

        if (toRoute.isEmpty()) {
            return;
        }

        Map<String, Id> queueIds = queueIdsByDeveloperName(queueNames);
        for (Case c : toRoute) {
            Id queueId = queueIds.get(Category_Routing__mdt.getInstance(c.Category__c).Queue_Developer_Name__c);
            if (queueId != null) {
                c.OwnerId = queueId;
            }
        }
    }

    private static Map<String, Id> queueIdsByDeveloperName(Set<String> developerNames) {
        Map<String, Id> result = new Map<String, Id>();
        for (Group g : [
            SELECT Id, DeveloperName
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName IN :developerNames
        ]) {
            result.put(g.DeveloperName, g.Id);
        }
        return result;
    }
}
