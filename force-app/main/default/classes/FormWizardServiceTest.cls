/**
 * @description Test class for FormWizardService
 * Tests utility methods for session management, token generation, OTP generation,
 * and form configuration retrieval
 *
 * @group form Tests
 * @author Dynamic Request Form Team
 */
@isTest
private class FormWizardServiceTest {

    // ==========================================
    // TEST SETUP
    // ==========================================

    @TestSetup
    static void setupTestData() {
        // Create test user with permissions
        TestDataFactory factory = new TestDataFactory();
        User testUser = factory.createUser();
        testUser.IsActive = true;
        testUser.Email = 'formwizardservice_' + System.currentTimeMillis() + '@company.com';
        insert testUser;

        // Assign Permission Set
        PermissionSet psBase = [SELECT Id FROM PermissionSet WHERE Name = 'Base_Public_User' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = psBase.Id);

        System.runAs(testUser) {
            // Create Form Wizard Configurations
            List<Dynamic_Form_Config__c> configs = new List<Dynamic_Form_Config__c>();

            // Main config with submissionController
            configs.add(new Dynamic_Form_Config__c(
                Title__c = 'Test_Wizard_Config',
                Label__c = 'Test Wizard Config',
                Form_Config__c = getTestWizardConfigJson()
            ));

            // Config without submissionController
            configs.add(new Dynamic_Form_Config__c(
                Title__c = 'No_Controller_Config',
                Label__c = 'No Controller Config',
                Form_Config__c = '{"title":"No Controller","steps":[]}'
            ));

            insert configs;

            // Create Study Request Sessions
            List<Form_Session__c> sessions = new List<Form_Session__c>();

            // Session for status update tests
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'status@example.com',
                Wizard_Type__c = 'Test_Wizard_Config',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{"test":"data"}',
                Session_Token__c = 'STATUS_TEST_TOKEN_123'
            ));

