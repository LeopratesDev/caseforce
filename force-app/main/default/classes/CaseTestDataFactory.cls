@IsTest
public class CaseTestDataFactory {

    public static final List<String> CATEGORIES = new List<String>{
        'Billing', 'Technical', 'Access', 'Question', 'Other'
    };

    public static Case build(String priority, String category) {
        return new Case(
            Subject = 'Caso de teste ' + category,
            Origin = 'Web',
            Priority = priority,
            Category__c = category
        );
    }

    public static List<Case> buildMany(Integer count, String priority, String category) {
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            cases.add(build(priority, category));
        }
        return cases;
    }

    // Usuario padrao (nao admin) so com o permission set pedido, para provar o que ele realmente libera.
    public static User userWith(String permissionSetName) {
        Id profileId = [
            SELECT Id FROM Profile
            WHERE UserType = 'Standard' AND PermissionsModifyAllData = false AND UserLicense.Name = 'Salesforce'
            LIMIT 1
        ].Id;
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
        User u = new User(
            Alias = 'u' + unique.left(6),
            Email = 'user' + unique + '@caseforce.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = permissionSetName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Sao_Paulo',
            ProfileId = profileId,
            Username = 'user' + unique + '@caseforce.example.com'
        );
        // Objetos de configuracao (User, PermissionSetAssignment) em contexto proprio: sem isso,
        // inserir um Case logo depois na mesma transacao falha com MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName].Id
            );
        }
        return u;
    }

    public static Id queueId(String developerName) {
        return [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }
}
