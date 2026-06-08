/**
 * @description Service class for sending emails with comprehensive logging.
 * Provides a centralized way to send emails with automatic logging of success and failures.
 */
public class FormEmailService {

    private static final String CLASS_NAME = 'FormEmailService';
    private static final String DEFAULT_NONPROD_EMAIL = 'revops@company.com';
    private static final List<String> DEFAULT_NONPROD_EMAILS = new List<String>{
        'user1@company.com',
        'revops@company.com',
        'admin@company.com',
        'user2@company.com',
        'user3@company.com'
    };

    // Addresses that bypass the non-prod redirect and receive emails as normal in sandbox.
    // Add team member / QA tester emails here so they can validate email flows without
    // affecting unrelated recipients.
    private static final Set<String> SANDBOX_ALLOWED_EMAILS = new Set<String>{
        'user1@company.com',
        'tester1@gmail.com',
        'user11@company.com',
        'tester2@gmail.com',
        'revops@company.com',
        'integration@company.com',
        'admin@company.com',
        'user2@company.com',
        'user3@company.com',
        'user4@company.com',
        'user5@company.com',
        'user6@company.com',
        'user7@company.com',
        'user8@company.com',
        'user9@company.com',
        'tester3@gmail.com',
        'user10@company.com',
        'revops2@company.com',
        'tester4@gmail.com',
        'tester5@gmail.com',
        'tester6@gmail.com',
        'tester7@gmail.com',
        'tester8@gmail.com'
    };

    // When true, emails will be sent to actual recipients even in non-prod
    @TestVisible
    private static Boolean bypassNonProdRedirect = false;

    // Override for testing - allows tests to simulate production or sandbox environment
    @TestVisible
    private static Boolean isProductionOrgOverride = null;

    /**
     * @description Result class to encapsulate email send results
     */
    public class EmailResult {
        public Boolean success { get; private set; }
        public String errorMessage { get; private set; }
        public List<String> recipients { get; private set; }

        public EmailResult(Boolean success, String errorMessage, List<String> recipients) {
            this.success = success;
            this.errorMessage = errorMessage;
            this.recipients = recipients;
        }
    }

    /**
     * @description Check if the current org is a production org
     * @return True if the org is production, false otherwise
     */
    public static Boolean isProductionOrg() {
        // Allow tests to override the production check
        if (isProductionOrgOverride != null) {
            return isProductionOrgOverride;
        }
        return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox == false;
    }

    /**
     * @description Enable sending emails to actual recipients in non-production environments.
     * Use this method when you need to test email delivery to real addresses in a sandbox.
     * WARNING: Use with caution to avoid sending test emails to real users.
     */
    public static void enableActualRecipients() {
        bypassNonProdRedirect = true;
        ApexLog.logMessage(
            ApexLog.LogLevel.WARN,
            'Non-prod email redirect bypassed - emails will be sent to actual recipients',
            CLASS_NAME,
            'enableActualRecipients',
            'Bypass enabled by user'
        );
    }

    /**
     * @description Disable bypass and restore default behavior of redirecting
     * non-production emails to the default address.
     */
    public static void disableActualRecipients() {
        bypassNonProdRedirect = false;
    }

    /**
     * @description Check if emails are being redirected for non-prod
     * @return True if emails are being redirected, false if going to actual recipients
     */
    public static Boolean isRedirectingEmails() {
        return !isProductionOrg() && !bypassNonProdRedirect;
    }

    /**
     * @description Get the default non-prod email address
     * @return The default email address used for non-prod environments
     */
    public static String getNonProdEmailAddress() {
        return DEFAULT_NONPROD_EMAIL;
    }

    /**
     * @description Get all default non-prod email addresses
     * @return The list of email addresses used for non-prod environments
     */
    public static List<String> getNonProdEmailAddresses() {
        return DEFAULT_NONPROD_EMAILS;
    }

    /**
     * @description Redirects email addresses to the default non-prod email if applicable.
     * In non-production environments (unless bypassed), all addresses are replaced
     * with the default non-prod email address.
     * @param addresses Original list of email addresses
     * @return Redirected or original addresses based on environment
     */
    private static List<String> redirectAddressesIfNeeded(List<String> addresses) {
        if (addresses == null || addresses.isEmpty()) {
            return addresses;
        }

        if (isProductionOrg() || bypassNonProdRedirect) {
            return addresses;
        }

        // Non-prod: pass through allowed addresses, redirect everything else to default
        Set<String> result = new Set<String>();
        for (String addr : addresses) {
            if (String.isNotBlank(addr) && SANDBOX_ALLOWED_EMAILS.contains(addr.toLowerCase())) {
                result.add(addr);
            }
        }
        if (result.isEmpty()) {
            result.add(DEFAULT_NONPROD_EMAIL);
        }
        return new List<String>(result);
    }

