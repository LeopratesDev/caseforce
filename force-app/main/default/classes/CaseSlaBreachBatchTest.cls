@IsTest
private class CaseSlaBreachBatchTest {

    private class WebhookMock implements HttpCalloutMock {
        Integer calls = 0;
        public HttpResponse respond(HttpRequest request) {
            calls++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{}');
            return response;
        }
    }

    // Fixa o prazo no passado sem mexer na prioridade, para o trigger nao recalcular.
    private static Case overdue(String category) {
        Case c = CaseTestDataFactory.build('Medium', category);
        insert c;
        update new Case(Id = c.Id, Resolution_Due_At__c = System.now().addHours(-1));
        return c;
    }

    // Escalar sobe a prioridade e o trigger recalcula o prazo a partir da criacao; num caso
    // recem-criado isso joga o prazo para o futuro. Por isso o atraso e fixado depois de escalar.
    private static Case escalatedAndOverdue(String category) {
        Case c = CaseTestDataFactory.build('Medium', category);
        insert c;
        update new Case(Id = c.Id, Status = 'Escalated');
        update new Case(Id = c.Id, Resolution_Due_At__c = System.now().addHours(-1));
        return c;
    }

    private static void runBatch() {
        Test.startTest();
        Database.executeBatch(new CaseSlaBreachBatch(), CaseSlaBreachBatch.SCOPE_SIZE);
        Test.stopTest();
    }