            // Session for load tests
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'load@example.com',
                Wizard_Type__c = 'Test_Wizard_Config',
                Status__c = 'In Progress',
                Current_Step__c = 2,
                Answers_JSON__c = '{"step":"2"}',
                Session_Token__c = 'LOAD_TEST_TOKEN_456'
            ));

            insert sessions;
        }
    }

    /**
     * @description Helper to retrieve the active test user created in @TestSetup
     */
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'formwizardservice_%' AND IsActive = TRUE LIMIT 1];
    }

    // ==========================================
    // getFormConfigByTitle TESTS
    // ==========================================

    @isTest
    static void testGetFormConfigByTitle_ReturnsSubmissionController() {
        System.runAs(getTestUser()) {
            Test.startTest();
            String controller = FormWizardService.getFormConfigByTitle('Test_Wizard_Config');
            Test.stopTest();

            System.assertEquals('FormSubmissionHandler', controller,
                'Should return the submissionController from config JSON');
        }
    }

    @isTest
    static void testGetFormConfigByTitle_NoSubmissionController_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            String controller = FormWizardService.getFormConfigByTitle('No_Controller_Config');
            Test.stopTest();

            System.assertEquals(null, controller,
                'Should return null when submissionController is not in config');
        }
    }

    @isTest
    static void testGetFormConfigByTitle_NotFound_ThrowsException() {
        System.runAs(getTestUser()) {
            Test.startTest();
            try {
                FormWizardService.getFormConfigByTitle('NonExistent_Config');
                System.assert(false, 'Should have thrown FormWizardServiceException');
            } catch (FormWizardService.FormWizardServiceException e) {
                System.assert(e.getMessage().contains('No form configuration found'),
                    'Exception message should indicate config not found. Got: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testGetFormConfigByTitle_NullTitle_ThrowsException() {
        System.runAs(getTestUser()) {
            Test.startTest();
            try {
                FormWizardService.getFormConfigByTitle(null);
                System.assert(false, 'Should have thrown FormWizardServiceException');
            } catch (FormWizardService.FormWizardServiceException e) {
                System.assert(e.getMessage().contains('No form configuration found'),
                    'Exception message should indicate config not found');
            }
            Test.stopTest();
        }
    }

    // ==========================================
    // setSessionStatus TESTS
    // ==========================================

    @isTest
    static void testSetSessionStatus_UpdatesStatus() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Status__c FROM Form_Session__c
                WHERE Guest_Email__c = 'status@example.com' LIMIT 1
            ];
            System.assertEquals('In Progress', session.Status__c, 'Initial status should be In Progress');

            Test.startTest();
            FormWizardService.setSessionStatus(session.Id, 'Submitted');
            Test.stopTest();

            // Verify status was updated
            Form_Session__c updatedSession = [
                SELECT Status__c FROM Form_Session__c WHERE Id = :session.Id
            ];
            System.assertEquals('Submitted', updatedSession.Status__c,
                'Status should be updated to Submitted');
        }
    }

    @isTest
    static void testSetSessionStatus_AbandonedStatus() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'status@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardService.setSessionStatus(session.Id, 'Abandoned');
            Test.stopTest();

            Form_Session__c updatedSession = [
                SELECT Status__c FROM Form_Session__c WHERE Id = :session.Id
            ];
            System.assertEquals('Abandoned', updatedSession.Status__c,
                'Status should be updated to Abandoned');
        }
    }

    @isTest
    static void testSetSessionStatus_ExpiredStatus() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'load@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardService.setSessionStatus(session.Id, 'Expired');
            Test.stopTest();

            Form_Session__c updatedSession = [
                SELECT Status__c FROM Form_Session__c WHERE Id = :session.Id
            ];
            System.assertEquals('Expired', updatedSession.Status__c,
                'Status should be updated to Expired');
        }
    }

    @isTest
    static void testSetSessionStatus_InvalidId_ThrowsException() {
        System.runAs(getTestUser()) {
            Test.startTest();
            try {
                // Use Form_Session__c prefix but non-existent Id
                // Get a valid key prefix for Form_Session__c
                String keyPrefix = Form_Session__c.SObjectType.getDescribe().getKeyPrefix();
                String fakeId = keyPrefix + '000000000000AAA';
                FormWizardService.setSessionStatus(fakeId, 'Submitted');
                System.assert(false, 'Should have thrown exception for invalid Id');
            } catch (DmlException e) {
                System.assert(true, 'Expected DmlException for non-existent session Id');
            } catch (System.TypeException e) {
                // Also valid - the ID format might be wrong
                System.assert(true, 'Expected TypeException for invalid Id format');
            }
            Test.stopTest();
        }
    }

    // ==========================================
    // createAndSubmitSession TESTS
    // ==========================================

    @isTest
    static void testCreateAndSubmitSession_CreatesNewSession() {
        System.runAs(getTestUser()) {
            // Create a session to build state model from
            Form_Session__c tempSession = new Form_Session__c(
                Guest_Email__c = 'newsubmit@example.com',
                Wizard_Type__c = 'Test_Wizard_Config',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{"firstName":"Test","lastName":"User"}',
                Session_Token__c = 'TEMP_TOKEN'
            );
            insert tempSession;

            // Create state model
            FormWizardStateModel stateModel = new FormWizardStateModel(tempSession);
            stateModel.primaryEmail = 'newsubmit@example.com';
            stateModel.formType = 'Test_Wizard_Config';
            stateModel.answers = '{"firstName":"Test","lastName":"User"}';

            Test.startTest();
            Form_Session__c result = FormWizardService.createAndSubmitSession(stateModel);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a session record');
            System.assertNotEquals(null, result.Id, 'Session should have an Id');
            System.assertNotEquals(null, result.Name, 'Session should have a Name (auto-number)');
            System.assertEquals('Submitted', result.Status__c, 'Status should be Submitted');
            System.assertEquals('Test_Wizard_Config', result.Wizard_Type__c, 'Wizard type should match');
            System.assertEquals('newsubmit@example.com', result.Guest_Email__c, 'Email should match');
            System.assertEquals(1, result.Current_Step__c, 'Current step should be 1');
        }
    }

    @isTest
    static void testCreateAndSubmitSession_SerializesAnswers() {
        System.runAs(getTestUser()) {
            // Create a session to build state model from
            Form_Session__c tempSession = new Form_Session__c(
                Guest_Email__c = 'answers@example.com',
                Wizard_Type__c = 'Test_Wizard_Config',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{}',
                Session_Token__c = 'ANSWER_TOKEN'
            );
            insert tempSession;

            // Create state model with specific answers
            FormWizardStateModel stateModel = new FormWizardStateModel(tempSession);
            stateModel.primaryEmail = 'answers@example.com';
            stateModel.formType = 'Test_Wizard_Config';
            stateModel.answers = '{"organization":"Test Corp","phone":"5551234567"}';

            Test.startTest();
            Form_Session__c result = FormWizardService.createAndSubmitSession(stateModel);
            Test.stopTest();

            // Verify answers are serialized (wrapped in quotes as string)
            System.assert(result.Answers_JSON__c.contains('organization'),
                'Answers should contain organization field');
            System.assert(result.Answers_JSON__c.contains('Test Corp'),
                'Answers should contain organization value');
        }
    }

    // ==========================================
    // loadSessionById TESTS
    // ==========================================

    @isTest
    static void testLoadSessionById_ReturnsSession() {
        System.runAs(getTestUser()) {
            Form_Session__c existingSession = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'load@example.com' LIMIT 1
            ];

            Test.startTest();
            Form_Session__c result = FormWizardService.loadSessionById(existingSession.Id);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a session');
            System.assertEquals(existingSession.Id, result.Id, 'Should return the correct session');
            System.assertEquals('load@example.com', result.Guest_Email__c, 'Email should match');
            System.assertEquals('LOAD_TEST_TOKEN_456', result.Session_Token__c, 'Token should match');
            System.assertEquals('Test_Wizard_Config', result.Wizard_Type__c, 'Wizard type should match');
            System.assertEquals(2, result.Current_Step__c, 'Current step should match');
        }
    }

    @isTest
    static void testLoadSessionById_ReturnsAllFields() {
        System.runAs(getTestUser()) {
            Form_Session__c existingSession = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'status@example.com' LIMIT 1
            ];

            Test.startTest();
            Form_Session__c result = FormWizardService.loadSessionById(existingSession.Id);
            Test.stopTest();

            // Verify all queried fields are present
            System.assertNotEquals(null, result.Id, 'Id should be populated');
            System.assertNotEquals(null, result.Name, 'Name should be populated');
            System.assertNotEquals(null, result.Session_Token__c, 'Session_Token__c should be populated');
            System.assertNotEquals(null, result.Guest_Email__c, 'Guest_Email__c should be populated');
            System.assertNotEquals(null, result.Wizard_Type__c, 'Wizard_Type__c should be populated');
            System.assertNotEquals(null, result.Status__c, 'Status__c should be populated');
            System.assertNotEquals(null, result.Current_Step__c, 'Current_Step__c should be populated');
        }
    }

    @isTest
    static void testLoadSessionById_NotFound_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Use a valid format but non-existent Id
            Form_Session__c result = FormWizardService.loadSessionById('a0000000000000AAAA');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for non-existent session');
        }
    }

    @isTest
    static void testLoadSessionById_NullId_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = FormWizardService.loadSessionById(null);
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for null Id');
        }
    }

    // ==========================================
    // generateToken TESTS
    // ==========================================

    @isTest
    static void testGenerateToken_Returns32CharHexString() {
        Test.startTest();
        String token = FormWizardService.generateToken(
            'test@example.com',
            Datetime.now(),
            'TestName'
        );
        Test.stopTest();

        System.assertNotEquals(null, token, 'Token should not be null');
        System.assertEquals(32, token.length(), 'Token should be 32 characters');
        // Verify it's a valid hex string (only contains 0-9, a-f)
        Pattern hexPattern = Pattern.compile('^[0-9a-f]{32}$');
        Matcher m = hexPattern.matcher(token);
        System.assert(m.matches(), 'Token should be valid hexadecimal: ' + token);
    }

    @isTest
    static void testGenerateToken_SameInputs_SameOutput() {
        Datetime fixedTime = Datetime.newInstance(2025, 1, 15, 10, 30, 0);

        Test.startTest();
        String token1 = FormWizardService.generateToken('same@example.com', fixedTime, 'SameName');
        String token2 = FormWizardService.generateToken('same@example.com', fixedTime, 'SameName');
        Test.stopTest();

        System.assertEquals(token1, token2,
            'Same inputs should produce same token (deterministic SHA-256)');
    }

    @isTest
    static void testGenerateToken_DifferentInputs_DifferentOutput() {
        Datetime time1 = Datetime.newInstance(2025, 1, 15, 10, 30, 0);
        Datetime time2 = Datetime.newInstance(2025, 1, 15, 10, 30, 1);

        Test.startTest();
        String token1 = FormWizardService.generateToken('diff@example.com', time1, 'Name1');
        String token2 = FormWizardService.generateToken('diff@example.com', time2, 'Name1');
        String token3 = FormWizardService.generateToken('diff2@example.com', time1, 'Name1');
        String token4 = FormWizardService.generateToken('diff@example.com', time1, 'Name2');
        Test.stopTest();

        System.assertNotEquals(token1, token2, 'Different datetime should produce different token');
        System.assertNotEquals(token1, token3, 'Different email should produce different token');
        System.assertNotEquals(token1, token4, 'Different name should produce different token');
    }

    @isTest
    static void testGenerateToken_SpecialCharacters() {
        Test.startTest();
        String token = FormWizardService.generateToken(
            'test+special@example.com',
            Datetime.now(),
            'Name With Spaces'
        );
        Test.stopTest();

        System.assertEquals(32, token.length(),
            'Token should still be 32 characters with special input');
    }

    @isTest
    static void testGenerateToken_EmptyStrings() {
        Test.startTest();
        String token = FormWizardService.generateToken('', Datetime.now(), '');
        Test.stopTest();

        System.assertEquals(32, token.length(),
            'Token should be 32 characters even with empty strings');
    }

    // ==========================================
    // generateOtp TESTS
    // ==========================================

    @isTest
    static void testGenerateOtp_Returns6DigitString() {
        Test.startTest();
        String otp = FormWizardService.generateOtp();
        Test.stopTest();

        System.assertNotEquals(null, otp, 'OTP should not be null');
        System.assertEquals(6, otp.length(), 'OTP should be 6 characters');
        // Verify it's a valid 6-digit number
        Pattern numPattern = Pattern.compile('^[0-9]{6}$');
        Matcher m = numPattern.matcher(otp);
        System.assert(m.matches(), 'OTP should be 6 digits: ' + otp);
    }

    @isTest
    static void testGenerateOtp_WithinValidRange() {
        Test.startTest();
        String otp = FormWizardService.generateOtp();
        Test.stopTest();

        Integer otpValue = Integer.valueOf(otp);
        System.assert(otpValue >= 100000, 'OTP should be at least 100000: ' + otpValue);
        System.assert(otpValue <= 999999, 'OTP should be at most 999999: ' + otpValue);
    }

    @isTest
    static void testGenerateOtp_MultipleCallsProduceDifferentValues() {
        Set<String> otpSet = new Set<String>();

        Test.startTest();
        // Generate multiple OTPs
        for (Integer i = 0; i < 10; i++) {
            otpSet.add(FormWizardService.generateOtp());
        }
        Test.stopTest();

        // Due to randomness, we should get mostly unique values
        // With 10 attempts from 900,000 possibilities, collision is extremely unlikely
        System.assert(otpSet.size() >= 8,
            'Should generate mostly unique OTPs. Got ' + otpSet.size() + ' unique values');
    }

    @isTest
    static void testGenerateOtp_BulkGeneration() {
        List<String> otps = new List<String>();

        Test.startTest();
        // Generate 200 OTPs to test bulk behavior
        for (Integer i = 0; i < 200; i++) {
            String otp = FormWizardService.generateOtp();
            otps.add(otp);
            // Verify each is valid
            System.assertEquals(6, otp.length(), 'Each OTP should be 6 digits');
            Integer val = Integer.valueOf(otp);
            System.assert(val >= 100000 && val <= 999999, 'OTP out of range: ' + val);
        }
        Test.stopTest();

        System.assertEquals(200, otps.size(), 'Should generate 200 OTPs');
    }

    // ==========================================
    // handleAndRethrow TESTS
    // ==========================================

    @isTest
    static void testHandleAndRethrow_RethrowsException() {
        Test.startTest();
        try {
            Exception testException = new FormWizardService.FormWizardServiceException('Test error message');
            FormWizardService.handleAndRethrow(testException, 'testMethod', 'Test context');
            System.assert(false, 'Should have rethrown the exception');
        } catch (FormWizardService.FormWizardServiceException e) {
            System.assertEquals('Test error message', e.getMessage(),
                'Should rethrow with original message');
        }
        Test.stopTest();
    }

    @isTest
    static void testHandleAndRethrow_WithDifferentExceptionType() {
        Test.startTest();
        try {
            Exception testException = new DmlException('DML error occurred');
            FormWizardService.handleAndRethrow(testException, 'dmlMethod', 'DML context');
            System.assert(false, 'Should have rethrown the exception');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('DML error'),
                'Should rethrow DmlException with message');
        }
        Test.stopTest();
    }

    @isTest
    static void testHandleAndRethrow_WithNullPointerException() {
        Test.startTest();
        try {
            Exception testException = new NullPointerException();
            FormWizardService.handleAndRethrow(testException, 'nullMethod', 'Null pointer context');
            System.assert(false, 'Should have rethrown the exception');
        } catch (NullPointerException e) {
            System.assert(true, 'Should rethrow NullPointerException');
        }
        Test.stopTest();
    }

    // ==========================================
    // DTO CLASSES TESTS
    // ==========================================

    @isTest
    static void testCreateSessionInput_DTO() {
        Test.startTest();
        FormWizardService.CreateSessionInput input = new FormWizardService.CreateSessionInput();
        input.email = 'dto@example.com';
        input.wizardType = 'Test_Wizard';
        input.ipAddress = '192.168.1.1';
        input.startingStep = 2;
        Test.stopTest();

        System.assertEquals('dto@example.com', input.email, 'Email should be set');
        System.assertEquals('Test_Wizard', input.wizardType, 'Wizard type should be set');
        System.assertEquals('192.168.1.1', input.ipAddress, 'IP address should be set');
        System.assertEquals(2, input.startingStep, 'Starting step should be set');
    }

    @isTest
    static void testUpdateSessionInput_DTO() {
        Test.startTest();
        FormWizardService.UpdateSessionInput input = new FormWizardService.UpdateSessionInput();
        input.sessionToken = 'TOKEN_123';
        input.currentStep = 3;
        input.answersJson = '{"key":"value"}';
        input.status = 'Completed';
        Test.stopTest();

        System.assertEquals('TOKEN_123', input.sessionToken, 'Session token should be set');
        System.assertEquals(3, input.currentStep, 'Current step should be set');
        System.assertEquals('{"key":"value"}', input.answersJson, 'Answers JSON should be set');
        System.assertEquals('Completed', input.status, 'Status should be set');
    }

    @isTest
    static void testLoadSessionInput_DTO() {
        Test.startTest();
        FormWizardService.LoadSessionInput input = new FormWizardService.LoadSessionInput();
        input.sessionToken = 'LOAD_TOKEN';
        input.email = 'load@example.com';
        Test.stopTest();

        System.assertEquals('LOAD_TOKEN', input.sessionToken, 'Session token should be set');
        System.assertEquals('load@example.com', input.email, 'Email should be set');
    }

    @isTest
    static void testCreateOnsiteSessionInput_DTO() {
        Test.startTest();
        FormWizardService.CreateOnsiteSessionInput input = new FormWizardService.CreateOnsiteSessionInput();
        input.email = 'onsite@example.com';
        input.wizardType = 'Onsite_Form';
        input.answersJson = '{"onsite":"data"}';
        input.ipAddress = '10.0.0.1';
        Test.stopTest();

        System.assertEquals('onsite@example.com', input.email, 'Email should be set');
        System.assertEquals('Onsite_Form', input.wizardType, 'Wizard type should be set');
        System.assertEquals('{"onsite":"data"}', input.answersJson, 'Answers JSON should be set');
        System.assertEquals('10.0.0.1', input.ipAddress, 'IP address should be set');
    }

    @isTest
    static void testValidateSessionInput_DTO() {
        Test.startTest();
        FormWizardService.ValidateSessionInput input = new FormWizardService.ValidateSessionInput();
        input.email = 'validate@example.com';
        input.otp = '123456';
        input.requestNewOtp = true;
        Test.stopTest();

        System.assertEquals('validate@example.com', input.email, 'Email should be set');
        System.assertEquals('123456', input.otp, 'OTP should be set');
        System.assertEquals(true, input.requestNewOtp, 'requestNewOtp should be set');
    }

    @isTest
    static void testValidateSessionResult_DTO() {
        Test.startTest();
        FormWizardService.ValidateSessionResult result = new FormWizardService.ValidateSessionResult();
        result.sent = true;
        result.verified = false;
        result.sessionToken = 'RESULT_TOKEN';
        result.message = 'Test message';
        result.sessionData = null;
        Test.stopTest();

        System.assertEquals(true, result.sent, 'sent should be set');
        System.assertEquals(false, result.verified, 'verified should be set');
        System.assertEquals('RESULT_TOKEN', result.sessionToken, 'Session token should be set');
        System.assertEquals('Test message', result.message, 'Message should be set');
        System.assertEquals(null, result.sessionData, 'Session data should be null');
    }

    @isTest
    static void testValidateSessionResult_WithSessionData() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Session_Token__c, Guest_Email__c, Wizard_Type__c,
                       Status__c, Current_Step__c, Answers_JSON__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'load@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardService.ValidateSessionResult result = new FormWizardService.ValidateSessionResult();
            result.sent = false;
            result.verified = true;
            result.sessionToken = session.Session_Token__c;
            result.message = 'Verification successful';
            result.sessionData = session;
            Test.stopTest();

            System.assertEquals(true, result.verified, 'verified should be true');
            System.assertNotEquals(null, result.sessionData, 'Session data should not be null');
            System.assertEquals('load@example.com', result.sessionData.Guest_Email__c,
                'Session data email should match');
        }
    }

    // ==========================================
    // CUSTOM EXCEPTION TESTS
    // ==========================================

    @isTest
    static void testFormWizardServiceException_CanBeThrown() {
        Test.startTest();
        try {
            throw new FormWizardService.FormWizardServiceException('Custom exception message');
        } catch (FormWizardService.FormWizardServiceException e) {
            System.assertEquals('Custom exception message', e.getMessage(),
                'Exception should have custom message');
        }
        Test.stopTest();
    }

    @isTest
    static void testFormWizardServiceException_EmptyMessage() {
        Test.startTest();
        try {
            throw new FormWizardService.FormWizardServiceException('');
        } catch (FormWizardService.FormWizardServiceException e) {
            System.assertEquals('', e.getMessage(),
                'Exception should accept empty message');
        }
        Test.stopTest();
    }

    // ==========================================
    // HELPER METHODS
    // ==========================================

    private static String getTestWizardConfigJson() {
        Map<String, Object> config = new Map<String, Object>{
            'title' => 'Test Wizard',
            'total_steps' => 3,
            'submissionController' => 'FormSubmissionHandler',
            'emailSessionRequired' => false,
            'allow_save_resume' => true,
            'steps' => new List<Object>{
                new Map<String, Object>{
                    'stepNumber' => 1,
                    'sections' => new List<Object>{
                        new Map<String, Object>{
                            'questions' => new List<Object>{
                                new Map<String, Object>{
                                    'name' => 'testField',
                                    'targetField' => 'Contact.FirstName',
                                    'type' => 'text',
                                    'isRequired' => true
                                }
                            }
                        }
                    }
                }
            }
        };
        return JSON.serialize(config);
    }
}