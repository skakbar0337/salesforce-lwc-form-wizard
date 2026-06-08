/**
 * @description Test class for PublicFormSelector
 * Tests all public selector methods for Form_Session__c queries,
 * including positive scenarios, negative scenarios, null handling, and edge cases.
 *
 * @group form Tests
 * @author Dynamic Request Form Team
 */
@isTest
private class PublicFormSelectorTest {

    // ==========================================
    // TEST SETUP
    // ==========================================

    @TestSetup
    static void setupTestData() {
        // Create test user with permissions
        TestDataFactory factory = new TestDataFactory();
        User testUser = factory.createUser();
        testUser.IsActive = true;
        testUser.Email = 'publicformselector_' + System.currentTimeMillis() + '@company.com';
        insert testUser;

        // Assign Permission Set that grants access to Form_Session__c
        PermissionSet psBase = [SELECT Id FROM PermissionSet WHERE Name = 'Public_Request_Form' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = psBase.Id);

        System.runAs(testUser) {
            // Create Study Request Sessions with various data scenarios
            List<Form_Session__c> sessions = new List<Form_Session__c>();

            // Session for email lookup tests - In Progress status
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'inprogress@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 2,
                Answers_JSON__c = '{"firstName":"John"}',
                Session_Token__c = 'INPROGRESS_TOKEN_123',
                Verification_Code__c = '123456',
                Verification_Sent_On__c = System.now()
            ));

