import { LightningElement, track } from 'lwc';
import validateSession from '@salesforce/apex/FormWizardController.validateSession';
import abandonAndCreateNewSession from '@salesforce/apex/FormWizardController.abandonAndCreateNewSession';
import expireAndCreateNewSession from '@salesforce/apex/FormWizardController.expireAndCreateNewSession';
import { debugInfo, debugError, debugSuccess } from 'c/formUtils';

export default class EmailVerification extends LightningElement {
    @track email = '';
    @track authCode = '';
    @track showAuthCodeInput = false;

    @track emailError = '';
    @track authCodeError = '';

    @track isSendingCode = false;
    @track isVerifying = false;

    @track successMessage = '';
    @track errorMessage = '';

    // Session choice modal properties
    @track showSessionChoiceModal = false;
    @track existingSessionData = null;

    // -----------------------------
    // Input handlers
    // -----------------------------

    handleEmailChange(event) {
        this.email = event.detail.value;
        this.emailError = '';
        this.errorMessage = '';
        debugInfo('Email entered:', this.email);
    }

    handleAuthCodeChange(event) {
        this.authCode = event.detail.value;
        this.authCodeError = '';
        this.errorMessage = '';
        debugInfo('Authorization code entered:', this.authCode);
    }

    // -----------------------------
    // Send authorization code
    // -----------------------------

    async handleSendCode() {
        debugInfo('Send Code Button Clicked');

        // Basic email validation
        if (!this.email) {
            this.emailError = 'Please enter an email address';
            debugError('Validation Error: Email is required');
            return;
        }

        const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailPattern.test(this.email)) {
            this.emailError = 'Please enter a valid email address';
            debugError('Validation Error: Invalid email format');
            return;
        }

        this.isSendingCode = true;
        this.emailError = '';
        this.authCodeError = '';
        this.successMessage = '';
        this.errorMessage = '';

