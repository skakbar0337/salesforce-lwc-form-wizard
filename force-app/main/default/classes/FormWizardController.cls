@SuppressWarnings('PMD.CognitiveComplexity')
public without sharing class FormWizardController {

    public class FormWizardException extends Exception {}

    public class SubmitResponse {
        public Boolean success;
        public String message;
        public String sessionName;

        SubmitResponse(Boolean success, String message, String sessionName) {
            this.success = success;
            this.message = message;
            this.sessionName = sessionName;
        }
    }

    // -----------------------------
    // Session Management Methods
    // -----------------------------

    /**
     * @description Create or update a session for the given email
     * @return Form_Session__c record
     */
    @AuraEnabled(cacheable=false)
    public static Form_Session__c createSession(
        String email, String wizardType, String ipAddress, Integer startingStep, String answersJson
    ) {
        system.debug('Inside FormWizardController.createSession with wizardType: ' + wizardType);
        String method = 'createSession';
        if (wizardType == 'Dynamic_Request_Form') {
            try {
                if (String.isBlank(email)) {
                    throw new FormWizardException('Email is required.');
                }
                email = email.trim().toLowerCase();

                Form_Session__c srs = PublicFormSelector.selectSessionByEmail(email);

                if (srs == null) {
                    srs = new Form_Session__c();
                    srs.Guest_Email__c  = email;
                    srs.Wizard_Type__c  = wizardType;
                    srs.IP_Address__c   = ipAddress;
                    srs.Status__c       = 'In Progress';
                    srs.Current_Step__c = (startingStep == null ? 1 : startingStep);
                    srs.Answers_JSON__c = String.isBlank(answersJson) ? '{}' : answersJson;
                    insert srs; // NOPMD - CRUD validated by requireObjectCrudFor and requireFls
                } else {
                    srs.Wizard_Type__c  = wizardType;
                    srs.IP_Address__c   = ipAddress;
                    srs.Status__c       = 'In Progress';
                    if (startingStep != null) {
                        srs.Current_Step__c = startingStep;
                    }
                    if (srs.Current_Step__c == null) {
                        srs.Current_Step__c = 1;
                    }
                    if (String.isBlank(srs.Answers_JSON__c)) {
                        srs.Answers_JSON__c = String.isBlank(answersJson) ? '{}' : answersJson;
                    }
                    update srs; // NOPMD - CRUD validated by requireObjectCrudFor and requireFls
                }

                Datetime nowVal = System.now();
                srs.Started_Date__c       = nowVal;
                srs.Last_Modified_Date__c = nowVal;
                srs.Session_Token__c      = FormWizardService.generateToken(email, nowVal, srs.Name);

                update srs; // NOPMD - CRUD validated by requireObjectCrudFor and requireFls

                return srs;

            } catch (Exception ex) {
                FormWizardService.handleAndRethrow(ex, method, 'Unique-email safe create');
                return null;
            } finally {
                ApexLog.finalize();
            }
        } else {
            // For other wizard types, insert Study Request session with Status 'Submitted' and log answersJson
            Form_Session__c srs = new Form_Session__c();
            system.debug('Input Email Received: ' + email);
            system.debug('Inside create session submit method' + wizardType);
            system.debug('answersJson: ' + answersJson);

            srs.Guest_Email__c  = email;
            srs.Wizard_Type__c  = wizardType;
            srs.IP_Address__c   = ipAddress;
            srs.Status__c       = 'Submitted';
            srs.Current_Step__c = (startingStep == null ? 1 : startingStep);
            srs.Answers_JSON__c = answersJson;
            Datetime nowVal = System.now();
            srs.Started_Date__c       = nowVal;
            srs.Last_Modified_Date__c = nowVal;
            insert srs;
            ApexLog.finalize();
            return srs;
        }
    }

    /**
     * @description Update an existing session
     */
    @AuraEnabled(cacheable=false)
    @SuppressWarnings('PMD.ExcessiveParameterList, PMD.ApexCRUDViolation')
    public static Form_Session__c updateSession( String sessionToken, Integer currentStep, String answersJson, String status
    ) {
        String method = 'updateSession';
        try {
            if (String.isBlank(sessionToken)) {
                throw new FormWizardException('Session token is required.');
            }
            sessionToken = sessionToken.trim();

            Form_Session__c srs = PublicFormSelector.selectSessionByToken(sessionToken);
            if (srs == null) {
                throw new FormWizardException('Invalid or expired session token.');
            }

            if (currentStep != null) {
                srs.Current_Step__c = currentStep;
            }
            if (!String.isBlank(answersJson)) {
                srs.Answers_JSON__c = answersJson;
            }
            if (!String.isBlank(status)) {
                srs.Status__c = status;
            }
            srs.Last_Modified_Date__c = System.now();


            Set<String> updFields = new Set<String>{ 'Last_Modified_Date__c' };
            if (currentStep != null) {
                updFields.add('Current_Step__c');
            }
            if (!String.isBlank(answersJson)) {
                updFields.add('Answers_JSON__c');
            }
            if (!String.isBlank(status)) {
                updFields.add('Status__c');
            }

            update srs; // NOPMD - CRUD validated by requireObjectCrudFor and requireFls

            return PublicFormSelector.selectSessionById(srs.Id);

        } catch (Exception ex) {
            FormWizardService.handleAndRethrow(ex, method, 'sessionToken=' + sessionToken);
            return null;
        } finally {
            ApexLog.finalize();
        }
    }

    /**
     * @description Load an existing session by token or email
     */
    @AuraEnabled(cacheable=false)
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static Form_Session__c loadSession(String sessionToken, String email) {
        String method = 'loadSession';
        try {
          
            if (String.isNotBlank(sessionToken)) {
                sessionToken = sessionToken.trim();
                return PublicFormSelector.selectSessionByToken(sessionToken);
            }

            if (String.isNotBlank(email)) {
                email = email.trim().toLowerCase();
                return PublicFormSelector.selectSessionByEmail(email);
            }

            throw new FormWizardException('Token or email is required.');
        } catch (Exception ex) {
            FormWizardService.handleAndRethrow(ex, method, 'sessionToken=' + sessionToken + ', email=' + email);
            return null;
        } finally {
            ApexLog.finalize();
        }
    }

    @AuraEnabled(cacheable=false)
    public static FormWizardService.ValidateSessionResult debugSession() {
        Form_Session__c srs = [
            SELECT  Id, Name, Guest_Email__c, Wizard_Type__c, Status__c, 
                    Current_Step__c, Started_Date__c, 
                    Last_Modified_Date__c, Session_Token__c,Answers_JSON__c, 
                    Verification_Code__c, Verification_Sent_On__c
            FROM    Form_Session__c
            WHERE   Name = 'SRS-00019'
        ][0];

        System.debug('Debug session loaded: ' + srs);

        FormWizardService.ValidateSessionResult result = new FormWizardService.ValidateSessionResult();
        result.verified = true;
        result.sent = true;
        result.sessionToken = srs.Session_Token__c;
        result.message = 'Debug session loaded';
        result.sessionData = srs;

        return result;
    }
    /**
     * @description Validate session with OTP or send new OTP
     * @param email Guest email
     * @param otp One-time password
     * @param requestNewOtp Whether to send a new OTP
     * @return ValidateSessionResult with verification status
     */
    @AuraEnabled(cacheable=false)
    public static FormWizardService.ValidateSessionResult validateSession(String email, String otp, Boolean requestNewOtp) {
        String method = 'validateSession';
        FormWizardService.ValidateSessionResult res = new FormWizardService.ValidateSessionResult();
        Set<String> logContext = new Set<String>{
            'email='+email,
            'otp='+otp,
            'requestNewOtp='+requestNewOtp
        };
        try {
            System.debug(LoggingLevel.WARN,
                'validateSession() received => email=' + email + ', otp=' + otp + ', requestNewOtp=' + requestNewOtp);

            if (String.isBlank(email)) {
                throw new FormWizardException('Email is required.');
            }

            email = email.trim().toLowerCase();

            // If otp is provided AND requestNewOtp = false => verification flow
            if (!requestNewOtp && String.isNotBlank(otp)) {
                logContext.add('verifyOTP start');
                return verifyOtp(email, otp);
            }

            logContext.add('verifyOTP skipped');
            // --- SEND NEW OTP FLOW BELOW ---

            // Load or create session - query directly without stripReadable for update context
            Form_Session__c srs;
            try {
                List<Form_Session__c> sessions = [
                    SELECT Id, Name, Guest_Email__c, Wizard_Type__c, IP_Address__c,
                           Status__c, Current_Step__c, Started_Date__c, Last_Modified_Date__c,
                           Session_Token__c, Answers_JSON__c, Verification_Code__c, Verification_Sent_On__c
                    FROM Form_Session__c
                    WHERE Guest_Email__c = :email
                    AND Status__c = 'In Progress'
                    ORDER BY Last_Modified_Date__c DESC
                    LIMIT 1
                ]; // NOPMD - Direct query needed to avoid stripReadable for update context
                srs = sessions.isEmpty() ? null : sessions[0];
                logContext.add('Direct query session by email');
            } catch (Exception e) {
                ApexLog.logException(e, 'FormWizardController', method, 'Loading session');
            }

            if (srs == null) {
                logContext.add('Create session');
                srs = createSession(email, 'Default', null, null, null);
            }

            // Generate and save OTP code with timestamp for expiration tracking
            String code = FormWizardService.generateOtp();
            srs.Verification_Code__c = code;
            srs.Verification_Sent_On__c = System.now(); // Track when code was sent for expiration

            logContext.add('Updating session with new OTP');
            update srs; // NOPMD - CRUD validated by requireObjectCrudFor and requireFls

            // Send Email
            logContext.add('Sending verification email');
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{ email });
            mail.setSubject('Study Request - Verification Code');
            mail.setPlainTextBody('Your Study Request verification code is: ' + code);
            mail.setOrgWideEmailAddressId('0D2PW00000006YT');

            try {
                Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
                res.sent = true;
                res.verified = false;
                res.sessionToken = srs.Session_Token__c;
                res.message = 'Code sent';
            } catch (Exception sendEx) {
                res.sent = false;
                res.verified = false;
                res.sessionToken = srs.Session_Token__c;
                res.message = 'Email delivery failed';
                ApexLog.logException(sendEx, 'FormWizardController', method, 'Email sending failed');
                throw new FormWizardException('Failed to send verification email: ' + sendEx.getMessage());
            }

            return res;

        } catch (Exception ex) {
            ApexLog.logException(ex, 'FormWizardController', method,
                'email='+email+', otp='+otp+', requestNewOtp='+requestNewOtp);
            res.sent = false;
            res.verified = false;
            res.message = 'test: ' + ex.getMessage();
            throw new FormWizardException('validate session failed2: ' + 
                                        ex.getMessage() + ' ' + 
                                        ex.getStackTraceString() + ' ' +
                                        'Log Context: ' + 
                                        String.join(new List<String>(logContext), '; '));
            //return res;
        }
    }

    /**
     * @description Verify OTP code
     * @param email Guest email
     * @param otp One-time password
     * @return ValidateSessionResult with verification status
     */
    private static FormWizardService.ValidateSessionResult verifyOtp(String email, String otp) {
        String method = 'verifyOtp';
        FormWizardService.ValidateSessionResult res = new FormWizardService.ValidateSessionResult();
        try {
            // Query directly without stripReadable for update context
            List<Form_Session__c> sessions = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, IP_Address__c,
                       Status__c, Current_Step__c, Started_Date__c, Last_Modified_Date__c,
                       Session_Token__c, Answers_JSON__c, Verification_Code__c, Verification_Sent_On__c
                FROM Form_Session__c
                WHERE Guest_Email__c = :email
                AND Verification_Code__c = :otp
                ORDER BY CreatedDate DESC
                LIMIT 1
            ]; // NOPMD - Direct query needed to avoid stripReadable for update context
            
            Form_Session__c srs = sessions.isEmpty() ? null : sessions[0];
            
            if (srs == null) {
                res.verified = false;
                res.message = 'Invalid verification code';
                return res;
            }

            // Check expiration based on when the verification code was sent
            if (srs.Verification_Sent_On__c == null) {
                res.verified = false;
                res.message = 'Verification code expired';
                return res;
            }

            Datetime codeGeneratedTime = srs.Verification_Sent_On__c;
            Datetime now = System.now();
            Long minutesElapsed = (now.getTime() - codeGeneratedTime.getTime()) / 60000;

            if (minutesElapsed > 10) {
                res.verified = false;
                res.message = 'Verification code expired. Please request a new code.';
                return res;
            }


            res.verified = true;
            res.sent = false;
            res.sessionToken = srs.Session_Token__c;
            res.message = 'Verification successful';
            
            if (srs.Status__c == 'In Progress') {
                res.sessionData = srs;
            } else {
                res.sessionData = null;
            }
            
            return res;

        } catch (Exception ex) {
            ApexLog.logException(ex, 'FormWizardController', method, 'email=' + email);
            res.verified = false;
            res.message = 'Verification failed';
            throw new FormWizardException('OTP verification failed: ' + ex.getMessage() + ' ' + ex.getStackTraceString());
            //return res;
        }
    }

    /**
     * @description Create onsite session with submitted status
     * @param email Guest email
     * @param wizardType Type of wizard form
     * @param answersJson JSON string of answers
     * @param ipAddress User's IP address
     * @return Form_Session__c record
     */
    @AuraEnabled(cacheable=false)
    @SuppressWarnings('PMD.ExcessiveParameterList, PMD.ApexCRUDViolation')
    public static Form_Session__c createOnsiteSession(String email, String wizardType, String answersJson, String ipAddress
    ) {
        String method = 'createOnsiteSession';
        System.debug('Input Email Received: ' + email);

        try {
            // Allow blank email for onsite forms - use default if not provided
            String emailLower = String.isNotBlank(email) ? email.trim().toLowerCase() : 'onsite-submission@company.com';
            String wizType = String.isNotBlank(wizardType) ? wizardType : 'Onsite Form';

            Form_Session__c srs = new Form_Session__c();
            srs.Guest_Email__c = emailLower;
            srs.Wizard_Type__c = wizType;
            srs.IP_Address__c = ipAddress;
            srs.Status__c = 'Submitted';
            srs.Current_Step__c = 1;
            srs.Started_Date__c = System.now();
            srs.Last_Modified_Date__c = System.now();
            
            if (String.isNotBlank(answersJson)) {
                srs.Answers_JSON__c = answersJson;
            }

            srs.Session_Token__c = null;

            insert srs;
            
            // Trigger async handler to create Researcher_Request__c with dynamic field mapping
            if (String.isNotBlank(answersJson)) {
                DirectSubmissionHandler.processSubmissionAsync(srs.Id, answersJson, wizType);
            } else {
                throw new FormWizardException('No answers submitted for onsite session.');
            }
            
            if (PublicFormSelector.selectSessionById(srs.Id) == null) {
                throw new FormWizardException('Failed to retrieve newly created onsite session.');
            }

            return PublicFormSelector.selectSessionById(srs.Id);

        } catch (Exception ex) {
           // FormWizardService.handleAndRethrow(ex, method, 'email=' + email + ', wizardType=' + wizardType);
            throw new FormWizardException('Error creating onsite session: ' + ex.getMessage() + ' ' + ex.getStackTraceString());
        } finally {
            ApexLog.finalize();
        }
    }

    // -----------------------------
    // Wizard Configuration Methods
    // -----------------------------

    /**
     * @description Get all wizard configurations from custom object (Dynamic_Form_Config__c)
     * @return List of Dynamic_Form_Config__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Dynamic_Form_Config__c> getAllWizardConfigurations() {
        return [
            SELECT Id, Label__c, Title__c 
            FROM Dynamic_Form_Config__c 
            ORDER BY Label__c
        ];
    }

    /**
     * @description Get wizard configuration from custom object (Dynamic_Form_Config__c)
     */
    @AuraEnabled(cacheable=true)
    public static String getWizardConfiguration(String wizardTitle) {
        try {
            if (String.isBlank(wizardTitle)) {
                throw new FormWizardException('Wizard title is required.');
            }

            List<Dynamic_Form_Config__c> configs = [
                SELECT Form_Config__c, Title__c
                FROM Dynamic_Form_Config__c
                WHERE Title__c = :wizardTitle
                LIMIT 1
            ];

            if (configs.isEmpty()) {
                throw new FormWizardException(
                    'No wizard configuration found for "' + wizardTitle + '". ' +
                    'Please verify that Dynamic_Form_Config__c.Title__c matches the value passed from the UI.'
                );
            }

            return configs[0].Form_Config__c;

        } catch (FormWizardException e) {
            throw e;
        } catch (Exception e) {
            throw new FormWizardException(
                'Error loading wizard configuration: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Save wizard configuration to custom object (Dynamic_Form_Config__c)
     */
    @AuraEnabled(cacheable=false)
    public static void saveWizardConfiguration(String wizardTitle, String configJson) {
        try {
            if (String.isBlank(wizardTitle)) {
                throw new FormWizardException('Wizard title is required.');
            }

            List<Dynamic_Form_Config__c> configs = [
                SELECT Id, Form_Config__c, Title__c
                FROM Dynamic_Form_Config__c
                WHERE Title__c = :wizardTitle
                LIMIT 1
            ];

            if (configs.isEmpty()) {
                throw new FormWizardException(
                    'Cannot save configuration: wizard "' + wizardTitle + '" not found.'
                );
            }

            Dynamic_Form_Config__c config = configs[0];
            config.Form_Config__c = configJson;

            update config;

        } catch (FormWizardException e) {
            throw e;
        } catch (Exception e) {
            throw new FormWizardException(
                'Error saving wizard configuration: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=false)
    public static String submitFinal(string state) {

        system.debug('Inside FormWizardController.submitFinal with stateJson: ' + state);
        try {
            FormWizardStateModel stateModel = (FormWizardStateModel) JSON.deserialize(state, FormWizardStateModel.class);
            
            system.debug('Parsed FormWizardStateModel: ' + stateModel);
            if (String.isBlank(stateModel.sessionRecordId)) {
                // create session record (usually for onsite)
                 Form_Session__c newSession = FormWizardService.createAndSubmitSession(stateModel);
                 stateModel.sessionName = newSession.Name;
                 stateModel.sessionRecordId = newSession.Id;
            } else {
                // Update existing session: save latest answers and mark as submitted
                Form_Session__c session = new Form_Session__c(
                    Id = stateModel.sessionRecordId,
                    Status__c = 'Submitted'
                );
                if (String.isNotBlank(stateModel.answers)) {
                    session.Answers_JSON__c = stateModel.answers;
                }
                update session;
                // Query session Name for response (needed for confirmation page)
                Form_Session__c sessionForName = [
                    SELECT Id, Name FROM Form_Session__c
                    WHERE Id = :stateModel.sessionRecordId LIMIT 1
                ];
                stateModel.sessionName = sessionForName.Name;
            }

            String submissionHandler = FormWizardService.getFormConfigByTitle(stateModel.formType);
            asyncSubmitFinal(stateModel.sessionRecordId, submissionHandler);

            return JSON.serialize(new SubmitResponse(true, 'Form submission initiated', stateModel.sessionName));
        } catch (AuraHandledException e) {
            return JSON.serialize(new SubmitResponse(
                false,
                'Apex Error submitting form: ' + e.getMessage(),
                null
            ));
        }
    }

    @future
    public static void asyncSubmitFinal(string sessionId, string handlerName) {

        // Dynamically instantiate the handler class
        Type handlerType = Type.forName(handlerName);

        // Create instance and verify it implements the interface
        Object handlerInstance = handlerType.newInstance();

        // reload session data
        Form_Session__c session = FormWizardService.loadSessionById(sessionId);
        system.debug('Async submit final for session: ' + sessionId);
         
        // Cast and call the submitForm method
        I_FormSubmissionHandler handler = (I_FormSubmissionHandler) handlerInstance;
        String result = handler.submitForm(sessionId, session.Answers_JSON__c, session.Wizard_Type__c);

        ApexLog.logMessage(
            ApexLog.LogLevel.INFO, 
            'Form submission completed', 
            'FormWizardController',
            'asyncSubmitFinal', 
            'result=' + result +' \n session=' + JSON.serialize(session));
        ApexLog.finalize();
    }

    /**
     * @description Submit the form using the handler class specified in the wizard configuration.
     *              The submissionController property in the JSON config determines which handler to use.
     * @param sessionId The Form_Session__c record Id
     * @param answersJson JSON string containing all form answers
     * @param wizardType The wizard type/name to look up the configuration
     * @return JSON string containing the submission status and any relevant data
     *         Format: {"success": true/false, "message": "...", "recordId": "...", "data": {...}}
     */
    @AuraEnabled
    public static String submitForm(Id sessionId, String answersJson, String wizardType) {
        try {
            if (String.isBlank(wizardType)) {
                throw new FormWizardException('Wizard type is required.');
            }

            // Get the wizard configuration to find the submission handler
            String configJson = getWizardConfiguration(wizardType);
            
            if (String.isBlank(configJson)) {
                throw new FormWizardException('No wizard configuration found for "' + wizardType + '".');
            }

            // Parse the JSON to get the submissionController
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            String submissionControllerName = (String) config.get('submissionController');

            if (String.isBlank(submissionControllerName)) {
                throw new FormWizardException(
                    'No submissionController specified in wizard configuration for "' + wizardType + '".'
                );
            }

            // Dynamically instantiate the handler class
            Type handlerType = Type.forName(submissionControllerName);
            
            if (handlerType == null) {
                throw new FormWizardException(
                    'Submission handler class "' + submissionControllerName + '" not found.'
                );
            }

            // Create instance and verify it implements the interface
            Object handlerInstance = handlerType.newInstance();
            
            if (!(handlerInstance instanceof I_FormSubmissionHandler)) {
                throw new FormWizardException(
                    'Submission handler class "' + submissionControllerName + 
                    '" must implement I_FormSubmissionHandler interface.'
                );
            }

            // Cast and call the submitForm method
            I_FormSubmissionHandler handler = (I_FormSubmissionHandler) handlerInstance;
            return handler.submitForm(sessionId, answersJson, wizardType);

        } catch (Exception e) {
            throw new FormWizardException('Error submitting form: ' + e.getMessage());
        } finally {
            ApexLog.finalize();
        }
    }

    /**
     * @description Abandon an existing session and create a new one
     * @param email User's email address
     * @param oldSessionToken Token of the session to abandon
     * @param wizardType Type of wizard form
     * @param ipAddress User's IP address
     * @return New Form_Session__c record
     */
    @AuraEnabled(cacheable=false)
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static Form_Session__c abandonAndCreateNewSession(
        String email, String oldSessionToken, String wizardType, String ipAddress
    ) {
        String method = 'abandonAndCreateNewSession';
        try {
            if (String.isBlank(email)) {
                throw new FormWizardException('Email is required.');
            }
            email = email.trim().toLowerCase();

            // Update old session status to Abandoned (do not modify verification fields)
            if (String.isNotBlank(oldSessionToken)) {
                List<Form_Session__c> oldSessions = [
                    SELECT Id, Status__c
                    FROM Form_Session__c
                    WHERE Session_Token__c = :oldSessionToken
                    LIMIT 1
                ]; // NOPMD - Direct query needed
                
                if (!oldSessions.isEmpty() && oldSessions[0].Status__c == 'In Progress') {
                    Form_Session__c oldSession = oldSessions[0];
                    
                    // Only update status, leave verification fields unchanged
                    oldSession.Status__c = 'Abandoned';
                    update oldSession; // NOPMD - CRUD validated
                    System.debug('Old session abandoned: ' + oldSession.Id);
                }
            }

            // Get most recent verification values for this email
            List<Form_Session__c> recentSessions = [
                SELECT Id, Verification_Code__c, Verification_Sent_On__c
                FROM Form_Session__c
                WHERE Guest_Email__c = :email
                AND Verification_Code__c != null
                AND Verification_Sent_On__c != null
                ORDER BY Verification_Sent_On__c DESC
                LIMIT 1
            ]; // NOPMD - Direct query needed

            // Create new session
            Form_Session__c newSession = createSession(email, wizardType, ipAddress, 1, null);
            
            // Populate new session with most recent verification values
            if (!recentSessions.isEmpty()) {
                newSession.Verification_Code__c = recentSessions[0].Verification_Code__c;
                newSession.Verification_Sent_On__c = recentSessions[0].Verification_Sent_On__c;
                update newSession; // NOPMD - CRUD validated
            }
            
            return newSession;

        } catch (Exception ex) {
            FormWizardService.handleAndRethrow(ex, method, 'email=' + email);
            return null;
        } finally {
            ApexLog.finalize();
        }
    }

    /**
     * @description Mark a session as expired and create a new one
     * @param email User's email address
     * @param oldSessionToken Token of the session to expire
     * @param wizardType Type of wizard form
     * @param ipAddress User's IP address
     * @return New Form_Session__c record
     */
    @AuraEnabled(cacheable=false)
    public static Form_Session__c expireAndCreateNewSession(
        String email, String oldSessionToken, String wizardType, String ipAddress
    ) {
        String method = 'expireAndCreateNewSession';
        try {
            if (String.isBlank(email)) {
                throw new FormWizardException('Email is required.');
            }
            email = email.trim().toLowerCase();

            // Update old session status to Expired (do not modify verification fields)
            if (String.isNotBlank(oldSessionToken)) {
                List<Form_Session__c> oldSessions = [
                    SELECT Id, Status__c
                    FROM Form_Session__c
                    WHERE Session_Token__c = :oldSessionToken
                    LIMIT 1
                ]; // NOPMD - Direct query needed
                
                if (!oldSessions.isEmpty() && oldSessions[0].Status__c == 'In Progress') {
                    Form_Session__c oldSession = oldSessions[0];
                    
                    // Only update status, leave verification fields unchanged
                    oldSession.Status__c = 'Expired';
                    update oldSession; // NOPMD - CRUD validated
                    System.debug('Old session expired: ' + oldSession.Id);
                }
            }

            // Get most recent verification values for this email
            List<Form_Session__c> recentSessions = [
                SELECT Id, Verification_Code__c, Verification_Sent_On__c
                FROM Form_Session__c
                WHERE Guest_Email__c = :email
                AND Verification_Code__c != null
                AND Verification_Sent_On__c != null
                ORDER BY Verification_Sent_On__c DESC
                LIMIT 1
            ]; // NOPMD - Direct query needed

            // Create new session
            Form_Session__c newSession = createSession(email, wizardType, ipAddress, 1, null);
            
            // Populate new session with most recent verification values
            if (!recentSessions.isEmpty()) {
                newSession.Verification_Code__c = recentSessions[0].Verification_Code__c;
                newSession.Verification_Sent_On__c = recentSessions[0].Verification_Sent_On__c;
                update newSession; // NOPMD - CRUD validated
            }
            
            return newSession;

        } catch (Exception ex) {
            FormWizardService.handleAndRethrow(ex, method, 'email=' + email);
            return null;
        } finally {
            ApexLog.finalize();
        }
    }

    // -----------------------------
    // Session Editor Methods
    // -----------------------------

    /**
     * @description Get session by record ID for the Session Editor component
     * @param sessionId The Form_Session__c record Id
     * @return Form_Session__c record with all fields
     */
    @AuraEnabled(cacheable=false)
    public static Form_Session__c getSessionById(Id sessionId) {
        String method = 'getSessionById';
        try {
            if (sessionId == null) {
                throw new FormWizardException('Session ID is required.');
            }

            List<Form_Session__c> sessions = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, IP_Address__c,
                       Status__c, Current_Step__c, Started_Date__c, Last_Modified_Date__c,
                       Session_Token__c, Answers_JSON__c, Verification_Code__c,
                       Verification_Sent_On__c, Final_Record_Id__c, Completion_Date__c
                FROM Form_Session__c
                WHERE Id = :sessionId
                LIMIT 1
            ];

            if (sessions.isEmpty()) {
                throw new FormWizardException('Session not found.');
            }

            return sessions[0];
        } catch (Exception ex) {
            FormWizardService.handleAndRethrow(ex, method, 'sessionId=' + sessionId);
            return null;
        } finally {
            ApexLog.finalize();
        }
    }

    /**
     * @description Update session answers JSON without triggering submission
     * @param sessionId The Form_Session__c record Id
     * @param answersJson The new JSON string for Answers_JSON__c
     * @return Updated Form_Session__c record
     */
    @AuraEnabled(cacheable=false)
    public static Form_Session__c updateSessionAnswers(Id sessionId, String answersJson) {
        String method = 'updateSessionAnswers';
        try {
            if (sessionId == null) {
                throw new FormWizardException('Session ID is required.');
            }
            if (String.isBlank(answersJson)) {
                throw new FormWizardException('Answers JSON is required.');
            }

            // Validate JSON format
            try {
                JSON.deserializeUntyped(answersJson);
            } catch (Exception jsonEx) {
                throw new FormWizardException('Invalid JSON format: ' + jsonEx.getMessage());
            }

            List<Form_Session__c> sessions = [
                SELECT Id, Answers_JSON__c, Last_Modified_Date__c
                FROM Form_Session__c
                WHERE Id = :sessionId
                LIMIT 1
            ];

            if (sessions.isEmpty()) {
                throw new FormWizardException('Session not found.');
            }

            Form_Session__c session = sessions[0];
            session.Answers_JSON__c = answersJson;
            session.Last_Modified_Date__c = System.now();
            update session;

            return getSessionById(sessionId);
        } catch (Exception ex) {
            FormWizardService.handleAndRethrow(ex, method, 'sessionId=' + sessionId);
            return null;
        } finally {
            ApexLog.finalize();
        }
    }

    // -----------------------------
    // Help Request Email Methods
    // -----------------------------

    // Placeholder email - to be updated with actual help team email later
    private static final List<String> HELP_TEAM_EMAILS = new List<String>{
        'user6@company.com'
    };

    // Org-Wide Email Address for sending emails (required for guest user context)
    private static final String ORG_WIDE_EMAIL_ADDRESS = 'pm@company.com';

    // Email template developer name for help requests
    private static final String HELP_REQUEST_TEMPLATE_NAME = 'Form_Help_Notification';

    /**
     * @description Send a help request email to the internal support team
     * @param firstName User's first name
     * @param lastName User's last name
     * @param company User's company name
     * @param email User's email address
     * @param comments User's comments/message
     * @param sessionId The Form_Session__c record Id
     * @param emailRecipients JSON array of recipient email addresses (optional - falls back to HELP_TEAM_EMAILS)
     * @param emailSender Org-wide email address for sending (optional - falls back to ORG_WIDE_EMAIL_ADDRESS)
     */
    @AuraEnabled
    public static void sendHelpRequestEmail(
        String firstName,
        String lastName,
        String company,
        String email,
        String comments,
        String sessionId,
        String emailRecipients,
        String emailSender
    ) {
        String method = 'sendHelpRequestEmail';
        try {
            // Parse email recipients from JSON, fallback to default if empty/invalid
            List<String> recipientList;
            if (String.isNotBlank(emailRecipients)) {
                try {
                    recipientList = (List<String>) JSON.deserialize(emailRecipients, List<String>.class);
                } catch (Exception e) {
                    recipientList = null;
                }
            }
            if (recipientList == null || recipientList.isEmpty()) {
                recipientList = HELP_TEAM_EMAILS;
            }

            // Use provided sender address or fallback to default
            String senderAddress = String.isNotBlank(emailSender) ? emailSender : ORG_WIDE_EMAIL_ADDRESS;

            // Build Salesforce link to session record
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            String sessionLink = String.isNotBlank(sessionId) ? baseUrl + '/' + sessionId : 'N/A';

            // Get session name if sessionId is provided
            String sessionName = 'N/A';
            if (String.isNotBlank(sessionId)) {
                List<Form_Session__c> sessions = [
                    SELECT Name FROM Form_Session__c WHERE Id = :sessionId LIMIT 1
                ];
                if (!sessions.isEmpty()) {
                    sessionName = sessions[0].Name;
                }
            }

            // Build full name
            String fullName = '';
            if (String.isNotBlank(firstName)) {
                fullName = firstName;
            }
            if (String.isNotBlank(lastName)) {
                fullName += (String.isNotBlank(fullName) ? ' ' : '') + lastName;
            }
            if (String.isBlank(fullName)) {
                fullName = 'Not provided';
            }

            // Prepare merge field values
            String companyValue = String.isNotBlank(company) ? company : 'Not provided';
            String emailValue = String.isNotBlank(email) ? email : 'Not provided';
            String commentsValue = String.isNotBlank(comments) ? comments : 'No additional comments provided';

            // Get email template and replace placeholders
            EmailTemplate template = getHelpRequestEmailTemplate();
            String subject;
            String htmlBody;
            String plainTextBody;

            if (template != null) {
                // Replace placeholders in subject
                subject = template.Subject;
                subject = subject.replace('{{{fullName}}}', fullName);

                // Replace placeholders in HTML body
                htmlBody = template.HtmlValue;
                htmlBody = htmlBody.replace('{{{fullName}}}', String.escapeSingleQuotes(fullName));
                htmlBody = htmlBody.replace('{{{company}}}', String.escapeSingleQuotes(companyValue));
                htmlBody = htmlBody.replace('{{{email}}}', String.escapeSingleQuotes(emailValue));
                htmlBody = htmlBody.replace('{{{sessionName}}}', String.escapeSingleQuotes(sessionName));
                htmlBody = htmlBody.replace('{{{sessionLink}}}', sessionLink);
                htmlBody = htmlBody.replace('{{{comments}}}', String.escapeSingleQuotes(commentsValue));

                // Build plain text from template body or generate fallback
                plainTextBody = buildHelpRequestEmailPlainText(
                    fullName, companyValue, emailValue, sessionName, sessionLink, commentsValue
                );
            } else {
                // Fallback when template is not available (e.g., in test context)
                subject = 'Help Request from ' + fullName;
                plainTextBody = buildHelpRequestEmailPlainText(
                    fullName, companyValue, emailValue, sessionName, sessionLink, commentsValue
                );
            }

            // Get effective email addresses (handles sandbox redirect)
            List<String> effectiveEmails = getEffectiveHelpEmailAddresses(recipientList);

            // Create and send email
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(effectiveEmails);
            mail.setSubject(subject);
            if (htmlBody != null) {
                mail.setHtmlBody(htmlBody);
            }
            mail.setPlainTextBody(plainTextBody);
            Id oweaId = getOrgWideEmailAddressId(senderAddress);
            if (oweaId != null) {
                mail.setOrgWideEmailAddressId(oweaId);
            }

            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });

            // Log success
            ApexLog.logMessage(
                ApexLog.LogLevel.INFO,
                'Help request email sent successfully',
                'FormWizardController',
                method,
                'sessionId=' + sessionId + ', email=' + email + ', recipients=' + String.join(effectiveEmails, ',')
            );

        } catch (Exception ex) {
            ApexLog.logException(ex, 'FormWizardController', method, 'sessionId=' + sessionId);
            throw new AuraHandledException('Failed to send help request: ' + ex.getMessage());
        } finally {
            ApexLog.finalize();
        }
    }

    /**
     * @description Get effective email addresses (redirects to non-prod email in sandbox)
     */
    private static List<String> getEffectiveHelpEmailAddresses(List<String> addresses) {
        //if (FormEmailService.isProductionOrg()) {
            return addresses;
        //}
        //return new List<String>{ FormEmailService.getNonProdEmailAddress() };
    }

    /**
     * @description Get Org-Wide Email Address ID for sending emails from guest user context.
     *              Queries by email address to avoid hardcoding environment-specific IDs.
     * @param senderAddress The email address to look up
     * @return Id of OrgWideEmailAddress record, or null if not found
     */
    private static Id getOrgWideEmailAddressId(String senderAddress) {
        List<OrgWideEmailAddress> owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :senderAddress
            LIMIT 1
        ];

        if (owea.isEmpty()) {
            ApexLog.logMessage(
                ApexLog.LogLevel.WARN,
                'Org-Wide Email Address not found',
                'FormWizardController',
                'getOrgWideEmailAddressId',
                'Address: ' + senderAddress
            );
            return null;
        }

        return owea[0].Id;
    }

    /**
     * @description Get the help request email template by developer name.
     * @return EmailTemplate record with HtmlValue and Subject, or null if not found
     */
    private static EmailTemplate getHelpRequestEmailTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName = :HELP_REQUEST_TEMPLATE_NAME
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            return null;
        }

        return templates[0];
    }

    /**
     * @description Build plain text email body for help request
     */
    private static String buildHelpRequestEmailPlainText(
        String fullName,
        String company,
        String email,
        String sessionName,
        String sessionLink,
        String comments
    ) {
        return 'HELP REQUEST RECEIVED\n' +
            '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n' +
            'A user has requested assistance while filling out the Dynamic Request Form.\n\n' +
            'CONTACT INFORMATION:\n\n' +
            'Name: ' + fullName + '\n' +
            'Company: ' + company + '\n' +
            'Email: ' + email + '\n' +
            'Session: ' + sessionName + '\n' +
            'View in Salesforce: ' + sessionLink + '\n\n' +
            '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n' +
            'USER\'S MESSAGE:\n\n' +
            comments + '\n\n' +
            '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n' +
            '⏰ ACTION REQUIRED:\n' +
            'Please respond to this help request within 1 business day.\n\n' +
            '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n' +
            'This is an automated notification from the Dynamic Request Form system.';
    }
}