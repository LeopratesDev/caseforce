/**
 * Prazos de SLA e primeira resposta. As metas vem de SLA_Policy__mdt, indexadas
 * pela prioridade, e sao contadas em minutos corridos (sem horario comercial).
 */
public with sharing class CaseSlaService {

    private static final String DEFAULT_PRIORITY = 'Medium';
    private static final String STATUS_NEW = 'New';
    private static final String STATUS_CLOSED = 'Closed';
    private static final String STATUS_ESCALATED = 'Escalated';

    /**
     * Calcula Response_Due_At__c e Resolution_Due_At__c na criacao e sempre que
     * a prioridade muda. Depois da primeira resposta, o prazo de resposta nao
     * se mexe mais.
     */
    public static void setDueDates(List<Case> cases, Map<Id, Case> oldCases) {
        for (Case c : cases) {
            Case old = oldCases == null ? null : oldCases.get(c.Id);
            Boolean isNew = old == null;

            if (c.Status == STATUS_CLOSED || (!isNew && old.Priority == c.Priority)) {
                continue;
            }

            SLA_Policy__mdt policy = policyFor(c.Priority);
            if (policy == null) {
                continue;
            }

            Datetime startedAt = isNew ? System.now() : c.CreatedDate;
            c.Resolution_Due_At__c = startedAt.addMinutes(policy.Resolution_Minutes__c.intValue());
            if (c.First_Response_At__c == null) {
                c.Response_Due_At__c = startedAt.addMinutes(policy.Response_Minutes__c.intValue());
            }
        }
    }

    /**
     * Primeira resposta = o caso chega pela primeira vez a um status que nao seja
     * "New" nem "Escalated". Escalar um caso que ninguem tocou (a mao ou pelo Batch de
     * SLA) nao e responder o cliente. Grava uma vez so; mudar de status depois nao
     * altera o valor.
     */
    public static void markFirstResponse(List<Case> cases, Map<Id, Case> oldCases) {
        for (Case c : cases) {
            Case old = oldCases.get(c.Id);
            Boolean answered = c.Status != old.Status && c.Status != STATUS_NEW && c.Status != STATUS_ESCALATED;
            if (answered && c.First_Response_At__c == null) {
                c.First_Response_At__c = System.now();
            }
        }
    }

    private static SLA_Policy__mdt policyFor(String priority) {
        return SLA_Policy__mdt.getInstance(String.isBlank(priority) ? DEFAULT_PRIORITY : priority);
    }
}
