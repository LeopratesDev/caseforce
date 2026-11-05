@IsTest
private class CaseClosingValidationTest {

    @IsTest
    static void blocksClosingWithoutResolutionSummary() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;

        c.Status = 'Closed';
        Database.SaveResult result = Database.update(c, false);

        System.assert(!result.isSuccess(), 'Nao pode fechar sem resumo');
        System.assert(result.getErrors()[0].getMessage().contains('resumo'), result.getErrors()[0].getMessage());
    }

    @IsTest
    static void allowsClosingWithResolutionSummary() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        insert c;

        c.Status = 'Closed';
        c.Resolution_Summary__c = 'Cobranca duplicada estornada.';
        update c;

        System.assertEquals('Closed', [SELECT Status FROM Case WHERE Id = :c.Id].Status);
    }

    @IsTest
    static void doesNotBlockEditingAlreadyClosedCase() {
        Case c = CaseTestDataFactory.build('Medium', 'Billing');
        c.Status = 'Closed';
        c.Resolution_Summary__c = 'Resolvido.';
        insert c;

        c.Subject = 'Assunto corrigido depois de fechar';
        update c;

        System.assertEquals('Assunto corrigido depois de fechar', [SELECT Subject FROM Case WHERE Id = :c.Id].Subject);
    }
}
