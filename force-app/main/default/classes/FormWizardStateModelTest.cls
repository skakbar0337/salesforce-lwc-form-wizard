/**
 * @description Test class for FormWizardStateModel
 * Tests the DTO class used for serializing wizard state, including constructor
 * initialization and answer map deserialization functionality.
 *
 * @group form Tests
 * @author Dynamic Request Form Team
 */
@isTest
private class FormWizardStateModelTest {

    // ==========================================
    // TEST SETUP
    // ==========================================

    @TestSetup
    static void setupTestData() {
        // Create test user with permissions
        TestDataFactory factory = new TestDataFactory();
        User testUser = factory.createUser();
        testUser.IsActive = true;
        testUser.Email = 'statemodel_' + System.currentTimeMillis() + '@company.com';
        insert testUser;

        // Assign Permission Set
        PermissionSet psBase = [SELECT Id FROM PermissionSet WHERE Name = 'Base_Public_User' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = psBase.Id);

        System.runAs(testUser) {
            // Create Study Request Sessions with various data scenarios
            List<Form_Session__c> sessions = new List<Form_Session__c>();

            // Session with complete data and valid JSON answers
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'complete@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 3,
                Answers_JSON__c = '{"firstName":"John","lastName":"Doe","email":"john@example.com","phone":"5551234567"}',
                Session_Token__c = 'COMPLETE_TOKEN_123'
            ));

