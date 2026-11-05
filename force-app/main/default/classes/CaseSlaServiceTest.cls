@IsTest
private class CaseSlaServiceTest {

    // O banco guarda datas com precisao de segundo; a folga evita falso negativo.
    private static void assertWithin(Datetime actual, Datetime earliest, Datetime latest, String message) {
        System.assertNotEquals(null, actual, message);
        System.assert(actual >= earliest.addSeconds(-1) && actual <= latest.addSeconds(1), message + ': ' + actual);
    }

    @IsTest
    static void setsDueDatesFromPriorityOnInsert() {
        SLA_Policy__mdt policy = SLA_Policy__mdt.getInstance('High');
        Case c = CaseTestDataFactory.build('High', 'Technical');

        Datetime before = System.now();
        insert c;
        Datetime after = System.now();

        c = [SELECT Response_Due_At__c, Resolution_Due_At__c FROM Case WHERE Id = :c.Id];
        assertWithin(c.Response_Due_At__c,
            before.addMinutes(policy.Response_Minutes__c.intValue()),
            after.addMinutes(policy.Response_Minutes__c.intValue()), 'Prazo de resposta');
        assertWithin(c.Resolution_Due_At__c,
            before.addMinutes(policy.Resolution_Minutes__c.intValue()),
            after.addMinutes(policy.Resolution_Minutes__c.intValue()), 'Prazo de resolucao');
    }

    @IsTest
    static void treatsBlankPriorityAsMedium() {
        SLA_Policy__mdt policy = SLA_Policy__mdt.getInstance('Medium');
        Case c = CaseTestDataFactory.build(null, 'Question');

        Datetime before = System.now();
        insert c;
        Datetime after = System.now();

        c = [SELECT Resolution_Due_At__c FROM Case WHERE Id = :c.Id];
        assertWithin(c.Resolution_Due_At__c,
            before.addMinutes(policy.Resolution_Minutes__c.intValue()),
            after.addMinutes(policy.Resolution_Minutes__c.intValue()), 'Prioridade vazia usa Medium');
    }

    @IsTest
    static void recalculatesFromCreationWhenPriorityChanges() {
        Case c = CaseTestDataFactory.build('Low', 'Access');
        insert c;
        Datetime createdAt = [SELECT CreatedDate FROM Case WHERE Id = :c.Id].CreatedDate;

        c.Priority = 'High';
        update c;

        SLA_Policy__mdt high = SLA_Policy__mdt.getInstance('High');
        c = [SELECT Response_Due_At__c, Resolution_Due_At__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(createdAt.addMinutes(high.Response_Minutes__c.intValue()), c.Response_Due_At__c);
        System.assertEquals(createdAt.addMinutes(high.Resolution_Minutes__c.intValue()), c.Resolution_Due_At__c);
    }

    @IsTest
    static void marksFirstResponseOnlyOnce() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;
        System.assertEquals(null, [SELECT First_Response_At__c FROM Case WHERE Id = :c.Id].First_Response_At__c);

        c.Status = 'Working';
        update c;
        Datetime firstResponse = [SELECT First_Response_At__c FROM Case WHERE Id = :c.Id].First_Response_At__c;
        System.assertNotEquals(null, firstResponse, 'Sair de New marca a primeira resposta');

        c.Status = 'Escalated';
        update c;
        System.assertEquals(firstResponse, [SELECT First_Response_At__c FROM Case WHERE Id = :c.Id].First_Response_At__c,
            'A primeira resposta nao pode ser sobrescrita');
    }

    @IsTest
    static void keepsResponseDueAfterFirstResponse() {
        Case c = CaseTestDataFactory.build('Low', 'Billing');
        insert c;
        c.Status = 'Working';
        update c;
        Datetime responseDue = [SELECT Response_Due_At__c FROM Case WHERE Id = :c.Id].Response_Due_At__c;

        c.Priority = 'High';
        update c;

        c = [SELECT Response_Due_At__c, Resolution_Due_At__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(responseDue, c.Response_Due_At__c, 'Depois de responder, o prazo de resposta fica fixo');
        System.assertNotEquals(null, c.Resolution_Due_At__c);
    }
}
