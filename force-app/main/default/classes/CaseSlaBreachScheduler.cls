/**
 * Agenda o CaseSlaBreachBatch. O agendador do Salesforce nao aceita "a cada 15 minutos"
 * numa unica expressao, entao sao 4 jobs, um por quarto de hora.
 *
 * Para ligar (uma vez, no Execute Anonymous):  CaseSlaBreachScheduler.scheduleEvery15Minutes();
 * Para desligar:                               CaseSlaBreachScheduler.abortScheduled();
 */
public with sharing class CaseSlaBreachScheduler implements Schedulable {

    @TestVisible private static final String JOB_PREFIX = 'CaseForce SLA breach check, minute ';
    private static final List<String> MINUTES = new List<String>{ '0', '15', '30', '45' };

    public void execute(SchedulableContext context) {
        Database.executeBatch(new CaseSlaBreachBatch(), CaseSlaBreachBatch.SCOPE_SIZE);
    }

    /** Idempotente: chamar de novo troca os jobs antigos pelos novos, sem duplicar. */
    public static void scheduleEvery15Minutes() {
        abortScheduled();
        for (String minute : MINUTES) {
            System.schedule(JOB_PREFIX + minute, '0 ' + minute + ' * * * ?', new CaseSlaBreachScheduler());
        }
    }

    public static void abortScheduled() {
        String pattern = JOB_PREFIX + '%';
        for (CronTrigger job : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern]) {
            System.abortJob(job.Id);
        }
    }
}
