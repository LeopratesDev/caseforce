@IsTest
private class CaseRestApiTest {

    private static void callPost(String body) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/caseforce/v1/cases';
        request.httpMethod = 'POST';
        request.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = request;
        RestContext.response = new RestResponse();
        CaseRestApi.createCase();
    }

    private static void callGet(String path) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/caseforce/v1/cases' + path;
        request.httpMethod = 'GET';
        RestContext.request = request;
        RestContext.response = new RestResponse();
        CaseRestApi.getCase();
    }

    private static Map<String, Object> responseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    private static Integer status() {
        return RestContext.response.statusCode;
    }

    private static String firstError() {
        return String.valueOf(((List<Object>) responseBody().get('errors'))[0]);
    }

    @IsTest
    static void createsACaseRoutedWithDueDates() {
        callPost('{"subject":"Cobranca duplicada","description":"Fatura de outubro","category":"Billing","priority":"High"}');

        System.assertEquals(201, status(), RestContext.response.responseBody.toString());
        Map<String, Object> body = responseBody();
        System.assertEquals('New', body.get('status'));
        System.assertEquals('High', body.get('priority'));
        System.assertNotEquals(null, body.get('responseDueAt'), 'O trigger calcula o prazo');
        System.assertNotEquals(null, body.get('resolutionDueAt'));

        String caseNumber = (String) body.get('caseNumber');
        // Owner.Name vem nulo para fila em contexto de teste; o dono e conferido pelo Id.
        Case saved = [SELECT Origin, Subject, OwnerId FROM Case WHERE CaseNumber = :caseNumber];
        System.assertEquals(CaseTestDataFactory.queueId('Billing_Support'), saved.OwnerId, 'O trigger roteia pela categoria');
        System.assertEquals('Web', saved.Origin);
        System.assertEquals('Cobranca duplicada', saved.Subject);
    }

    @IsTest
    static void defaultsPriorityToMediumAndAllowsNoCategory() {
        callPost('{"subject":"Duvida simples"}');

        System.assertEquals(201, status());
        System.assertEquals('Medium', responseBody().get('priority'));
    }

    @IsTest
    static void linksTheContactFoundByEmail() {
        Account account = new Account(Name = 'Cliente Teste');
        insert account;
        Contact contact = new Contact(LastName = 'Silva', Email = 'cliente@example.com', AccountId = account.Id);
        insert contact;

        callPost('{"subject":"Ajuda","contactEmail":"cliente@example.com"}');

        Id caseId = (Id) responseBody().get('id');
        Case saved = [SELECT ContactId, AccountId FROM Case WHERE Id = :caseId];
        System.assertEquals(contact.Id, saved.ContactId);
        System.assertEquals(account.Id, saved.AccountId);
    }

    @IsTest
    static void stillCreatesTheCaseWhenTheEmailMatchesNoContact() {
        callPost('{"subject":"Ajuda","contactEmail":"ninguem@example.com"}');

        System.assertEquals(201, status());
        Id caseId = (Id) responseBody().get('id');
        System.assertEquals(null, [SELECT ContactId FROM Case WHERE Id = :caseId].ContactId);
    }

    @IsTest
    static void rejectsMissingSubject() {
        callPost('{"category":"Billing"}');

        System.assertEquals(400, status());
        System.assert(firstError().contains('subject'), firstError());
        System.assertEquals(0, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void rejectsUnknownCategoryAndPriorityListingTheValidOnes() {
        callPost('{"subject":"x","category":"Cobranca"}');
        System.assertEquals(400, status());
        System.assert(firstError().contains('Billing'), 'Deve listar as categorias validas: ' + firstError());

        callPost('{"subject":"x","priority":"Urgent"}');
        System.assertEquals(400, status());
        System.assert(firstError().contains('High'), firstError());
    }

    @IsTest
    static void rejectsSubjectOverTheLimit() {
        callPost('{"subject":"' + 'a'.repeat(256) + '"}');

        System.assertEquals(400, status());
        System.assert(firstError().contains('255'), firstError());
    }

    @IsTest
    static void rejectsMalformedAndEmptyBodies() {
        callPost('{isto nao e json');
        System.assertEquals(400, status());

        callPost(null);
        System.assertEquals(400, status(), 'Sem corpo tambem e requisicao invalida, nao erro 500');
    }

    @IsTest
    static void returnsACaseByNumber() {
        Case c = CaseTestDataFactory.build('High', 'Technical');
        insert c;
        String caseNumber = [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;

        callGet('/' + caseNumber);

        System.assertEquals(200, status());
        Map<String, Object> body = responseBody();
        System.assertEquals(caseNumber, body.get('caseNumber'));
        System.assertEquals(CaseTestDataFactory.queueId('Technical_Support'), [SELECT OwnerId FROM Case WHERE Id = :c.Id].OwnerId);
        System.assertEquals(0, body.get('escalationLevel'));
    }

    @IsTest
    static void returnsNotFoundForUnknownNumber() {
        callGet('/99999999');

        System.assertEquals(404, status());
        System.assert(firstError().contains('99999999'));
    }

    @IsTest
    static void asksForTheNumberWhenNoneIsGiven() {
        callGet('');

        System.assertEquals(400, status());
    }

    @IsTest
    static void integrationUserCreatesAndReadsButCannotEscapeItsPermissions() {
        User integrationUser = CaseTestDataFactory.userWith('CaseForce_Integration');

        System.runAs(integrationUser) {
            callPost('{"subject":"Aberto por integracao","category":"Access","priority":"Low"}');

            System.assertEquals(201, status(), RestContext.response.responseBody.toString());
            callGet('/' + responseBody().get('caseNumber'));
            System.assertEquals(200, status(), 'Quem cria tambem consegue consultar');
        }
    }

}
