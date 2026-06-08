public class FormWizardStateModel {

    public String primaryEmail;
    public String sessionName;
    public String sessionToken;
    public String sessionRecordId;
    public String formType;
    public String currentStep;
    public String answers;
    private Form_Session__c sessionRecord;

    public Map<String, Object> getAnswerMap() {
        if (String.isBlank(answers)) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(answers);
    }

    // construct from study session record
    public FormWizardStateModel(Form_Session__c session) {
        this.sessionRecord      = session;
        this.sessionRecordId    = session.Id;
        this.sessionName        = session.Name;
        this.sessionToken       = session.Session_Token__c;
        this.formType           = session.Wizard_Type__c;
        this.primaryEmail       = session.Guest_Email__c;
        this.currentStep        = String.valueOf(session.Current_Step__c);
        this.answers            = session.Answers_JSON__c;
    }
}