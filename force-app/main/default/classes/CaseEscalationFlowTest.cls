@IsTest
private class CaseEscalationFlowTest {

    @IsTest
    static void escalatingRaisesLevelPriorityAndMovesToEscalationQueue() {
        Case c = CaseTestDataFactory.build('Low', 'Billing');
        insert c;

        c.Status = 'Escalated';
        update c;

        c = [SELECT Escalation_Level__c, Priority, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(1, c.Escalation_Level__c);
        System.assertEquals('Medium', c.Priority, 'Low sobe um degrau');
        System.assertEquals(CaseTestDataFactory.queueId('Escalation_Support'), c.OwnerId);
    }

    @IsTest
    static void highPriorityStaysHighButLevelStillGrows() {
        Case c = CaseTestDataFactory.build('High', 'Technical');
        insert c;

        c.Status = 'Escalated';
        update c;

        c = [SELECT Escalation_Level__c, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals(1, c.Escalation_Level__c);
        System.assertEquals('High', c.Priority);
    }

    @IsTest
    static void escalatingAgainIncrementsLevelAgain() {
        Case c = CaseTestDataFactory.build('Low', 'Access');
        insert c;
        c.Status = 'Escalated';
        update c;

        // Atualiza so os campos que mudam: reenviar o objeto antigo desfaria o que o Flow gravou.
        update new Case(Id = c.Id, Status = 'Working');
        update new Case(Id = c.Id, Status = 'Escalated');

        c = [SELECT Escalation_Level__c, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals(2, c.Escalation_Level__c);
        System.assertEquals('High', c.Priority, 'Low > Medium > High');
    }

    @IsTest
    static void editingAnEscalatedCaseDoesNotEscalateAgain() {
        Case c = CaseTestDataFactory.build('Low', 'Billing');
        insert c;
        c.Status = 'Escalated';
        update c;

        update new Case(Id = c.Id, Subject = 'Assunto alterado');

        System.assertEquals(1, [SELECT Escalation_Level__c FROM Case WHERE Id = :c.Id].Escalation_Level__c,
            'So a mudanca para Escalated escalona');
    }

    @IsTest
    static void otherStatusChangesDoNotEscalate() {
        Case c = CaseTestDataFactory.build('Low', 'Billing');
        insert c;

        c.Status = 'Working';
        update c;

        c = [SELECT Escalation_Level__c, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals(0, c.Escalation_Level__c);
        System.assertEquals('Low', c.Priority);
    }

    @IsTest
    static void escalationRecalculatesSlaAndIsAudited() {
        Case c = CaseTestDataFactory.build('Low', 'Billing');
        insert c;
        Datetime lowResolutionDue = [SELECT Resolution_Due_At__c FROM Case WHERE Id = :c.Id].Resolution_Due_At__c;

        c.Status = 'Escalated';
        update c;

        c = [SELECT Resolution_Due_At__c FROM Case WHERE Id = :c.Id];
        System.assert(c.Resolution_Due_At__c < lowResolutionDue, 'Prioridade maior encurta o prazo de resolucao');

        Set<String> audited = new Set<String>();
        for (Case_Audit__c entry : [SELECT Field_Name__c FROM Case_Audit__c WHERE Case__c = :c.Id]) {
            audited.add(entry.Field_Name__c);
        }
        System.assert(audited.containsAll(new Set<String>{ 'Status', 'Priority', 'OwnerId', 'Escalation_Level__c' }),
            'Tudo que o Flow muda precisa aparecer na auditoria: ' + audited);
    }

    @IsTest
    static void escalatesAWholeBatch() {
        List<Case> cases = CaseTestDataFactory.buildMany(200, 'Low', 'Question');
        insert cases;

        for (Case c : cases) {
            c.Status = 'Escalated';
        }
        Test.startTest();
        update cases;
        Test.stopTest();

        System.assertEquals(200, [SELECT COUNT() FROM Case WHERE Escalation_Level__c = 1 AND Priority = 'Medium']);
    }
}
