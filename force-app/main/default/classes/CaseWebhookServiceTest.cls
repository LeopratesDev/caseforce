@IsTest
private class CaseWebhookServiceTest {

    private class WebhookMock implements HttpCalloutMock {
        Integer statusCode;
        Boolean throwError;
        List<HttpRequest> requests = new List<HttpRequest>();

        WebhookMock(Integer statusCode, Boolean throwError) {
            this.statusCode = statusCode;
            this.throwError = throwError;
        }

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            if (throwError) {
                throw new CalloutException('Connection reset');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody('{}');
            return response;
        }
    }

    private static Case newEscalatableCase() {
        Case c = CaseTestDataFactory.build('Low', 'Billing');
        c.Subject = 'Dado sensivel do cliente: CPF 000.000.000-00';
        c.Description = 'Texto livre que nao pode sair da org';
        insert c;
        return c;
    }

    private static List<Case_Audit__c> webhookAudits(Id caseId) {
        return [SELECT New_Value__c FROM Case_Audit__c WHERE Case__c = :caseId AND Field_Name__c = 'Webhook'];
    }

    @IsTest
    static void escalationPostsToTheNamedCredentialAndRecordsTheResult() {
        CaseWebhookService.enabledInTests = true;
        WebhookMock mock = new WebhookMock(200, false);
        Test.setMock(HttpCalloutMock.class, mock);
        Case c = newEscalatableCase();

        Test.startTest();
        update new Case(Id = c.Id, Status = 'Escalated');
        Test.stopTest();

        System.assertEquals(1, mock.requests.size());
        HttpRequest sent = mock.requests[0];
        System.assertEquals('callout:CaseForce_Webhook/post', sent.getEndpoint());
        System.assertEquals('POST', sent.getMethod());
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(sent.getBody());
        System.assertEquals('case.escalated', payload.get('event'));
        System.assertEquals(1, payload.get('escalationLevel'), 'Le o caso depois do Flow: ja com o nivel novo');
        System.assertEquals('Medium', payload.get('priority'));
        // Owner.Name vem nulo para fila em contexto de teste, entao o campo queue so e conferido na org.
        System.assert(payload.containsKey('queue'));
        System.assertEquals(CaseTestDataFactory.queueId('Escalation_Support'), [SELECT OwnerId FROM Case WHERE Id = :c.Id].OwnerId);

        List<Case_Audit__c> audits = webhookAudits(c.Id);
        System.assertEquals(1, audits.size());
        System.assertEquals('HTTP 200', audits[0].New_Value__c);
    }

    @IsTest
    static void payloadNeverCarriesFreeText() {
        CaseWebhookService.enabledInTests = true;
        WebhookMock mock = new WebhookMock(200, false);
        Test.setMock(HttpCalloutMock.class, mock);
        Case c = newEscalatableCase();

        Test.startTest();
        update new Case(Id = c.Id, Status = 'Escalated');
        Test.stopTest();

        String body = mock.requests[0].getBody();
        System.assert(!body.contains('CPF'), 'Assunto nao pode sair: ' + body);
        System.assert(!body.contains('Texto livre'), 'Descricao nao pode sair: ' + body);
        System.assert(!body.contains('subject') && !body.contains('description'));
    }

    @IsTest
    static void recordsHttpFailuresInTheAuditTrail() {
        CaseWebhookService.enabledInTests = true;
        Test.setMock(HttpCalloutMock.class, new WebhookMock(500, false));
        Case c = newEscalatableCase();

        Test.startTest();
        update new Case(Id = c.Id, Status = 'Escalated');
        Test.stopTest();

        System.assertEquals('HTTP 500', webhookAudits(c.Id)[0].New_Value__c);
    }

    @IsTest
    static void aCalloutExceptionNeverBreaksTheEscalation() {
        CaseWebhookService.enabledInTests = true;
        Test.setMock(HttpCalloutMock.class, new WebhookMock(0, true));
        Case c = newEscalatableCase();

        Test.startTest();
        update new Case(Id = c.Id, Status = 'Escalated');
        Test.stopTest();

        System.assertEquals('Escalated', [SELECT Status FROM Case WHERE Id = :c.Id].Status, 'O caso escala mesmo sem o webhook');
        System.assert(webhookAudits(c.Id)[0].New_Value__c.startsWith('Erro:'), 'A falha fica registrada');
    }

    @IsTest
    static void onlyTheTransitionToEscalatedCallsTheWebhook() {
        CaseWebhookService.enabledInTests = true;
        WebhookMock mock = new WebhookMock(200, false);
        Test.setMock(HttpCalloutMock.class, mock);
        Case c = newEscalatableCase();

        Test.startTest();
        update new Case(Id = c.Id, Status = 'Working');
        update new Case(Id = c.Id, Subject = 'Assunto novo');
        Test.stopTest();

        System.assertEquals(0, mock.requests.size());
        System.assertEquals(0, webhookAudits(c.Id).size());
    }

    @IsTest
    static void editingAnAlreadyEscalatedCaseDoesNotCallAgain() {
        // Escala com o webhook desligado nos testes, para nao contar essa chamada.
        Case c = newEscalatableCase();
        update new Case(Id = c.Id, Status = 'Escalated');

        CaseWebhookService.enabledInTests = true;
        WebhookMock mock = new WebhookMock(200, false);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        update new Case(Id = c.Id, Subject = 'Assunto novo');
        Test.stopTest();

        System.assertEquals(0, mock.requests.size());
    }

    @IsTest
    static void largeBatchesAreSplitIntoJobsOfAtMostOneHundredCallouts() {
        CaseWebhookService.enabledInTests = true;
        WebhookMock mock = new WebhookMock(200, false);
        Test.setMock(HttpCalloutMock.class, mock);
        List<Case> cases = CaseTestDataFactory.buildMany(120, 'Low', 'Question');
        insert cases;
        List<Case> escalate = new List<Case>();
        for (Case c : cases) {
            escalate.add(new Case(Id = c.Id, Status = 'Escalated'));
        }

        Test.startTest();
        update escalate;
        Test.stopTest();

        System.assertEquals(120, mock.requests.size());
        System.assertEquals(120, [SELECT COUNT() FROM Case_Audit__c WHERE Field_Name__c = 'Webhook' AND New_Value__c = 'HTTP 200']);
    }

    @IsTest
    static void staysQuietWhenDisabledSoOtherTestsNeverTouchTheNetwork() {
        // enabledInTests fica no padrao (false): nenhum job e enfileirado.
        Case c = newEscalatableCase();

        Test.startTest();
        update new Case(Id = c.Id, Status = 'Escalated');
        Test.stopTest();

        System.assertEquals(0, webhookAudits(c.Id).size());
    }
}
