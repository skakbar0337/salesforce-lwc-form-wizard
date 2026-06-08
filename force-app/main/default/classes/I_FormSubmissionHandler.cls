/**
 * @description Interface for form submission handlers.
 *              Each form type can have its own handler class that implements this interface.
 *              The handler class name is specified in the JSON config's submissionController property.
 */
public interface I_FormSubmissionHandler {
    
    /**
     * @description Process the form submission with the provided answers
     * @param sessionId The Form_Session__c record Id
     * @param answersJson JSON string containing all form answers
     * @param wizardType The type/name of the wizard form being submitted
     * @return JSON string containing success status, message, and any relevant data
     *         Expected format: {"success": true/false, "message": "...", "recordId": "...", "data": {...}}
     */
    String submitForm(Id sessionId, String answersJson, String wizardType);
}