    /**
     * @description Redirects a single email address based on environment.
     * In non-production environments, addresses in SANDBOX_ALLOWED_EMAILS pass through;
     * all others are redirected to the default non-prod address.
     * @param address Original email address
     * @return Redirected or original address based on environment
     */
    private static String redirectAddressIfNeeded(String address) {
        if (String.isBlank(address)) {
            return address;
        }

        if (isProductionOrg() || bypassNonProdRedirect) {
            return address;
        }

        if (SANDBOX_ALLOWED_EMAILS.contains(address.toLowerCase())) {
            return address;
        }

        return DEFAULT_NONPROD_EMAIL;
    }

    /**
     * @description Redirects a single email address to the full list of non-prod emails if applicable.
     * Used by methods that need to send to multiple non-prod stakeholders.
     * @param address Original email address
     * @return Redirected or original addresses as a list based on environment
     */
    private static List<String> redirectAddressToMultipleIfNeeded(String address) {
        if (String.isBlank(address)) {
            return new List<String>{ address };
        }

        if (isProductionOrg() || bypassNonProdRedirect) {
            return new List<String>{ address };
        }

        return DEFAULT_NONPROD_EMAILS;
    }

    /**
     * @description Send a single email to one recipient
     * @param toAddress The recipient email address
     * @param subject The email subject
     * @param body The email body (plain text)
     * @param isHtml Whether the body is HTML formatted
     * @return EmailResult containing success status and any error message
     */
    public static EmailResult sendEmail(String toAddress, String subject, String body, Boolean isHtml) {
        return sendEmail(new List<String>{ toAddress }, null, null, subject, body, isHtml);
    }

