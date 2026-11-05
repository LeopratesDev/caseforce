/**
 * API REST de entrada: sistemas externos abrem e consultam casos.
 *
 *   POST /services/apexrest/caseforce/v1/cases          cria um caso
 *   GET  /services/apexrest/caseforce/v1/cases/{numero} consulta um caso
 *
 * Roda com as permissoes de quem chama (USER_MODE), entao o usuario de
 * integracao so faz o que o permission set CaseForce_Integration libera.
 */
@RestResource(urlMapping='/caseforce/v1/cases/*')
global with sharing class CaseRestApi {

    private static final String DEFAULT_PRIORITY = 'Medium';
    private static final String ORIGIN_API = 'Web';
    private static final Integer SUBJECT_MAX_LENGTH = 255;

    global class CreateRequest {
        global String subject;
        global String description;
        global String category;
        global String priority;
        global String contactEmail;
    }

    @HttpPost
    global static void createCase() {
        CreateRequest request;
        try {
            request = (CreateRequest) JSON.deserialize(RestContext.request.requestBody.toString(), CreateRequest.class);
        } catch (Exception e) {
            respondError(400, new List<String>{ 'Corpo da requisicao nao e um JSON valido.' });
            return;
        }

        List<String> problems = validate(request);
        if (!problems.isEmpty()) {
            respondError(400, problems);
            return;
        }

        Case newCase = new Case(
            Subject = request.subject.trim(),
            Description = request.description,
            Category__c = blankToNull(request.category),
            Priority = String.isBlank(request.priority) ? DEFAULT_PRIORITY : request.priority,
            Origin = ORIGIN_API
        );
        attachContact(newCase, request.contactEmail);

        Database.SaveResult result = Database.insert(newCase, false, AccessLevel.USER_MODE);
        if (!result.isSuccess()) {
            Database.Error error = result.getErrors()[0];
            Boolean denied = error.getStatusCode() == StatusCode.INSUFFICIENT_ACCESS_OR_READONLY
                || error.getStatusCode() == StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY;
            respondError(denied ? 403 : 400, new List<String>{ error.getMessage() });
            return;
        }

        // Le de volta: o trigger ja roteou o caso e calculou os prazos.
        respond(201, toResponse(queryById(newCase.Id)));
    }

    @HttpGet
    global static void getCase() {
        String requestUri = RestContext.request.requestURI;
        String caseNumber = requestUri.substring(requestUri.lastIndexOf('/') + 1);
        if (String.isBlank(caseNumber) || caseNumber == 'cases') {
            respondError(400, new List<String>{ 'Informe o numero do caso: /caseforce/v1/cases/{numero}.' });
            return;
        }

        List<Case> found = [
            SELECT Id, CaseNumber, Status, Priority, Category__c, Escalation_Level__c,
                   Response_Due_At__c, Resolution_Due_At__c, Owner.Name
            FROM Case
            WHERE CaseNumber = :caseNumber
            WITH USER_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            respondError(404, new List<String>{ 'Caso ' + caseNumber + ' nao encontrado.' });
            return;
        }
        respond(200, toResponse(found[0]));
    }

    private static List<String> validate(CreateRequest request) {
        List<String> problems = new List<String>();
        if (request == null || String.isBlank(request.subject)) {
            problems.add('subject e obrigatorio.');
            return problems;
        }
        if (request.subject.trim().length() > SUBJECT_MAX_LENGTH) {
            problems.add('subject aceita no maximo ' + SUBJECT_MAX_LENGTH + ' caracteres.');
        }
        if (String.isNotBlank(request.category) && !picklistValues(Case.Category__c).contains(request.category)) {
            problems.add('category invalida. Use: ' + String.join(new List<String>(picklistValues(Case.Category__c)), ', ') + '.');
        }
        if (String.isNotBlank(request.priority) && !picklistValues(Case.Priority).contains(request.priority)) {
            problems.add('priority invalida. Use: ' + String.join(new List<String>(picklistValues(Case.Priority)), ', ') + '.');
        }
        return problems;
    }

    private static Set<String> picklistValues(Schema.SObjectField field) {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static void attachContact(Case newCase, String email) {
        if (String.isBlank(email)) {
            return;
        }
        List<Contact> contacts = [SELECT Id, AccountId FROM Contact WHERE Email = :email WITH USER_MODE LIMIT 1];
        if (!contacts.isEmpty()) {
            newCase.ContactId = contacts[0].Id;
            newCase.AccountId = contacts[0].AccountId;
        }
    }

    private static Case queryById(Id caseId) {
        return [
            SELECT Id, CaseNumber, Status, Priority, Category__c, Escalation_Level__c,
                   Response_Due_At__c, Resolution_Due_At__c, Owner.Name
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
        ];
    }

    private static Map<String, Object> toResponse(Case c) {
        return new Map<String, Object>{
            'id' => c.Id,
            'caseNumber' => c.CaseNumber,
            'status' => c.Status,
            'priority' => c.Priority,
            'category' => c.Category__c,
            'queue' => c.Owner.Name,
            'escalationLevel' => c.Escalation_Level__c == null ? 0 : c.Escalation_Level__c.intValue(),
            'responseDueAt' => c.Response_Due_At__c,
            'resolutionDueAt' => c.Resolution_Due_At__c
        };
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value;
    }

    private static void respondError(Integer statusCode, List<String> messages) {
        respond(statusCode, new Map<String, Object>{ 'errors' => messages });
    }

    private static void respond(Integer statusCode, Object body) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
