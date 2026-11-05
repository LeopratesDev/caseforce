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

    public static Id queueId(String developerName) {
        return [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }
}