    /**
     * @description Send an email to multiple recipients with CC and BCC support
     * @param toAddresses List of primary recipient email addresses
     * @param ccAddresses List of CC email addresses (can be null)
     * @param bccAddresses List of BCC email addresses (can be null)
     * @param subject The email subject
     * @param body The email body
     * @param isHtml Whether the body is HTML formatted
     * @return EmailResult containing success status and any error message
     */
    public static EmailResult sendEmail(List<String> toAddresses, List<String> ccAddresses,
                                        List<String> bccAddresses, String subject,
                                        String body, Boolean isHtml) {
        String methodName = 'sendEmail';

        // Validate required parameters
        if (toAddresses == null || toAddresses.isEmpty()) {
            String errorMsg = 'To addresses cannot be null or empty';
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                errorMsg,
                CLASS_NAME,
                methodName,
                'Email validation failed: no recipients provided'
            );
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, new List<String>());
        }

        if (String.isBlank(subject)) {
            String errorMsg = 'Email subject cannot be blank';
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                errorMsg,
                CLASS_NAME,
                methodName,
                'Email validation failed: no subject provided'
            );
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, toAddresses);
        }

        try {
            // Store original addresses for logging
            List<String> originalToAddresses = toAddresses;
            List<String> originalCcAddresses = ccAddresses;
            List<String> originalBccAddresses = bccAddresses;

            // Redirect addresses for non-prod environments
            List<String> effectiveToAddresses = redirectAddressesIfNeeded(toAddresses);
            List<String> effectiveCcAddresses = redirectAddressesIfNeeded(ccAddresses);
            List<String> effectiveBccAddresses = redirectAddressesIfNeeded(bccAddresses);

            // Log if redirecting
            if (isRedirectingEmails()) {
                String originalRecipients = buildRecipientInfo(originalToAddresses, originalCcAddresses, originalBccAddresses);
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    'Non-prod email redirect active',
                    CLASS_NAME,
                    methodName,
                    'Original recipients: ' + originalRecipients + ' | Redirected to: ' + DEFAULT_NONPROD_EMAIL
                );
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(effectiveToAddresses);

            if (effectiveCcAddresses != null && !effectiveCcAddresses.isEmpty()) {
                email.setCcAddresses(effectiveCcAddresses);
            }

            if (effectiveBccAddresses != null && !effectiveBccAddresses.isEmpty()) {
                email.setBccAddresses(effectiveBccAddresses);
            }

            email.setSubject(subject);

            if (isHtml) {
                email.setHtmlBody(body);
            } else {
                email.setPlainTextBody(body);
            }

            email.setSaveAsActivity(false);

            // Send the email
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            if (results[0].isSuccess()) {
                // Log successful email send
                String recipientInfo = buildRecipientInfo(toAddresses, ccAddresses, bccAddresses);
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    'Email sent successfully',
                    CLASS_NAME,
                    methodName,
                    'Subject: ' + subject + ' | Recipients: ' + recipientInfo
                );
                ApexLog.flushLogs();
                return new EmailResult(true, null, toAddresses);
            } else {
                // Handle failed email send
                return handleSingleEmailFailure(results[0], subject, toAddresses, methodName);
            }
        } catch (Exception ex) {
            ApexLog.logException(ex, CLASS_NAME, methodName, 'Subject: ' + subject + ' | To: ' + String.join(toAddresses, ', '));
            return new EmailResult(false, ex.getMessage(), toAddresses);
        }
    }

    /**
     * @description Send an email with an Org-Wide Email Address override.
     * Identical to the 6-param overload but additionally sets the OWA and saveAsActivity flag.
     * @param toAddresses List of primary recipient email addresses
     * @param ccAddresses List of CC email addresses (can be null)
     * @param bccAddresses List of BCC email addresses (can be null)
     * @param subject The email subject
     * @param body The email body
     * @param isHtml Whether the body is HTML formatted
     * @param orgWideEmailAddressId OrgWideEmailAddress Id to send from (can be null)
     * @param saveAsActivity Whether to save the email as an activity (false recommended for system emails)
     * @return EmailResult containing success status and any error message
     */
    public static EmailResult sendEmail(List<String> toAddresses, List<String> ccAddresses,
                                        List<String> bccAddresses, String subject,
                                        String body, Boolean isHtml,
                                        Id orgWideEmailAddressId, Boolean saveAsActivity) {
        String methodName = 'sendEmail';

        if (toAddresses == null || toAddresses.isEmpty()) {
            String errorMsg = 'To addresses cannot be null or empty';
            ApexLog.logMessage(ApexLog.LogLevel.ERROR, errorMsg, CLASS_NAME, methodName,
                'Email validation failed: no recipients provided');
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, new List<String>());
        }

        if (String.isBlank(subject)) {
            String errorMsg = 'Email subject cannot be blank';
            ApexLog.logMessage(ApexLog.LogLevel.ERROR, errorMsg, CLASS_NAME, methodName,
                'Email validation failed: no subject provided');
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, toAddresses);
        }

        try {
            List<String> effectiveToAddresses  = redirectAddressesIfNeeded(toAddresses);
            List<String> effectiveCcAddresses  = redirectAddressesIfNeeded(ccAddresses);
            List<String> effectiveBccAddresses = redirectAddressesIfNeeded(bccAddresses);

            if (isRedirectingEmails()) {
                String originalRecipients = buildRecipientInfo(toAddresses, ccAddresses, bccAddresses);
                ApexLog.logMessage(ApexLog.LogLevel.INFO, 'Non-prod email redirect active',
                    CLASS_NAME, methodName,
                    'Original recipients: ' + originalRecipients + ' | Redirected to: ' + DEFAULT_NONPROD_EMAIL);
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(effectiveToAddresses);

            if (effectiveCcAddresses != null && !effectiveCcAddresses.isEmpty()) {
                email.setCcAddresses(effectiveCcAddresses);
            }
            if (effectiveBccAddresses != null && !effectiveBccAddresses.isEmpty()) {
                email.setBccAddresses(effectiveBccAddresses);
            }

            email.setSubject(subject);

            if (isHtml) {
                email.setHtmlBody(body);
            } else {
                email.setPlainTextBody(body);
            }

            if (orgWideEmailAddressId != null) {
                email.setOrgWideEmailAddressId(orgWideEmailAddressId);
            }

            email.setSaveAsActivity(saveAsActivity == true);

            List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ email });

            if (results[0].isSuccess()) {
                String recipientInfo = buildRecipientInfo(toAddresses, ccAddresses, bccAddresses);
                ApexLog.logMessage(ApexLog.LogLevel.INFO, 'Email sent successfully',
                    CLASS_NAME, methodName,
                    'Subject: ' + subject + ' | Recipients: ' + recipientInfo);
                ApexLog.flushLogs();
                return new EmailResult(true, null, toAddresses);
            } else {
                return handleSingleEmailFailure(results[0], subject, toAddresses, methodName);
            }
        } catch (Exception ex) {
            ApexLog.logException(ex, CLASS_NAME, methodName,
                'Subject: ' + subject + ' | To: ' + String.join(toAddresses, ', '));
            return new EmailResult(false, ex.getMessage(), toAddresses);
        }
    }

    /**
     * @description Send multiple emails in a batch
     * @param emails List of SingleEmailMessage objects to send
     * @return List of EmailResult for each email
     */
    public static List<EmailResult> sendBulkEmails(List<Messaging.SingleEmailMessage> emails) {
        String methodName = 'sendBulkEmails';
        List<EmailResult> results = new List<EmailResult>();

        if (emails == null || emails.isEmpty()) {
            String errorMsg = 'Email list cannot be null or empty';
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                errorMsg,
                CLASS_NAME,
                methodName,
                'Bulk email validation failed: no emails provided'
            );
            ApexLog.flushLogs();
            return results;
        }

        try {
            // Redirect addresses for non-prod environments
            if (isRedirectingEmails()) {
                for (Messaging.SingleEmailMessage email : emails) {
                    List<String> originalTo = email.getToAddresses();
                    String originalRecipients = originalTo != null ? String.join(originalTo, ', ') : '';

                    email.setToAddresses(new List<String>{ DEFAULT_NONPROD_EMAIL });
                    email.setCcAddresses(null);
                    email.setBccAddresses(null);

                    ApexLog.logMessage(
                        ApexLog.LogLevel.INFO,
                        'Non-prod bulk email redirect active',
                        CLASS_NAME,
                        methodName,
                        'Original recipients: ' + originalRecipients + ' | Redirected to: ' + DEFAULT_NONPROD_EMAIL
                    );
                }
            }

            List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emails, false);

            for (Integer i = 0; i < sendResults.size(); i++) {
                Messaging.SendEmailResult sendResult = sendResults[i];
                List<String> toAddresses = emails[i].getToAddresses();

                if (sendResult.isSuccess()) {
                    ApexLog.logMessage(
                        ApexLog.LogLevel.INFO,
                        'Bulk email sent successfully',
                        CLASS_NAME,
                        methodName,
                        'Email ' + (i + 1) + ' of ' + emails.size() + ' | To: ' + String.join(toAddresses, ', ')
                    );
                    results.add(new EmailResult(true, null, toAddresses));
                } else {
                    handleBulkEmailFailure(sendResult, toAddresses, i, emails.size(), methodName);
                    String errorMsg = getErrorMessage(sendResult.getErrors());
                    results.add(new EmailResult(false, errorMsg, toAddresses));
                }
            }

            ApexLog.flushLogs();
        } catch (Exception ex) {
            ApexLog.logException(ex, CLASS_NAME, methodName, 'Failed to send bulk emails');
            // Return error results for all emails
            for (Messaging.SingleEmailMessage email : emails) {
                results.add(new EmailResult(false, ex.getMessage(), email.getToAddresses()));
            }
        }

        return results;
    }

    /**
     * @description Send an email using an email template
     * @param toAddress Recipient email address
     * @param templateDeveloperName Developer name of the email template
     * @param targetObjectId The ID of the record to use for merge fields (e.g., Contact or Lead ID)
     * @param whatId The ID of the related record (e.g., Case, Opportunity)
     * @return EmailResult containing success status and any error message
     */
    public static EmailResult sendTemplateEmail(String toAddress, String templateDeveloperName,
                                                 Id targetObjectId, Id whatId) {
        String methodName = 'sendTemplateEmail';

        if (String.isBlank(toAddress)) {
            String errorMsg = 'To address cannot be blank';
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                errorMsg,
                CLASS_NAME,
                methodName,
                'Template email validation failed: no recipient provided'
            );
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, new List<String>());
        }

        if (String.isBlank(templateDeveloperName)) {
            String errorMsg = 'Template developer name cannot be blank';
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                errorMsg,
                CLASS_NAME,
                methodName,
                'Template email validation failed: no template specified'
            );
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, new List<String>{ toAddress });
        }

        try {
            // Look up the email template by developer name
            List<EmailTemplate> templates = [
                SELECT Id, DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName = :templateDeveloperName
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                String errorMsg = 'Email template not found: ' + templateDeveloperName;
                ApexLog.logMessage(
                    ApexLog.LogLevel.ERROR,
                    errorMsg,
                    CLASS_NAME,
                    methodName,
                    'Template lookup failed'
                );
                ApexLog.flushLogs();
                return new EmailResult(false, errorMsg, new List<String>{ toAddress });
            }

            Id templateId = templates[0].Id;

            // Redirect address for non-prod environments
            String effectiveToAddress = redirectAddressIfNeeded(toAddress);

            // Log if redirecting
            if (isRedirectingEmails()) {
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    'Non-prod template email redirect active',
                    CLASS_NAME,
                    methodName,
                    'Original recipient: ' + toAddress + ' | Redirected to: ' + DEFAULT_NONPROD_EMAIL
                );
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ effectiveToAddress });
            email.setTemplateId(templateId);
            email.setTargetObjectId(targetObjectId);

            if (whatId != null) {
                email.setWhatId(whatId);
            }

            email.setSaveAsActivity(false);

            List<Messaging.SendEmailResult> results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            if (results[0].isSuccess()) {
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    'Template email sent successfully',
                    CLASS_NAME,
                    methodName,
                    'Template: ' + templateDeveloperName + ' | To: ' + toAddress
                );
                ApexLog.flushLogs();
                return new EmailResult(true, null, new List<String>{ toAddress });
            } else {
                // Handle failed template email send
                return handleTemplateEmailFailure(results[0], templateDeveloperName, toAddress, methodName);
            }
        } catch (Exception ex) {
            ApexLog.logException(ex, CLASS_NAME, methodName,
                'Template: ' + templateDeveloperName + ' | To: ' + toAddress);
            return new EmailResult(false, ex.getMessage(), new List<String>{ toAddress });
        }
    }

    /**
     * @description Send an email using an email template with Org-Wide Email Address support.
     *              Redirects to multiple non-prod stakeholders in sandbox environments.
     *              Use this method when sending from a guest/portal user context where OWA is required.
     * @param toAddress Recipient email address
     * @param templateDeveloperName Developer name of the email template
     * @param targetObjectId The ID of the record to use for merge fields (Contact or Lead ID)
     * @param whatId The ID of the related record (e.g., Form_Session__c)
     * @param orgWideEmailAddressId Id of the OrgWideEmailAddress to send from (can be null)
     * @return EmailResult containing success status and any error message
     */
    public static EmailResult sendTemplateEmailWithOWA(String toAddress, String templateDeveloperName,
                                                 Id targetObjectId, Id whatId, Id orgWideEmailAddressId) {
        String methodName = 'sendTemplateEmailWithOWA';

        if (String.isBlank(toAddress)) {
            String errorMsg = 'To address cannot be blank';
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                errorMsg,
                CLASS_NAME,
                methodName,
                'Template email validation failed: no recipient provided'
            );
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, new List<String>());
        }

        if (String.isBlank(templateDeveloperName)) {
            String errorMsg = 'Template developer name cannot be blank';
            ApexLog.logMessage(
                ApexLog.LogLevel.ERROR,
                errorMsg,
                CLASS_NAME,
                methodName,
                'Template email validation failed: no template specified'
            );
            ApexLog.flushLogs();
            return new EmailResult(false, errorMsg, new List<String>{ toAddress });
        }

        try {
            // Look up the email template by developer name
            List<EmailTemplate> templates = [
                SELECT Id, DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName = :templateDeveloperName
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                String errorMsg = 'Email template not found: ' + templateDeveloperName;
                ApexLog.logMessage(
                    ApexLog.LogLevel.ERROR,
                    errorMsg,
                    CLASS_NAME,
                    methodName,
                    'Template lookup failed'
                );
                ApexLog.flushLogs();
                return new EmailResult(false, errorMsg, new List<String>{ toAddress });
            }

            Id templateId = templates[0].Id;

            // Redirect address for non-prod environments (to multiple stakeholders)
            List<String> effectiveToAddresses = redirectAddressToMultipleIfNeeded(toAddress);

            // Log if redirecting
            if (isRedirectingEmails()) {
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    'Non-prod template email redirect active',
                    CLASS_NAME,
                    methodName,
                    'Original recipient: ' + toAddress + ' | Redirected to: ' + String.join(DEFAULT_NONPROD_EMAILS, ', ')
                );
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(effectiveToAddresses);
            email.setTemplateId(templateId);
            email.setTargetObjectId(targetObjectId);

            if (whatId != null) {
                email.setWhatId(whatId);
            }

            if (orgWideEmailAddressId != null) {
                email.setOrgWideEmailAddressId(orgWideEmailAddressId);
            }

            email.setSaveAsActivity(false);

            List<Messaging.SendEmailResult> results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            if (results[0].isSuccess()) {
                ApexLog.logMessage(
                    ApexLog.LogLevel.INFO,
                    'Template email sent successfully',
                    CLASS_NAME,
                    methodName,
                    'Template: ' + templateDeveloperName + ' | To: ' + toAddress
                );
                ApexLog.flushLogs();
                return new EmailResult(true, null, new List<String>{ toAddress });
            } else {
                // Handle failed template email send
                return handleTemplateEmailFailure(results[0], templateDeveloperName, toAddress, methodName);
            }
        } catch (Exception ex) {
            ApexLog.logException(ex, CLASS_NAME, methodName,
                'Template: ' + templateDeveloperName + ' | To: ' + toAddress);
            return new EmailResult(false, ex.getMessage(), new List<String>{ toAddress });
        }
    }

    /**
     * @description Handle a failed single email send by logging and returning error result
     * @param sendResult The failed send result
     * @param subject The email subject
     * @param toAddresses The recipient addresses
     * @param methodName The calling method name for logging
     * @return EmailResult with failure details
     */
    @TestVisible
    private static EmailResult handleSingleEmailFailure(
        Messaging.SendEmailResult sendResult,
        String subject,
        List<String> toAddresses,
        String methodName
    ) {
        String errorMsg = getErrorMessage(sendResult.getErrors());
        ApexLog.logMessage(
            ApexLog.LogLevel.ERROR,
            'Email send failed: ' + errorMsg,
            CLASS_NAME,
            methodName,
            'Subject: ' + subject + ' | To: ' + String.join(toAddresses, ', ')
        );
        ApexLog.flushLogs();
        return new EmailResult(false, errorMsg, toAddresses);
    }

    /**
     * @description Handle a failed template email send by logging and returning error result
     * @param sendResult The failed send result
     * @param templateName The template developer name
     * @param toAddress The recipient address
     * @param methodName The calling method name for logging
     * @return EmailResult with failure details
     */
    @TestVisible
    private static EmailResult handleTemplateEmailFailure(
        Messaging.SendEmailResult sendResult,
        String templateName,
        String toAddress,
        String methodName
    ) {
        String errorMsg = getErrorMessage(sendResult.getErrors());
        ApexLog.logMessage(
            ApexLog.LogLevel.ERROR,
            'Template email send failed: ' + errorMsg,
            CLASS_NAME,
            methodName,
            'Template: ' + templateName + ' | To: ' + toAddress
        );
        ApexLog.flushLogs();
        return new EmailResult(false, errorMsg, new List<String>{ toAddress });
    }

    /**
     * @description Handle a failed bulk email send by logging
     * @param sendResult The failed send result
     * @param toAddresses The recipient addresses
     * @param emailIndex The index of the email in the bulk send
     * @param totalEmails The total number of emails being sent
     * @param methodName The calling method name for logging
     */
    @TestVisible
    private static void handleBulkEmailFailure(
        Messaging.SendEmailResult sendResult,
        List<String> toAddresses,
        Integer emailIndex,
        Integer totalEmails,
        String methodName
    ) {
        String errorMsg = getErrorMessage(sendResult.getErrors());
        ApexLog.logMessage(
            ApexLog.LogLevel.ERROR,
            'Bulk email send failed: ' + errorMsg,
            CLASS_NAME,
            methodName,
            'Email ' + (emailIndex + 1) + ' of ' + totalEmails + ' | To: ' + String.join(toAddresses, ', ')
        );
    }

    /**
     * @description Build a string representation of all recipients
     */
    private static String buildRecipientInfo(List<String> toAddresses, List<String> ccAddresses,
                                             List<String> bccAddresses) {
        List<String> parts = new List<String>();

        if (toAddresses != null && !toAddresses.isEmpty()) {
            parts.add('To: ' + String.join(toAddresses, ', '));
        }

        if (ccAddresses != null && !ccAddresses.isEmpty()) {
            parts.add('CC: ' + String.join(ccAddresses, ', '));
        }

        if (bccAddresses != null && !bccAddresses.isEmpty()) {
            parts.add('BCC: ' + String.join(bccAddresses, ', '));
        }

        return String.join(parts, ' | ');
    }

    /**
     * @description Extract error messages from SendEmailError list
     */
    private static String getErrorMessage(List<Messaging.SendEmailError> errors) {
        if (errors == null || errors.isEmpty()) {
            return 'Unknown error';
        }

        List<String> errorMessages = new List<String>();
        for (Messaging.SendEmailError error : errors) {
            errorMessages.add(error.getMessage());
        }

        return String.join(errorMessages, '; ');
    }
}