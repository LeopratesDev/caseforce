@IsTest
private class CaseAuditServiceTest {

    @IsTest
    static void recordsStatusChangeWithOldAndNewValue() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;

        c.Status = 'Working';
        update c;

        List<Case_Audit__c> entries = [
            SELECT Field_Name__c, Old_Value__c, New_Value__c, Changed_By__c
            FROM Case_Audit__c
            WHERE Case__c = :c.Id AND Field_Name__c = 'Status'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('New', entries[0].Old_Value__c);
        System.assertEquals('Working', entries[0].New_Value__c);
        System.assertEquals(UserInfo.getUserId(), entries[0].Changed_By__c);
    }

    @IsTest
    static void ignoresChangesOnUntrackedFields() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;

        c.Subject = 'Outro assunto';
        c.Description = 'Mais detalhes';
        update c;

        System.assertEquals(0, [SELECT COUNT() FROM Case_Audit__c WHERE Case__c = :c.Id]);
    }

    @IsTest
    static void recordsOneEntryPerChangedField() {
        Case c = CaseTestDataFactory.build('Low', 'Billing');
        insert c;

        c.Status = 'Escalated';
        c.Priority = 'High';
        c.Escalation_Level__c = 1;
        update c;

        Set<String> fields = new Set<String>();
        for (Case_Audit__c entry : [SELECT Field_Name__c FROM Case_Audit__c WHERE Case__c = :c.Id]) {
            fields.add(entry.Field_Name__c);
        }
        System.assertEquals(new Set<String>{ 'Status', 'Priority', 'Escalation_Level__c' }, fields);
    }

    @IsTest
    static void recordsOwnerChangeCausedByRouting() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;

        c.Category__c = 'Technical';
        update c;

        Map<String, Case_Audit__c> byField = new Map<String, Case_Audit__c>();
        for (Case_Audit__c entry : [SELECT Field_Name__c, New_Value__c FROM Case_Audit__c WHERE Case__c = :c.Id]) {
            byField.put(entry.Field_Name__c, entry);
        }
        System.assert(byField.containsKey('Category__c'), 'Deve auditar a categoria');
        System.assert(byField.containsKey('OwnerId'), 'Deve auditar a troca de dono feita pelo roteamento');
        System.assertEquals(String.valueOf(CaseTestDataFactory.queueId('Technical_Support')), byField.get('OwnerId').New_Value__c);
    }

    @IsTest
    static void auditsBulkUpdate() {
        List<Case> cases = CaseTestDataFactory.buildMany(200, 'Medium', 'Question');
        insert cases;

        for (Case c : cases) {
            c.Status = 'Working';
        }
        Test.startTest();
        update cases;
        Test.stopTest();

        System.assertEquals(200, [SELECT COUNT() FROM Case_Audit__c WHERE Field_Name__c = 'Status']);
    }
}