        try {
            debugInfo('Sending OTP to:', this.email);

            // new Apex signature: (email, otp, requestNewOtp)
            const result = await validateSession({
                email: this.email,
                otp: null,
                requestNewOtp: true
            });

            debugInfo('validateSession result (Send Code):', JSON.stringify(result));

            if (result && result.sent) {
                this.showAuthCodeInput = true;
                this.successMessage = `Authorization code sent to ${this.email}`;
                this.errorMessage = '';
                debugSuccess('OTP sent successfully to:', this.email);
            } else {
                const msg = result?.message || 'Failed to send verification code.';
                this.emailError = msg;
                this.errorMessage = msg;
                this.successMessage = '';
                debugError('Failed to send OTP:', msg);
            }
        } catch (error) {
            const msg =
                (error.body && error.body.message) ||
                error.message ||
                'Failed to send verification code. Please try again.';
            this.emailError = msg;
            this.errorMessage = msg;
            debugError('Error sending OTP', { error: msg });
        } finally {
            this.isSendingCode = false;
        }
    }

    // -----------------------------
    // Verify authorization code
    // -----------------------------

    async handleVerifyCode() {
        debugInfo('Verify Code Button Clicked');

        if (!this.authCode) {
            this.authCodeError = 'Please enter the authorization code';
            debugError('Validation Error: Authorization code is required');
            return;
        }

        this.isVerifying = true;
        this.authCodeError = '';
        this.errorMessage = '';
        this.successMessage = '';

        try {
            debugInfo('Verifying OTP:', this.authCode, 'for email:', this.email);

            const result = await validateSession({
                email: this.email,
                otp: this.authCode,
                requestNewOtp: false
            });

            debugInfo('validateSession result (Verify Code):', JSON.stringify(result));

            if (result && result.verified) {
                // Verification successful
                this.showAuthCodeInput = true;
                this.successMessage = 'Email verified successfully.';
                this.errorMessage = '';
                debugSuccess('OTP verified successfully for:', this.email);

                // Check if there's an existing session with "In Progress" status
                if (result.sessionData && result.sessionData.Status__c === 'In Progress') {
                    // Check if session is older than 30 days
                    const verificationSetOn = result.sessionData.Verification_Sent_On__c;
                    if (verificationSetOn) {
                        const sentDate = new Date(verificationSetOn);
                        const now = new Date();
                        const daysDiff = Math.floor((now - sentDate) / (1000 * 60 * 60 * 24));

                        if (daysDiff > 30) {
                            // Session is expired - create new session automatically
                            debugInfo('Session is older than 30 days, marking as expired');
                            this.handleExpiredSession(result.sessionData);
                            return;
                        }
                    }

                    // Session is valid and less than 30 days old - show choice modal
                    debugInfo('Found existing "In Progress" session, showing choice modal');
                    this.existingSessionData = result.sessionData;
                    this.showSessionChoiceModal = true;
                } else {
                    // No existing "In Progress" session or completed session - proceed normally
                    this.notifyParentVerified(result.sessionData, result.sessionToken);
                }
            } else {
                const msg = result?.message || 'Invalid verification code. Please try again.';
                this.authCodeError = msg;
                this.errorMessage = msg;
                this.successMessage = '';
                debugError('OTP verification failed:', msg);
            }
        } catch (error) {
            const msg =
                (error.body && error.body.message) ||
                error.message ||
                'Invalid verification code. Please try again.';
            this.authCodeError = msg;
            this.errorMessage = msg;
            debugError('Error verifying OTP', { error: msg });
        } finally {
            this.isVerifying = false;
        }
    }

    // -----------------------------
    // Resend code
    // -----------------------------

    async handleResendCode() {
        debugInfo('Resend Code Button Clicked');

        // Reuse the same flow as Send Code, but keep authCode blank
        this.authCode = '';
        this.authCodeError = '';
        this.successMessage = '';
        this.errorMessage = '';

        this.isSendingCode = true;

        try {
            debugInfo('Resending OTP to:', this.email);

            const result = await validateSession({
                email: this.email,
                otp: null,
                requestNewOtp: true
            });

            debugInfo('validateSession result (Resend Code):', JSON.stringify(result));

            if (result && result.sent) {
                this.showAuthCodeInput = true;
                this.successMessage = `A new authorization code has been sent to ${this.email}`;
                this.errorMessage = '';
                debugSuccess('OTP resent successfully to:', this.email);
            } else {
                const msg = result?.message || 'Failed to resend verification code. Please try again.';
                this.authCodeError = msg;
                this.errorMessage = msg;
                this.successMessage = '';
                debugError('Failed to resend OTP:', msg);
            }
        } catch (error) {
            const msg =
                (error.body && error.body.message) ||
                error.message ||
                'Failed to resend verification code. Please try again.';
            this.authCodeError = msg;
            this.errorMessage = msg;
            debugError('Error resending OTP', { error: msg });
        } finally {
            this.isSendingCode = false;
        }

        debugInfo('Authorization code input cleared, new code requested');
    }

    // -----------------------------
    // Cancel / reset
    // -----------------------------

    handleCancel() {
        debugInfo('Cancel Button Clicked');
        this.email = '';
        this.authCode = '';
        this.showAuthCodeInput = false;
        this.emailError = '';
        this.authCodeError = '';
        this.successMessage = '';
        this.errorMessage = '';
        debugInfo('Form reset to initial state');
    }

    // -----------------------------
    // Session Choice Modal Handlers
    // -----------------------------

    handleStartNew() {
        debugInfo('User chose to start a new application');
        this.showSessionChoiceModal = false;
        this.abandonExistingSession();
    }

    handleResume() {
        debugInfo('User chose to resume previous session');
        this.showSessionChoiceModal = false;
        this.notifyParentVerified(this.existingSessionData, this.existingSessionData.Session_Token__c);
    }

    async abandonExistingSession() {
        try {
            debugInfo('Abandoning existing session and creating new one');
            const newSession = await abandonAndCreateNewSession({
                email: this.email,
                oldSessionToken: this.existingSessionData.Session_Token__c,
                wizardType: 'Default',
                ipAddress: null
            });

            debugSuccess('New session created after abandoning old session');
            this.notifyParentVerified(newSession, newSession.Session_Token__c);
        } catch (error) {
            debugError('Error abandoning session', error);
            this.errorMessage = 'Failed to create new session. Please try again.';
        }
    }

    async handleExpiredSession(sessionData) {
        try {
            debugInfo('Marking session as expired and creating new one');
            const newSession = await expireAndCreateNewSession({
                email: this.email,
                oldSessionToken: sessionData.Session_Token__c,
                wizardType: 'Default',
                ipAddress: null
            });

            debugSuccess('New session created after expiring old session');
            this.notifyParentVerified(newSession, newSession.Session_Token__c);
        } catch (error) {
            debugError('Error expiring session', error);
            this.errorMessage = 'Failed to create new session. Please try again.';
        }
    }

    notifyParentVerified(sessionData, sessionToken) {
        debugInfo('Notifying parent of successful verification');
        this.dispatchEvent(
            new CustomEvent('emailverified', {
                detail: {
                    email: this.email,
                    sessionData: sessionData || null,
                    sessionToken: sessionToken || null
                },
                bubbles: true,
                composed: true
            })
        );
    }
}