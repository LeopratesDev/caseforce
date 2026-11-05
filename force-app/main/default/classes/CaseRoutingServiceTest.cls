@IsTest
private class CaseRoutingServiceTest {

    @IsTest
    static void routesToCategoryQueueOnInsert() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');

        Test.startTest();
        insert c;
        Test.stopTest();

        c = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(CaseTestDataFactory.queueId('Billing_Support'), c.OwnerId, 'Billing deve ir para Billing_Support');
    }

    @IsTest
    static void questionAndOtherShareTheGeneralQueue() {
        List<Case> cases = new List<Case>{
            CaseTestDataFactory.build('Low', 'Question'),
            CaseTestDataFactory.build('Low', 'Other')
        };

        insert cases;

        Id generalQueue = CaseTestDataFactory.queueId('General_Support');
        for (Case c : [SELECT OwnerId FROM Case WHERE Id IN :cases]) {
            System.assertEquals(generalQueue, c.OwnerId);
        }
    }

    @IsTest
    static void reroutesWhenCategoryChanges() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;

        c.Category__c = 'Technical';
        update c;

        c = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(CaseTestDataFactory.queueId('Technical_Support'), c.OwnerId);
    }

    @IsTest
    static void keepsOwnerWhenCategoryDoesNotChange() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;
        c.OwnerId = UserInfo.getUserId();
        update c;

        c.Subject = 'Assunto alterado';
        update c;

        c = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(UserInfo.getUserId(), c.OwnerId, 'Quem assumiu o caso nao pode perde-lo');
    }

    @IsTest
    static void leavesCaseWithoutCategoryWithItsOwner() {
        Case c = CaseTestDataFactory.build('Medium', null);

        insert c;

        c = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(UserInfo.getUserId(), c.OwnerId);
    }

    @IsTest
    static void routesBulkInsertWithMixedCategories() {
        List<Case> cases = new List<Case>();
        for (String category : CaseTestDataFactory.CATEGORIES) {
            cases.addAll(CaseTestDataFactory.buildMany(40, 'Medium', category));
        }

        Test.startTest();
        insert cases;
        Integer queries = Limits.getQueries();
        Test.stopTest();

        System.assert(queries < 10, 'Roteamento deve ser em lote, nao uma consulta por caso. Consultas: ' + queries);
        Map<String, Id> expected = new Map<String, Id>{
            'Billing' => CaseTestDataFactory.queueId('Billing_Support'),
            'Technical' => CaseTestDataFactory.queueId('Technical_Support'),
            'Access' => CaseTestDataFactory.queueId('Access_Support'),
            'Question' => CaseTestDataFactory.queueId('General_Support'),
            'Other' => CaseTestDataFactory.queueId('General_Support')
        };
        for (Case c : [SELECT Category__c, OwnerId FROM Case WHERE Id IN :cases]) {
            System.assertEquals(expected.get(c.Category__c), c.OwnerId, 'Categoria ' + c.Category__c);
        }
    }
}
