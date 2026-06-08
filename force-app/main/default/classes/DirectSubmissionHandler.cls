/**
 * @description Generic submission handler for onsite forms
 * Dynamically maps form answers to Researcher_Request__c fields using targetField configuration
 * @author BioRequest Corp
 * @date 2025-12-05
 * @workItem WI-000316 
 */
public without sharing class DirectSubmissionHandler implements I_FormSubmissionHandler {

    public class DirectSubmissionHandlerException extends Exception {}
    private static final String LOG_PREFIX = 'DirectSubmissionHandler';
    
    /**
     * @description Submit form data synchronously (delegates to async method)
     * @param sessionId The Form_Session__c record Id
     * @param answersJson JSON string containing form answers
     * @param wizardType The type of form wizard
     * @return JSON string containing success status, message, and recordId
     */
    public String submitForm(Id sessionId, String answersJson, String wizardType) {
        try {
            // Validate inputs
            if (sessionId == null || String.isBlank(answersJson) || String.isBlank(wizardType)) {
                logError('submitForm', 'Invalid input parameters', 
                    'sessionId=' + sessionId + ', wizardType=' + wizardType + ', answersJson length=' + 
                    (String.isBlank(answersJson) ? '0' : String.valueOf(answersJson.length())));
                return JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'message' => 'Invalid input parameters',
                    'recordId' => null
                });
            }
            
            // Call processing method directly (no longer async)
            processSubmissionAsync(String.valueOf(sessionId), answersJson, wizardType);
            // Return success after processing
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Submission processed',
                'recordId' => String.valueOf(sessionId)
            });
            
        } catch (Exception e) {
            logError('submitForm', 'Unexpected error', e);
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'message' => 'Submission failed: ' + e.getMessage(),
                'recordId' => null
            });
        }
    }
    
    /**
     * @description Process form submission asynchronously
     */
    public static void processSubmissionAsync(String sessionId, String answersJson, String wizardType) {

            // Load form configuration
            Dynamic_Form_Config__c config = loadFormConfiguration(wizardType);
            if (config == null) {
                 throw new DirectSubmissionHandlerException('Form configuration not found for wizard type: ' + wizardType);
            }
            
            // Parse configuration and answers
            Map<String, Object> configMap = parseJson(config.Form_Config__c, 'Form configuration');

            System.debug(LOG_PREFIX + ': Raw answersJson: ' + answersJson);

            // Remove escaped quotes from answersJson if present
            String cleanedAnswersJson = answersJson;
            if (cleanedAnswersJson.startsWith('"') && cleanedAnswersJson.endsWith('"')) {
                // Remove surrounding quotes and unescape inner quotes
                cleanedAnswersJson = cleanedAnswersJson.substring(1, cleanedAnswersJson.length() - 1);
                cleanedAnswersJson = cleanedAnswersJson.replace('\\"', '"');
            }
            // Also handle double-escaped quotes
            cleanedAnswersJson = cleanedAnswersJson.replace('\\\\"', '"');
            
            System.debug(LOG_PREFIX + ': Cleaned answersJson: ' + cleanedAnswersJson);
            
            Map<String, Object> answersMap = (Map<String, Object>) JSON.deserializeUntyped(cleanedAnswersJson);
           // Map<String, Object> answersMap = (Map<String, Object>) JSON.deserializeUntyped(answersJson);


            // Debug: Log the raw JSON and parsed maps
            System.debug(LOG_PREFIX + ': Raw answersJson: ' + answersJson);
            System.debug(LOG_PREFIX + ': Raw config.Form_Config__c: ' + config.Form_Config__c);
            System.debug(LOG_PREFIX + ': Parsed configMap: ' + String.valueOf(configMap));
            System.debug(LOG_PREFIX + ': Parsed answersMap: ' + String.valueOf(answersMap));

            if (configMap == null || answersMap == null) {
                throw new DirectSubmissionHandlerException('Failed to parse form configuration or answers JSON');
            }

            // Debug: Log all answer keys to identify the actual field name
            System.debug(LOG_PREFIX + ': All answer keys: ' + answersMap.keySet());

            // Dynamically find email confirmation and email fields from config
            Map<String, String> specialFields = findSpecialFields(configMap);
            String emailConfirmationFieldName = specialFields.get('emailConfirmation');
            String emailFieldName = specialFields.get('email');
            
            // Check if user wants email copy
            Boolean sendEmailCopy = false;
            String researcherEmail = null;
            Object sendCopyValue = null;
            
            // Get the value from the dynamically identified field
            if (String.isNotBlank(emailConfirmationFieldName)) {
                sendCopyValue = answersMap.get(emailConfirmationFieldName);
                // Use shared converter to handle Boolean/int/string variants (true/yes/1)
                if (sendCopyValue != null) {
                    try {
                        sendEmailCopy = convertToBoolean(sendCopyValue);
                    } catch (Exception e) {
                        // Fall back to previous conservative behavior if conversion fails
                        String strValue = String.valueOf(sendCopyValue).toLowerCase();
                        sendEmailCopy = (strValue == 'yes' || strValue == 'true');
                    }
                }
            }
            
            // Get researcher email from the dynamically identified field
            if (String.isNotBlank(emailFieldName)) {
                Object emailValue = answersMap.get(emailFieldName);
                System.debug(LOG_PREFIX + ': Raw emailValue from answersMap for key [' + emailFieldName + '] = ' + emailValue);
                if (emailValue != null) {
                    if (emailValue instanceof String) {
                        researcherEmail = (String) emailValue;
                    } else if (emailValue instanceof List<Object>) {
                        List<Object> listVal = (List<Object>) emailValue;
                        if (!listVal.isEmpty() && listVal[0] != null) {
                            researcherEmail = String.valueOf(listVal[0]);
                        }
                    } else {
                        // Fallback: stringify other types
                        researcherEmail = String.valueOf(emailValue);
                    }
                    if (researcherEmail != null) {
                        researcherEmail = researcherEmail.trim();
                    }
                }
            }
            
            // Debug logging for email feature
            System.debug(LOG_PREFIX + ': Email feature check - sendEmailCopy=' + sendEmailCopy + 
                ', researcherEmail=' + researcherEmail + ', sendCopyValue=' + sendCopyValue);
            // Helpful diagnostic: if an email exists but confirmation isn't set, log that explicitly
            if (String.isNotBlank(researcherEmail) && !sendEmailCopy) {
                System.debug(LOG_PREFIX + ': Researcher provided email [' + researcherEmail + '] but email confirmation flag is false or not found.');
            }
            
            // Create Researcher_Request__c record with dynamic field mapping
            Researcher_Request__c researcherRequest = createResearcherRequest(configMap, answersMap, sessionId, wizardType);
            
            if (researcherRequest != null) {
                // Lookup and populate Researcher Contact based on email
                if (String.isNotBlank(researcherEmail)) {
                    populateResearcherContact(researcherRequest, researcherEmail);
                }
                
                // Insert the record
                insertResearcherRequest(researcherRequest, sessionId);

                // --- Link uploaded files to records ---
                // Example: look for file upload question(s) in config and link ContentDocumentId(s)
                List<String> fileQuestionNames = new List<String>();
                List<Object> steps = (List<Object>) configMap.get('steps');
                if (steps != null) {
                    for (Object stepObj : steps) {
                        Map<String, Object> step = (Map<String, Object>) stepObj;
                        List<Object> sections = (List<Object>) step.get('sections');
                        if (sections != null) {
                            for (Object sectionObj : sections) {
                                Map<String, Object> section = (Map<String, Object>) sectionObj;
                                List<Object> questions = (List<Object>) section.get('questions');
                                if (questions != null) {
                                    for (Object questionObj : questions) {
                                        Map<String, Object> question = (Map<String, Object>) questionObj;
                                        String qType = (String) question.get('type');
                                        String qName = (String) question.get('name');
                                        if (qType == 'file' && String.isNotBlank(qName)) {
                                            fileQuestionNames.add(qName);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // For each file question, link the file to both records if present
                List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
                for (String fileQ : fileQuestionNames) {
                    Object fileIdObj = answersMap.get(fileQ);
                    if (fileIdObj != null) {
                        String fileId = String.valueOf(fileIdObj);
                        if (!String.isBlank(fileId)) {
                            // Link to Researcher_Request__c
                            linksToInsert.add(new ContentDocumentLink(
                                ContentDocumentId = fileId,
                                LinkedEntityId = researcherRequest.Id,
                                ShareType = 'V',
                                Visibility = 'AllUsers'
                            ));
                            // Link to Form_Session__c
                            linksToInsert.add(new ContentDocumentLink(
                                ContentDocumentId = fileId,
                                LinkedEntityId = sessionId,
                                ShareType = 'V',
                                Visibility = 'AllUsers'
                            ));
                        }
                    }
                }
                if (!linksToInsert.isEmpty()) {
                    try {
                        insert linksToInsert;
                        System.debug(LOG_PREFIX + ': Linked uploaded files to records: ' + linksToInsert.size());
                    } catch (Exception fileLinkEx) {
                        throw new DirectSubmissionHandlerException('Failed to link uploaded files: ' + fileLinkEx.getMessage());
                    }
                }

                // Send email copy if requested and email is provided
                if (sendEmailCopy && String.isNotBlank(researcherEmail)) {
                    try {
                        sendFormResponseEmail(researcherEmail, wizardType, answersMap, config, false);
                        System.debug(LOG_PREFIX + ': Email sent successfully to ' + researcherEmail);
                    } catch (Exception emailEx) {
                        // Log but don't fail the submission if email fails
                       throw new DirectSubmissionHandlerException('Failed to send email notification: ' + emailEx.getMessage());
                    }
                }

                // Send PM notification for same-day forms only
                String formType = (String) configMap.get('formType');
                if (formType != null && formType.equalsIgnoreCase('Sameday Forms')) {
                    try {
                        sendFormResponseEmail('pm@company.com', wizardType, answersMap, config, true);
                        System.debug(LOG_PREFIX + ': PM notification sent to pm@company.com for same-day form');
                    } catch (Exception pmEmailEx) {
                        System.debug(LOG_PREFIX + ': Failed to send PM notification: ' + pmEmailEx.getMessage());
                    }
                }

                // Send ClientD onsite notification
                if (wizardType != null && wizardType.equalsIgnoreCase('ClientD_Onsite')) {
                    try {
                        sendFormResponseEmail('clientd.onsite@company.com', wizardType, answersMap, config, true);
                        System.debug(LOG_PREFIX + ': ClientD notification sent to clientd.onsite@company.com');
                    } catch (Exception clientDEmailEx) {
                        System.debug(LOG_PREFIX + ': Failed to send ClientD notification: ' + clientDEmailEx.getMessage());
                    }
                }
            } else {
                throw new DirectSubmissionHandlerException('Failed to create Researcher_Request__c record');
            }
    }
    
    /**
     * @description Find special fields (email, email confirmation) in form config by label patterns
     * @param configMap Parsed form configuration
     * @return Map with keys 'email' and 'emailConfirmation' containing field names
     */
    private static Map<String, String> findSpecialFields(Map<String, Object> configMap) {
        Map<String, String> specialFields = new Map<String, String>{
            'email' => null,
            'emailConfirmation' => null
        };
        
        if (configMap == null) {
            return specialFields;
        }
        
        try {
            List<Object> steps = (List<Object>) configMap.get('steps');
            if (steps == null) {
                return specialFields;
            }
            
            for (Object stepObj : steps) {
                Map<String, Object> step = (Map<String, Object>) stepObj;
                List<Object> sections = (List<Object>) step.get('sections');
                
                if (sections == null) {
                    continue;
                }
                
                for (Object sectionObj : sections) {
                    Map<String, Object> section = (Map<String, Object>) sectionObj;
                    List<Object> questions = (List<Object>) section.get('questions');
                    
                    if (questions == null) {
                        continue;
                    }
                    
                    for (Object questionObj : questions) {
                        Map<String, Object> question = (Map<String, Object>) questionObj;
                        String questionName = (String) question.get('name');
                        String questionLabel = (String) question.get('label');
                        
                        if (String.isBlank(questionName) || String.isBlank(questionLabel)) {
                            continue;
                        }
                        
                        String labelLower = questionLabel.toLowerCase();
                        String questionType = (String) question.get('type');
                        
                        // Skip display-text fields entirely - they're just labels, not inputs
                        if (questionType == 'display-text') {
                            continue;
                        }
                        
                        // Check for email confirmation field (checkbox/radio only)
                        if (specialFields.get('emailConfirmation') == null &&
                            (labelLower.contains('send me a copy') ||
                             labelLower.contains('confirmation email') ||
                             labelLower.contains('receive a copy') ||
                             labelLower.contains('email me'))) {
                            specialFields.put('emailConfirmation', questionName);
                            System.debug(LOG_PREFIX + ': Found email confirmation field: ' + questionName + ' (label: ' + questionLabel + ', type: ' + questionType + ')');
                        }
                        
                        // Check for email field
                        if (specialFields.get('email') == null &&
                            labelLower.contains('email') && 
                            !labelLower.contains('confirmation') &&
                            !labelLower.contains('copy')) {
                            specialFields.put('email', questionName);
                            System.debug(LOG_PREFIX + ': Found email field: ' + questionName + ' (label: ' + questionLabel + ', type: ' + questionType + ')');
                        }
                    }
                }
            }
        } catch (Exception e) {
            logError('findSpecialFields', 'Error finding special fields', e);
        }
        
        return specialFields;
    }
    
    /**
     * @description Get Record Type ID based on formType from JSON configuration
     * Uses the formType property to find the matching Record Type
     * @param formType The form type from JSON config (e.g., "Onsite Forms", "Sameday Forms")
     * @return Record Type ID or null if no mapping found
     */
    private static Id getRecordTypeByFormType(String formType) {
        // Default to "Onsite Forms" if no formType provided
        if (String.isBlank(formType)) {
            formType = 'Onsite Forms';
        }

        try {
            List<RecordType> rts = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Researcher_Request__c'
                AND Name = :formType
                AND IsActive = true
                LIMIT 1
            ];

            if (!rts.isEmpty()) {
                System.debug(LOG_PREFIX + ': Found RecordType for formType: ' + formType);
                return rts[0].Id;
            }

            System.debug(LOG_PREFIX + ': No Record Type found for formType: ' + formType);
            return null;

        } catch (Exception e) {
            logError('getRecordTypeByFormType', 'Error querying Record Types', e);
            return null;
        }
    }
    
    /**
     * @description Load form configuration from database
     * @param wizardType The type of form wizard
     * @return Dynamic_Form_Config__c record or null if not found
     */
    private static Dynamic_Form_Config__c loadFormConfiguration(String wizardType) {
        try {
            List<Dynamic_Form_Config__c> configs = [
                SELECT Id, Form_Config__c 
                FROM Dynamic_Form_Config__c 
                WHERE Title__c = :wizardType
                LIMIT 1
            ];
            
            if (configs.isEmpty()) {
                logError('loadFormConfiguration', 'No active configuration found', 'wizardType=' + wizardType);
                return null;
            }
            
            return configs[0];
            
        } catch (Exception e) {
            logError('loadFormConfiguration', 'Database query failed', e);
            return null;
        }
    }
    
    /**
     * @description Parse JSON string safely
     * @param jsonString The JSON string to parse
     * @param context Context for error logging
     * @return Parsed map or null if parsing fails
     */
    private static Map<String, Object> parseJson(String jsonString, String context) {
        try {
            if (String.isBlank(jsonString)) {
                logError('parseJson', 'Empty JSON string', 'context=' + context);
                return null;
            }
            
            return (Map<String, Object>) JSON.deserializeUntyped(jsonString);
            
        } catch (Exception e) {
            logError('parseJson', 'JSON parsing failed for ' + context, e);
            return null;
        }
    }
    
    /**
     * @description Lookup and populate Researcher Contact information based on email
     * @param researcherRequest The Researcher_Request__c record to populate
     * @param email The email address to lookup
     */
    private static void populateResearcherContact(Researcher_Request__c researcherRequest, String email) {
        try {
            if (String.isBlank(email)) {
                System.debug(LOG_PREFIX + ': No email provided for contact lookup');
                return;
            }
            
            // Query for Contact with matching email (order by CreatedDate DESC to get newest first)
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Name, Email, RecordType.DeveloperName
                FROM Contact 
                WHERE Email = :email 
                ORDER BY CreatedDate DESC
                LIMIT 2
            ];
            
            if (!contacts.isEmpty()) {
                // If there are 2 contacts with the same email, pick the second one (newer contact at index 0)
                // Otherwise, use the first (and only) one
                Contact researcherContact = contacts[0];
                
                // Populate Researcher_Contact__c field with contact name
                researcherRequest.Researcher_Contact__c = researcherContact.Name;
                
                // If the email wasn't already set, set it
                if (String.isBlank(researcherRequest.Researcher_Contact_Email__c)) {
                    researcherRequest.Researcher_Contact_Email__c = researcherContact.Email;
                }
                
                System.debug(LOG_PREFIX + ': Found and linked Contact: ' + researcherContact.Name + 
                    ' (Id: ' + researcherContact.Id + ', RecordType: ' + 
                    (researcherContact.RecordType != null ? researcherContact.RecordType.DeveloperName : 'None') + 
                    ', Total contacts with this email: ' + contacts.size() + ')');
            } else {
                System.debug(LOG_PREFIX + ': No Contact found with email: ' + email);
                
                // Optionally set the email even if no contact found
                if (String.isBlank(researcherRequest.Researcher_Contact_Email__c)) {
                    researcherRequest.Researcher_Contact_Email__c = email;
                }
            }
            
        } catch (Exception e) {
            // Log error but don't fail the submission
            logError('populateResearcherContact', 'Failed to lookup researcher contact', e);
        }
    }
    
    /**
     * @description Create Researcher_Request__c record with dynamic field mapping
     * @param configMap Parsed form configuration
     * @param answersMap Parsed form answers
     * @param sessionId The Form_Session__c record Id
     * @param wizardType The type of form wizard (used for Record Type assignment)
     * @return Researcher_Request__c record or null if creation fails
     */
    private static Researcher_Request__c createResearcherRequest(
        Map<String, Object> configMap,
        Map<String, Object> answersMap,
        String sessionId,
        String wizardType
    ) {

            Researcher_Request__c req = new Researcher_Request__c();
            // Note: Add lookup field to Form_Session__c if needed
            // req.Form_Session__c = sessionId;

            // Set the form title directly from wizardType (the form configuration title)
            req.Submitted_Form_Title__c = wizardType;
            System.debug(LOG_PREFIX + ': Set Submitted_Form_Title__c to: ' + wizardType);

            // Read formType and accountId from JSON configuration
            String formType = (String) configMap.get('formType');
            String accountId = (String) configMap.get('accountId');

            // Set Record Type based on formType from config (defaults to "Onsite Forms")
            Id recordTypeId = getRecordTypeByFormType(formType);
            if (recordTypeId != null) {
                req.RecordTypeId = recordTypeId;
                System.debug(LOG_PREFIX + ': Assigned RecordTypeId: ' + recordTypeId + ' for formType: ' + formType);
            } else {
                System.debug(LOG_PREFIX + ': No matching RecordType found for formType: ' + formType + ' - using default');
            }

            // Set Related Account lookup if accountId provided in config
            if (String.isNotBlank(accountId)) {
                try {
                    req.Related_Account__c = Id.valueOf(accountId);
                    System.debug(LOG_PREFIX + ': Set Related_Account__c to: ' + accountId);
                } catch (Exception e) {
                    System.debug(LOG_PREFIX + ': Invalid accountId in config: ' + accountId + ' - ' + e.getMessage());
                }
            }
            
            Integer mappedFields = 0;
            
            // Walk through configuration structure: steps -> sections -> questions
            List<Object> steps = (List<Object>) configMap.get('steps');
            if (steps == null) {
                logError('createResearcherRequest', 'No steps found in configuration', '');
                return null;
            }
            
            for (Object stepObj : steps) {
                Map<String, Object> step = (Map<String, Object>) stepObj;
                List<Object> sections = (List<Object>) step.get('sections');
                
                if (sections == null) {
                    continue;
                }
                
                for (Object sectionObj : sections) {
                    Map<String, Object> section = (Map<String, Object>) sectionObj;
                    List<Object> questions = (List<Object>) section.get('questions');
                    
                    if (questions == null) {
                        continue;
                    }
                    
                    for (Object questionObj : questions) {
                        Map<String, Object> question = (Map<String, Object>) questionObj;
                        
                        // Check if question has targetField and answer exists
                        String targetField = (String) question.get('targetField');
                        String questionName = (String) question.get('name');
                        String questionType = (String) question.get('type');
                        
                        if (String.isNotBlank(targetField) && String.isNotBlank(questionName)) {
                            Object answerValue = answersMap.get(questionName);
                            
                            if (answerValue != null) {
                                // Convert and set field value based on question type
                                Boolean success = setFieldValue(req, targetField, answerValue, questionType);
                                if (success) {
                                    mappedFields++;
                                }
                            }
                        }
                    }
                }
            }
            
            System.debug(LOG_PREFIX + ': Successfully mapped ' + mappedFields + ' fields to Researcher_Request__c');
            
            return req;          
    }
    
    /**
     * @description Set field value on sObject with type conversion
     * @param record The sObject record to update
     * @param fieldName The API name of the field
     * @param value The value to set
     * @param questionType The type of question (checkbox, date, time, text, dropdown, etc.)
     * @return True if successful, false otherwise
     */
    private static Boolean setFieldValue(
        sObject record, 
        String fieldName, 
        Object value, 
        String questionType
    ) {
        try {
            // Handle null or empty values
            if (value == null) {
                return false;
            }
            
            // Convert based on question type
            if (questionType == 'checkbox' || questionType == 'single-checkbox') {
                // Checkbox -> Boolean
                Boolean boolValue = convertToBoolean(value);
                record.put(fieldName, boolValue);
                
            } else if (questionType == 'date') {
                // Date -> Date
                Date dateValue = convertToDate(value);
                if (dateValue != null) {
                    record.put(fieldName, dateValue);
                } else {
                    return false;
                }
                
            } else if (questionType == 'time') {
                // Time -> Time
                Time timeValue;
                if (value instanceof Time) {
                    timeValue = (Time) value;
                } else if (value instanceof String) {
                    String strValue = String.valueOf(value);
                    timeValue = convertToTime(strValue);
                } else {
                    timeValue = convertToTime(value);
                }
                if (timeValue != null) {
                    record.put(fieldName, timeValue);
                } else {
                    System.debug(LoggingLevel.ERROR, LOG_PREFIX + '.setFieldValue: Could not parse time value for field ' + fieldName + ' from value: ' + value);
                    return false;
                }
                
            } else if (questionType == 'number') {
                // Number -> Decimal or Integer
                Decimal decimalValue = convertToDecimal(value);
                if (decimalValue != null) {
                    record.put(fieldName, decimalValue);
                } else {
                    return false;
                }
                
            } else if (questionType == 'dropdown' || questionType == 'select') {
                // Dropdown - need to detect target field type
               String strValue = String.valueOf(value);
                // Check if target field is a Time field
                Boolean isTimeField = false;
                if (record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) {
                    Schema.DescribeFieldResult fieldDescribe = record.getSObjectType().getDescribe().fields.getMap().get(fieldName).getDescribe();
                    isTimeField = (fieldDescribe.getType() == Schema.DisplayType.Time);
                }

                // If target is a Time field, attempt time conversion for any format (e.g., "9:00 a.m.", "0930")
                if (isTimeField) {
                    Time timeValue = convertToTime(value);
                    if (timeValue != null) {
                        record.put(fieldName, timeValue);
                        return true;
                        } else {
                        System.debug(LoggingLevel.ERROR, LOG_PREFIX + '.setFieldValue: Failed to convert dropdown value to Time for field ' + fieldName + ' value: ' + strValue);
                        return false;
                    }
                }
                 // For non-Time fields, treat as string/picklist
                if (String.isNotBlank(strValue)) {
                   record.put(fieldName, strValue);
                } else {
                    return false;
                }
                
            } else {
                // Default: text, textarea, radio, etc. -> String
                String stringValue = String.valueOf(value);
                if (String.isNotBlank(stringValue)) {
                    record.put(fieldName, stringValue);
                } else {
                    return false;
                }
            }
            
            return true;
            
        } catch (Exception e) {
            logError('setFieldValue', 'Failed to set field: ' + fieldName, e);
            return false;
        }
    }
    
    /**
     * @description Convert value to Boolean
     * @param value The value to convert
     * @return Boolean value
     */
    private static Boolean convertToBoolean(Object value) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String strValue = String.valueOf(value).toLowerCase();
        return strValue == 'true' || strValue == '1' || strValue == 'yes';
    }
    
    /**
     * @description Convert value to Date
     * @param value The value to convert
     * @return Date value or null if conversion fails
     */
    private static Date convertToDate(Object value) {
        try {
            if (value instanceof Date) {
                return (Date) value;
            }
            String strValue = String.valueOf(value);
            if (String.isNotBlank(strValue)) {
                // Try ISO format (YYYY-MM-DD)
                return Date.valueOf(strValue);
            }
        } catch (Exception e) {
            logError('convertToDate', 'Date conversion failed', 'value=' + value);
        }
        return null;
    }
    
    /**
     * @description Convert value to Time
     * @param value The value to convert
     * @return Time value or null if conversion fails
     */
    private static Time convertToTime(Object value) {
        try {
            if (value instanceof Time) {
                return (Time) value;
            }
            String strValue = String.valueOf(value).trim();
            if (String.isNotBlank(strValue)) {
                // Handle HHMM format (e.g., "0930", "1200", "1300")
                if (strValue.length() == 4 && strValue.isNumeric()) {
                    Integer hours = Integer.valueOf(strValue.substring(0, 2));
                    Integer minutes = Integer.valueOf(strValue.substring(2, 4));
                    return Time.newInstance(hours, minutes, 0, 0);
                }
                // Parse HH:mm or HH:mm:ss format (24-hour)
                else if (strValue.contains(':')) {
                    // Check for AM/PM (12-hour) format
                    Pattern p = Pattern.compile('^(\\d{1,2}):(\\d{2})(?::(\\d{2}))?\\s*([AaPp][.]?[Mm][.]?)?$');
                    Matcher m = p.matcher(strValue);
                    if (m.matches()) {
                        Integer hours = Integer.valueOf(m.group(1));
                        Integer minutes = Integer.valueOf(m.group(2));
                        Integer seconds = m.group(3) != null ? Integer.valueOf(m.group(3)) : 0;
                        String ampm = m.group(4);
                        if (ampm != null) {
                            ampm = ampm.replace('.', '').toLowerCase();
                            if (ampm == 'pm' && hours < 12) {
                                hours += 12;
                            } else if (ampm == 'am' && hours == 12) {
                                hours = 0;
                            }
                        }
                        return Time.newInstance(hours, minutes, seconds, 0);
                    }
                    // Fallback: try splitting and parsing as 24-hour
                    List<String> parts = strValue.split(':');
                    if (parts.size() >= 2) {
                        Integer hours = Integer.valueOf(parts[0]);
                        Integer minutes = Integer.valueOf(parts[1]);
                        Integer seconds = parts.size() > 2 ? Integer.valueOf(parts[2]) : 0;
                        return Time.newInstance(hours, minutes, seconds, 0);
                    }
                }
                // Try to match 12-hour format with AM/PM without colon (e.g., "10am", "3pm")
                Pattern p2 = Pattern.compile('^(\\d{1,2})\\s*([AaPp][.]?[Mm][.]?)$');
                Matcher m2 = p2.matcher(strValue);
                if (m2.matches()) {
                    Integer hours = Integer.valueOf(m2.group(1));
                    Integer minutes = 0;
                    String ampm = m2.group(2).replace('.', '').toLowerCase();
                    if (ampm == 'pm' && hours < 12) {
                        hours += 12;
                    } else if (ampm == 'am' && hours == 12) {
                        hours = 0;
                    }
                    return Time.newInstance(hours, minutes, 0, 0);
                }
            }
        } catch (Exception e) {
            logError('convertToTime', 'Time conversion failed', 'value=' + value);
        }
        return null;
    }
    
    /**
     * @description Convert value to Decimal
     * @param value The value to convert
     * @return Decimal value or null if conversion fails
     */
    private static Decimal convertToDecimal(Object value) {
        try {
            if (value instanceof Decimal) {
                return (Decimal) value;
            }
            if (value instanceof Integer) {
                return Decimal.valueOf((Integer) value);
            }
            String strValue = String.valueOf(value);
            if (String.isNotBlank(strValue)) {
                return Decimal.valueOf(strValue);
            }
        } catch (Exception e) {
            logError('convertToDecimal', 'Decimal conversion failed', 'value=' + value);
        }
        return null;
    }
    
    /**
     * @description Insert Researcher_Request__c record and update session
     * Creates multiple clones based on Donor_Quantity__c field
     * Links each request to matching Contact (excluding Patient record type)
     * @param req The Researcher_Request__c record to insert
     * @param sessionId The Form_Session__c record Id
     */
    private static void insertResearcherRequest(Researcher_Request__c req, String sessionId) {
        try {
            // Get donor quantity (default to 1 if not specified)
            Integer numRecords = 1;
            if (String.isNotBlank(req.Donor_Quantity__c)) {
                try {
                    numRecords = Integer.valueOf(req.Donor_Quantity__c);
                } catch (Exception e) {
                    numRecords = 1;
                }
            }
            
            // Validate quantity
            if (numRecords < 1) {
                numRecords = 1;
            }
            
            // Find matching Contact by email (excluding Patient record type)
            Id matchingContactId = findContactByEmail(req.Researcher_Contact_Email__c);
            if (matchingContactId != null) {
                req.Researcher_Contact__c = matchingContactId;
                System.debug(LOG_PREFIX + ': Linked to Contact: ' + matchingContactId);
            }
            
            // Create list to hold all records to insert
            List<Researcher_Request__c> recordsToInsert = new List<Researcher_Request__c>();
            
            // Add the original record
            recordsToInsert.add(req);
            
            // Create additional clones if donor quantity > 1
            for (Integer i = 1; i < numRecords; i++) {
                Researcher_Request__c clone = req.clone(false, true, false, false);
                recordsToInsert.add(clone);
            }
            
            // Insert all records
            insert recordsToInsert;
            
            System.debug(LOG_PREFIX + ': Successfully inserted ' + recordsToInsert.size() + ' Researcher_Request__c record(s)');
            
            // Update session with the first researcher request reference
            updateSession(sessionId, recordsToInsert[0].Id);
            
        } catch (DmlException e) {
             throw new DirectSubmissionHandlerException('Insert researcher request DML operation failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Find Contact by email address (excluding Patient record type)
     * @param email The email address to search for
     * @return Contact Id or null if not found
     */
    private static Id findContactByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        
        try {
            // Get Patient record type ID
            Id patientRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                .get('Patient_Layout')?.getRecordTypeId();
            
            // Query for matching Contact (excluding Patient record type)
            List<Contact> contacts = [
                SELECT Id, Email 
                FROM Contact 
                WHERE Email = :email 
                AND RecordTypeId != :patientRecordTypeId
                LIMIT 1
            ];
            
            if (!contacts.isEmpty()) {
                System.debug(LOG_PREFIX + ': Found matching Contact for email: ' + email);
                return contacts[0].Id;
            }
            
        } catch (Exception e) {
            logError('findContactByEmail', 'Error finding Contact by email: ' + email, e);
        }
        
        return null;
    }
    
    /**
     * @description Update Form_Session__c with Researcher_Request__c reference
     * @param sessionId The Form_Session__c record Id
     * @param requestId The Researcher_Request__c record Id
     */
    private static void updateSession(String sessionId, String requestId) {
        try {
            Form_Session__c session = new Form_Session__c(
                Id = sessionId,
                Final_Record_Id__c = requestId
            );
            
            
            update session;
            
            System.debug(LOG_PREFIX + ': Successfully linked session ' + sessionId + ' to request ' + requestId);
            
        } catch (DmlException e) {
            logError('updateSession', 'Failed to update session with request reference', e);
        } catch (Exception e) {
            logError('updateSession', 'Unexpected error updating session', e);
        }
    }
    
    /**
     * @description Log error with context
     * @param methodName The method where error occurred
     * @param message Error message
     * @param details Additional details
     */
    private static void logError(String methodName, String message, String details) {
        String errorMsg = LOG_PREFIX + '.' + methodName + ': ' + message;
        if (String.isNotBlank(details)) {
            errorMsg += ' | Details: ' + details;
        }
        System.debug(LoggingLevel.ERROR, errorMsg);
    }
    
    /**
     * @description Log error with exception
     * @param methodName The method where error occurred
     * @param message Error message
     * @param e The exception
     */
    private static void logError(String methodName, String message, Exception e) {
        String errorMsg = LOG_PREFIX + '.' + methodName + ': ' + message + 
            ' | Exception: ' + e.getTypeName() + 
            ' | Message: ' + e.getMessage() + 
            ' | Line: ' + e.getLineNumber() + 
            ' | Stack: ' + e.getStackTraceString();
        System.debug(LoggingLevel.ERROR, errorMsg);
    }
    
    /**
     * @description Send form response email to researcher
     * Added: 2025-12-08 - WI-000316 - Email copy of form responses
     * @param researcherEmail Email address to send to
     * @param wizardType Form type name
     * @param answersMap Map of form answers
     * @param config Form configuration
     */
    private static void sendFormResponseEmail(
        String researcherEmail,
        String wizardType,
        Map<String, Object> answersMap,
        Dynamic_Form_Config__c config,
        Boolean isInternal
    ) {
        try {
            // Determine form label from config formType
            Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(config.Form_Config__c);
            String formType = (String) configMap.get('formType');
            Boolean isSameday = String.isNotBlank(formType) && formType.containsIgnoreCase('Sameday');
            String formLabel = isSameday ? 'Same-Day' : 'Onsite';

            // Build email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

            email.setToAddresses(new List<String>{ researcherEmail });
            String subjectPrefix = isInternal ? '' : 'Your ';
            email.setSubject(subjectPrefix + formLabel + ' Form Submission - ' + wizardType);
            email.setHtmlBody(buildEmailBody(wizardType, answersMap, config, formLabel, isInternal));
            email.setSaveAsActivity(false);
            email.setOrgWideEmailAddressId('0D2PW00000006YT0AY');

            // Send email with error handling
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
                if (results != null && results.size() > 0 && !results[0].isSuccess()) {
                    logError('sendFormResponseEmail', 'sendEmail failed', results[0].getErrors() != null ? String.valueOf(results[0].getErrors()) : 'Unknown error');
                } else {
                    System.debug(LOG_PREFIX + ': Email sent successfully to ' + researcherEmail);
                }
            } catch (Exception sendEx) {
                logError('sendFormResponseEmail', 'Exception during sendEmail', sendEx);
                throw sendEx;
            }

        } catch (Exception e) {
            logError('sendFormResponseEmail', 'Error sending email', e);
            throw e; // Re-throw so caller can handle
        }
    }
    
    /**
     * @description Build HTML email body with formatted form responses
     * @param wizardType Type of form
     * @param answersMap Map of answers
     * @param config Form configuration
     * @return HTML string for email body
     */
    private static String buildEmailBody(
        String wizardType,
        Map<String, Object> answersMap,
        Dynamic_Form_Config__c config,
        String formLabel,
        Boolean isInternal
    ) {
        String html = '<html><head><style>';
        html += 'body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }';
        html += '.header { background-color: #0070d2; color: white; padding: 20px; text-align: center; }';
        html += '.content { padding: 20px; }';
        html += '.field { margin-bottom: 15px; border-bottom: 1px solid #e0e0e0; padding-bottom: 10px; }';
        html += '.label { font-weight: bold; color: #0070d2; display: block; margin-bottom: 5px; }';
        html += '.value { color: #333; margin-left: 10px; }';
        html += '.footer { background-color: #f4f4f4; padding: 15px; text-align: center; font-size: 12px; color: #666; margin-top: 30px; }';
        html += '</style></head><body>';
        
        // Header
        html += '<div class="header">';
        html += '<h1>' + formLabel + ' Form Submission Confirmation</h1>';
        html += '<p>' + wizardType + '</p>';
        html += '</div>';
        
        // Content
        html += '<div class="content">';
        if (isInternal) {
            html += '<p>A ' + formLabel.toLowerCase() + ' form has been submitted. Below are the responses:</p>';
        } else {
            html += '<p>Thank you for submitting your ' + formLabel.toLowerCase() + ' form. Below is a copy of your responses:</p>';
        }
        
        // Parse form config to get question labels
        Map<String, String> questionLabels = getQuestionLabels(config);
        
        // Find the email confirmation field name to skip it
        Map<String, String> specialFields = findSpecialFields(
            (Map<String, Object>) JSON.deserializeUntyped(config.Form_Config__c)
        );
        String emailConfirmationFieldName = specialFields.get('emailConfirmation');
        
        // Display answers
        html += '<div class="answers">';
        for (String questionName : answersMap.keySet()) {
            // Skip the email confirmation field
            if (String.isNotBlank(emailConfirmationFieldName) && 
                questionName.equalsIgnoreCase(emailConfirmationFieldName)) {
                continue;
            }
            
            Object value = answersMap.get(questionName);
            if (value != null) {
                String label = questionLabels.containsKey(questionName) 
                    ? questionLabels.get(questionName) 
                    : formatLabel(questionName);
                String displayValue = formatValue(value);
                
                html += '<div class="field">';
                html += '<span class="label">' + label + ':</span>';
                html += '<span class="value">' + displayValue + '</span>';
                html += '</div>';
            }
        }
        html += '</div>';
        html += '</div>';
        
        // Footer
        html += '<div class="footer">';
        html += '<p>This is an automated confirmation email from BioRequest Corp.</p>';
        html += '<p>If you have any questions, please contact ';
        if (formLabel == 'Onsite') {
            html += 'us at onsite@company.com';
        } else {
            html += 'your project manager';
        }
        html += '</p>';
        html += '<p style="margin-top: 10px;">&copy; ' + Date.today().year() + ' BioRequest Corp. All rights reserved.</p>';
        html += '</div>';
        
        html += '</body></html>';
        
        return html;
    }
    
    /**
     * @description Extract question labels from form configuration
     * @param config Form configuration
     * @return Map of question names to labels
     */
    private static Map<String, String> getQuestionLabels(Dynamic_Form_Config__c config) {
        Map<String, String> questionLabels = new Map<String, String>();
        
        if (config == null || String.isBlank(config.Form_Config__c)) {
            return questionLabels;
        }
        
        try {
            Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(config.Form_Config__c);
            List<Object> steps = (List<Object>) configMap.get('steps');
            
            if (steps != null) {
                for (Object stepObj : steps) {
                    Map<String, Object> step = (Map<String, Object>) stepObj;
                    List<Object> sections = (List<Object>) step.get('sections');
                    
                    if (sections != null) {
                        for (Object sectionObj : sections) {
                            Map<String, Object> section = (Map<String, Object>) sectionObj;
                            List<Object> questions = (List<Object>) section.get('questions');
                            
                            if (questions != null) {
                                for (Object questionObj : questions) {
                                    Map<String, Object> question = (Map<String, Object>) questionObj;
                                    String name = (String) question.get('name');
                                    String label = (String) question.get('label');
                                    if (name != null && label != null) {
                                        questionLabels.put(name, label);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            logError('getQuestionLabels', 'Error parsing config for labels', e);
        }
        
        return questionLabels;
    }
    
    /**
     * @description Format question name into readable label
     * Converts camelCase/snake_case to Title Case
     */
    private static String formatLabel(String questionName) {
        if (String.isBlank(questionName)) return '';
        
        // Replace underscores with spaces
        String formatted = questionName.replace('_', ' ');
        
        // Add space before capital letters (camelCase to Title Case)
        formatted = formatted.replaceAll('([A-Z])', ' $1');
        
        // Capitalize first letter of each word
        List<String> words = formatted.split(' ');
        List<String> capitalizedWords = new List<String>();
        for (String word : words) {
            if (String.isNotBlank(word)) {
                capitalizedWords.add(word.substring(0, 1).toUpperCase() + word.substring(1).toLowerCase());
            }
        }
        
        return String.join(capitalizedWords, ' ').trim();
    }
    
    /**
     * @description Format answer value for display
     * Handles different data types (String, List, Boolean, etc.)
     */
    private static String formatValue(Object value) {
        if (value == null) {
            return '(Not provided)';
        }
        
        if (value instanceof List<Object>) {
            List<Object> listValue = (List<Object>) value;
            if (listValue.isEmpty()) {
                return '(Not provided)';
            }
            return String.join(listValue, ', ');
        }
        
        if (value instanceof Boolean) {
            return (Boolean) value ? 'Yes' : 'No';
        }
        
        String stringValue = String.valueOf(value).trim();
        return String.isBlank(stringValue) ? '(Not provided)' : stringValue;
    }
}