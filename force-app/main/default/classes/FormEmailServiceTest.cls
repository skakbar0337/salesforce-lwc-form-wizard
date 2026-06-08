@IsTest
private class FormEmailServiceTest {

    @IsTest
    static void testSendEmailSuccess() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendEmail(
            'test@example.com',
            'Test Subject',
            'Test body content',
            false
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.recipients, 'Recipients should not be null');
    }

    @IsTest
    static void testSendEmailWithHtml() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendEmail(
            'test@example.com',
            'Test Subject',
            '<html><body>Test HTML content</body></html>',
            true
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testSendEmailWithMultipleRecipients() {
        List<String> toAddresses = new List<String>{ 'test1@example.com', 'test2@example.com' };
        List<String> ccAddresses = new List<String>{ 'cc@example.com' };
        List<String> bccAddresses = new List<String>{ 'bcc@example.com' };

        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendEmail(
            toAddresses,
            ccAddresses,
            bccAddresses,
            'Test Subject',
            'Test body',
            false
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testSendEmailWithNullToAddresses() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendEmail(
            null,
            null,
            null,
            'Test Subject',
            'Test body',
            false
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with null to addresses');
        System.assertEquals('To addresses cannot be null or empty', result.errorMessage);
    }

    @IsTest
    static void testSendEmailWithBlankSubject() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendEmail(
            new List<String>{ 'test@example.com' },
            null,
            null,
            '',
            'Test body',
            false
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with blank subject');
        System.assertEquals('Email subject cannot be blank', result.errorMessage);
    }

    @IsTest
    static void testSendBulkEmailsSuccess() {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        Messaging.SingleEmailMessage email1 = new Messaging.SingleEmailMessage();
        email1.setToAddresses(new List<String>{ 'test1@example.com' });
        email1.setSubject('Test Subject 1');
        email1.setPlainTextBody('Test body 1');
        emails.add(email1);

        Messaging.SingleEmailMessage email2 = new Messaging.SingleEmailMessage();
        email2.setToAddresses(new List<String>{ 'test2@example.com' });
        email2.setSubject('Test Subject 2');
        email2.setPlainTextBody('Test body 2');
        emails.add(email2);

        Test.startTest();
        List<FormEmailService.EmailResult> results = FormEmailService.sendBulkEmails(emails);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(2, results.size(), 'Should return 2 results');
    }

    @IsTest
    static void testSendBulkEmailsWithNullList() {
        Test.startTest();
        List<FormEmailService.EmailResult> results = FormEmailService.sendBulkEmails(null);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Should return empty list');
    }

    @IsTest
    static void testSendTemplateEmailWithBlankToAddress() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmail(
            '',
            'TestTemplate',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with blank to address');
        System.assertEquals('To address cannot be blank', result.errorMessage);
    }

    @IsTest
    static void testSendTemplateEmailWithBlankTemplateName() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmail(
            'test@example.com',
            '',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with blank template name');
        System.assertEquals('Template developer name cannot be blank', result.errorMessage);
    }

    @IsTest
    static void testSendTemplateEmailWithNonExistentTemplate() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmail(
            'test@example.com',
            'NonExistentTemplate_xyz123',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with non-existent template');
        System.assert(result.errorMessage.contains('Email template not found'),
            'Error message should indicate template not found');
    }

    @IsTest
    static void testEmailResultConstructor() {
        List<String> recipients = new List<String>{ 'test@example.com' };

        Test.startTest();
        FormEmailService.EmailResult result = new FormEmailService.EmailResult(true, null, recipients);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Success should be true');
        System.assertEquals(null, result.errorMessage, 'Error message should be null');
        System.assertEquals(recipients, result.recipients, 'Recipients should match');
    }

    @IsTest
    static void testIsProductionOrg() {
        Test.startTest();
        Boolean isProd = FormEmailService.isProductionOrg();
        Test.stopTest();

        System.assertNotEquals(null, isProd, 'Should return a boolean value');
    }

    @IsTest
    static void testGetNonProdEmailAddress() {
        Test.startTest();
        String nonProdEmail = FormEmailService.getNonProdEmailAddress();
        Test.stopTest();

        System.assertEquals('revops@company.com', nonProdEmail, 'Should return the default non-prod email');
    }

    @IsTest
    static void testGetNonProdEmailAddresses() {
        Test.startTest();
        List<String> nonProdEmails = FormEmailService.getNonProdEmailAddresses();
        Test.stopTest();

        System.assertEquals(4, nonProdEmails.size(), 'Should return 4 non-prod emails');
        System.assert(nonProdEmails.contains('revops@company.com'), 'Should contain revops email');
        System.assert(nonProdEmails.contains('admin@company.com'), 'Should contain admin email');
        System.assert(nonProdEmails.contains('user2@company.com'), 'Should contain user2 email');
        System.assert(nonProdEmails.contains('user3@company.com'), 'Should contain user3 email');
    }

    @IsTest
    static void testEnableAndDisableActualRecipients() {
        Test.startTest();

        FormEmailService.enableActualRecipients();
        Boolean isRedirectingAfterEnable = FormEmailService.isRedirectingEmails();

        FormEmailService.disableActualRecipients();
        Boolean isRedirectingAfterDisable = FormEmailService.isRedirectingEmails();

        Test.stopTest();

        System.assertEquals(false, isRedirectingAfterEnable, 'Should not redirect after enabling actual recipients');

        Boolean isProd = FormEmailService.isProductionOrg();
        if (isProd) {
            System.assertEquals(false, isRedirectingAfterDisable, 'Production should not redirect');
        } else {
            System.assertEquals(true, isRedirectingAfterDisable, 'Sandbox should redirect after disabling bypass');
        }
    }

    @IsTest
    static void testSendEmailWithRedirect() {
        Test.startTest();

        FormEmailService.disableActualRecipients();

        FormEmailService.EmailResult result = FormEmailService.sendEmail(
            'customer@example.com',
            'Test Subject',
            'Test body content',
            false
        );

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testSendBulkEmailsWithRedirect() {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        Messaging.SingleEmailMessage email1 = new Messaging.SingleEmailMessage();
        email1.setToAddresses(new List<String>{ 'test1@example.com' });
        email1.setCcAddresses(new List<String>{ 'cc@example.com' });
        email1.setBccAddresses(new List<String>{ 'bcc@example.com' });
        email1.setSubject('Test Subject 1');
        email1.setPlainTextBody('Test body 1');
        emails.add(email1);

        Test.startTest();

        FormEmailService.disableActualRecipients();
        List<FormEmailService.EmailResult> results = FormEmailService.sendBulkEmails(emails);

        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return 1 result');
    }

    @IsTest
    static void testSendTemplateEmailWithWhatId() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'WhatId',
            Email = 'whatid@example.com'
        );
        insert testContact;

        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        List<EmailTemplate> templates = [SELECT DeveloperName FROM EmailTemplate LIMIT 1];

        if (templates.isEmpty()) {
            return;
        }

        Test.startTest();

        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmail(
            'whatid@example.com',
            templates[0].DeveloperName,
            testContact.Id,
            testOpp.Id
        );

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testBuildRecipientInfoWithAllRecipients() {
        Test.startTest();

        FormEmailService.enableActualRecipients();

        List<String> toAddresses = new List<String>{ 'to1@example.com', 'to2@example.com' };
        List<String> ccAddresses = new List<String>{ 'cc1@example.com' };
        List<String> bccAddresses = new List<String>{ 'bcc1@example.com' };

        FormEmailService.EmailResult result = FormEmailService.sendEmail(
            toAddresses,
            ccAddresses,
            bccAddresses,
            'Test All Recipients',
            'Testing buildRecipientInfo coverage',
            false
        );

        FormEmailService.disableActualRecipients();

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testIsProductionOrgOverride() {
        Test.startTest();

        // Test overriding to production
        FormEmailService.isProductionOrgOverride = true;
        Boolean isProdOverride = FormEmailService.isProductionOrg();
        System.assertEquals(true, isProdOverride, 'Should return true when overridden to production');

        // Test overriding to sandbox
        FormEmailService.isProductionOrgOverride = false;
        Boolean isSandboxOverride = FormEmailService.isProductionOrg();
        System.assertEquals(false, isSandboxOverride, 'Should return false when overridden to sandbox');

        // Test resetting to actual value
        FormEmailService.isProductionOrgOverride = null;
        Boolean isActualValue = FormEmailService.isProductionOrg();
        System.assertNotEquals(null, isActualValue, 'Should return actual value when override is null');

        Test.stopTest();
    }

    @IsTest
    static void testIsRedirectingEmailsInProduction() {
        Test.startTest();

        // Simulate production environment
        FormEmailService.isProductionOrgOverride = true;
        FormEmailService.disableActualRecipients();

        Boolean isRedirecting = FormEmailService.isRedirectingEmails();

        FormEmailService.isProductionOrgOverride = null;

        Test.stopTest();

        System.assertEquals(false, isRedirecting, 'Production should not redirect emails');
    }

    @IsTest
    static void testIsRedirectingEmailsInSandbox() {
        Test.startTest();

        // Simulate sandbox environment
        FormEmailService.isProductionOrgOverride = false;
        FormEmailService.disableActualRecipients();

        Boolean isRedirecting = FormEmailService.isRedirectingEmails();

        FormEmailService.isProductionOrgOverride = null;

        Test.stopTest();

        System.assertEquals(true, isRedirecting, 'Sandbox should redirect emails when not bypassed');
    }

    @IsTest
    static void testIsRedirectingEmailsInSandboxWithBypass() {
        Test.startTest();

        // Simulate sandbox environment with bypass enabled
        FormEmailService.isProductionOrgOverride = false;
        FormEmailService.enableActualRecipients();

        Boolean isRedirecting = FormEmailService.isRedirectingEmails();

        FormEmailService.disableActualRecipients();
        FormEmailService.isProductionOrgOverride = null;

        Test.stopTest();

        System.assertEquals(false, isRedirecting, 'Sandbox should not redirect when bypass is enabled');
    }

    @IsTest
    static void testHandleSingleEmailFailure() {
        Test.startTest();

        // Create a mock SendEmailResult with errors
        Messaging.SendEmailResult mockResult = createMockFailedEmailResult();

        List<String> toAddresses = new List<String>{ 'test@example.com' };
        String subject = 'Test Subject';
        String methodName = 'testMethod';

        FormEmailService.EmailResult result = FormEmailService.handleSingleEmailFailure(
            mockResult,
            subject,
            toAddresses,
            methodName
        );

        Test.stopTest();

        System.assertEquals(false, result.success, 'Result should indicate failure');
        System.assertNotEquals(null, result.errorMessage, 'Error message should not be null');
        System.assertEquals(toAddresses, result.recipients, 'Recipients should match input');
    }

    @IsTest
    static void testHandleTemplateEmailFailure() {
        Test.startTest();

        // Create a mock SendEmailResult with errors
        Messaging.SendEmailResult mockResult = createMockFailedEmailResult();

        String toAddress = 'test@example.com';
        String templateName = 'TestTemplate';
        String methodName = 'testMethod';

        FormEmailService.EmailResult result = FormEmailService.handleTemplateEmailFailure(
            mockResult,
            templateName,
            toAddress,
            methodName
        );

        Test.stopTest();

        System.assertEquals(false, result.success, 'Result should indicate failure');
        System.assertNotEquals(null, result.errorMessage, 'Error message should not be null');
        System.assertEquals(1, result.recipients.size(), 'Should have one recipient');
        System.assertEquals(toAddress, result.recipients[0], 'Recipient should match input');
    }

    @IsTest
    static void testHandleBulkEmailFailure() {
        Test.startTest();

        // Create a mock SendEmailResult with errors
        Messaging.SendEmailResult mockResult = createMockFailedEmailResult();

        List<String> toAddresses = new List<String>{ 'test1@example.com', 'test2@example.com' };
        Integer emailIndex = 0;
        Integer totalEmails = 5;
        String methodName = 'testMethod';

        // This method doesn't return anything, but we can verify it doesn't throw exceptions
        FormEmailService.handleBulkEmailFailure(
            mockResult,
            toAddresses,
            emailIndex,
            totalEmails,
            methodName
        );

        Test.stopTest();

        // If we got here without an exception, the test passes
        System.assert(true, 'handleBulkEmailFailure should execute without errors');
    }

    // ==================== Tests for new sendTemplateEmailWithOWA method ====================

    @IsTest
    static void testSendTemplateEmailWithOWABlankToAddress() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmailWithOWA(
            '',
            'TestTemplate',
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with blank to address');
        System.assertEquals('To address cannot be blank', result.errorMessage);
    }

    @IsTest
    static void testSendTemplateEmailWithOWABlankTemplateName() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmailWithOWA(
            'test@example.com',
            '',
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with blank template name');
        System.assertEquals('Template developer name cannot be blank', result.errorMessage);
    }

    @IsTest
    static void testSendTemplateEmailWithOWANonExistentTemplate() {
        Test.startTest();
        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmailWithOWA(
            'test@example.com',
            'NonExistentTemplate_xyz123',
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with non-existent template');
        System.assert(result.errorMessage.contains('Email template not found'),
            'Error message should indicate template not found');
    }

    @IsTest
    static void testSendTemplateEmailWithOWAAndWhatId() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'OWA',
            Email = 'owa@example.com'
        );
        insert testContact;

        Opportunity testOpp = new Opportunity(
            Name = 'Test OWA Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        List<EmailTemplate> templates = [SELECT DeveloperName FROM EmailTemplate LIMIT 1];

        if (templates.isEmpty()) {
            return;
        }

        Test.startTest();

        FormEmailService.EmailResult result = FormEmailService.sendTemplateEmailWithOWA(
            'owa@example.com',
            templates[0].DeveloperName,
            testContact.Id,
            testOpp.Id,
            null
        );

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    /**
     * Helper method to create a mock failed email result
     * Since we can't directly instantiate SendEmailResult, we'll trigger an actual failure
     */
    private static Messaging.SendEmailResult createMockFailedEmailResult() {
        // Create an email that will fail (invalid email address format)
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ 'invalid-email-format' });
        email.setSubject('Test');
        email.setPlainTextBody('Test');

        List<Messaging.SendEmailResult> results = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ email },
            false // Don't throw exception on failure
        );

        return results[0];
    }
}