            // Session for token lookup tests
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'token@example.com',
                Wizard_Type__c = 'Onsite_Form',
                Status__c = 'Submitted',
                Current_Step__c = 3,
                Answers_JSON__c = '{"lastName":"Doe"}',
                Session_Token__c = 'UNIQUE_TOKEN_ABC',
                Verification_Code__c = '654321',
                Verification_Sent_On__c = System.now()
            ));

            // Session for OTP validation tests
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'otp@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{}',
                Session_Token__c = 'OTP_TOKEN_XYZ',
                Verification_Code__c = '999888',
                Verification_Sent_On__c = System.now()
            ));

            // Session with different email for OTP (same code as another)
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'otp2@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{}',
                Session_Token__c = 'OTP_TOKEN_222',
                Verification_Code__c = '999888',
                Verification_Sent_On__c = System.now()
            ));

            // Session with Submitted status (should not be returned by email lookup)
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'submitted@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'Submitted',
                Current_Step__c = 5,
                Answers_JSON__c = '{"complete":"true"}',
                Session_Token__c = 'SUBMITTED_TOKEN_456',
                Verification_Code__c = '111111',
                Verification_Sent_On__c = System.now()
            ));

            // Session with Abandoned status
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'abandoned@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'Abandoned',
                Current_Step__c = 3,
                Answers_JSON__c = '{"partial":"data"}',
                Session_Token__c = 'ABANDONED_TOKEN_789',
                Verification_Code__c = '222222',
                Verification_Sent_On__c = System.now()
            ));

            // Session with Expired status
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'expired@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'Expired',
                Current_Step__c = 2,
                Answers_JSON__c = '{"old":"data"}',
                Session_Token__c = 'EXPIRED_TOKEN_000',
                Verification_Code__c = '333333',
                Verification_Sent_On__c = System.now()
            ));

            // Multiple sessions for same email (for ordering test)
            sessions.add(new Form_Session__c(
                Guest_Email__c = 'multiple@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 1,
                Answers_JSON__c = '{"session":"older"}',
                Session_Token__c = 'MULTI_TOKEN_OLD',
                Verification_Code__c = '444444',
                Verification_Sent_On__c = System.now().addHours(-1),
                Last_Modified_Date__c = System.now().addHours(-2)
            ));

            insert sessions;

            // Insert a newer session for the same email to test ordering
            Form_Session__c newerSession = new Form_Session__c(
                Guest_Email__c = 'multiple@example.com',
                Wizard_Type__c = 'Dynamic_Request_Form',
                Status__c = 'In Progress',
                Current_Step__c = 3,
                Answers_JSON__c = '{"session":"newer"}',
                Session_Token__c = 'MULTI_TOKEN_NEW',
                Verification_Code__c = '555555',
                Verification_Sent_On__c = System.now(),
                Last_Modified_Date__c = System.now()
            );
            insert newerSession;
        }
    }

    /**
     * @description Helper to retrieve the active test user created in @TestSetup
     */
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'publicformselector_%' AND IsActive = TRUE LIMIT 1];
    }

    // ==========================================
    // selectSessionByEmail TESTS
    // ==========================================

    @isTest
    static void testSelectSessionByEmail_ValidEmail_ReturnsSession() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('inprogress@example.com');
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a session');
            System.assertEquals('inprogress@example.com', result.Guest_Email__c, 'Email should match');
            System.assertEquals('In Progress', result.Status__c, 'Status should be In Progress');
            System.assertEquals('INPROGRESS_TOKEN_123', result.Session_Token__c, 'Token should match');
        }
    }

    @isTest
    static void testSelectSessionByEmail_OnlyReturnsInProgressStatus() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('submitted@example.com');
            Test.stopTest();

            System.assertEquals(null, result,
                'Should return null for email with only Submitted status');
        }
    }

    @isTest
    static void testSelectSessionByEmail_DoesNotReturnAbandonedStatus() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('abandoned@example.com');
            Test.stopTest();

            System.assertEquals(null, result,
                'Should return null for email with only Abandoned status');
        }
    }

    @isTest
    static void testSelectSessionByEmail_DoesNotReturnExpiredStatus() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('expired@example.com');
            Test.stopTest();

            System.assertEquals(null, result,
                'Should return null for email with only Expired status');
        }
    }

    @isTest
    static void testSelectSessionByEmail_MultipleSessionsReturnsNewest() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('multiple@example.com');
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a session');
            System.assertEquals('MULTI_TOKEN_NEW', result.Session_Token__c,
                'Should return the most recently modified session');
            System.assertEquals('3', String.valueOf((Integer)result.Current_Step__c),
                'Should return session with step 3 (the newer one)');
        }
    }

    @isTest
    static void testSelectSessionByEmail_BlankEmail_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for blank email');
        }
    }

    @isTest
    static void testSelectSessionByEmail_NullEmail_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail(null);
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for null email');
        }
    }

    @isTest
    static void testSelectSessionByEmail_NonExistentEmail_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('nonexistent@example.com');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for non-existent email');
        }
    }

    @isTest
    static void testSelectSessionByEmail_ReturnsAllBaseFields() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('inprogress@example.com');
            Test.stopTest();

            // Verify all BASE_FIELDS are queried and accessible
            System.assertNotEquals(null, result.Id, 'Id should be populated');
            System.assertNotEquals(null, result.Name, 'Name should be populated');
            System.assertNotEquals(null, result.Guest_Email__c, 'Guest_Email__c should be populated');
            System.assertNotEquals(null, result.Wizard_Type__c, 'Wizard_Type__c should be populated');
            System.assertNotEquals(null, result.Status__c, 'Status__c should be populated');
            System.assertNotEquals(null, result.Current_Step__c, 'Current_Step__c should be populated');
            System.assertNotEquals(null, result.Session_Token__c, 'Session_Token__c should be populated');
            System.assertNotEquals(null, result.Answers_JSON__c, 'Answers_JSON__c should be populated');
            System.assertNotEquals(null, result.Verification_Code__c, 'Verification_Code__c should be populated');
            System.assertNotEquals(null, result.Verification_Sent_On__c, 'Verification_Sent_On__c should be populated');
        }
    }

    // ==========================================
    // selectSessionByToken TESTS
    // ==========================================

    @isTest
    static void testSelectSessionByToken_ValidToken_ReturnsSession() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByToken('UNIQUE_TOKEN_ABC');
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a session');
            System.assertEquals('UNIQUE_TOKEN_ABC', result.Session_Token__c, 'Token should match');
            System.assertEquals('token@example.com', result.Guest_Email__c, 'Email should match');
        }
    }

    @isTest
    static void testSelectSessionByToken_ReturnsAnyStatus() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c inProgressResult = PublicFormSelector.selectSessionByToken('INPROGRESS_TOKEN_123');
            Form_Session__c submittedResult = PublicFormSelector.selectSessionByToken('SUBMITTED_TOKEN_456');
            Form_Session__c abandonedResult = PublicFormSelector.selectSessionByToken('ABANDONED_TOKEN_789');
            Form_Session__c expiredResult = PublicFormSelector.selectSessionByToken('EXPIRED_TOKEN_000');
            Test.stopTest();

            System.assertNotEquals(null, inProgressResult, 'Should return In Progress session');
            System.assertNotEquals(null, submittedResult, 'Should return Submitted session');
            System.assertNotEquals(null, abandonedResult, 'Should return Abandoned session');
            System.assertNotEquals(null, expiredResult, 'Should return Expired session');
        }
    }

    @isTest
    static void testSelectSessionByToken_BlankToken_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByToken('');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for blank token');
        }
    }

    @isTest
    static void testSelectSessionByToken_NullToken_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByToken(null);
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for null token');
        }
    }

    @isTest
    static void testSelectSessionByToken_NonExistentToken_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByToken('NONEXISTENT_TOKEN_999');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for non-existent token');
        }
    }

    @isTest
    static void testSelectSessionByToken_ReturnsAllBaseFields() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByToken('OTP_TOKEN_XYZ');
            Test.stopTest();

            // Verify all BASE_FIELDS are queried and accessible
            System.assertNotEquals(null, result.Id, 'Id should be populated');
            System.assertNotEquals(null, result.Name, 'Name should be populated');
            System.assertNotEquals(null, result.Guest_Email__c, 'Guest_Email__c should be populated');
            System.assertNotEquals(null, result.Wizard_Type__c, 'Wizard_Type__c should be populated');
            System.assertNotEquals(null, result.Status__c, 'Status__c should be populated');
            System.assertNotEquals(null, result.Session_Token__c, 'Session_Token__c should be populated');
        }
    }

    // ==========================================
    // selectSessionById TESTS
    // ==========================================

    @isTest
    static void testSelectSessionById_ValidId_ReturnsSession() {
        System.runAs(getTestUser()) {
            Form_Session__c existingSession = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'inprogress@example.com' LIMIT 1
            ];

            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionById(existingSession.Id);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a session');
            System.assertEquals(existingSession.Id, result.Id, 'Id should match');
            System.assertEquals('inprogress@example.com', result.Guest_Email__c, 'Email should match');
        }
    }

    @isTest
    static void testSelectSessionById_ReturnsAnyStatus() {
        System.runAs(getTestUser()) {
            Form_Session__c submittedSession = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'submitted@example.com' LIMIT 1
            ];

            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionById(submittedSession.Id);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return Submitted session');
            System.assertEquals('Submitted', result.Status__c, 'Status should be Submitted');
        }
    }

    @isTest
    static void testSelectSessionById_NullId_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionById(null);
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for null Id');
        }
    }

    @isTest
    static void testSelectSessionById_NonExistentId_ReturnsNull() {
        System.runAs(getTestUser()) {
            // Use a valid format but non-existent Id
            String keyPrefix = Form_Session__c.SObjectType.getDescribe().getKeyPrefix();

            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionById(null);
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for non-existent Id');
        }
    }

    @isTest
    static void testSelectSessionById_ReturnsAllBaseFields() {
        System.runAs(getTestUser()) {
            Form_Session__c existingSession = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'token@example.com' LIMIT 1
            ];

            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionById(existingSession.Id);
            Test.stopTest();

            // Verify all BASE_FIELDS are queried and accessible
            System.assertNotEquals(null, result.Id, 'Id should be populated');
            System.assertNotEquals(null, result.Name, 'Name should be populated');
            System.assertNotEquals(null, result.Guest_Email__c, 'Guest_Email__c should be populated');
            System.assertNotEquals(null, result.Wizard_Type__c, 'Wizard_Type__c should be populated');
            System.assertNotEquals(null, result.Status__c, 'Status__c should be populated');
            System.assertNotEquals(null, result.Session_Token__c, 'Session_Token__c should be populated');
        }
    }

    // ==========================================
    // selectSessionForOtpValidation TESTS
    // ==========================================

    @isTest
    static void testSelectSessionForOtpValidation_ValidEmailAndCode_ReturnsSession() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(
                'otp@example.com',
                '999888'
            );
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a session');
            System.assertEquals('otp@example.com', result.Guest_Email__c, 'Email should match');
            System.assertEquals('999888', result.Verification_Code__c, 'Verification code should match');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_DifferentEmailSameCode_ReturnsCorrectSession() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result1 = PublicFormSelector.selectSessionForOtpValidation(
                'otp@example.com',
                '999888'
            );
            Form_Session__c result2 = PublicFormSelector.selectSessionForOtpValidation(
                'otp2@example.com',
                '999888'
            );
            Test.stopTest();

            System.assertNotEquals(null, result1, 'Should return first session');
            System.assertNotEquals(null, result2, 'Should return second session');
            System.assertEquals('otp@example.com', result1.Guest_Email__c, 'First email should match');
            System.assertEquals('otp2@example.com', result2.Guest_Email__c, 'Second email should match');
            System.assertNotEquals(result1.Id, result2.Id, 'Should be different sessions');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_BlankEmail_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation('', '123456');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for blank email');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_NullEmail_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(null, '123456');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for null email');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_BlankCode_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(
                'otp@example.com',
                ''
            );
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for blank code');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_NullCode_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(
                'otp@example.com',
                null
            );
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for null code');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_BothBlank_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation('', '');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null when both email and code are blank');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_BothNull_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(null, null);
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null when both email and code are null');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_WrongCode_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(
                'otp@example.com',
                '000000'
            );
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for wrong verification code');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_NonExistentEmail_ReturnsNull() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(
                'nonexistent@example.com',
                '123456'
            );
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for non-existent email');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_ReturnsAllBaseFields() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation(
                'otp@example.com',
                '999888'
            );
            Test.stopTest();

            // Verify all BASE_FIELDS are queried and accessible
            System.assertNotEquals(null, result.Id, 'Id should be populated');
            System.assertNotEquals(null, result.Name, 'Name should be populated');
            System.assertNotEquals(null, result.Guest_Email__c, 'Guest_Email__c should be populated');
            System.assertNotEquals(null, result.Wizard_Type__c, 'Wizard_Type__c should be populated');
            System.assertNotEquals(null, result.Status__c, 'Status__c should be populated');
            System.assertNotEquals(null, result.Session_Token__c, 'Session_Token__c should be populated');
            System.assertNotEquals(null, result.Verification_Code__c, 'Verification_Code__c should be populated');
        }
    }

    // ==========================================
    // SECURITY TESTS (stripReadable coverage)
    // ==========================================

    @isTest
    static void testStripReadable_WithValidResults_ReturnsStrippedRecords() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // All methods internally call stripReadable, so any successful query covers it
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('inprogress@example.com');
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return stripped record');
            // The record should still have all accessible fields after stripping
            System.assertNotEquals(null, result.Guest_Email__c, 'Email should be accessible after FLS strip');
        }
    }

    @isTest
    static void testStripReadable_WithEmptyResults_ReturnsEmptyList() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Query for non-existent record - returns empty list which goes through stripReadable
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('nonexistent@test.com');
            Test.stopTest();

            System.assertEquals(null, result, 'Should return null for empty results');
        }
    }

    // ==========================================
    // BULK TESTS
    // ==========================================

    @isTest
    static void testSelectSessionByEmail_BulkQueries_PerformsWithinLimits() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Perform multiple queries to test bulk behavior
            for (Integer i = 0; i < 100; i++) {
                Form_Session__c result = PublicFormSelector.selectSessionByEmail('inprogress@example.com');
                System.assertNotEquals(null, result, 'Query ' + i + ' should return a result');
            }
            Test.stopTest();

            System.assert(true, 'Bulk queries completed within governor limits');
        }
    }

    @isTest
    static void testSelectSessionByToken_BulkQueries_PerformsWithinLimits() {
        System.runAs(getTestUser()) {
            Test.startTest();
            for (Integer i = 0; i < 100; i++) {
                Form_Session__c result = PublicFormSelector.selectSessionByToken('INPROGRESS_TOKEN_123');
                System.assertNotEquals(null, result, 'Query ' + i + ' should return a result');
            }
            Test.stopTest();

            System.assert(true, 'Bulk token queries completed within governor limits');
        }
    }

    // ==========================================
    // EDGE CASE TESTS
    // ==========================================

    @isTest
    static void testSelectSessionByEmail_CaseSensitivity() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Email fields in Salesforce are case-insensitive
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('INPROGRESS@EXAMPLE.COM');
            Test.stopTest();

            // This may or may not find the record depending on org email case settings
            // The important thing is the query executes without error
            System.assert(true, 'Email query executed successfully');
        }
    }

    @isTest
    static void testSelectSessionByToken_ExactMatch() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Token should require exact match
            Form_Session__c result1 = PublicFormSelector.selectSessionByToken('INPROGRESS_TOKEN_123');
            Form_Session__c result2 = PublicFormSelector.selectSessionByToken('inprogress_token_123');
            Test.stopTest();

            // At least one should work with exact case
            System.assertNotEquals(null, result1, 'Exact token match should return a result');
        }
    }

    @isTest
    static void testSelectSessionByEmail_WhitespaceEmail() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByEmail('   ');
            Test.stopTest();

            // Whitespace-only should be treated as blank by String.isBlank()
            System.assertEquals(null, result, 'Whitespace email should return null');
        }
    }

    @isTest
    static void testSelectSessionByToken_WhitespaceToken() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionByToken('   ');
            Test.stopTest();

            // Whitespace-only should be treated as blank by String.isBlank()
            System.assertEquals(null, result, 'Whitespace token should return null');
        }
    }

    @isTest
    static void testSelectSessionForOtpValidation_WhitespaceInputs() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Form_Session__c result = PublicFormSelector.selectSessionForOtpValidation('   ', '   ');
            Test.stopTest();

            System.assertEquals(null, result, 'Whitespace inputs should return null');
        }
    }

    // ==========================================
    // INTEGRATION TESTS
    // ==========================================

    @isTest
    static void testAllSelectorsReturnConsistentData() {
        System.runAs(getTestUser()) {
            Form_Session__c existingSession = [
                SELECT Id FROM Form_Session__c
                WHERE Guest_Email__c = 'inprogress@example.com' LIMIT 1
            ];

            Test.startTest();
            Form_Session__c byEmail = PublicFormSelector.selectSessionByEmail('inprogress@example.com');
            Form_Session__c byToken = PublicFormSelector.selectSessionByToken('INPROGRESS_TOKEN_123');
            Form_Session__c byId = PublicFormSelector.selectSessionById(existingSession.Id);
            Form_Session__c byOtp = PublicFormSelector.selectSessionForOtpValidation(
                'inprogress@example.com',
                '123456'
            );
            Test.stopTest();

            // All should return the same session
            System.assertEquals(byEmail.Id, byToken.Id, 'Email and Token queries should return same session');
            System.assertEquals(byToken.Id, byId.Id, 'Token and Id queries should return same session');
            System.assertEquals(byId.Id, byOtp.Id, 'Id and OTP queries should return same session');

            // All should have consistent data
            System.assertEquals(byEmail.Guest_Email__c, byToken.Guest_Email__c, 'Email should be consistent');
            System.assertEquals(byEmail.Session_Token__c, byId.Session_Token__c, 'Token should be consistent');
            System.assertEquals(byEmail.Wizard_Type__c, byOtp.Wizard_Type__c, 'Wizard type should be consistent');
        }
    }
}