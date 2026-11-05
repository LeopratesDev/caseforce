@IsTest
private class CaseBoardControllerTest {

    private static Set<Id> idsOf(List<CaseBoardController.CaseRow> rows) {
        Set<Id> ids = new Set<Id>();
        for (CaseBoardController.CaseRow row : rows) {
            ids.add(row.id);
        }
        return ids;
    }

    // Usuario padrao (nao admin) com o permission set de agente, para provar o USER_MODE.
    private static User agentUser() {
        Id profileId = [
            SELECT Id FROM Profile
            WHERE UserType = 'Standard' AND PermissionsModifyAllData = false AND UserLicense.Name = 'Salesforce'
            LIMIT 1
        ].Id;
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
        User u = new User(
            Alias = 'agt' + unique.left(4),
            Email = 'agent' + unique + '@caseforce.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Agent',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Sao_Paulo',
            ProfileId = profileId,
            Username = 'agent' + unique + '@caseforce.example.com'
        );
        insert u;
        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'CaseForce_Agent'].Id
        );
        return u;
    }

    @IsTest
    static void returnsAllCasesWithoutFilters() {
        List<Case> cases = new List<Case>{
            CaseTestDataFactory.build('High', 'Billing'),
            CaseTestDataFactory.build('Low', 'Access')
        };
        insert cases;

        List<CaseBoardController.CaseRow> rows = CaseBoardController.getCases(null, null, null, null, null);

        System.assertEquals(idsOf(rows), new Set<Id>{ cases[0].Id, cases[1].Id });
        System.assertNotEquals(null, rows[0].caseNumber);
    }

    @IsTest
    static void filtersByStatusPriorityAndCategory() {
        Case target = CaseTestDataFactory.build('High', 'Billing');
        Case otherPriority = CaseTestDataFactory.build('Low', 'Billing');
        Case otherCategory = CaseTestDataFactory.build('High', 'Access');
        insert new List<Case>{ target, otherPriority, otherCategory };

        System.assertEquals(new Set<Id>{ target.Id },
            idsOf(CaseBoardController.getCases('New', 'High', 'Billing', null, false)));
        System.assertEquals(2, CaseBoardController.getCases(null, 'High', null, null, false).size());
        System.assertEquals(0, CaseBoardController.getCases('Closed', null, null, null, false).size());
    }

    @IsTest
    static void searchesSubjectAndTreatsWildcardsAsText() {
        Case match = CaseTestDataFactory.build('Medium', 'Billing');
        match.Subject = 'Cobranca duplicada na fatura';
        Case other = CaseTestDataFactory.build('Medium', 'Billing');
        other.Subject = 'Acesso bloqueado';
        insert new List<Case>{ match, other };

        System.assertEquals(new Set<Id>{ match.Id },
            idsOf(CaseBoardController.getCases(null, null, null, 'duplicada', false)));
        System.assertEquals(0, CaseBoardController.getCases(null, null, null, '%', false).size(),
            '% digitado e texto, nao curinga');
        System.assertEquals(0, CaseBoardController.getCases(null, null, null, 'x\' OR Name != \'', false).size(),
            'Aspas no texto nao podem virar SOQL');
    }

    @IsTest
    static void overdueFilterReturnsOnlyOpenCasesPastDue() {
        Case late = CaseTestDataFactory.build('High', 'Billing');
        Case onTime = CaseTestDataFactory.build('High', 'Billing');
        insert new List<Case>{ late, onTime };
        // Prioridade nao mudou, entao o trigger nao recalcula: da para fixar os prazos.
        update new List<Case>{
            new Case(Id = late.Id, Resolution_Due_At__c = System.now().addHours(-2)),
            new Case(Id = onTime.Id, Resolution_Due_At__c = System.now().addHours(2))
        };

        List<CaseBoardController.CaseRow> rows = CaseBoardController.getCases(null, null, null, null, true);

        System.assertEquals(new Set<Id>{ late.Id }, idsOf(rows));
        System.assertEquals(true, rows[0].isOverdue);
    }

    @IsTest
    static void closedCaseIsNeverOverdue() {
        Case c = CaseTestDataFactory.build('High', 'Billing');
        insert c;
        update new Case(Id = c.Id, Resolution_Due_At__c = System.now().addHours(-2));
        update new Case(Id = c.Id, Status = 'Closed', Resolution_Summary__c = 'Resolvido.');

        System.assertEquals(0, CaseBoardController.getCases(null, null, null, null, true).size());
        System.assertEquals(false, CaseBoardController.getCases(null, null, null, null, null)[0].isOverdue);
    }

    @IsTest
    static void ordersByResolutionDueSoonestFirst() {
        Case later = CaseTestDataFactory.build('Low', 'Billing');
        Case sooner = CaseTestDataFactory.build('High', 'Billing');
        insert new List<Case>{ later, sooner };

        List<CaseBoardController.CaseRow> rows = CaseBoardController.getCases(null, null, null, null, null);

        System.assertEquals(sooner.Id, rows[0].id, 'High vence antes que Low');
    }

    @IsTest
    static void capsTheResultAt200Rows() {
        insert CaseTestDataFactory.buildMany(205, 'Medium', 'Question');

        System.assertEquals(200, CaseBoardController.getCases(null, null, null, null, null).size());
    }

    @IsTest
    static void metricsCountOpenEscalatedAndOverdue() {
        Case escalated = CaseTestDataFactory.build('Low', 'Billing');
        Case late = CaseTestDataFactory.build('High', 'Billing');
        Case closed = CaseTestDataFactory.build('Low', 'Billing');
        insert new List<Case>{ escalated, late, closed };
        update new Case(Id = escalated.Id, Status = 'Escalated');
        update new Case(Id = late.Id, Resolution_Due_At__c = System.now().addHours(-1));
        update new Case(Id = closed.Id, Status = 'Closed', Resolution_Summary__c = 'Resolvido.');

        CaseBoardController.BoardMetrics metrics = CaseBoardController.getMetrics();

        System.assertEquals(2, metrics.open);
        System.assertEquals(1, metrics.escalated);
        System.assertEquals(1, metrics.overdue);
    }

    @IsTest
    static void filterOptionsListActivePicklistValues() {
        Map<String, List<CaseBoardController.Option>> options = CaseBoardController.getFilterOptions();

        Set<String> categories = new Set<String>();
        for (CaseBoardController.Option option : options.get('category')) {
            categories.add(option.value);
        }
        System.assertEquals(new Set<String>{ 'Billing', 'Technical', 'Access', 'Question', 'Other' }, categories);
        System.assert(options.get('status').size() >= 4);
        System.assertEquals(3, options.get('priority').size());
    }

    @IsTest
    static void agentSeesTheirOwnCasesWithCustomFields() {
        User agent = agentUser();
        // Sem categoria, para o roteamento nao mandar o caso para uma fila.
        Case c = CaseTestDataFactory.build('High', null);
        c.OwnerId = agent.Id;
        insert c;

        System.runAs(agent) {
            System.assertEquals(new Set<Id>{ c.Id }, idsOf(CaseBoardController.getCases(null, null, null, null, null)),
                'O agente enxerga o caso que e dele, inclusive os campos customizados');
        }
    }
}
