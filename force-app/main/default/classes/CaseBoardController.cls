/**
 * Dados do painel de casos (LWC caseBoard). Tudo roda em USER_MODE, entao
 * respeita as permissoes de objeto e de campo de quem esta usando o painel.
 */
public with sharing class CaseBoardController {

    private static final Integer MAX_ROWS = 200;

    public class CaseRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String category;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Integer escalationLevel;
        @AuraEnabled public Datetime resolutionDueAt;
        @AuraEnabled public Boolean isOverdue;
    }

    public class BoardMetrics {
        @AuraEnabled public Integer open;
        @AuraEnabled public Integer escalated;
        @AuraEnabled public Integer overdue;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // Parametros simples de proposito: um objeto de filtros chegava vazio pelo Aura,
    // e a consulta devolvia tudo sem aplicar filtro nenhum.
    @AuraEnabled
    public static List<CaseRow> getCases(
        String status,
        String priority,
        String category,
        String searchTerm,
        Boolean onlyOverdue
    ) {
        Datetime now = System.now();

        List<String> conditions = new List<String>();
        Map<String, Object> binds = new Map<String, Object>{ 'now' => now };

        if (String.isNotBlank(status)) {
            conditions.add('Status = :status');
            binds.put('status', status);
        }
        if (String.isNotBlank(priority)) {
            conditions.add('Priority = :priority');
            binds.put('priority', priority);
        }
        if (String.isNotBlank(category)) {
            conditions.add('Category__c = :category');
            binds.put('category', category);
        }
        if (String.isNotBlank(searchTerm)) {
            conditions.add('(Subject LIKE :pattern OR CaseNumber LIKE :pattern)');
            binds.put('pattern', '%' + escapeLike(searchTerm.trim()) + '%');
        }
        if (onlyOverdue == true) {
            conditions.add('IsClosed = false AND Resolution_Due_At__c < :now');
        }

        // Os campos e a ordenacao sao fixos; so valores do usuario entram, e como bind.
        String soql = 'SELECT Id, CaseNumber, Subject, Status, Priority, Category__c, Owner.Name,'
            + ' Escalation_Level__c, Resolution_Due_At__c, IsClosed FROM Case'
            + (conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND '))
            + ' ORDER BY Resolution_Due_At__c ASC NULLS LAST, CreatedDate DESC LIMIT ' + MAX_ROWS;

        List<CaseRow> rows = new List<CaseRow>();
        for (Case c : (List<Case>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            CaseRow row = new CaseRow();
            row.id = c.Id;
            row.caseNumber = c.CaseNumber;
            row.subject = c.Subject;
            row.status = c.Status;
            row.priority = c.Priority;
            row.category = c.Category__c;
            row.ownerName = c.Owner.Name;
            row.escalationLevel = c.Escalation_Level__c == null ? 0 : c.Escalation_Level__c.intValue();
            row.resolutionDueAt = c.Resolution_Due_At__c;
            row.isOverdue = !c.IsClosed && c.Resolution_Due_At__c != null && c.Resolution_Due_At__c < now;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static BoardMetrics getMetrics() {
        Datetime now = System.now();
        BoardMetrics metrics = new BoardMetrics();
        metrics.open = [SELECT COUNT() FROM Case WHERE IsClosed = false WITH USER_MODE];
        metrics.escalated = [SELECT COUNT() FROM Case WHERE Status = 'Escalated' WITH USER_MODE];
        metrics.overdue = [
            SELECT COUNT() FROM Case
            WHERE IsClosed = false AND Resolution_Due_At__c < :now
            WITH USER_MODE
        ];
        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<Option>> getFilterOptions() {
        return new Map<String, List<Option>>{
            'status' => toOptions(Case.Status.getDescribe().getPicklistValues()),
            'priority' => toOptions(Case.Priority.getDescribe().getPicklistValues()),
            'category' => toOptions(Case.Category__c.getDescribe().getPicklistValues())
        };
    }

    private static List<Option> toOptions(List<Schema.PicklistEntry> entries) {
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    // % e _ digitados pelo usuario sao texto, nao curingas do LIKE.
    private static String escapeLike(String text) {
        return text.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}