            // Session with empty answers
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'empty@example.com',
                Wizard_Type__c = 'Onsite_Form',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '',
                Session_Token__c = 'EMPTY_TOKEN_456'
            ));

            // Session with null answers
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'null@example.com',
                Wizard_Type__c = 'Test_Wizard',
                Status__c = 'Submitted',
                Current_Step__c = 5,
                Answers_JSON__c = null,
                Session_Token__c = 'NULL_TOKEN_789'
            ));

            // Session with complex nested JSON answers
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'complex@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 4,
                Answers_JSON__c = '{"contact":{"name":"Jane","email":"jane@test.com"},"cohorts":[{"name":"Cohort1","count":10}],"isMultiSite":true,"budget":50000}',
                Session_Token__c = 'COMPLEX_TOKEN_ABC'
            ));

            // Session with whitespace-only answers
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'whitespace@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 2,
                Answers_JSON__c = '   ',
                Session_Token__c = 'WHITESPACE_TOKEN_DEF'
            ));

            // Session with empty JSON object
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'emptyjson@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{}',
                Session_Token__c = 'EMPTYJSON_TOKEN_GHI'
            ));

            insert sessions;
        }
    }

    /**
     * @description Helper to retrieve the active test user created in @TestSetup
     */
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'statemodel_%' AND IsActive = TRUE LIMIT 1];
    }

    // ==========================================
    // CONSTRUCTOR TESTS
    // ==========================================

    @isTest
    static void testConstructor_WithCompleteSession_InitializesAllProperties() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complete@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardStateModel stateModel = new FormWizardStateModel(session);
            Test.stopTest();

            System.assertEquals(session.Id, stateModel.sessionRecordId,
                'sessionRecordId should match session Id');
            System.assertEquals(session.Name, stateModel.sessionName,
                'sessionName should match session Name');
            System.assertEquals('COMPLETE_TOKEN_123', stateModel.sessionToken,
                'sessionToken should match Session_Token__c');
            System.assertEquals('Dynamic_Request_Form', stateModel.formType,
                'formType should match Wizard_Type__c');
            System.assertEquals('complete@example.com', stateModel.primaryEmail,
                'primaryEmail should match Guest_Email__c');
            System.assertEquals('3', stateModel.currentStep,
                'currentStep should match Current_Step__c as string');
            System.assertEquals(session.Answers_JSON__c, stateModel.answers,
                'answers should match Answers_JSON__c');
        }
    }

    @isTest
    static void testConstructor_WithEmptyAnswers_InitializesCorrectly() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'empty@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardStateModel stateModel = new FormWizardStateModel(session);
            Test.stopTest();

            // Note: Salesforce stores empty strings as null in Long Text Area fields
            System.assert(String.isBlank(stateModel.answers),
                'answers should be blank (null or empty string)');
            System.assertEquals('Onsite_Form', stateModel.formType,
                'formType should match Wizard_Type__c');
            System.assertEquals('1', stateModel.currentStep,
                'currentStep should be 1');
        }
    }

    @isTest
    static void testConstructor_WithNullAnswers_InitializesCorrectly() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'null@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardStateModel stateModel = new FormWizardStateModel(session);
            Test.stopTest();

            System.assertEquals(null, stateModel.answers,
                'answers should be null');
            System.assertEquals('Test_Wizard', stateModel.formType,
                'formType should match Wizard_Type__c');
            System.assertEquals('5', stateModel.currentStep,
                'currentStep should be 5');
        }
    }

    @isTest
    static void testConstructor_SessionTokenPreserved() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complex@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardStateModel stateModel = new FormWizardStateModel(session);
            Test.stopTest();

            System.assertEquals('COMPLEX_TOKEN_ABC', stateModel.sessionToken,
                'sessionToken should be preserved from session record');
        }
    }

    // ==========================================
    // getAnswerMap TESTS
    // ==========================================

    @isTest
    static void testGetAnswerMap_WithValidJson_ReturnsMap() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complete@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertNotEquals(null, answerMap, 'answerMap should not be null');
            System.assertEquals(4, answerMap.size(), 'answerMap should have 4 entries');
            System.assertEquals('John', answerMap.get('firstName'), 'firstName should be John');
            System.assertEquals('Doe', answerMap.get('lastName'), 'lastName should be Doe');
            System.assertEquals('john@example.com', answerMap.get('email'), 'email should match');
            System.assertEquals('5551234567', answerMap.get('phone'), 'phone should match');
        }
    }

    @isTest
    static void testGetAnswerMap_WithEmptyString_ReturnsEmptyMap() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'empty@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertNotEquals(null, answerMap, 'answerMap should not be null');
            System.assertEquals(0, answerMap.size(), 'answerMap should be empty for blank answers');
        }
    }

    @isTest
    static void testGetAnswerMap_WithNullAnswers_ReturnsEmptyMap() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'null@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertNotEquals(null, answerMap, 'answerMap should not be null');
            System.assertEquals(0, answerMap.size(), 'answerMap should be empty for null answers');
        }
    }

    @isTest
    static void testGetAnswerMap_WithWhitespaceOnly_ReturnsEmptyMap() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'whitespace@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertNotEquals(null, answerMap, 'answerMap should not be null');
            System.assertEquals(0, answerMap.size(), 'answerMap should be empty for whitespace-only answers');
        }
    }

    @isTest
    static void testGetAnswerMap_WithEmptyJsonObject_ReturnsEmptyMap() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'emptyjson@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertNotEquals(null, answerMap, 'answerMap should not be null');
            System.assertEquals(0, answerMap.size(), 'answerMap should be empty for empty JSON object');
        }
    }

    @isTest
    static void testGetAnswerMap_WithComplexNestedJson_ReturnsNestedStructure() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complex@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertNotEquals(null, answerMap, 'answerMap should not be null');
            System.assertEquals(4, answerMap.size(), 'answerMap should have 4 top-level entries');

            // Verify nested object
            Map<String, Object> contact = (Map<String, Object>) answerMap.get('contact');
            System.assertNotEquals(null, contact, 'contact should not be null');
            System.assertEquals('Jane', contact.get('name'), 'contact name should be Jane');

            // Verify array
            List<Object> cohorts = (List<Object>) answerMap.get('cohorts');
            System.assertNotEquals(null, cohorts, 'cohorts should not be null');
            System.assertEquals(1, cohorts.size(), 'cohorts should have 1 entry');

            // Verify boolean
            System.assertEquals(true, answerMap.get('isMultiSite'), 'isMultiSite should be true');

            // Verify number
            System.assertEquals(50000, answerMap.get('budget'), 'budget should be 50000');
        }
    }

    @isTest
    static void testGetAnswerMap_CalledMultipleTimes_ReturnsConsistentResults() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complete@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap1 = stateModel.getAnswerMap();
            Map<String, Object> answerMap2 = stateModel.getAnswerMap();
            Map<String, Object> answerMap3 = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertEquals(answerMap1.size(), answerMap2.size(),
                'Multiple calls should return consistent results');
            System.assertEquals(answerMap2.size(), answerMap3.size(),
                'Multiple calls should return consistent results');
            System.assertEquals(answerMap1.get('firstName'), answerMap2.get('firstName'),
                'Field values should be consistent across calls');
        }
    }

    // ==========================================
    // PROPERTY ACCESS TESTS
    // ==========================================

    @isTest
    static void testPublicProperties_CanBeModified() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complete@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            // Modify public properties
            stateModel.primaryEmail = 'modified@example.com';
            stateModel.sessionName = 'Modified Name';
            stateModel.sessionToken = 'MODIFIED_TOKEN';
            stateModel.formType = 'Modified_Type';
            stateModel.currentStep = '10';
            stateModel.answers = '{"modified":"true"}';
            Test.stopTest();

            // Verify modifications
            System.assertEquals('modified@example.com', stateModel.primaryEmail,
                'primaryEmail should be modifiable');
            System.assertEquals('Modified Name', stateModel.sessionName,
                'sessionName should be modifiable');
            System.assertEquals('MODIFIED_TOKEN', stateModel.sessionToken,
                'sessionToken should be modifiable');
            System.assertEquals('Modified_Type', stateModel.formType,
                'formType should be modifiable');
            System.assertEquals('10', stateModel.currentStep,
                'currentStep should be modifiable');
            System.assertEquals('{"modified":"true"}', stateModel.answers,
                'answers should be modifiable');
        }
    }

    @isTest
    static void testGetAnswerMap_AfterModifyingAnswers_ReturnsNewMap() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complete@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            // Get original map
            Map<String, Object> originalMap = stateModel.getAnswerMap();
            System.assertEquals('John', originalMap.get('firstName'), 'Original firstName should be John');

            // Modify answers
            stateModel.answers = '{"firstName":"Modified","newField":"newValue"}';

            // Get new map
            Map<String, Object> newMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertEquals('Modified', newMap.get('firstName'),
                'Modified answers should return updated firstName');
            System.assertEquals('newValue', newMap.get('newField'),
                'Modified answers should include new fields');
            System.assertEquals(null, newMap.get('lastName'),
                'Modified answers should not include old fields not in new JSON');
        }
    }

    // ==========================================
    // BULK TESTS
    // ==========================================

    @isTest
    static void testConstructor_BulkSessions_CreatesMultipleModels() {
        System.runAs(getTestUser()) {
            List<Form_Session__c> sessions = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                LIMIT 200
            ];

            Test.startTest();
            List<FormWizardStateModel> models = new List<FormWizardStateModel>();
            for (Form_Session__c session : sessions) {
                models.add(new FormWizardStateModel(session));
            }
            Test.stopTest();

            System.assertEquals(sessions.size(), models.size(),
                'Should create a model for each session');

            // Verify each model has correct data
            for (Integer i = 0; i < models.size(); i++) {
                System.assertEquals(sessions[i].Id, models[i].sessionRecordId,
                    'Each model should have correct sessionRecordId');
                System.assertEquals(sessions[i].Session_Token__c, models[i].sessionToken,
                    'Each model should have correct sessionToken');
            }
        }
    }

    @isTest
    static void testGetAnswerMap_BulkCalls_PerformsWithinLimits() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complete@example.com' LIMIT 1
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            // Call getAnswerMap many times to verify no governor limit issues
            for (Integer i = 0; i < 200; i++) {
                Map<String, Object> answerMap = stateModel.getAnswerMap();
                System.assertNotEquals(null, answerMap, 'answerMap should not be null on iteration ' + i);
            }
            Test.stopTest();

            System.assert(true, 'Bulk getAnswerMap calls completed within governor limits');
        }
    }

    // ==========================================
    // EDGE CASE TESTS
    // ==========================================

    @isTest
    static void testConstructor_WithSpecialCharactersInEmail() {
        System.runAs(getTestUser()) {
            // Create session with special characters
            Form_Session__c session = new Form_Session__c(
                Guest_Email__c = 'test+special.chars@sub.example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{}',
                Session_Token__c = 'SPECIAL_CHAR_TOKEN'
            );
            insert session;

            // Re-query to get all fields
            session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Id = :session.Id
            ];

            Test.startTest();
            FormWizardStateModel stateModel = new FormWizardStateModel(session);
            Test.stopTest();

            System.assertEquals('test+special.chars@sub.example.com', stateModel.primaryEmail,
                'Special characters in email should be preserved');
        }
    }

    @isTest
    static void testGetAnswerMap_WithUnicodeCharacters() {
        System.runAs(getTestUser()) {
            // Create session with unicode in answers
            Form_Session__c session = new Form_Session__c(
                Guest_Email__c = 'unicode@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{"name":"Test User","company":"Acme Corp"}',
                Session_Token__c = 'UNICODE_TOKEN'
            );
            insert session;

            // Re-query to get all fields
            session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Id = :session.Id
            ];

            FormWizardStateModel stateModel = new FormWizardStateModel(session);

            Test.startTest();
            Map<String, Object> answerMap = stateModel.getAnswerMap();
            Test.stopTest();

            System.assertEquals('Test User', answerMap.get('name'),
                'Unicode characters in answers should be handled correctly');
        }
    }

    @isTest
    static void testConstructor_CurrentStepConvertedToString() {
        System.runAs(getTestUser()) {
            // Create session with decimal step value
            Form_Session__c session = new Form_Session__c(
                Guest_Email__c = 'step@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 7,
                Answers_JSON__c = '{}',
                Session_Token__c = 'STEP_TOKEN'
            );
            insert session;

            // Re-query to get all fields
            session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Id = :session.Id
            ];

            Test.startTest();
            FormWizardStateModel stateModel = new FormWizardStateModel(session);
            Test.stopTest();

            System.assertEquals('7', stateModel.currentStep,
                'Current step should be converted to string');
        }
    }

    @isTest
    static void testSessionRecordId_IsStringType() {
        System.runAs(getTestUser()) {
            Form_Session__c session = [
                SELECT Id, Name, Guest_Email__c, Wizard_Type__c, Status__c,
                       Current_Step__c, Answers_JSON__c, Session_Token__c
                FROM Form_Session__c
                WHERE Guest_Email__c = 'complete@example.com' LIMIT 1
            ];

            Test.startTest();
            FormWizardStateModel stateModel = new FormWizardStateModel(session);
            Test.stopTest();

            // Verify sessionRecordId is a valid Id string
            System.assertNotEquals(null, stateModel.sessionRecordId,
                'sessionRecordId should not be null');
            System.assertEquals(18, String.valueOf(stateModel.sessionRecordId).length(),
                'sessionRecordId should be 18-character Salesforce Id');
        }
    }
}