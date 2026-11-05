/**
 * Grava uma linha em Case_Audit__c para cada campo acompanhado que mudou.
 * Roda no after update e nao altera o Case, entao nao ha risco de recursao.
 */
public with sharing class CaseAuditService {

    private static final Integer VALUE_MAX_LENGTH = 255;

    private static final List<Schema.SObjectField> TRACKED_FIELDS = new List<Schema.SObjectField>{
        Case.Status,
        Case.Priority,
        Case.OwnerId,
        Case.Category__c,
        Case.Escalation_Level__c
    };

    // O describe e caro; resolve o nome de cada campo uma unica vez por transacao.
    private static Map<Schema.SObjectField, String> fieldNames {
        get {
            if (fieldNames == null) {
                fieldNames = new Map<Schema.SObjectField, String>();
                for (Schema.SObjectField field : TRACKED_FIELDS) {
                    fieldNames.put(field, field.getDescribe().getName());
                }
            }
            return fieldNames;
        }
        private set;
    }

    public static void recordChanges(List<Case> cases, Map<Id, Case> oldCases) {
        List<Case_Audit__c> entries = new List<Case_Audit__c>();

        for (Case c : cases) {
            Case old = oldCases.get(c.Id);
            for (Schema.SObjectField field : TRACKED_FIELDS) {
                Object before = old.get(field);
                Object after = c.get(field);
                if (before == after) {
                    continue;
                }
                entries.add(new Case_Audit__c(
                    Case__c = c.Id,
                    Field_Name__c = fieldNames.get(field),
                    Old_Value__c = toAuditValue(before),
                    New_Value__c = toAuditValue(after),
                    Changed_By__c = UserInfo.getUserId()
                ));
            }
        }

        if (!entries.isEmpty()) {
            insert entries;
        }
    }

    private static String toAuditValue(Object value) {
        return value == null ? null : String.valueOf(value).abbreviate(VALUE_MAX_LENGTH);
    }
}
