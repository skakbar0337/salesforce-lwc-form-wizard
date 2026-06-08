/**
 * @description Submission handler for Dynamic Request Forms (SRF).
 *              Implements I_FormSubmissionHandler interface to process form submissions.
 *              This handler uses a DYNAMIC FIELD MAPPING ENGINE that reads targetField properties
 *              from the JSON configuration to automatically map form fields to Salesforce records.
 * 
 * @group SRF
 * @author Dynamic Request Form Team
 * 
 * WITHOUT SHARING JUSTIFICATION:
 * This class runs without sharing to allow public form submissions from guest users
 * who do not have standard Salesforce sharing rules applied. All record creation
 * is intentional and required for public Dynamic Request Form functionality.
 */
@SuppressWarnings('PMD.ExcessiveClassLength, PMD.CognitiveComplexity')
public without sharing class FormSubmissionHandler implements I_FormSubmissionHandler {

    private Map<String, Object> wizardConfig;
    private Map<String, Map<String, Object>> fieldMappingCache;

    // Email Template Developer Names
    private static final String SUBMITTER_TEMPLATE_NAME = 'Form_Submitter_Confirmation';
    private static final String SALES_TEMPLATE_NAME = 'Form_Team_Notification';
    private static final String FAILURE_TEMPLATE_NAME = 'Form_Submission_Failure_Notification';

    // Org-Wide Email Address for sending emails (required for guest user context)
    private static final String ORG_WIDE_EMAIL_ADDRESS = 'info@company.com';

    // Sales Team Recipients
    private static final List<String> SALES_TEAM_EMAILS = new List<String>{
        'user2@company.com',
        'sales1@company.com',
        'sales2@company.com',
        'marketing@company.com'
    };

    private static final List<String> FAILURE_NOTIFICATION_EMAILS = new List<String>{
        'info@company.com',
        'support@company.com'
    };

    private static final Map<String, String> BIOSPECIMEN_VALUE_MAP = new Map<String, String>{
        'leukopak' => 'Leukopak',
        'wholeBlood' => 'Whole Blood',
        'plasma' => 'Plasma',
        'serum' => 'Serum',
        'dna' => 'DNA',
        'rna' => 'RNA',
        'pbmc' => 'PBMC',
        'rbc' => 'RBC',
        'tCell' => 'T Cell',
        'bCell' => 'B Cell',
        'nkCell' => 'NK Cell',
        'buffyCoat' => 'Buffy Coat',
        'bulkPlasma' => 'Bulk Plasma',
        'buccal' => 'Buccal',
        'buccalSwabs' => 'Buccal',
        'nasalSwabs' => 'Nasal',
        'nasal' => 'Nasal',
        'saliva' => 'Saliva',
        'semen' => 'Semen',
        'urine' => 'Urine',
        'stool' => 'Stool',
        'sputum' => 'Sputum',
        'hair' => 'Hair',
        'fingernails' => 'Nail',
        'nail' => 'Nail',
        'skinTapeStrips' => 'Skin Tape',
        'skinTape' => 'Skin Tape',
        'skinPunch' => 'Skin Punch Biopsy',
        'skinPunchBiopsy' => 'Skin Punch Biopsy',
        'synovialFluid' => 'Synovial Fluid',
        'other' => 'Other'
    };

    private Account accountRecord;
    private Contact contactRecord;
    private Opportunity opportunityRecord;
    private List<Research_Proposal__c> cohortRecords;
    private List<Site_Codes__c> siteCodeRecords;
    private List<I_E_Criterion__c> ieCriteriaRecords;

    // Deferred field updates - fields that trigger CohortIEOrchestrator are set after insert
    // to avoid INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY errors from trigger handlers
    // running with sharing in guest user context
    private Map<Integer, Map<String, Object>> deferredCohortFields;

    // Session name for error log prefixing - enables easy cross-reference to errors
    private String sessionName;
    
    /**
     * @description Process the Dynamic Request Form submission using dynamic field mapping
     *              Reads targetField properties from JSON config and automatically creates records
     * 
     * @param sessionId The Form_Session__c record Id
     * @param answersJson JSON string containing all form answers
     * @param wizardType The type/name of the wizard form being submitted
     * @return JSON string containing success status, message, and any relevant data
     */
    public String submitForm(Id sessionId, String answersJson, String wizardType) {
        try {
            if (String.isBlank(answersJson)) {
                throw new SRFSubmissionException('Form answers are required.');
            }

            // Query session name early for error log prefixing
            if (sessionId != null) {
                List<Form_Session__c> sessions = [
                    SELECT Id, Name
                    FROM Form_Session__c
                    WHERE Id = :sessionId
                    LIMIT 1
                ];
                if (!sessions.isEmpty()) {
                    this.sessionName = sessions[0].Name;
                }
            }

            Map<String, Object> answers = (Map<String, Object>) JSON.deserializeUntyped(answersJson);

            loadWizardConfiguration(wizardType);

           

            buildFieldMappingCache();

            ApexLog.logMessage(
                ApexLog.LogLevel.INFO,
                withSessionPrefix('SRF submission initiated with dynamic field mapping'),
                'FormSubmissionHandler',
                'submitForm',
                'Session: ' + sessionId + ', Wizard Type: ' + wizardType
            );
            
            cohortRecords = new List<Research_Proposal__c>();
            siteCodeRecords = new List<Site_Codes__c>();
            ieCriteriaRecords = new List<I_E_Criterion__c>();
            deferredCohortFields = new Map<Integer, Map<String, Object>>();

            Id opportunityId;
            try {
                opportunityId = createRecordsDynamically(answers, sessionId);
                updateSessionStatus(sessionId);

                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    withSessionPrefix('SRF records created successfully'),
                    'FormSubmissionHandler',
                    'submitForm',
                    'Session: ' + sessionId + ', Opportunity: ' + opportunityId
                );

                String submitterEmail = (String) answers.get('email');
                sendSubmitterEmail(sessionId, submitterEmail);
                queueSalesTeamEmail(sessionId, opportunityId);

            } catch (Exception recordEx) {
                Form_Session__c sessionForError = [
                    SELECT Id, Name
                    FROM Form_Session__c
                    WHERE Id = :sessionId
                    LIMIT 1
                ];

                ApexLog.logMessage(
                    ApexLog.LogLevel.ERROR,
                    withSessionPrefix('Record creation failed'),
                    'FormSubmissionHandler',
                    'submitForm',
                    'Session: ' + sessionId + ', Application Number: ' + sessionForError.Name + ', Error: ' + recordEx.getMessage()
                );

                sendFailureNotificationEmail(sessionId, sessionForError.Name, recordEx.getMessage());

                throw recordEx;
            }

            Form_Session__c sessionRecord = [
                SELECT Id, Name 
                FROM Form_Session__c 
                WHERE Id = :sessionId 
                LIMIT 1
            ];

            Map<String, Object> postSubmit = new Map<String, Object>{
                'showConfirmationPage' => true,
                'messageBody' => 'We are reviewing the details of your project and preparing a quote.',
                'whatNext' => new Map<String, Object>{
                    'title' => 'What\'s Next?',
                    'items' => new List<String>{
                        'A BioRequest team member will reach out within 1 business day to confirm any additional details about your study or donor requirements.',
                        'A summary of your request has been sent to your email (check spam if it is not in your inbox).',
                        'Your quote will follow shortly after we verify feasibility, donor availability, and any required clinical metadata.'
                    }
                },
                'footerText' => 'While you wait, check out our available <a href="https://www.company.com/products/?pro_inventory=inventory" target="_blank">inventory</a>. If you have any questions, please contact contact@company.com.',
                'signatureText' => 'Thank you,',
                'signatureName' => 'BioRequest Team',
                'contactEmail' => 'contact@company.com',
                'applicationNumber' => sessionRecord.Name
            };

            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'message' => 'Study request submitted successfully!',
                'sessionId' => sessionId,
                'opportunityId' => opportunityId,
                'recordId' => opportunityId,
                'postSubmit' => postSubmit
            };

            return JSON.serialize(result);
            
        } catch (SRFSubmissionException ex) {
            
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                withSessionPrefix('SRF submission validation failed'),
                'FormSubmissionHandler',
                'submitForm',
                'Session: ' + sessionId + ', Error: ' + ex.getMessage()
            );
            
            return buildErrorResponse(ex.getMessage(), sessionId);
            
        }
    }

    /**
     * @description Prefixes a message with the session name for easy cross-reference in logs
     * @param message The original log message
     * @return The message prefixed with session name if available
     */
    private String withSessionPrefix(String message) {
        if (String.isNotBlank(this.sessionName)) {
            return '[Session: ' + this.sessionName + '] ' + message;
        }
        return message;
    }

    /**
     * @description Load wizard configuration from custom metadata
     * @param wizardType The wizard type to load configuration for
     */
    private void loadWizardConfiguration(String wizardType) {

            
            Dynamic_Form_Config__c config = [
                SELECT Id, Title__c, Form_Config__c
                FROM Dynamic_Form_Config__c
                WHERE Title__c = :wizardType
                LIMIT 1
            ];
            
            wizardConfig = (Map<String, Object>) JSON.deserializeUntyped(config.Form_Config__c);
            
       
    }
    
    /**
     * @description Build a cache of field mappings from the wizard configuration
     *              This parses all targetField properties from the JSON config
     */
    private void buildFieldMappingCache() {
        fieldMappingCache = new Map<String, Map<String, Object>>();
        
        // Parse step-level field mappings
        List<Object> steps = (List<Object>) wizardConfig.get('steps');
        
        if (steps == null) {
            return;
        }
        
        for (Object stepObj : steps) {
            Map<String, Object> step = (Map<String, Object>) stepObj;
            parseStepSections(step);
        }
        
        // Store cohort and shipping mappings for nested object processing
        Object cohortMappingsObj = wizardConfig.get('cohortFieldMappings');
        Object shippingMappingsObj = wizardConfig.get('shippingFieldMappings');
        
        fieldMappingCache.put('__cohortFieldMappings', (Map<String, Object>) cohortMappingsObj);
        fieldMappingCache.put('__shippingFieldMappings', (Map<String, Object>) shippingMappingsObj);
    }
    
    /**
     * @description Parse sections from a step and extract field mappings
     * @param step The step map containing sections
     */
    private void parseStepSections(Map<String, Object> step) {
        List<Object> sections = (List<Object>) step.get('sections');
        if (sections == null) {
            return;
        }
        
        for (Object sectionObj : sections) {
            Map<String, Object> section = (Map<String, Object>) sectionObj;
            List<Object> questions = (List<Object>) section.get('questions');
            
            if (questions != null) {
                parseQuestions(questions);
            }
        }
    }
    
    /**
     * @description Parse questions and add field mappings to cache
     * @param questions List of question objects
     */
    private void parseQuestions(List<Object> questions) {
        for (Object questionObj : questions) {
            Map<String, Object> question = (Map<String, Object>) questionObj;
            String fieldName = (String) question.get('name');
            String targetField = (String) question.get('targetField');
            
            if (String.isNotBlank(fieldName) && String.isNotBlank(targetField)) {
                fieldMappingCache.put(fieldName, new Map<String, Object>{
                    'targetField' => targetField,
                    'type' => question.get('type'),
                    'isRequired' => question.get('isRequired')
                });
            }
        }
    }
    
    /**
     * @description Create all Salesforce records using comprehensive field mapping
     *              Maps all form form fields to Salesforce objects per field mapping specification
     * 
     * @param answers Map of form answers from Answers_JSON__c
     * @param sessionId Form_Session__c Id (not currently used but kept for interface compatibility)
     * @return Id of created Opportunity
     */
    private Id createRecordsDynamically(Map<String, Object> answers, Id sessionId) {
        createAccountAndContact(answers);
        createOpportunity(answers);

        String studyType = (String) answers.get('studyType');
        createCohortsWithBiospecimens(answers, studyType);
        createIECriteriaWithAttributes(answers);
        applyDeferredCohortFields();
        createSiteCodesWithAssignments(answers);

        return opportunityRecord.Id;
    }
    
    /**
     * @description Create Account record from Organization field
     * NOTE: FLS check removed - class runs 'without sharing' to support guest user submissions
     * @param answers Form answers map
     */
    private void createAccount(Map<String, Object> answers) {
        accountRecord = new Account();

        String organizationName = (String) answers.get('organization');
        accountRecord.Name = organizationName;

        Id accountRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Sales_Layout')?.getRecordTypeId();
        if (accountRtId != null) {
            accountRecord.RecordTypeId = accountRtId;
        }

        try {
            insert accountRecord;
            ApexLog.logMessage(
                ApexLog.LogLevel.INFO,
                withSessionPrefix('Account created successfully'),
                'FormSubmissionHandler',
                'createAccount',
                'Account Id: ' + accountRecord.Id + ', Name: ' + organizationName
            );
        } catch (Exception ex) {
            ApexLog.logException(ex, 'FormSubmissionHandler', 'createAccount', withSessionPrefix('Failed to create Account. Name: ' + organizationName));
            throw ex;
        }
    }
    
    /**
     * @description Create Contact record from Contact Information Section.
     * Called only when no duplicate contact was found by findDuplicateContact().
     * NOTE: FLS check removed - class runs 'without sharing' to support guest user submissions
     * @param answers Form answers map
     */
    private void createContact(Map<String, Object> answers) {
        contactRecord = new Contact();
        contactRecord.AccountId = accountRecord.Id;

        Id contactRtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
            .get('Researcher')?.getRecordTypeId();

        if (contactRtId != null) {
            contactRecord.RecordTypeId = contactRtId;
        } else {
            throw new SRFSubmissionException('Contact record type Researcher not found. Required for public user permissions.');
        }

        contactRecord.FirstName = (String) answers.get('firstName');
        contactRecord.LastName = (String) answers.get('lastName');
        contactRecord.Email = (String) answers.get('email');
        contactRecord.Phone = (String) answers.get('phone');
        contactRecord.Title = (String) answers.get('role');

        // Allow duplicates since we already checked via findDuplicateContact()
        // This handles race conditions where a duplicate appears between check and insert
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        dmlOptions.DuplicateRuleHeader.runAsCurrentUser = false;

        Database.SaveResult saveResult = Database.insert(contactRecord, dmlOptions);

        if (!saveResult.isSuccess()) {
            String errorMsg = '';
            for (Database.Error err : saveResult.getErrors()) {
                errorMsg += err.getMessage() + '; ';
            }
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                withSessionPrefix('Failed to create Contact'),
                'FormSubmissionHandler',
                'createContact',
                'Email: ' + contactRecord.Email + ', Error: ' + errorMsg
            );
            throw new SRFSubmissionException('Failed to create Contact: ' + errorMsg);
        }

        ApexLog.logMessage(
            ApexLog.LogLevel.INFO,
            withSessionPrefix('Contact created successfully'),
            'FormSubmissionHandler',
            'createContact',
            'Contact Id: ' + contactRecord.Id + ', Email: ' + contactRecord.Email
        );
    }

    /**
     * @description Check for duplicate contact before creating records.
     * Uses Datacloud.FindDuplicates to find existing contacts without DML.
     * @param answers Form answers map
     * @return Id of existing contact if duplicate found, null otherwise
     */
    private Id findDuplicateContact(Map<String, Object> answers) {
        Contact contactToCheck = new Contact();
        contactToCheck.FirstName = (String) answers.get('firstName');
        contactToCheck.LastName = (String) answers.get('lastName');
        contactToCheck.Email = (String) answers.get('email');
        contactToCheck.Phone = (String) answers.get('phone');
        contactToCheck.Title = (String) answers.get('role');

        Schema.RecordTypeInfo dupContactRtInfo = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Researcher');
        if (dupContactRtInfo != null) {
            contactToCheck.RecordTypeId = dupContactRtInfo.getRecordTypeId();
        }

        try {
            List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicates.findDuplicates(
                new List<SObject>{ contactToCheck }
            );

            for (Datacloud.FindDuplicatesResult result : results) {
                for (Datacloud.DuplicateResult duplicateResult : result.getDuplicateResults()) {
                    for (Datacloud.MatchResult matchResult : duplicateResult.getMatchResults()) {
                        for (Datacloud.MatchRecord matchRecord : matchResult.getMatchRecords()) {
                            if (matchRecord.getRecord() != null && matchRecord.getRecord().Id != null) {
                                ApexLog.logMessage(
                                    ApexLog.LogLevel.INFO,
                                    withSessionPrefix('Duplicate contact detected during pre-check'),
                                    'FormSubmissionHandler',
                                    'findDuplicateContact',
                                    'Existing Contact Id: ' + matchRecord.getRecord().Id + ', Email: ' + contactToCheck.Email
                                );
                                return matchRecord.getRecord().Id;
                            }
                        }
                    }
                }
            }
        } catch (Exception ex) {
            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                withSessionPrefix('Error checking for duplicate contact'),
                'FormSubmissionHandler',
                'findDuplicateContact',
                'Email: ' + contactToCheck.Email + ', Error: ' + ex.getMessage()
            );
        }

        // No duplicate found
        return null;
    }

    /**
     * @description Create Account and Contact with duplicate detection.
     * Checks for duplicate contact FIRST before creating any records.
     * If duplicate found, uses existing contact and its account (if present).
     * If duplicate is orphan (no account), creates new account and links it.
     * @param answers Form answers map
     */
    private void createAccountAndContact(Map<String, Object> answers) {
        Id existingContactId = findDuplicateContact(answers);

        if (existingContactId != null) {
            // Duplicate contact found - query for contact and its account
            Contact existingContact = [
                SELECT Id, AccountId, FirstName, LastName, Email
                FROM Contact
                WHERE Id = :existingContactId
                LIMIT 1
            ];
            contactRecord = existingContact;

            if (existingContact.AccountId != null) {
                // Contact has an account - use existing account
                accountRecord = new Account(Id = existingContact.AccountId);
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    withSessionPrefix('Using existing Account from duplicate Contact'),
                    'FormSubmissionHandler',
                    'createAccountAndContact',
                    'Account Id: ' + existingContact.AccountId + ', Contact Id: ' + existingContactId
                );
            } else {
                // Orphan contact - create new account and link
                createAccount(answers);
                contactRecord.AccountId = accountRecord.Id;
                update contactRecord;
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    withSessionPrefix('Linked orphan Contact to new Account'),
                    'FormSubmissionHandler',
                    'createAccountAndContact',
                    'Account Id: ' + accountRecord.Id + ', Contact Id: ' + existingContactId
                );
            }

            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                withSessionPrefix('Using existing duplicate Contact'),
                'FormSubmissionHandler',
                'createAccountAndContact',
                'Contact Id: ' + existingContactId + ', Email: ' + existingContact.Email
            );
        } else {
            // No duplicate - create new account and contact
            createAccount(answers);
            createContact(answers);
        }
    }

    /**
     * @description Create Opportunity with comprehensive field mapping per CSV specification
     * NOTE: FLS check removed - class runs 'without sharing' to support guest user submissions
     * @param answers Form answers map
     */
    @SuppressWarnings('PMD.CognitiveComplexity')
    private void createOpportunity(Map<String, Object> answers) {
        opportunityRecord = new Opportunity();

        opportunityRecord.Name = Date.today().format() + '_' + accountRecord.Id + '_Study';

        opportunityRecord.AccountId = accountRecord.Id;
        opportunityRecord.StageName = 'Stage 1 - Information Gathering';
        opportunityRecord.Type = 'New Business';
        opportunityRecord.ForecastCategoryName = 'Pipeline';
        opportunityRecord.CloseDate = Date.today();

        opportunityRecord.put('Sponsor_Type__c', 'Big Pharma');

        // Map Budget Estimate from form - field is Currency/Decimal, must convert from String
        String budgetEstimate = (String) answers.get('budgetEstimate');
        if (String.isNotBlank(budgetEstimate)) {
            try {
                opportunityRecord.put('Estimated_Study_Budget__c', Decimal.valueOf(budgetEstimate));
            } catch (TypeException te) {
                ApexLog.logMessage(ApexLog.LogLevel.WARN, withSessionPrefix('Budget estimate not numeric, skipped: ' + budgetEstimate), 'FormSubmissionHandler', 'createOpportunity', '');
            }
        }

        String studyType = (String) answers.get('studyType');

        Map<String, Schema.RecordTypeInfo> oppRtMap = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();

        if (String.isNotBlank(studyType)) {
            if (studyType.equalsIgnoreCase('Cohort_Standard') || studyType.equalsIgnoreCase('Prospective')) {
                Schema.RecordTypeInfo oppRtInfo = oppRtMap.get('Opp_without_Qoute');
                if (oppRtInfo != null) {
                    opportunityRecord.RecordTypeId = oppRtInfo.getRecordTypeId();
                } else {
                    ApexLog.logMessage(ApexLog.LogLevel.WARN, withSessionPrefix('Opportunity RT Opp_without_Qoute not found - proceeding without RT'), 'FormSubmissionHandler', 'createOpportunity', '');
                }
                opportunityRecord.put('Project_Type__c', 'Home-Based Collection');

            } else if (studyType.equalsIgnoreCase('Leukopak')) {
                String condition = (String) answers.get('cohort0_leuko_condition');
                String rtDevName = (condition != null && condition.equalsIgnoreCase('Healthy')) ? 'Leukopak_Healthy' : 'Leukopak';
                Schema.RecordTypeInfo oppRtInfo = oppRtMap.get(rtDevName);
                if (oppRtInfo != null) {
                    opportunityRecord.RecordTypeId = oppRtInfo.getRecordTypeId();
                } else {
                    ApexLog.logMessage(ApexLog.LogLevel.WARN, withSessionPrefix('Opportunity RT ' + rtDevName + ' not found - proceeding without RT'), 'FormSubmissionHandler', 'createOpportunity', '');
                }
                opportunityRecord.put('Project_Type__c', 'Leukopak Collection');
            }
        }

        // Use Database.DMLOptions to allow duplicates
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        dmlOptions.DuplicateRuleHeader.runAsCurrentUser = false;

        Database.SaveResult saveResult = Database.insert(opportunityRecord, dmlOptions, AccessLevel.SYSTEM_MODE);

        if (!saveResult.isSuccess()) {
            String errorMsg = '';
            Boolean isDuplicateError = false;
            for (Database.Error err : saveResult.getErrors()) {
                errorMsg += err.getMessage() + '; ';
                if (err.getStatusCode() == StatusCode.DUPLICATES_DETECTED) {
                    isDuplicateError = true;
                }
            }

            if (isDuplicateError) {
                ApexLog.logMessage(
                    ApexLog.LogLevel.WARN,
                    withSessionPrefix('Duplicate Opportunity detected but allowed'),
                    'FormSubmissionHandler',
                    'createOpportunity',
                    'Opportunity Name: ' + opportunityRecord.Name + ', Error: ' + errorMsg
                );
            } else {
                ApexLog.logMessage(
                    ApexLog.LogLevel.ERROR,
                    withSessionPrefix('Failed to create Opportunity'),
                    'FormSubmissionHandler',
                    'createOpportunity',
                    'Opportunity Name: ' + opportunityRecord.Name + ', Error: ' + errorMsg
                );
                throw new SRFSubmissionException('Failed to create Opportunity: ' + errorMsg);
            }
        } else {
            ApexLog.logMessage(
                ApexLog.LogLevel.INFO,
                withSessionPrefix('Opportunity created successfully'),
                'FormSubmissionHandler',
                'createOpportunity',
                'Opportunity Id: ' + opportunityRecord.Id + ', Name: ' + opportunityRecord.Name
            );
        }
    }
    
    /**
     * @description Create Research_Proposal__c (Cohort) records with comprehensive biospecimen field mapping
     *              Maps all 100+ biospecimen, testing, timeline, and leukopak fields per CSV specification
     * @param answers Form answers map
     * @param studyType Study type (Prospective or Leukopak)
     * NOTE: FLS check removed - class runs 'without sharing' to support guest user submissions
     */
    @SuppressWarnings('PMD.CognitiveComplexity')
    private void createCohortsWithBiospecimens(Map<String, Object> answers, String studyType) {
        // Determine number of cohorts
        Integer numberOfCohorts = 1;
        Object cohortCountObj = answers.get('numberOfCohorts');
        if (cohortCountObj != null) {

                numberOfCohorts = Integer.valueOf(cohortCountObj);

        }

        Id cohortRecordTypeId = null;
        if (String.isNotBlank(studyType)) {
            // Both Prospective and Leukopak studies use 'Cohort Standard' record type for cohorts
            if (studyType.equalsIgnoreCase('Cohort_Standard') || studyType.equalsIgnoreCase('Prospective') || studyType.equalsIgnoreCase('Leukopak')) {
                Schema.RecordTypeInfo cohortRtInfo = Schema.SObjectType.Research_Proposal__c.getRecordTypeInfosByDeveloperName().get('Cohort_Standard');
                if (cohortRtInfo != null) {
                    cohortRecordTypeId = cohortRtInfo.getRecordTypeId();
                }
            }
        }

        // Build all cohort records first (without trigger-causing fields)
        List<Research_Proposal__c> cohortsToInsert = new List<Research_Proposal__c>();

        for (Integer i = 0; i < numberOfCohorts; i++) {
            String cohortPrefix = 'cohort' + i + '_';

            Research_Proposal__c cohort = new Research_Proposal__c();
            cohort.Proposal__c = opportunityRecord.Id;

            if (cohortRecordTypeId != null) {
                cohort.RecordTypeId = cohortRecordTypeId;
            }

            cohort.Lab_Storage_Required__c = true;
            cohort.Lab_Storage_Type__c = '-70/-80C Freezer';

            String cohortLabel = (String) answers.get(cohortPrefix + 'cohortLabel');
            if (String.isBlank(cohortLabel)) {
                Object cohortNamesObj = answers.get('cohortNames');
                if (cohortNamesObj instanceof List<Object>) {
                    List<Object> cohortNamesList = (List<Object>) cohortNamesObj;
                    if (i < cohortNamesList.size() && cohortNamesList[i] != null) {
                        cohortLabel = String.valueOf(cohortNamesList[i]);
                    }
                }
            }

            if (String.isNotBlank(cohortLabel)) {
                cohort.Cohort_Label__c = cohortLabel;
            }

            mapBiospecimenFields(cohort, answers, cohortPrefix);
            mapTestingFields(cohort, answers, cohortPrefix);
            // mapTimelineFields deferred - sets Requirements_besides_confirmed_diagnosis__c
            // which triggers CohortIEOrchestrator causing INSUFFICIENT_ACCESS errors
            mapTimelineFieldsDeferred(cohort, answers, cohortPrefix, i);

            if (studyType != null && studyType.equalsIgnoreCase('Leukopak')) {
                mapLeukopakFields(cohort, answers, cohortPrefix);
            }

            cohortsToInsert.add(cohort);
        }

        // Bulk insert all cohorts (trigger fires but won't create I/E criteria
        // because Opportunity_Diagnosis__c and Requirements_besides_confirmed_diagnosis__c are null)
        if (!cohortsToInsert.isEmpty()) {
            try {
                insert cohortsToInsert;
                cohortRecords.addAll(cohortsToInsert);

                List<String> cohortIds = new List<String>();
                for (Research_Proposal__c c : cohortsToInsert) {
                    cohortIds.add(c.Id);
                }
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    withSessionPrefix('Cohorts created successfully'),
                    'FormSubmissionHandler',
                    'createCohortsWithBiospecimens',
                    'Cohort Ids: ' + String.join(cohortIds, ', ') + ', Count: ' + cohortsToInsert.size()
                );
            } catch (Exception ex) {
                ApexLog.logException(
                    ex,
                    'FormSubmissionHandler',
                    'createCohortsWithBiospecimens',
                    withSessionPrefix('Failed to create Cohorts. Count: ' + cohortsToInsert.size())
                );
                throw ex;
            }
        }

    }
    
    /**
     * @description Map all biospecimen fields from form to cohort record
     *              Includes: Whole Blood, Plasma, Serum, DNA, RNA, PBMC, T Cell, B Cell, NK Cell,
     *                       Buccal, Nasal, Saliva, Semen, Hair, Nail, Urine, Stool, Sputum,
     *                       Skin Tape Strips, Skin Punch Biopsy, Synovial Fluid, Bulk Plasma, Buffy Coat, Other
     * @param cohort Research_Proposal__c record to populate
     * @param answers Form answers map
     * @param cohortPrefix Prefix for this cohort (e.g., "cohort0_")
     */
    @SuppressWarnings('PMD.NcssMethodCount')
    private void mapBiospecimenFields(Research_Proposal__c cohort, Map<String, Object> answers, String cohortPrefix) {
        // Whole Blood
        setFieldIfPresent(cohort, 'Whole_Blood_Collection_Mats__c', answers.get(cohortPrefix + 'wholeBlood_collection_materials'));
        setFieldIfPresent(cohort, 'Target_Whole_Blood_Volume_mL__c', answers.get(cohortPrefix + 'wholeBlood_volume'));
        setFieldIfPresent(cohort, 'Whole_Blood_Temp_Options__c', answers.get(cohortPrefix + 'wholeBlood_temperature'));
        setFieldIfPresent(cohort, 'Custom_Blood_Materials__c', answers.get(cohortPrefix + 'wholeBlood_custom_materials'));
        
        // RBC (Red Blood Cells)
        setFieldIfPresent(cohort, 'RBC_Collection_Mats__c', answers.get(cohortPrefix + 'rbc_collection_materials'));
        setFieldIfPresent(cohort, 'Blood_Vol_for_RBC_isolation__c', answers.get(cohortPrefix + 'rbc_blood_volume'));
        setFieldIfPresent(cohort, 'RBC_Temp_Options__c', answers.get(cohortPrefix + 'rbc_temperature_options'));
        setFieldIfPresent(cohort, 'RBC_Aliquot_Size__c', answers.get(cohortPrefix + 'rbc_aliquot_size'));
        setFieldIfPresent(cohort, 'Custom_RBC_Materials__c', answers.get(cohortPrefix + 'rbc_custom_materials'));
        
        // Plasma
        setFieldIfPresent(cohort, 'Plasma_Isolation_Collection_Mats__c', answers.get(cohortPrefix + 'plasma_collection_materials'));
        setFieldIfPresent(cohort, 'Plasma_Volume__c', answers.get(cohortPrefix + 'plasma_volume'));
        setFieldIfPresent(cohort, 'Plasma_Aliquot_Size_mL__c', answers.get(cohortPrefix + 'plasma_aliquot_size'));
        setFieldIfPresent(cohort, 'Plasma_Isolation_Temp_Options__c', answers.get(cohortPrefix + 'plasma_temperature'));
        setFieldIfPresent(cohort, 'Plasma_Processing_Location__c', answers.get(cohortPrefix + 'plasma_processing_location'));
        setFieldIfPresent(cohort, 'WB_Shipment_for_Plasma_Temp_Options__c', answers.get(cohortPrefix + 'plasma_shipping_temp'));
        setFieldIfPresent(cohort, 'Custom_Plasma_Materials__c', answers.get(cohortPrefix + 'plasma_custom_materials'));

        // Bulk Plasma (maps to plasma fields)
        setFieldIfPresent(cohort, 'Plasma_Volume__c', answers.get(cohortPrefix + 'bulkPlasma_volume'));
        setFieldIfPresent(cohort, 'Plasma_Isolation_Temp_Options__c', answers.get(cohortPrefix + 'bulkPlasma_temperature'));

        // Serum
        setFieldIfPresent(cohort, 'Serum_Isolation_Collection_Mats__c', answers.get(cohortPrefix + 'serum_collection_materials'));
        setFieldIfPresent(cohort, 'Serum_Volume__c', answers.get(cohortPrefix + 'serum_volume'));
        setFieldIfPresent(cohort, 'Serum_Aliquot_Size_mL__c', answers.get(cohortPrefix + 'serum_aliquot_size'));
        setFieldIfPresent(cohort, 'Serum_Isolation_Temp_Options__c', answers.get(cohortPrefix + 'serum_temperature'));
        setFieldIfPresent(cohort, 'Serum_Processing_Location__c', answers.get(cohortPrefix + 'serum_processing_location'));
        setFieldIfPresent(cohort, 'WB_Shipment_for_Serum_Temp_Options__c', answers.get(cohortPrefix + 'serum_shipping_temp'));
        setFieldIfPresent(cohort, 'Custom_Serum_Materials__c', answers.get(cohortPrefix + 'serum_custom_materials'));
        
        // DNA
        setFieldIfPresent(cohort, 'DNA_Collection_Mats__c', answers.get(cohortPrefix + 'dna_collection_materials'));
        setFieldIfPresent(cohort, 'DNA_Volume__c', answers.get(cohortPrefix + 'dna_volume'));
        setFieldIfPresent(cohort, 'DNA_Temp_Options__c', answers.get(cohortPrefix + 'dna_temperature'));
        setFieldIfPresent(cohort, 'Custom_DNA_Collection_Materials__c', answers.get(cohortPrefix + 'dna_custom_materials'));
        
        // RNA
        setFieldIfPresent(cohort, 'RNA_Collection_Mats__c', answers.get(cohortPrefix + 'rna_collection_materials'));
        setFieldIfPresent(cohort, 'RNA_Volume__c', answers.get(cohortPrefix + 'rna_volume'));
        setFieldIfPresent(cohort, 'RNA_Temp_Options__c', answers.get(cohortPrefix + 'rna_temperature'));
        setFieldIfPresent(cohort, 'Custom_RNA_Materials__c', answers.get(cohortPrefix + 'rna_custom_materials'));
        
        // PBMC
        setFieldIfPresent(cohort, 'PBMC_Isolation_Tubes_Collection_Mats__c', answers.get(cohortPrefix + 'pbmc_collection_materials'));
        setFieldIfPresent(cohort, 'Custom_PBMC_Materials__c', answers.get(cohortPrefix + 'pbmc_custom_materials'));
        setFieldIfPresent(cohort, 'PBMC_Volume__c', answers.get(cohortPrefix + 'pbmc_volume'));
        setFieldIfPresent(cohort, 'PBMC_Aliquot_Unit_of_Measurement__c', answers.get(cohortPrefix + 'pbmc_aliquot_size'));
        setFieldIfPresent(cohort, 'PBMC_Isolation_Temp_Options__c', answers.get(cohortPrefix + 'pbmc_temperature'));
        setFieldIfPresent(cohort, 'PBMC_Isolation_Temp_Options__c', answers.get(cohortPrefix + 'pbmc_shipping_temperature'));
        setFieldIfPresent(cohort, 'WB_Shipment_for_PBMC_Temp_Options__c', answers.get(cohortPrefix + 'pbmc_wb_shipment_temp'));
        setFieldIfPresent(cohort, 'PBMC_Unit_of_Measure_Custom_Millions__c', answers.get(cohortPrefix + 'pbmc_custom_aliquot_size'));
        
        // T Cell
        setFieldIfPresent(cohort, 'T_Cell_Collection_Mats__c', answers.get(cohortPrefix + 'tCell_collection_materials'));
        setFieldIfPresent(cohort, 'Whole_Blood_Volume_for_T_Cell_Isolation__c', answers.get(cohortPrefix + 'tCell_volume'));
        setFieldIfPresent(cohort, 'T_Cell_Aliquot_Size__c', answers.get(cohortPrefix + 'tCell_aliquot_size'));
        setFieldIfPresent(cohort, 'T_Cell_Selection_Method__c', answers.get(cohortPrefix + 'tCell_selection_method'));
        setFieldIfPresent(cohort, 'Custom_T_Cell_Materials__c', answers.get(cohortPrefix + 'tCell_custom_materials'));
        setFieldIfPresent(cohort, 'Custom_T_Aliquot_Size_Million__c', answers.get(cohortPrefix + 'tCell_custom_aliquot_size'));
        
        // B Cell
        setFieldIfPresent(cohort, 'B_Cell_Collection_Mats__c', answers.get(cohortPrefix + 'bCell_collection_materials'));
        setFieldIfPresent(cohort, 'Whole_Blood_Volume_for_B_Cell_Isolation__c', answers.get(cohortPrefix + 'bCell_volume'));
        setFieldIfPresent(cohort, 'B_Cell_Aliquot_Size__c', answers.get(cohortPrefix + 'bCell_aliquot_size'));
        setFieldIfPresent(cohort, 'B_Cell_Selection_Method__c', answers.get(cohortPrefix + 'bCell_selection_method'));
        setFieldIfPresent(cohort, 'Custom_B_Cell_Materials__c', answers.get(cohortPrefix + 'bCell_custom_materials'));
        setFieldIfPresent(cohort, 'Custom_B_Aliquot_Size_Million__c', answers.get(cohortPrefix + 'bCell_custom_aliquot_size'));

        // NK Cell
        setFieldIfPresent(cohort, 'NK_Cell_Collection_Mats__c', answers.get(cohortPrefix + 'nkCell_collection_materials'));
        setFieldIfPresent(cohort, 'Whole_Blood_Volume_for_NK_Cell_Isolation__c', answers.get(cohortPrefix + 'nkCell_volume'));
        setFieldIfPresent(cohort, 'NK_Cell_Aliquot_Size__c', answers.get(cohortPrefix + 'nkCell_aliquot_size'));
        setFieldIfPresent(cohort, 'Custom_NK_Cell_Materials__c', answers.get(cohortPrefix + 'nkCell_custom_materials'));
        setFieldIfPresent(cohort, 'Custom_NK_Cell_Aliquot_Size_Million__c', answers.get(cohortPrefix + 'nkCell_custom_aliquot_size'));
        
        // Buccal Swabs
        setFieldIfPresent(cohort, 'Buccal_Collection_Mats__c', answers.get(cohortPrefix + 'buccalSwabs_collection_materials'));
        setFieldIfPresent(cohort, 'Buccal_Temp_Options__c', answers.get(cohortPrefix + 'buccalSwabs_temperature'));
        setFieldIfPresent(cohort, 'Buccal_Aliquot_Number_of_Swabs__c', answers.get(cohortPrefix + 'buccalSwabs_number'));
        setFieldIfPresent(cohort, 'PC_Custom_Buccal_Materials__c', answers.get(cohortPrefix + 'buccal_custom_materials'));
        
        // Nasal Swabs
        setFieldIfPresent(cohort, 'Nasal_Swabs_Collection_Mats__c', answers.get(cohortPrefix + 'nasalSwabs_collection_materials'));
        setFieldIfPresent(cohort, 'Nasal_Swabs__c', answers.get(cohortPrefix + 'nasalSwabs_temperature'));
        setFieldIfPresent(cohort, 'Nasal_Swabs_Number_of_Swabs__c', answers.get(cohortPrefix + 'nasalSwabs_number'));
        
        // Saliva
        setFieldIfPresent(cohort, 'Saliva_Collection_Materials__c', answers.get(cohortPrefix + 'saliva_collection_materials'));
        setFieldIfPresent(cohort, 'Saliva_Temperature_Requirement__c', answers.get(cohortPrefix + 'saliva_temperature'));
        setFieldIfPresent(cohort, 'Saliva_Volume__c', answers.get(cohortPrefix + 'saliva_volume'));
        
        // Semen
        setFieldIfPresent(cohort, 'Semen_Collection_Mats__c', answers.get(cohortPrefix + 'semen_collection_materials'));
        setFieldIfPresent(cohort, 'Semen_Temp_Options__c', answers.get(cohortPrefix + 'semen_temperature'));
        setFieldIfPresent(cohort, 'Semen_Collection_Mats_Custom__c', answers.get(cohortPrefix + 'semen_custom_materials'));
        
        // Hair
        setFieldIfPresent(cohort, 'Hair_Collection_Mats__c', answers.get(cohortPrefix + 'hair_collection_materials'));
        setFieldIfPresent(cohort, 'Hair_Temp_Options__c', answers.get(cohortPrefix + 'hair_temperature'));
        
        // Nail (Fingernails)
        setFieldIfPresent(cohort, 'Nail_Collection_Mats__c', answers.get(cohortPrefix + 'fingernails_collection_materials'));
        setFieldIfPresent(cohort, 'Nail_Temp_Options__c', answers.get(cohortPrefix + 'fingernails_temperature'));
        
        // Urine
        setFieldIfPresent(cohort, 'Urine_Collection_Mats__c', answers.get(cohortPrefix + 'urine_collection_materials'));
        setFieldIfPresent(cohort, 'Urine_Temp_Options__c', answers.get(cohortPrefix + 'urine_temperature'));
        setFieldIfPresent(cohort, 'Urine_Aliquot_Size__c', answers.get(cohortPrefix + 'urine_aliquot_size'));
        setFieldIfPresent(cohort, 'First_Void__c', answers.get(cohortPrefix + 'urine_first_void'));
        setFieldIfPresent(cohort, 'Urine_processing_required__c', answers.get(cohortPrefix + 'urine_processing_required'));
        setFieldIfPresent(cohort, 'Separation_of_Supernatant_from_Pellet__c', answers.get(cohortPrefix + 'urine_separate_supernatant'));
        setFieldIfPresent(cohort, 'Discard_pellet__c', answers.get(cohortPrefix + 'urine_discard_pellet'));
        setFieldIfPresent(cohort, 'Urine_Collection_Details__c', answers.get(cohortPrefix + 'urine_collection_details'));
        setFieldIfPresent(cohort, 'Urine_Collection_Mats_Custom__c', answers.get(cohortPrefix + 'urine_custom_materials'));
        setFieldIfPresent(cohort, 'Urine_Aliquot_Size_Custom__c', answers.get(cohortPrefix + 'urine_custom_aliquot_size'));

        // Stool
        setFieldIfPresent(cohort, 'Stool_Collection_Mats__c', answers.get(cohortPrefix + 'stool_collection_materials'));
        setFieldIfPresent(cohort, 'Stool_Temp_Options__c', answers.get(cohortPrefix + 'stool_temperature'));
        setFieldIfPresent(cohort, 'Stool_Requirements__c', answers.get(cohortPrefix + 'stool_requirements'));
        setFieldIfPresent(cohort, 'Stool_Collection_Mats_Custom__c', answers.get(cohortPrefix + 'stool_custom_materials'));
        
        // Sputum
        setFieldIfPresent(cohort, 'Sputum_Collection_Mats__c', answers.get(cohortPrefix + 'sputum_collection_materials'));
        setFieldIfPresent(cohort, 'Sputum_Temp_Options__c', answers.get(cohortPrefix + 'sputum_temperature'));
        setFieldIfPresent(cohort, 'Sputum_Collection_Mats_Custom__c', answers.get(cohortPrefix + 'sputum_custom_materials'));
        
        // Skin Tape Strips
        setFieldIfPresent(cohort, 'Skin_Collection_Mats__c', answers.get(cohortPrefix + 'skinTapeStrips_collection_materials'));
        setFieldIfPresent(cohort, 'Number_of_Strips__c', answers.get(cohortPrefix + 'skinTapeStrips_number'));
        setFieldIfPresent(cohort, 'Skin_Temp_Options__c', answers.get(cohortPrefix + 'skinTapeStrips_temperature'));
        setFieldIfPresent(cohort, 'Regions_for_Skin_Taping__c', answers.get(cohortPrefix + 'skinTapeStrips_regions'));
        
        // Skin Punch Biopsy
        setFieldIfPresent(cohort, 'Number_of_Skin_Punch_Biopsy_Samples__c', answers.get(cohortPrefix + 'skinPunchBiopsy_number'));
        setFieldIfPresent(cohort, 'Skin_Punch_Biopsy_Depth__c', answers.get(cohortPrefix + 'skinPunchBiopsy_size'));
        setFieldIfPresent(cohort, 'Skin_Punch_Biopsy_Shipment_Temp_Options__c', answers.get(cohortPrefix + 'skinPunchBiopsy_temperature'));
        setFieldIfPresent(cohort, 'Skin_Punch_Biopsy_Details__c', answers.get(cohortPrefix + 'skinPunchBiopsy_details'));
        
        // Synovial Fluid
        setFieldIfPresent(cohort, 'Synovial_Fluid_Details__c', answers.get(cohortPrefix + 'synovialFluid_details'));
        setFieldIfPresent(cohort, 'Synovial_Fluid_Volume_mL__c', answers.get(cohortPrefix + 'synovialFluid_volume'));
        setFieldIfPresent(cohort, 'Synovial_Fluid_Shipment_Temp_Options__c', answers.get(cohortPrefix + 'synovialFluid_temperature'));
        setFieldIfPresent(cohort, 'Synovial_Fluid_Aliquot_Size_mL__c', answers.get(cohortPrefix + 'synovialFluid_aliquot_size'));
        
        // Buffy Coat
        setFieldIfPresent(cohort, 'Buffy_Coat_Collection_Mats__c', answers.get(cohortPrefix + 'buffyCoat_collection_materials'));
        setFieldIfPresent(cohort, 'Buffy_Coat_Temp_Options__c', answers.get(cohortPrefix + 'buffyCoat_temperature'));
        setFieldIfPresent(cohort, 'Blood_vol_For_Buffy_Coat__c', answers.get(cohortPrefix + 'buffyCoat_volume'));
        setFieldIfPresent(cohort, 'Custom_Buffy_Coat_Materials__c', answers.get(cohortPrefix + 'buffyCoat_custom_materials'));
        
        // Other/Custom Biospecimen
        setFieldIfPresent(cohort, 'Other_Sample_Volume__c', answers.get(cohortPrefix + 'other_sample_volume'));
        setFieldIfPresent(cohort, 'Other_Collection_Processing_Requirements__c', answers.get(cohortPrefix + 'other_collection_materials'));
        setFieldIfPresent(cohort, 'Other_Biospecimen_Collection_Temp_Req__c', answers.get(cohortPrefix + 'other_temperature'));
        setFieldIfPresent(cohort, 'Other_Biospecimen_Materials__c', answers.get(cohortPrefix + 'other_materials'));
        setFieldIfPresent(cohort, 'Other_Shipping_Requirements__c', answers.get(cohortPrefix + 'other_shipping_requirements'));
        
        // Collection Type (from Other Custom Biospecimen card)
        setFieldIfPresent(cohort, 'Collection_Type__c', answers.get(cohortPrefix + 'other_collection_type'));
    }
    
    /**
     * @description Map testing fields to cohort record
     * @param cohort Research_Proposal__c record
     * @param answers Form answers map
     * @param cohortPrefix Cohort prefix
     */
    private void mapTestingFields(Research_Proposal__c cohort, Map<String, Object> answers, String cohortPrefix) {
        setFieldIfPresent(cohort, 'Lab_Tests__c', answers.get(cohortPrefix + 'testing_no_testing'));
        setFieldIfPresent(cohort, 'Lab_Tests__c', answers.get(cohortPrefix + 'testing_custom_testing'));
    }
    
    /**
     * @description Map timeline fields to cohort record - DEFERRED VERSION
     *              Stores trigger-causing fields (Requirements_besides_confirmed_diagnosis__c)
     *              for later update to avoid CohortIEOrchestrator running with sharing context
     *              Timeline is now a shared step - all cohorts use the same timeline values
     * @param cohort Research_Proposal__c record
     * @param answers Form answers map
     * @param cohortPrefix Cohort prefix (not used for timeline as it's shared)
     * @param cohortIndex Index of the cohort for deferred field tracking
     */
    private void mapTimelineFieldsDeferred(Research_Proposal__c cohort, Map<String, Object> answers, String cohortPrefix, Integer cohortIndex) {
        String startDate = (String) answers.get('timeline_start');
        String targetCompletion = (String) answers.get('timeline_end');

        if (String.isNotBlank(startDate) || String.isNotBlank(targetCompletion)) {
            String timelineText = '';
            if (String.isNotBlank(startDate)) {
                timelineText += 'Start Date: ' + startDate;
            }
            if (String.isNotBlank(targetCompletion)) {
                if (String.isNotBlank(timelineText)) {
                    timelineText += '\n';
                }
                timelineText += 'Target Completion: ' + targetCompletion;
            }
            // Defer this field - it triggers CohortIEOrchestrator.createDiagnosisCriteria
            // which runs with sharing and causes INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
            if (!deferredCohortFields.containsKey(cohortIndex)) {
                deferredCohortFields.put(cohortIndex, new Map<String, Object>());
            }
            deferredCohortFields.get(cohortIndex).put('Requirements_besides_confirmed_diagnosis__c', timelineText);
        }

        // Number_of_Subjects__c is safe to set during insert (not checked by trigger)
        Object numDonors = answers.get(cohortPrefix + 'num_donors');
        if (numDonors != null) {
            setFieldIfPresent(cohort, 'Number_of_Subjects__c', numDonors);
        }
    }

    /**
     * @description Apply deferred cohort fields after I/E criteria have been created
     *              This updates cohorts with fields that would trigger CohortIEOrchestrator
     *              The trigger will fire but our I/E criteria already exist, avoiding conflicts
     */
    private void applyDeferredCohortFields() {
        if (deferredCohortFields == null || deferredCohortFields.isEmpty() || cohortRecords.isEmpty()) {
            return;
        }

        List<Research_Proposal__c> cohortsToUpdate = new List<Research_Proposal__c>();

        for (Integer i = 0; i < cohortRecords.size(); i++) {
            if (deferredCohortFields.containsKey(i)) {
                Map<String, Object> fields = deferredCohortFields.get(i);
                Research_Proposal__c cohortUpdate = new Research_Proposal__c(Id = cohortRecords[i].Id);

                for (String fieldName : fields.keySet()) {
                    setFieldIfPresent(cohortUpdate, fieldName, fields.get(fieldName));
                }

                cohortsToUpdate.add(cohortUpdate);
            }
        }

        if (!cohortsToUpdate.isEmpty()) {
            try {
                update cohortsToUpdate;
            } catch (Exception ex) {
                // Log but don't fail - these are supplementary fields
                ApexLog.logMessage(
                    ApexLog.LogLevel.WARN,
                    withSessionPrefix('Failed to apply deferred cohort fields'),
                    'FormSubmissionHandler',
                    'applyDeferredCohortFields',
                    'Error: ' + ex.getMessage()
                );
            }
        }
    }
    
    /**
     * @description Map leukopak-specific fields to cohort record
     * @param cohort Research_Proposal__c record
     * @param answers Form answers map
     * @param cohortPrefix Cohort prefix
     */
    private void mapLeukopakFields(Research_Proposal__c cohort, Map<String, Object> answers, String cohortPrefix) {
        Object condition = answers.get(cohortPrefix + 'leuko_condition');
        if (condition == null) {
            condition = answers.get(cohortPrefix + 'leukopak_condition');
        }
        setFieldIfPresent(cohort, 'Leukopak_Condition__c', condition);

        Object donorHla = answers.get(cohortPrefix + 'leukopak_hla_typing');
        if (donorHla != null && !(donorHla instanceof Boolean)) {
            setFieldIfPresent(cohort, 'Leukopak_HLA_requirement_s__c', donorHla);
        }

        Object donorMedical = answers.get(cohortPrefix + 'leuko_donor_medical');
        if (donorMedical != null) {
            setFieldIfPresent(cohort, 'Medical_Records_Required_New__c', donorMedical);
        } else {
            setFieldIfPresent(cohort, 'Medical_Records_Required_New__c', answers.get(cohortPrefix + 'leukopak_medical_records'));
        }

        Object furtherProcessing = answers.get(cohortPrefix + 'leuko_further_processing');
        Boolean hasFurtherProcessing = (furtherProcessing != null && Boolean.valueOf(furtherProcessing));

        if (hasFurtherProcessing) {
            Object isolationType = answers.get(cohortPrefix + 'leuko_isolation_type');
            if (isolationType == null) {
                isolationType = answers.get(cohortPrefix + 'leukopak_cell_isolation_type');
            }
            setFieldIfPresent(cohort, 'Leukopak_Cell_Isolation_Type__c', isolationType);

            Object aliquot = answers.get(cohortPrefix + 'leuko_aliquot');
            if (aliquot == null) {
                aliquot = answers.get(cohortPrefix + 'leukopak_aliquot_size');
            }
            setFieldIfPresent(cohort, 'Leukopak_Aliquot_Size__c', aliquot);
        }

        Object size = answers.get(cohortPrefix + 'leuko_size');
        if (size == null) {
            size = answers.get(cohortPrefix + 'leukopak_size');
        }
        setFieldIfPresent(cohort, 'Leukopak_Size__c', size);

        Object quantity = answers.get(cohortPrefix + 'leuko_quantity');
        if (quantity == null) {
            quantity = answers.get(cohortPrefix + 'leukopak_quantity');
        }
        setFieldIfPresent(cohort, 'Leukopak_Quantity__c', quantity);

        Object type = answers.get(cohortPrefix + 'leuko_type');
        if (type == null) {
            type = answers.get(cohortPrefix + 'leukopak_type');
        }
        setFieldIfPresent(cohort, 'Leukopack_Type__c', type);

        Object usage = answers.get(cohortPrefix + 'leuko_usage');
        if (usage == null) {
            usage = answers.get(cohortPrefix + 'leukopak_usage');
        }
        setFieldIfPresent(cohort, 'Usage_of_Leukopak__c', usage);

        setFieldIfPresent(cohort, 'Required_Donor_Information__c', answers.get(cohortPrefix + 'leukopak_donor_info'));
    }
    
    /**
     * @description Helper method to set field value only if present in answers
     * @param record SObject record
     * @param fieldName Field API name
     * @param value Value from form answers
     */
    private void setFieldIfPresent(SObject record, String fieldName, Object value) {
        if (value != null && String.isNotBlank(String.valueOf(value))) {
            try {
                setFieldValue(record, fieldName, value);
            } catch (Exception ex) {
                ApexLog.logException(
                    ex,
                    'FormSubmissionHandler',
                    'setFieldIfPresent',
                    withSessionPrefix('Error setting field: ' + fieldName)
                );
            }
        }
    }
    
    /**
     * @description Create I_E_Criterion__c records with proper Attribute_Type__c mapping
     *              Creates 6 records per cohort: Inclusion (Diagnoses, Medications, Other) + Exclusion (Diagnoses, Medications, Other)
     * NOTE: FLS check removed - class runs 'without sharing' to support guest user submissions
     * @param answers Form answers map
     */
    private void createIECriteriaWithAttributes(Map<String, Object> answers) {
        for (Integer i = 0; i < cohortRecords.size(); i++) {
            String cohortPrefix = 'cohort' + i + '_';
            Research_Proposal__c cohort = cohortRecords[i];

            createIECriterion(answers, cohort, cohortPrefix, 'Inclusion', 'Diagnoses', cohortPrefix + 'incl_diag');
            createIECriterion(answers, cohort, cohortPrefix, 'Inclusion', 'Medications/Treatments', cohortPrefix + 'incl_med');
            createIECriterion(answers, cohort, cohortPrefix, 'Inclusion', 'Other', cohortPrefix + 'incl_other');

            createIECriterion(answers, cohort, cohortPrefix, 'Exclusion', 'Diagnoses', cohortPrefix + 'excl_diag');
            createIECriterion(answers, cohort, cohortPrefix, 'Exclusion', 'Medications/Treatments', cohortPrefix + 'excl_med');
            createIECriterion(answers, cohort, cohortPrefix, 'Exclusion', 'Other', cohortPrefix + 'excl_other');
        }

        if (!ieCriteriaRecords.isEmpty()) {
            try {
                insert ieCriteriaRecords;

                List<String> criteriaIds = new List<String>();
                for (I_E_Criterion__c ie : ieCriteriaRecords) {
                    criteriaIds.add(ie.Id);
                }
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    withSessionPrefix('I/E Criteria created successfully'),
                    'FormSubmissionHandler',
                    'createIECriteriaWithAttributes',
                    'I/E Criteria Ids: ' + String.join(criteriaIds, ', ') + ', Count: ' + ieCriteriaRecords.size()
                );
            } catch (Exception ieEx) {
                ApexLog.logException(
                    ieEx,
                    'FormSubmissionHandler',
                    'createIECriteriaWithAttributes',
                    withSessionPrefix('Failed to create I/E Criteria. Count: ' + ieCriteriaRecords.size())
                );
                throw ieEx;
            }
        }
    }
    
    /**
     * @description Create individual I/E Criterion record
     * @param answers Form answers
     * @param cohort Related cohort
     * @param cohortPrefix Cohort prefix
     * @param criterionType Inclusion or Exclusion
     * @param attributeType Diagnoses, Medications/Treatments, or Other
     * @param answerKey Key in answers map
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private void createIECriterion(
        Map<String, Object> answers,
        Research_Proposal__c cohort,
        String cohortPrefix,
        String criterionType,
        String attributeType,
        String answerKey
    ) {
        String criteriaText = (String) answers.get(answerKey);
        
        if (String.isNotBlank(criteriaText)) {
            I_E_Criterion__c criterion = new I_E_Criterion__c();
            criterion.Opportunity__c = opportunityRecord.Id;
            criterion.Cohort__c = cohort.Id;
            criterion.Criterion_Type__c = criterionType;
            criterion.Attribute_Type__c = attributeType;
            criterion.Criterion_Details__c = criteriaText;
            
            ieCriteriaRecords.add(criterion);
        }
    }
    
    /**
     * @description Create Site_Codes__c records with biospecimen shipping assignments
     *              Links Site Codes to Cohorts and assigns biospecimen types per shipping logic
     * NOTE: FLS check removed - class runs 'without sharing' to support guest user submissions
     * @param answers Form answers map
     */
    @SuppressWarnings('PMD.CognitiveComplexity')
    private void createSiteCodesWithAssignments(Map<String, Object> answers) {
        Boolean multipleLocations = false;
        Object multipleLocObj = answers.get('multipleLocations');
        if (multipleLocObj != null) {
            // Form sends 'single' or 'multiple' as string values, not boolean
            String multipleLocStr = String.valueOf(multipleLocObj);
            multipleLocations = multipleLocStr.equalsIgnoreCase('multiple') || multipleLocStr.equalsIgnoreCase('true');
        }

        Id siteCodeRtId = Schema.SObjectType.Site_Codes__c
            .getRecordTypeInfosByName()
            .get('Study Request')
            ?.getRecordTypeId();

        if (siteCodeRtId == null) {
            siteCodeRtId = Schema.SObjectType.Site_Codes__c
                .getRecordTypeInfosByName()
                .get('Collection')
                ?.getRecordTypeId();
        }

        // Collect all shipping addresses first
        List<String> addressSuffixes = new List<String>();
        List<Integer> addressIndices = new List<Integer>();

        if (multipleLocations) {
            // First address: form sends without suffix (company, fullName, etc.)
            if (hasShippingData(answers, '')) {
                addressSuffixes.add('');
                addressIndices.add(0);
            }
            // Additional addresses: form sends with _1, _2, etc. suffixes
            for (Integer i = 1; i < 10; i++) {
                String suffix = '_' + i;
                if (hasShippingData(answers, suffix)) {
                    addressSuffixes.add(suffix);
                    addressIndices.add(i);
                }
            }
        } else {
            // Single location: try without suffix first, then with _0
            if (hasShippingData(answers, '')) {
                addressSuffixes.add('');
                addressIndices.add(0);
            } else if (hasShippingData(answers, '_0')) {
                addressSuffixes.add('_0');
                addressIndices.add(0);
            }
        }

        // Create a site code for EACH cohort × EACH address
        for (Integer cohortIdx = 0; cohortIdx < Math.max(cohortRecords.size(), 1); cohortIdx++) {
            for (Integer addrIdx = 0; addrIdx < addressSuffixes.size(); addrIdx++) {
                String suffix = addressSuffixes[addrIdx];
                Integer addressIndex = addressIndices[addrIdx];
                Site_Codes__c siteCode = buildSiteCodeRecord(answers, suffix, addressIndex, siteCodeRtId, cohortIdx);
                if (siteCode != null) {
                    siteCodeRecords.add(siteCode);
                }
            }
        }

        if (siteCodeRecords.isEmpty()) {
            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                withSessionPrefix('No Site Codes to create - shipping data not found in form answers'),
                'FormSubmissionHandler',
                'createSiteCodesWithAssignments',
                'multipleLocations: ' + multipleLocations + ', Checked keys: company_0, fullName_0, address_0, company, fullName, address'
            );
            return;
        }

        if (!siteCodeRecords.isEmpty()) {
            try {
                // Use Database.DMLOptions to allow duplicates
                Database.DMLOptions dmlOptions = new Database.DMLOptions();
                dmlOptions.DuplicateRuleHeader.allowSave = true;
                dmlOptions.DuplicateRuleHeader.runAsCurrentUser = false;

                List<Database.SaveResult> saveResults = Database.insert(siteCodeRecords, dmlOptions);

                List<String> successIds = new List<String>();
                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    if (!sr.isSuccess()) {
                        String errorMsg = '';
                        Boolean isDuplicateError = false;
                        for (Database.Error err : sr.getErrors()) {
                            errorMsg += err.getMessage() + '; ';
                            if (err.getStatusCode() == StatusCode.DUPLICATES_DETECTED) {
                                isDuplicateError = true;
                            }
                        }

                        if (isDuplicateError) {
                            ApexLog.logMessage(
                                ApexLog.LogLevel.WARN,
                                withSessionPrefix('Duplicate Site Code detected but allowed'),
                                'FormSubmissionHandler',
                                'createSiteCodesWithAssignments',
                                'Site Code Index: ' + i + ', Error: ' + errorMsg
                            );
                        } else {
                            ApexLog.logMessage(
                                ApexLog.LogLevel.ERROR,
                                withSessionPrefix('Failed to create Site Code'),
                                'FormSubmissionHandler',
                                'createSiteCodesWithAssignments',
                                'Site Code Index: ' + i + ', Error: ' + errorMsg
                            );
                            throw new SRFSubmissionException('Failed to create Site Code: ' + errorMsg);
                        }
                    } else {
                        successIds.add(sr.getId());
                    }
                }

                if (!successIds.isEmpty()) {
                    ApexLog.logMessage(
                        ApexLog.LogLevel.INFO,
                        withSessionPrefix('Site Codes created successfully'),
                        'FormSubmissionHandler',
                        'createSiteCodesWithAssignments',
                        'Site Code Ids: ' + String.join(successIds, ', ') + ', Count: ' + successIds.size()
                    );
                }
            } catch (SRFSubmissionException siteEx) {
                throw siteEx;
            } catch (Exception siteEx) {
                ApexLog.logException(
                    siteEx,
                    'FormSubmissionHandler',
                    'createSiteCodesWithAssignments',
                    withSessionPrefix('Failed to create Site Codes. Count: ' + siteCodeRecords.size())
                );
                throw siteEx;
            }
        }
    }

    /**
     * @description Transform biospecimen values from UI format to Salesforce picklist format
     * @param uiValue Value from UI (e.g., "wholeBlood")
     * @return Salesforce picklist value (e.g., "Whole Blood") or original value if not found
     */
    private String transformBiospecimenValue(String uiValue) {
        if (String.isBlank(uiValue)) {
            return uiValue;
        }

        uiValue = uiValue.trim();

        if (BIOSPECIMEN_VALUE_MAP.containsKey(uiValue)) {
            return BIOSPECIMEN_VALUE_MAP.get(uiValue);
        }

        return uiValue;
    }

    /**
     * @description Build individual Site_Codes__c record from form answers
     * @param answers Form answers map
     * @param suffix Field name suffix (_0, _1, etc.)
     * @param addressIndex Index of this address
     * @param recordTypeId Site_Codes__c Record Type Id
     * @param cohortIndex Index of the cohort to link this site code to
     * @return Site_Codes__c record or null if no data
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private Site_Codes__c buildSiteCodeRecord(
        Map<String, Object> answers,
        String suffix,
        Integer addressIndex,
        Id recordTypeId,
        Integer cohortIndex
    ) {
        String company = (String) answers.get('company' + suffix);
        String fullName = (String) answers.get('fullName' + suffix);
        String address = (String) answers.get('address' + suffix);
        String city = (String) answers.get('city' + suffix);

        if (String.isBlank(company) && String.isBlank(fullName) && String.isBlank(address)) {
            return null;
        }

        Site_Codes__c siteCode = new Site_Codes__c();
        siteCode.RecordTypeId = recordTypeId;

        String country = (String) answers.get('country' + suffix);
        Boolean isInternational = String.isNotBlank(country) && country.equalsIgnoreCase('International');

        // For International country, set 'N/A' for required fields that are empty
        siteCode.Lab_Name__c = String.isBlank(company) && isInternational ? 'N/A' : company;
        siteCode.Lab_Attn__c = String.isBlank(fullName) && isInternational ? 'N/A' : fullName;
        siteCode.Lab_Address__c = String.isBlank(address) && isInternational ? 'N/A' : address;
        siteCode.Lab_City__c = String.isBlank(city) && isInternational ? 'N/A' : city;
        siteCode.Lab_State__c = (String) answers.get('state' + suffix);
        siteCode.Lab_Zip__c = (String) answers.get('zipCode' + suffix);
        siteCode.Lab_Phone__c = (String) answers.get('phone' + suffix);
        siteCode.Lab_Country__c = country;

        if (String.isNotBlank(company)) {
            siteCode.Name = company;
        } else if (String.isNotBlank(fullName)) {
            siteCode.Name = fullName;
        } else {
            siteCode.Name = 'Shipping Address ' + (addressIndex + 1);
        }

        if (!cohortRecords.isEmpty() && cohortIndex < cohortRecords.size()) {
            siteCode.Cohort__c = cohortRecords[cohortIndex].Id;
        }

        String biospecimenFieldName = 'cohort' + cohortIndex + '_biospecimens' + suffix;
        String biospecimenAssignment = (String) answers.get(biospecimenFieldName);
        
        if (String.isNotBlank(biospecimenAssignment)) {
            try {
                List<Object> biospecimenList = (List<Object>) JSON.deserializeUntyped(biospecimenAssignment);
                if (biospecimenList != null && !biospecimenList.isEmpty()) {
                    List<String> biospecimenValues = new List<String>();
                    for (Object bio : biospecimenList) {
                        String uiValue = String.valueOf(bio);
                        String salesforceValue = transformBiospecimenValue(uiValue);
                        biospecimenValues.add(salesforceValue);
                    }
                    siteCode.Biospecimen_Shipping_Assignment__c = String.join(biospecimenValues, ';');
                }
            } catch (Exception e) {
                ApexLog.logException(
                    e,
                    'FormSubmissionHandler',
                    'buildSiteCodeRecord',
                    withSessionPrefix('Error parsing biospecimen assignment')
                );
                String transformedValue = transformBiospecimenValue(biospecimenAssignment);
                siteCode.Biospecimen_Shipping_Assignment__c = transformedValue;
            }
        }

        if (String.isBlank(siteCode.Biospecimen_Shipping_Assignment__c)) {
            String fallbackAssignment = (String) answers.get('shipping_biospecimen_assignment' + suffix);
            if (String.isNotBlank(fallbackAssignment)) {
                String transformedFallback = transformBiospecimenValue(fallbackAssignment);
                siteCode.Biospecimen_Shipping_Assignment__c = transformedFallback;
            }
        }
        
        return siteCode;
    }

    /**
     * @description Check if shipping data exists for a given address suffix
     * @param answers Form answers map
     * @param suffix Field name suffix ('' for first, '_1', '_2', etc.)
     * @return True if any shipping data exists for this suffix
     */
    private Boolean hasShippingData(Map<String, Object> answers, String suffix) {
        String company = (String) answers.get('company' + suffix);
        String fullName = (String) answers.get('fullName' + suffix);
        String address = (String) answers.get('address' + suffix);
        return String.isNotBlank(company) || String.isNotBlank(fullName) || String.isNotBlank(address);
    }

    /**
     * @description Get RecordTypeId dynamically based on object and study type
     * @param sobjectType SObject API name
     * @param studyType Study type value
     * @param answers Form answers for additional logic
     * @return RecordTypeId or null
     */
    @SuppressWarnings('PMD.CognitiveComplexity')
    private Id getRecordTypeId(String sobjectType, String studyType, Map<String, Object> answers) {
        String recordTypeName = null;
        
        if (sobjectType == 'Opportunity') {
            if (studyType == 'Cohort_Standard') {
                recordTypeName = 'Prospective Collection';
            } else if (studyType == 'Leukopak') {
                String condition = (String) answers.get('cohort_0_leukopak_condition');
                recordTypeName = (condition == 'Healthy') ? 'Leukopak - Healthy' : 'Leukopak - Diseased';
            } else {
                recordTypeName = 'Prospective Collection';
            }
        } else if (sobjectType == 'Research_Proposal__c') {
            // All cohorts use 'Cohort Standard' record type (including Leukopak studies)
            recordTypeName = 'Cohort Standard';
        }
        
        if (recordTypeName != null) {
            Schema.DescribeSObjectResult describeResult = 
                Schema.getGlobalDescribe().get(sobjectType).getDescribe();
            Map<String, Schema.RecordTypeInfo> recordTypeMap = 
                describeResult.getRecordTypeInfosByName();
            
            if (recordTypeMap.containsKey(recordTypeName)) {
                return recordTypeMap.get(recordTypeName).getRecordTypeId();
            }
        }
        
        return null;
    }
    
    /**
     * @description Dynamically set field value on SObject using reflection
     *              Handles type conversion based on field type
     * 
     * @param record SObject record to update
     * @param fieldName API name of field
     * @param value Value to set (will be converted to appropriate type)
     */
    private void setFieldValue(SObject record, String fieldName, Object value) {
        try {
            Schema.SObjectType sobjectType = record.getSObjectType();
            Schema.DescribeSObjectResult describeResult = sobjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            
            if (!fieldMap.containsKey(fieldName)) {
                ApexLog.logMessage(
                    ApexLog.LogLevel.WARN,
                    withSessionPrefix('Field not found on SObject'),
                    'FormSubmissionHandler',
                    'setFieldValue',
                    'SObject: ' + sobjectType.getDescribe().getName() + ', Field: ' + fieldName
                );
                return;
            }
            
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            Schema.DisplayType fieldType = fieldDescribe.getType();

            Object convertedValue = convertValueToFieldType(value, fieldType);

            record.put(fieldName, convertedValue);

        } catch (Exception ex) {
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                withSessionPrefix('Error setting field value'),
                'FormSubmissionHandler',
                'setFieldValue',
                'Field: ' + fieldName + ', Value: ' + value + ', Error: ' + ex.getMessage()
            );
        }
    }
    
    /**
     * @description Convert value to appropriate type based on field type
     * @param value Original value
     * @param fieldType Target field type
     * @return Converted value
     */
    private Object convertValueToFieldType(Object value, Schema.DisplayType fieldType) {
        if (value == null) {
            return null;
        }
        
        String valueStr = String.valueOf(value);
        
        try {
            switch on fieldType {
                when STRING, TEXTAREA, EMAIL, PHONE, URL, PICKLIST, MULTIPICKLIST {
                    return valueStr;
                }
                when BOOLEAN {
                    return Boolean.valueOf(value);
                }
                when INTEGER {
                    return Integer.valueOf(value);
                }
                when DOUBLE, CURRENCY, PERCENT {
                    return Decimal.valueOf(valueStr);
                }
                when DATE {
                    return Date.valueOf(valueStr);
                }
                when DATETIME {
                    return Datetime.valueOf(valueStr);
                }
                when else {
                    return value;
                }
            }
        } catch (Exception ex) {
            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                withSessionPrefix('Type conversion failed, using original value'),
                'FormSubmissionHandler',
                'convertValueToFieldType',
                'Value: ' + valueStr + ', Target Type: ' + fieldType + ', Error: ' + ex.getMessage()
            );
            return value;
        }
    }
    
    /**
     * @description Build an error response JSON string
     * @param message Error message
     * @param recordId Session record Id
     * @return JSON string with error response
     */
    private String buildErrorResponse(String message, Id recordId) {
        Map<String, Object> errorResult = new Map<String, Object>{
            'success' => false,
            'message' => message,
            'recordId' => recordId,
            'data' => new Map<String, Object>()
        };
        
        return JSON.serialize(errorResult);
    }
    
    /**
     * @description Update Form_Session__c status to Submitted
     * NOTE: FLS check removed because Guest Users cannot have Edit permission on custom objects
     * but session update is required for form submission. Class runs 'without sharing' to allow this.
     * @param sessionId Session record Id
     */
    private void updateSessionStatus(Id sessionId) {
        Form_Session__c session = new Form_Session__c(
            Id = sessionId,
            Status__c = 'Submitted',
            Completion_Date__c = Datetime.now()
        );

        // Set Final_Record_Id__c only if Opportunity was successfully created
        if (opportunityRecord != null && opportunityRecord.Id != null) {
            session.Final_Record_Id__c = opportunityRecord.Id;
        } else {
            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                withSessionPrefix('Opportunity Id not available for Final_Record_Id__c'),
                'FormSubmissionHandler',
                'updateSessionStatus',
                'Session: ' + sessionId
            );
        }

        update session;
    }
    
    // ==================== Email Helper Methods ====================

    /**
     * @description Send submitter confirmation email using template
     *              Uses Contact as TargetObjectId because WhatId only works with Contact/Lead, not User
     *              Uses FormEmailService for sending with built-in logging and non-prod redirect
     * @param sessionId Form_Session__c record Id
     * @param submitterEmail Email address of the form submitter
     */
    private void sendSubmitterEmail(Id sessionId, String submitterEmail) {
        if (String.isBlank(submitterEmail)) {
            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                withSessionPrefix('Submitter email is blank, skipping email'),
                'FormSubmissionHandler',
                'sendSubmitterEmail',
                'Session: ' + sessionId
            );
            return;
        }

        try {
            // Query session data directly (without sharing gives access)
            Form_Session__c session = querySessionForEmails(sessionId);
            Id oweaId = getOrgWideEmailAddressId();
            List<String> toAddresses = getEffectiveEmailAddresses(new List<String>{ submitterEmail });

            // Build email with resolved merge fields (bypasses Guest User record access limitation)
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(toAddresses);
            email.setSubject('Your BioRequestspecimen Request has been received - ' + session.Name);
            email.setHtmlBody(buildSubmitterHtmlBody(session));
            email.setPlainTextBody(buildSubmitterPlainTextBody(session));
            email.setSaveAsActivity(false);

            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            ApexLog.logMessage(
                ApexLog.LogLevel.INFO,
                withSessionPrefix('Submitter email sent successfully'),
                'FormSubmissionHandler',
                'sendSubmitterEmail',
                'Session: ' + sessionId + ', Email: ' + submitterEmail
            );
            ApexLog.flushLogs();
        } catch (Exception ex) {
            ApexLog.logException(
                ex,
                'FormSubmissionHandler',
                'sendSubmitterEmail',
                withSessionPrefix('Failed to send submitter email. Error: ' + ex.getMessage())
            );
        }
    }

    /**
     * @description Queue or send sales team notification email
     * @param sessionId Form_Session__c record Id
     * @param opportunityId Opportunity record Id
     */
    private void queueSalesTeamEmail(Id sessionId, Id opportunityId) {
        if (System.isFuture() || System.isBatch() || System.isQueueable()) {
            sendSalesTeamEmailDirect(sessionId, opportunityId);
        } else {
            System.enqueueJob(new FormSalesEmailQueueable(sessionId, opportunityId));
        }
    }

    /**
     * @description Send sales team email directly (synchronous)
     *              Uses Contact as TargetObjectId because WhatId only works with Contact/Lead, not User
     * @param sessionId Form_Session__c record Id
     * @param opportunityId Opportunity record Id
     */
    @TestVisible
    void sendSalesTeamEmailDirect(Id sessionId, Id opportunityId) {
        try {
            // Query session data directly (without sharing gives access)
            Form_Session__c session = querySessionForEmails(sessionId);
            List<String> toAddresses = getEffectiveEmailAddresses(SALES_TEAM_EMAILS);

            // Build email with resolved merge fields (bypasses Guest User record access limitation)
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(toAddresses);
            email.setSubject('New Study Request Submitted - ' + session.Name);
            email.setHtmlBody(buildSalesTeamHtmlBody(session));
            email.setPlainTextBody(buildSalesTeamPlainTextBody(session));
            email.setSaveAsActivity(false);

            // Set Org-Wide Email Address (required for guest user context)
            Id oweaId = getOrgWideEmailAddressId();
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            ApexLog.logMessage(
                ApexLog.LogLevel.INFO,
                withSessionPrefix('Sales team email sent successfully'),
                'FormSubmissionHandler',
                'sendSalesTeamEmailDirect',
                'Session: ' + sessionId + ', Opportunity: ' + opportunityId
            );
        } catch (Exception ex) {
            ApexLog.logException(
                ex,
                'FormSubmissionHandler',
                'sendSalesTeamEmailDirect',
                withSessionPrefix('Failed to send sales team email. Error: ' + ex.getMessage())
            );
        }
    }

    /**
     * @description Send failure notification email to sales team and RevOps
     *              Uses Contact as TargetObjectId because WhatId only works with Contact/Lead, not User
     * @param sessionId Form_Session__c record Id
     * @param applicationNumber Application Number
     * @param errorMessage Error message
     */
    private void sendFailureNotificationEmail(Id sessionId, String applicationNumber, String errorMessage) {
        try {
            // Query session data directly (without sharing gives access)
            Form_Session__c session = querySessionForEmails(sessionId);
            List<String> toAddresses = getEffectiveEmailAddresses(FAILURE_NOTIFICATION_EMAILS);

            // Build email with resolved merge fields (bypasses Guest User record access limitation)
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(toAddresses);
            email.setSubject('SRF Submission Failed - ' + (String.isNotBlank(applicationNumber) ? applicationNumber : session.Name));
            email.setHtmlBody(buildFailureHtmlBody(session, applicationNumber, errorMessage));
            email.setPlainTextBody(buildFailurePlainTextBody(session, applicationNumber, errorMessage));
            email.setSaveAsActivity(false);

            // Set Org-Wide Email Address (required for guest user context)
            Id oweaId = getOrgWideEmailAddressId();
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            ApexLog.logMessage(
                ApexLog.LogLevel.INFO,
                withSessionPrefix('Failure notification email sent'),
                'FormSubmissionHandler',
                'sendFailureNotificationEmail',
                'Session: ' + sessionId + ', Application Number: ' + applicationNumber
            );
        } catch (Exception ex) {
            ApexLog.logException(
                ex,
                'FormSubmissionHandler',
                'sendFailureNotificationEmail',
                withSessionPrefix('Failed to send failure notification email. Session: ' + sessionId)
            );
        }
    }

    /**
     * @description Get email template by developer name
     * @param templateName Developer name of the email template
     * @return EmailTemplate record or null if not found
     */
    private EmailTemplate getEmailTemplate(String templateName) {
        try {
            return [
                SELECT Id, DeveloperName, Subject, Body, HtmlValue
                FROM EmailTemplate
                WHERE DeveloperName = :templateName
                LIMIT 1
            ];
        } catch (QueryException ex) {
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                withSessionPrefix('Email template not found'),
                'FormSubmissionHandler',
                'getEmailTemplate',
                'Template Name: ' + templateName + ', Error: ' + ex.getMessage()
            );
            return null;
        }
    }

    /**
     * @description Get Contact ID for email template rendering
     *              WhatId only works with Contact/Lead as TargetObjectId, not User
     *              Priority: 1) Contact from current submission, 2) Query by email, 3) Any contact
     * @param email Optional email address to find contact for (can be null)
     * @return Id of Contact record
     */
    private Id getContactIdForEmail(String email) {
        // Priority 1: Use contact from current submission if available
        if (contactRecord != null && contactRecord.Id != null) {
            return contactRecord.Id;
        }

        // Priority 2: Query for existing contact by email
        if (String.isNotBlank(email)) {
            List<Contact> contacts = [
                SELECT Id
                FROM Contact
                WHERE Email = :email
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (!contacts.isEmpty()) {
                return contacts[0].Id;
            }
        }

        // Priority 3: Fallback to any contact (required for template rendering)
        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];

        if (!contacts.isEmpty()) {
            return contacts[0].Id;
        }

        throw new SRFSubmissionException('No Contact record found for email template rendering.');
    }

    /**
     * @description Get Contact ID for email template rendering by session
     *              Queries session's guest email and delegates to getContactIdForEmail
     * @param sessionId Form_Session__c record Id
     * @return Id of Contact record
     */
    private Id getContactIdForSession(Id sessionId) {
        // First, check if we have a contact from the current submission
        if (contactRecord != null && contactRecord.Id != null) {
            return contactRecord.Id;
        }

        // Query session to get guest email, then delegate
        Form_Session__c session = [
            SELECT Guest_Email__c
            FROM Form_Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];

        return getContactIdForEmail(session.Guest_Email__c);
    }

    /**
     * @description Get effective email addresses, redirecting to non-prod email if needed
     * Uses Core FormEmailService for environment detection
     * @param addresses Original email addresses
     * @return Effective email addresses (redirected in non-prod)
     */
    private List<String> getEffectiveEmailAddresses(List<String> addresses) {
        if (addresses == null || addresses.isEmpty()) {
            return addresses;
        }

        if (FormEmailService.isProductionOrg()) {
            return addresses;
        }

        return FormEmailService.getNonProdEmailAddresses();
    }

    /**
     * @description Get Org-Wide Email Address ID for sending emails from guest user context
     *              Queries by email address to avoid hardcoding environment-specific IDs
     * @return Id of OrgWideEmailAddress record, or null if not found
     */
    private Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
            LIMIT 1
        ];

        if (owea.isEmpty()) {
            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                withSessionPrefix('Org-Wide Email Address not found'),
                'FormSubmissionHandler',
                'getOrgWideEmailAddressId',
                'Address: ' + ORG_WIDE_EMAIL_ADDRESS
            );
            return null;
        }

        return owea[0].Id;
    }

    // ==================== Email Body Builder Methods ====================
    // These methods build email HTML/text directly because Guest Users cannot access
    // Form_Session__c records via Messaging API (whatId binding fails due to
    // record-level sharing). The handler's without-sharing context allows SOQL access
    // but Messaging.sendEmail() template rendering uses the Guest User's permissions.

    private Form_Session__c querySessionForEmails(Id sessionId) {
        return [
            SELECT Id, Name, Guest_Email__c, Final_Record_Id__c, Status__c, Completion_Date__c
            FROM Form_Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];
    }

    private String getSalesforceBaseUrl() {
        return URL.getOrgDomainUrl().toExternalForm();
    }

    private String safe(Object val) {
        return val != null ? String.valueOf(val) : '';
    }

    private String buildSubmitterHtmlBody(Form_Session__c s) {
        return '<html><head><style type="text/css">'
            + 'body{font-family:\'Salesforce Sans\',Arial,sans-serif;margin:0;padding:0;background-color:#f4f6f9;}'
            + '.email-container{max-width:800px;margin:2rem auto;padding:3rem;background-color:#ffffff;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}'
            + '.header{text-align:center;margin-bottom:2rem;}'
            + '.header h1{font-size:28px;color:#2e844a;margin-bottom:0.5rem;font-weight:600;}'
            + '.highlight-box{background-color:#f3f3f3;border-left:4px solid #2e844a;padding:1.5rem;margin-bottom:2rem;border-radius:4px;}'
            + '.highlight-box p{font-size:16px;color:#3e3e3c;margin-bottom:1rem;line-height:1.6;}'
            + '.application-number{font-size:20px;margin-top:1rem;color:#3e3e3c;}'
            + '.application-number strong{color:#0070d2;font-size:22px;}'
            + '.section-title{font-size:20px;color:#3e3e3c;margin-bottom:1rem;font-weight:600;}'
            + '.whats-next{margin-bottom:2rem;}'
            + '.whats-next ul{line-height:1.8;color:#3e3e3c;padding-left:1.5rem;}'
            + '.whats-next li{margin-bottom:0.8rem;}'
            + '.info-box{background-color:#f4f6f9;border:1px solid #c9daf8;padding:1.5rem;margin-bottom:2rem;border-radius:4px;}'
            + '.info-box p{font-size:16px;color:#3e3e3c;margin:0;}'
            + '.info-box a{font-weight:bold;color:#0070d2;text-decoration:none;}'
            + '.footer{border-top:1px solid #dddbda;padding-top:2rem;text-align:center;margin-top:2rem;}'
            + '.footer p{font-size:16px;color:#706e6b;line-height:1.6;}'
            + '.footer a{color:#0070d2;text-decoration:none;}'
            + '.signature{margin-top:1rem;color:#706e6b;}'
            + 'strong{font-weight:600;}'
            + '</style></head><body>'
            + '<div class="email-container">'
            + '<div class="header"><h1>Thank You for Your Biospecimen Request</h1></div>'
            + '<div class="highlight-box">'
            + '<p>We are reviewing the details of your project and preparing a quote.</p>'
            + '<p class="application-number">Your Application Number: <strong>' + safe(s.Name) + '</strong></p>'
            + '</div>'
            + '<div class="whats-next"><h2 class="section-title">What\'s Next?</h2><ul>'
            + '<li>A BioRequest team member will reach out within <strong>1 business day</strong> to confirm any additional details about your study or donor requirements.</li>'
            + '<li>A summary of your request has been sent to your email (check spam if it is not in your inbox).</li>'
            + '<li>Your quote will follow shortly after we verify feasibility, donor availability, and any required clinical metadata.</li>'
            + '</ul></div>'
            + '<div class="info-box"><p>While you wait, check out our <a href="https://www.company.com/products/?pro_inventory=inventory" target="_blank" rel="noopener noreferrer">available inventory</a>.</p></div>'
            + '<div class="footer">'
            + '<p>If you have any questions, please contact <a href="mailto:contact@company.com">contact@company.com</a></p>'
            + '<p class="signature">Thank you,<br/><strong>BioRequest Team</strong></p>'
            + '</div></div></body></html>';
    }

    private String buildSubmitterPlainTextBody(Form_Session__c s) {
        return 'Thank You for Your Biospecimen Request\n'
            + String.fromCharArray(new List<Integer>{9473}).repeat(49) + '\n\n'
            + 'We are reviewing the details of your project and preparing a quote.\n\n'
            + 'Your Application Number: ' + safe(s.Name) + '\n\n'
            + String.fromCharArray(new List<Integer>{9473}).repeat(49) + '\n\n'
            + 'What\'s Next?\n\n'
            + '- A BioRequest team member will reach out within 1 business day to confirm any additional details about your study or donor requirements.\n\n'
            + '- A summary of your request has been sent to your email (check spam if it is not in your inbox).\n\n'
            + '- Your quote will follow shortly after we verify feasibility, donor availability, and any required clinical metadata.\n\n'
            + String.fromCharArray(new List<Integer>{9473}).repeat(49) + '\n\n'
            + 'While you wait, check out our available inventory:\n'
            + 'https://www.company.com/products/?pro_inventory=inventory\n\n'
            + 'If you have any questions, please contact contact@company.com\n\n'
            + 'Thank you,\nBioRequest Team';
    }

    private String buildSalesTeamHtmlBody(Form_Session__c s) {
        String baseUrl = getSalesforceBaseUrl();
        return '<html><head><style type="text/css">'
            + 'body{font-family:Arial,sans-serif;margin:0;padding:0;background-color:#f4f6f9;}'
            + '.email-container{max-width:700px;margin:2rem auto;padding:2rem;background-color:#ffffff;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}'
            + '.header{border-bottom:3px solid #2e844a;padding-bottom:1rem;margin-bottom:1.5rem;}'
            + '.header h2{color:#2e844a;font-size:24px;margin:0;font-weight:600;}'
            + '.intro{font-size:16px;color:#3e3e3c;margin-bottom:1.5rem;line-height:1.6;}'
            + '.details-table{border-collapse:collapse;width:100%;margin-bottom:1.5rem;box-shadow:0 2px 4px rgba(0,0,0,0.1);}'
            + '.details-table tr:nth-child(even){background-color:#f3f3f3;}'
            + '.details-table td{padding:12px;border:1px solid #dddbda;color:#3e3e3c;}'
            + '.details-table td:first-child{font-weight:bold;width:40%;background-color:#f8f8f8;}'
            + '.details-table a{color:#0070d2;text-decoration:none;font-weight:500;}'
            + '.application-number{color:#0070d2;font-weight:bold;font-size:18px;}'
            + '.action-box{background-color:#fff6e5;border-left:4px solid #ffb75d;padding:15px;margin-bottom:1.5rem;border-radius:4px;}'
            + '.action-box p{margin:0;color:#3e3e3c;font-size:15px;}'
            + '.action-box strong{color:#c23934;}'
            + '.footer{border-top:1px solid #dddbda;padding-top:15px;text-align:center;color:#706e6b;font-size:14px;margin-top:2rem;}'
            + '</style></head><body>'
            + '<div class="email-container">'
            + '<div class="header"><h2>New Study Request Submitted</h2></div>'
            + '<p class="intro">A new Dynamic Request Form has been submitted and an Opportunity has been created. Please review and reach out to the submitter as needed.</p>'
            + '<table class="details-table">'
            + '<tr><td>Application Number</td><td class="application-number">' + safe(s.Name) + '</td></tr>'
            + '<tr><td>Opportunity ID</td><td><a href="' + baseUrl + '/' + safe(s.Final_Record_Id__c) + '" target="_blank">' + safe(s.Final_Record_Id__c) + '</a></td></tr>'
            + '<tr><td>Session ID</td><td><a href="' + baseUrl + '/' + safe(s.Id) + '" target="_blank">' + safe(s.Id) + '</a></td></tr>'
            + '<tr><td>Submitter Email</td><td><a href="mailto:' + safe(s.Guest_Email__c) + '">' + safe(s.Guest_Email__c) + '</a></td></tr>'
            + '<tr><td>Submission Date</td><td>' + safe(s.Completion_Date__c) + '</td></tr>'
            + '<tr><td>Status</td><td><strong>' + safe(s.Status__c) + '</strong></td></tr>'
            + '</table>'
            + '<div class="action-box"><p>&#9200; <strong>Action Required:</strong> A BioRequest team member should reach out to the submitter within <strong>1 business day</strong>.</p></div>'
            + '<div class="footer"><p>This is an automated notification from the Dynamic Request Form system.</p></div>'
            + '</div></body></html>';
    }

    private String buildSalesTeamPlainTextBody(Form_Session__c s) {
        String baseUrl = getSalesforceBaseUrl();
        return 'NEW STUDY REQUEST SUBMITTED\n'
            + '============================================================\n\n'
            + 'A new Dynamic Request Form has been submitted and an Opportunity has been created.\n\n'
            + 'APPLICATION NUMBER: ' + safe(s.Name) + '\n\n'
            + '============================================================\n\n'
            + 'SUBMISSION DETAILS:\n\n'
            + 'Opportunity ID: ' + safe(s.Final_Record_Id__c) + '\n'
            + 'View in Salesforce: ' + baseUrl + '/' + safe(s.Final_Record_Id__c) + '\n\n'
            + 'Session ID: ' + safe(s.Id) + '\n'
            + 'View in Salesforce: ' + baseUrl + '/' + safe(s.Id) + '\n\n'
            + 'Submitter Email: ' + safe(s.Guest_Email__c) + '\n\n'
            + 'Submission Date: ' + safe(s.Completion_Date__c) + '\n\n'
            + 'Status: ' + safe(s.Status__c) + '\n\n'
            + '============================================================\n\n'
            + 'ACTION REQUIRED:\nA BioRequest team member should reach out to the submitter within 1 business day.\n\n'
            + '============================================================\n\n'
            + 'This is an automated notification from the Dynamic Request Form system.';
    }

    private String buildFailureHtmlBody(Form_Session__c s, String applicationNumber, String errMsg) {
        String baseUrl = getSalesforceBaseUrl();
        String appNum = String.isNotBlank(applicationNumber) ? applicationNumber : safe(s.Name);
        return '<html><head><style type="text/css">'
            + 'body{font-family:Arial,sans-serif;margin:0;padding:0;background-color:#f4f6f9;}'
            + '.email-container{max-width:700px;margin:2rem auto;padding:2rem;background-color:#ffffff;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}'
            + '.header{border-bottom:3px solid #c23934;padding-bottom:1rem;margin-bottom:1.5rem;}'
            + '.header h2{color:#c23934;font-size:24px;margin:0;font-weight:600;}'
            + '.intro{font-size:16px;color:#3e3e3c;margin-bottom:1.5rem;line-height:1.6;}'
            + '.details-table{border-collapse:collapse;width:100%;margin-bottom:1.5rem;box-shadow:0 2px 4px rgba(0,0,0,0.1);}'
            + '.details-table tr:nth-child(even){background-color:#f3f3f3;}'
            + '.details-table td{padding:12px;border:1px solid #dddbda;color:#3e3e3c;}'
            + '.details-table td:first-child{font-weight:bold;width:40%;background-color:#f8f8f8;}'
            + '.details-table a{color:#0070d2;text-decoration:none;font-weight:500;}'
            + '.application-number{color:#c23934;font-weight:bold;font-size:18px;}'
            + '.alert-box{background-color:#fef0ef;border-left:4px solid #c23934;padding:15px;margin-bottom:1.5rem;border-radius:4px;}'
            + '.alert-box p{margin:0;color:#3e3e3c;font-size:15px;}'
            + '.alert-box strong{color:#c23934;}'
            + '.action-box{background-color:#fff6e5;border-left:4px solid #ffb75d;padding:15px;margin-bottom:1.5rem;border-radius:4px;}'
            + '.action-box p{margin:0 0 10px 0;color:#3e3e3c;font-size:15px;}'
            + '.action-box ul{margin:0;padding-left:20px;}'
            + '.action-box li{margin-bottom:5px;}'
            + '.footer{border-top:1px solid #dddbda;padding-top:15px;text-align:center;color:#706e6b;font-size:14px;margin-top:2rem;}'
            + '</style></head><body>'
            + '<div class="email-container">'
            + '<div class="header"><h2>SRF Submission Failed</h2></div>'
            + '<div class="alert-box"><p>&#9888; <strong>Alert:</strong> A Dynamic Request Form submission has failed during record creation. Immediate attention is required.</p></div>'
            + '<p class="intro">The following submission encountered an error and the records could not be created in Salesforce. Please investigate and manually process if needed.</p>'
            + '<table class="details-table">'
            + '<tr><td>Application Number</td><td class="application-number">' + appNum + '</td></tr>'
            + '<tr><td>Session ID</td><td><a href="' + baseUrl + '/' + safe(s.Id) + '" target="_blank">' + safe(s.Id) + '</a></td></tr>'
            + '<tr><td>Submitter Email</td><td><a href="mailto:' + safe(s.Guest_Email__c) + '">' + safe(s.Guest_Email__c) + '</a></td></tr>'
            + '<tr><td>Submission Date</td><td>' + safe(s.Completion_Date__c) + '</td></tr>'
            + '<tr><td>Status</td><td><strong>' + safe(s.Status__c) + '</strong></td></tr>'
            + '</table>'
            + '<div class="action-box"><p>&#9997; <strong>Action Required:</strong></p><ul>'
            + '<li>Review the Session record in Salesforce for submitted data</li>'
            + '<li>Check Apex Logs for detailed error information</li>'
            + '<li>Manually create the required records if necessary</li>'
            + '<li>Contact the submitter if additional information is needed</li>'
            + '</ul></div>'
            + '<div class="footer"><p>This is an automated failure notification from the Dynamic Request Form system.</p></div>'
            + '</div></body></html>';
    }

    private String buildFailurePlainTextBody(Form_Session__c s, String applicationNumber, String errMsg) {
        String baseUrl = getSalesforceBaseUrl();
        String appNum = String.isNotBlank(applicationNumber) ? applicationNumber : safe(s.Name);
        return 'SRF SUBMISSION FAILED\n'
            + '============================================================\n\n'
            + 'ALERT: A Dynamic Request Form submission has failed during record creation.\n'
            + 'Immediate attention is required.\n\n'
            + 'APPLICATION NUMBER: ' + appNum + '\n\n'
            + '============================================================\n\n'
            + 'SUBMISSION DETAILS:\n\n'
            + 'Session ID: ' + safe(s.Id) + '\n'
            + 'View in Salesforce: ' + baseUrl + '/' + safe(s.Id) + '\n\n'
            + 'Submitter Email: ' + safe(s.Guest_Email__c) + '\n\n'
            + 'Submission Date: ' + safe(s.Completion_Date__c) + '\n\n'
            + 'Status: ' + safe(s.Status__c) + '\n\n'
            + '============================================================\n\n'
            + 'ACTION REQUIRED:\n\n'
            + '1. Review the Session record in Salesforce for submitted data\n'
            + '2. Check Apex Logs for detailed error information\n'
            + '3. Manually create the required records if necessary\n'
            + '4. Contact the submitter if additional information is needed\n\n'
            + '============================================================\n\n'
            + 'This is an automated failure notification from the Dynamic Request Form system.';
    }

    /**
     * @description Queueable class for async sales team email sending
     */
    public class FormSalesEmailQueueable implements Queueable {
        private Id sessionId;
        private Id opportunityId;

        public FormSalesEmailQueueable(Id sessionId, Id opportunityId) {
            this.sessionId = sessionId;
            this.opportunityId = opportunityId;
        }

        public void execute(QueueableContext context) {
            try {
                FormSubmissionHandler handler = new FormSubmissionHandler();
                handler.sendSalesTeamEmailDirect(sessionId, opportunityId);
            } catch (Exception e) {
                String sessionNameForLog = '';
                try {
                    List<Form_Session__c> sessions = [
                        SELECT Name FROM Form_Session__c WHERE Id = :sessionId LIMIT 1
                    ];
                    if (!sessions.isEmpty()) {
                        sessionNameForLog = '[Session: ' + sessions[0].Name + '] ';
                    }
                } catch (Exception ignored) {
                    // Ignore query errors for logging prefix
                }
                ApexLog.logException(
                    e,
                    'FormSubmissionHandler',
                    'FormSalesEmailQueueable.execute',
                    sessionNameForLog + 'Failed to send sales team email. Error: ' + e.getMessage()
                );
            }
        }
    }

    /**
     * @description Custom exception class for form submission validation errors
     */
    public class SRFSubmissionException extends Exception {}
}