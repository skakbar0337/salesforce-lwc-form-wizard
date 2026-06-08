// FormWizardService.cls (refactor: constants + small helpers, no behavior change)
public without sharing class FormWizardService {

    public class FormWizardServiceException extends Exception {}

    // ===== Constants (remove magic numbers) =====
    private static final Integer TOKEN_LENGTH = 32;
    private static final Integer OTP_MIN  = 100000;
	private static final Integer OTP_SPAN = 900000;

    // -----------------------------
    // DTOs
    // -----------------------------
    public class CreateSessionInput {
        @AuraEnabled public String  email;
        @AuraEnabled public String  wizardType;
        @AuraEnabled public String  ipAddress;
        @AuraEnabled public Integer startingStep; // optional
    }

    public class UpdateSessionInput {
        @AuraEnabled public String  sessionToken;
        @AuraEnabled public Integer currentStep;
        @AuraEnabled public String  answersJson;
        @AuraEnabled public String  status; // In Progress, Completed, Expired, Abandoned
    }
    public class LoadSessionInput {
        @AuraEnabled public String sessionToken;
        @AuraEnabled public String email; // fallback
    }
    public class CreateOnsiteSessionInput {
        @AuraEnabled public String email;
        @AuraEnabled public String wizardType;
        @AuraEnabled public String answersJson;
        @AuraEnabled public String ipAddress;
    }
    public class ValidateSessionInput {
        @AuraEnabled public String email;
        @AuraEnabled public String otp; // For verification; null = send new OTP
        @AuraEnabled public Boolean requestNewOtp; // Explicit flag to send new OTP
    }
    public class ValidateSessionResult {
        @AuraEnabled public Boolean sent;
        @AuraEnabled public Boolean verified;
        @AuraEnabled public String  sessionToken;
        @AuraEnabled public String  message;
        @AuraEnabled public Form_Session__c sessionData; // Full session data on successful verification
    }


    public static String getFormConfigByTitle(String wizardTitle) {
        List<Dynamic_Form_Config__c> configs = [
            SELECT Form_Config__c, Title__c
            FROM Dynamic_Form_Config__c
            WHERE Title__c = :wizardTitle
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new FormWizardServiceException('No form configuration found for wizard title: ' + wizardTitle);
        }

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configs[0].Form_Config__c);
        return (String) config.get('submissionController');
    }

    public static void setSessionStatus(string sessionId, string status) {
        Form_Session__c session = new Form_Session__c(
            Id = sessionId,
            Status__c = status
        );
        update session;
    }
    
    // returns session name
    public static  Form_Session__c createAndSubmitSession(FormWizardStateModel stateModel) {

        Form_Session__c newSession = new Form_Session__c(
           Wizard_Type__c  = stateModel.formType,
           Answers_JSON__c = JSON.serialize(stateModel.answers),
           Guest_Email__c  = stateModel.primaryEmail,
           Current_Step__c = 1,
           Status__c       = 'Submitted'
        );
        insert newSession;

        // query for session name
        newSession = loadSessionById(newSession.Id);

        return newSession;
    }

    public static Form_Session__c loadSessionById(string sessionId) {
        List<Form_Session__c> sessions = [
            SELECT Id, Session_Token__c, Name,
                   Answers_JSON__c, Wizard_Type__c,
                   Guest_Email__c, Current_Step__c, Status__c 
            FROM   Form_Session__c 
            WHERE  Id = :sessionId LIMIT 1];
        return sessions.isEmpty() ? null : sessions[0];
    }

    // -----------------------------
    // Small utility helpers (no behavior change)
    // -----------------------------
    public static String generateToken(String email, Datetime startedAt, String nameVal) {
        String data = email + '|' + String.valueOf(startedAt.getTime()) + '|' + nameVal;
        Blob   b    = Crypto.generateDigest('SHA-256', Blob.valueOf(data));
        String hex  = EncodingUtil.convertToHex(b);
        return hex.substring(0, TOKEN_LENGTH);
    }

    public static String generateOtp() {
        Long rnd = Crypto.getRandomLong();
        if (rnd < 0) rnd = -rnd;                       // avoid negative
        Integer code = Integer.valueOf(Math.mod(rnd, OTP_SPAN)) + OTP_MIN; // 100000..999999
        return String.valueOf(code);                   // always 6 digits
    }


    public static void handleAndRethrow(Exception ex, String method, String context) {
        ApexLog.logException(ex, 'FormWizardService', method, context);
        throw ex;
    }
}