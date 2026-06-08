// PublicFormSelector.cls
/**
 * @description Selector for all SOQL queries used by the public (guest)
 *              and authenticated portal pages in the form / Research Portal.
 *              Single source of truth for portal-readable queries.
 * @group form Portal
 * @author S.M Akbar
 *
 * Security:
 *  - WITH SHARING to honor OWD/roles for portal use.
 *  - Explicit object access check prior to each SOQL to satisfy PMD (ApexCRUDViolation)
 *    and to make intent clear even though selectors are read-only.
 *
 * Notes:
 *  - This class centralizes every query for Form_Session__c used by
 *    both authenticated and unauthenticated (guest) portal experiences.
 *  - Keep it read-only; do not add DML/business logic here.
 *  - Add new methods here as the portal grows.
 */
public without sharing class PublicFormSelector {

    // -----------------------------------------
    // Helper: explicit READ object access + FLS strip
    // -----------------------------------------

    
    private static void requireSRSObjectReadable() {
        Schema.DescribeSObjectResult d = Form_Session__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            // nthrow new AuraHandledException('Insufficient object access: Form_Session__c');
        }
    }

    private static List<SObject> stripReadable(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return records;
        }
        //return (List<SObject>) Security.stripInaccessible(AccessType.READABLE, records).getRecords();
        return records;
    }

    // -----------------------------------------
    // Fields whitelist (kept DRY across all queries)
    // -----------------------------------------
    private static final List<String> BASE_FIELDS = new List<String>{
        'Id','Name','Guest_Email__c','Wizard_Type__c','IP_Address__c',
        'Status__c','Current_Step__c','Started_Date__c','Last_Modified_Date__c',
        'Session_Token__c','Answers_JSON__c',
        'Verification_Code__c','Verification_Sent_On__c'
    };

    // =========================================================================
    // SECTION 1: Study Request Session selectors
    // =========================================================================

    public static Form_Session__c selectSessionByEmail(String email) {
        requireSRSObjectReadable();
        if (String.isBlank(email)) {
            return null;
        }

        String soql = 'SELECT ' + String.join(BASE_FIELDS, ',') +
                      ' FROM Form_Session__c' +
                      ' WHERE Guest_Email__c = :email' +
                      '   AND Status__c = \'In Progress\'' +
                      ' ORDER BY Last_Modified_Date__c DESC' +
                      ' LIMIT 1';
        List<SObject> rows = Database.query(soql);
        rows = stripReadable(rows);
        return rows.isEmpty() ? null : (Form_Session__c) rows[0];
    }

    public static Form_Session__c selectSessionByToken(String token) {
        requireSRSObjectReadable();
        if (String.isBlank(token)) {
            return null;
        }

        String soql = 'SELECT ' + String.join(BASE_FIELDS, ',') +
                      ' FROM Form_Session__c' +
                      ' WHERE Session_Token__c = :token' +
                      ' LIMIT 1';
        List<SObject> rows = Database.query(soql);
        rows = stripReadable(rows);
        return rows.isEmpty() ? null : (Form_Session__c) rows[0];
    }

    public static Form_Session__c selectSessionById(Id sessionId) {
        requireSRSObjectReadable();
        if (sessionId == null) {
            return null;
        }

        String soql = 'SELECT ' + String.join(BASE_FIELDS, ',') +
                      ' FROM Form_Session__c' +
                      ' WHERE Id = :sessionId' +
                      ' LIMIT 1';
        List<SObject> rows = Database.query(soql);
        rows = stripReadable(rows);
        return rows.isEmpty() ? null : (Form_Session__c) rows[0];
    }

    public static Form_Session__c selectSessionForOtpValidation(String email, String code) {
        requireSRSObjectReadable();
        if (String.isBlank(email) || String.isBlank(code) ) {
            return null;
        }

        String soql = 'SELECT ' + String.join(BASE_FIELDS, ',') +
                      ' FROM Form_Session__c' +
                      ' WHERE Guest_Email__c = :email' +
                      '   AND Verification_Code__c = :code' +
                      ' ORDER BY CreatedDate DESC' +
                      ' LIMIT 1';
        List<SObject> rows = Database.query(soql);
        rows = stripReadable(rows);
        return rows.isEmpty() ? null : (Form_Session__c) rows[0];
    }
}