    @IsTest
    static void flagsAndEscalatesACasePastItsResolutionDue() {
        Case c = overdue('Billing');

        runBatch();

        c = [SELECT SLA_Breached__c, Status, Escalation_Level__c, OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(true, c.SLA_Breached__c);
        System.assertEquals('Escalated', c.Status);
        System.assertEquals(1, c.Escalation_Level__c, 'O Flow de escalonamento roda junto');
        System.assertEquals(CaseTestDataFactory.queueId('Escalation_Support'), c.OwnerId);
    }

    @IsTest
    static void aResponseBreachWithoutAnyAnswerIsFlaggedButIsNotAFirstResponse() {
        Case c = CaseTestDataFactory.build('Medium', 'Access');
        insert c;
        update new Case(Id = c.Id, Response_Due_At__c = System.now().addMinutes(-10));

        runBatch();

        c = [SELECT SLA_Breached__c, Status, First_Response_At__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(true, c.SLA_Breached__c);
        System.assertEquals('Escalated', c.Status);
        System.assertEquals(null, c.First_Response_At__c, 'Escalar pelo SLA nao e responder o cliente');
    }

    @IsTest
    static void doesNotFlagACaseThatWasAnsweredEvenIfTheResponseDueHasPassed() {
        Case c = CaseTestDataFactory.build('Medium', 'Access');
        insert c;
        update new Case(Id = c.Id, Status = 'Working');
        update new Case(Id = c.Id, Response_Due_At__c = System.now().addMinutes(-10));

        runBatch();

        System.assertEquals(false, [SELECT SLA_Breached__c FROM Case WHERE Id = :c.Id].SLA_Breached__c);
    }

    @IsTest
    static void doesNotTouchClosedOnTimeOrAlreadyFlaggedCases() {
        Case closed = overdue('Billing');
        update new Case(Id = closed.Id, Status = 'Closed', Resolution_Summary__c = 'Resolvido.');
        Case onTime = CaseTestDataFactory.build('Low', 'Billing');
        insert onTime;
        Case flagged = overdue('Access');
        update new Case(Id = flagged.Id, SLA_Breached__c = true, Status = 'Working');

        runBatch();

        System.assertEquals(false, [SELECT SLA_Breached__c FROM Case WHERE Id = :closed.Id].SLA_Breached__c);
        System.assertEquals(false, [SELECT SLA_Breached__c FROM Case WHERE Id = :onTime.Id].SLA_Breached__c);
        System.assertEquals('Working', [SELECT Status FROM Case WHERE Id = :flagged.Id].Status,
            'Quem ja foi marcado nao e reprocessado');
    }

    @IsTest
    static void aCaseThatIsAlreadyEscalatedIsFlaggedButNotEscalatedAgain() {
        Case c = escalatedAndOverdue('Billing');
        Integer levelBefore = (Integer) [SELECT Escalation_Level__c FROM Case WHERE Id = :c.Id].Escalation_Level__c;

        runBatch();

        c = [SELECT SLA_Breached__c, Escalation_Level__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(true, c.SLA_Breached__c);
        System.assertEquals(levelBefore, c.Escalation_Level__c, 'Ja escalado: o nivel nao sobe de novo');
    }

    @IsTest
    static void writesASummaryOfTheRun() {
        overdue('Billing');
        overdue('Access');
        escalatedAndOverdue('Technical');

        runBatch();

        SLA_Run__c run = [
            SELECT Cases_Flagged__c, Cases_Escalated__c, Failures__c, Error_Sample__c FROM SLA_Run__c
        ];
        System.assertEquals(3, run.Cases_Flagged__c);
        System.assertEquals(2, run.Cases_Escalated__c, 'So 2 precisaram ser escalados; o terceiro ja estava');
        System.assertEquals(0, run.Failures__c);
        System.assertEquals(null, run.Error_Sample__c);
    }

    @IsTest
    static void anEmptyRunLeavesNoSummary() {
        insert CaseTestDataFactory.build('Low', 'Billing');

        runBatch();

        System.assertEquals(0, [SELECT COUNT() FROM SLA_Run__c]);
    }

    @IsTest
    static void flaggingIsAuditedSoTheTrailExplainsWhy() {
        Case c = overdue('Billing');

        runBatch();

        List<Case_Audit__c> audits = [
            SELECT New_Value__c FROM Case_Audit__c WHERE Case__c = :c.Id AND Field_Name__c = 'SLA_Breached__c'
        ];
        System.assertEquals(1, audits.size());
        System.assertEquals('true', audits[0].New_Value__c);
    }

    @IsTest
    static void aFullScopeEnqueuesASingleWebhookJobWithoutBreakingTheAsyncLimit() {
        CaseWebhookService.enabledInTests = true;
        WebhookMock mock = new WebhookMock();
        Test.setMock(HttpCalloutMock.class, mock);
        List<Case> cases = CaseTestDataFactory.buildMany(CaseSlaBreachBatch.SCOPE_SIZE, 'Medium', 'Question');
        insert cases;
        List<Case> late = new List<Case>();
        for (Case c : cases) {
            late.add(new Case(Id = c.Id, Resolution_Due_At__c = System.now().addHours(-1)));
        }
        update late;

        runBatch();

        System.assertEquals(CaseSlaBreachBatch.SCOPE_SIZE, mock.calls, 'Um webhook por caso escalado, num unico job');
        System.assertEquals(CaseSlaBreachBatch.SCOPE_SIZE,
            [SELECT COUNT() FROM Case WHERE SLA_Breached__c = true AND Status = 'Escalated']);
    }

    @IsTest
    static void schedulerCreatesFourJobsAndIsIdempotent() {
        Test.startTest();
        CaseSlaBreachScheduler.scheduleEvery15Minutes();
        CaseSlaBreachScheduler.scheduleEvery15Minutes();
        Test.stopTest();

        String pattern = CaseSlaBreachScheduler.JOB_PREFIX + '%';
        System.assertEquals(4, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern],
            'Chamar duas vezes nao duplica os jobs');
    }

    @IsTest
    static void abortRemovesTheScheduledJobs() {
        CaseSlaBreachScheduler.scheduleEvery15Minutes();

        CaseSlaBreachScheduler.abortScheduled();

        String pattern = CaseSlaBreachScheduler.JOB_PREFIX + '%';
        System.assertEquals(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern]);
    }

    @IsTest
    static void theScheduledJobRunsTheBatch() {
        Case c = overdue('Billing');

        Test.startTest();
        new CaseSlaBreachScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(true, [SELECT SLA_Breached__c FROM Case WHERE Id = :c.Id].SLA_Breached__c);
    }
}
