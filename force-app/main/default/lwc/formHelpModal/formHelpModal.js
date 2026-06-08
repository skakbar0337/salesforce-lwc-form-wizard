import { LightningElement, api, track } from 'lwc';
import sendHelpRequestEmail from '@salesforce/apex/FormWizardController.sendHelpRequestEmail';

export default class FormHelpModal extends LightningElement {
    @api isOpen = false;
    @api contactInfo = {};
    @api sessionId = '';
    @api sessionName = '';
    @api helpConfig = {};

    @track comments = '';
    @track isSubmitting = false;
    @track showSuccess = false;
    @track errorMessage = '';

    // Editable field values (initialized from contactInfo)
    @track editedFirstName = '';
    @track editedLastName = '';
    @track editedCompany = '';
    @track editedEmail = '';

    // Edit mode states
    @track isEditingName = false;
    @track isEditingCompany = false;
    @track isEditingEmail = false;

    // Track if values have been initialized
    _initialized = false;

    renderedCallback() {
        // Initialize editable values from contactInfo once
        if (!this._initialized && this.contactInfo) {
            this.editedFirstName = this.contactInfo.firstName || '';
            this.editedLastName = this.contactInfo.lastName || '';
            this.editedCompany = this.contactInfo.company || '';
            this.editedEmail = this.contactInfo.email || '';
            this._initialized = true;
        }
    }

    // Computed properties for display values
    get displayName() {
        const fullName = `${this.editedFirstName} ${this.editedLastName}`.trim();
        return fullName || 'Not provided';
    }

    get displayCompany() {
        return this.editedCompany || 'Not provided';
    }

    get displayEmail() {
        return this.editedEmail || 'Not provided';
    }

    get hasName() {
        return this.displayName !== 'Not provided';
    }

    get hasCompany() {
        return this.editedCompany && this.editedCompany.trim() !== '';
    }

    get hasEmail() {
        return this.editedEmail && this.editedEmail.trim() !== '';
    }

    // ==========================================
    // Configurable Properties (from helpConfig)
    // ==========================================

    // Modal title
    get modalTitle() {
        return this.helpConfig?.modalTitle || 'How Can We Help?';
    }

    // Field visibility getters
    get showNameField() {
        return this.helpConfig?.fields?.name?.show !== false;
    }

    get showCompanyField() {
        return this.helpConfig?.fields?.company?.show !== false;
    }

    get showEmailField() {
        return this.helpConfig?.fields?.email?.show !== false;
    }

    get showCommentsField() {
        return this.helpConfig?.fields?.comments?.show !== false;
    }

    // Field label getters
    get nameLabel() {
        return this.helpConfig?.fields?.name?.label || 'Name';
    }

    get firstNameLabel() {
        return this.helpConfig?.fields?.name?.firstNameLabel || 'First Name';
    }

    get lastNameLabel() {
        return this.helpConfig?.fields?.name?.lastNameLabel || 'Last Name';
    }

    get companyLabel() {
        return this.helpConfig?.fields?.company?.label || 'Company';
    }

    get emailLabel() {
        return this.helpConfig?.fields?.email?.label || 'Email';
    }

    get commentsLabel() {
        return this.helpConfig?.fields?.comments?.label || 'Comments';
    }

    get commentsPlaceholder() {
        return this.helpConfig?.fields?.comments?.placeholder || 'How can we help you?';
    }

    get commentsMaxLength() {
        return this.helpConfig?.fields?.comments?.maxLength || 2000;
    }

    // Submit button labels
    get submitButtonLabel() {
        return this.helpConfig?.submitButton?.label || 'Send Message';
    }

    get submitButtonLoadingLabel() {
        return this.helpConfig?.submitButton?.loadingLabel || 'Sending...';
    }

    // Success message getters
    get successTitle() {
        return this.helpConfig?.successMessage?.title || 'Thank you for reaching out!';
    }

    get successBody() {
        return this.helpConfig?.successMessage?.body || 'A member of our team will respond to your message within 1 business day.';
    }

    get successSubtext() {
        return this.helpConfig?.successMessage?.subtext || 'In the meantime, you can continue filling out your study request form.';
    }

    // Contact info section getters
    get showContactInfo() {
        return this.helpConfig?.contactInfo?.show !== false;
    }

    get contactSectionLabel() {
        return this.helpConfig?.contactInfo?.sectionLabel || 'Or Reach Us Directly';
    }

    get showAddressCard() {
        return this.helpConfig?.contactInfo?.address?.show !== false;
    }

    get addressLabel() {
        return this.helpConfig?.contactInfo?.address?.label || 'Address';
    }

    get addressValue() {
        return this.helpConfig?.contactInfo?.address?.value || '3030 Bunker Hill St, Suite 119, San Diego, CA 92109';
    }

    get showEmailCard() {
        return this.helpConfig?.contactInfo?.email?.show !== false;
    }

    get contactEmailLabel() {
        return this.helpConfig?.contactInfo?.email?.label || 'Email';
    }

    get contactEmailValue() {
        return this.helpConfig?.contactInfo?.email?.value || 'LearnMore@company.com';
    }

    get contactEmailHref() {
        return 'mailto:' + this.contactEmailValue;
    }

    get showPhoneCard() {
        return this.helpConfig?.contactInfo?.phone?.show !== false;
    }

    get phoneLabel() {
        return this.helpConfig?.contactInfo?.phone?.label || 'Phone';
    }

    get phoneValue() {
        return this.helpConfig?.contactInfo?.phone?.value || '(855) 836-4759';
    }

    get phoneHref() {
        const phone = this.phoneValue.replace(/[^0-9]/g, '');
        return 'tel:+1' + phone;
    }

    get showSocialLinks() {
        return this.helpConfig?.contactInfo?.socialLinks?.show !== false;
    }

    get showLinkedIn() {
        return this.helpConfig?.contactInfo?.socialLinks?.linkedin?.show !== false;
    }

    get linkedInUrl() {
        return this.helpConfig?.contactInfo?.socialLinks?.linkedin?.url || 'https://www.linkedin.com/company/your-company';
    }

    get linkedInLabel() {
        return this.helpConfig?.contactInfo?.socialLinks?.linkedin?.label || 'LinkedIn';
    }

    get showYouTube() {
        return this.helpConfig?.contactInfo?.socialLinks?.youtube?.show !== false;
    }

    get youTubeUrl() {
        return this.helpConfig?.contactInfo?.socialLinks?.youtube?.url || 'https://www.youtube.com/user/your-company';
    }

    get youTubeLabel() {
        return this.helpConfig?.contactInfo?.socialLinks?.youtube?.label || 'YouTube';
    }

    // Email config getters (for sending)
    get emailRecipients() {
        return this.helpConfig?.emailConfig?.recipients || [];
    }

    get emailSender() {
        return this.helpConfig?.emailConfig?.senderAddress || '';
    }

    // Event handlers
    handleBackdropClick(event) {
        // Only close if clicking directly on the backdrop, not its children
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleContentClick(event) {
        // Prevent clicks inside the modal from closing it
        event.stopPropagation();
    }

    handleClose() {
        // Reset state when closing
        this.comments = '';
        this.showSuccess = false;
        this.isSubmitting = false;

        // Reset edit states
        this.isEditingName = false;
        this.isEditingCompany = false;
        this.isEditingEmail = false;

        // Reset to allow re-initialization on next open
        this._initialized = false;

        // Dispatch close event to parent
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCommentsChange(event) {
        this.comments = event.target.value;
    }

    // Inline edit handlers for Name
    handleEditName() {
        this.isEditingName = true;
    }

    handleFirstNameChange(event) {
        this.editedFirstName = event.target.value;
    }

    handleLastNameChange(event) {
        this.editedLastName = event.target.value;
    }

    handleSaveName() {
        this.isEditingName = false;
    }

    handleCancelNameEdit() {
        // Revert to original values
        this.editedFirstName = this.contactInfo?.firstName || '';
        this.editedLastName = this.contactInfo?.lastName || '';
        this.isEditingName = false;
    }

    // Inline edit handlers for Company
    handleEditCompany() {
        this.isEditingCompany = true;
    }

    handleCompanyChange(event) {
        this.editedCompany = event.target.value;
    }

    handleSaveCompany() {
        this.isEditingCompany = false;
    }

    handleCancelCompanyEdit() {
        this.editedCompany = this.contactInfo?.company || '';
        this.isEditingCompany = false;
    }

    // Inline edit handlers for Email
    handleEditEmail() {
        this.isEditingEmail = true;
    }

    handleEmailChange(event) {
        this.editedEmail = event.target.value;
    }

    handleSaveEmail() {
        this.isEditingEmail = false;
    }

    handleCancelEmailEdit() {
        this.editedEmail = this.contactInfo?.email || '';
        this.isEditingEmail = false;
    }

    async handleSubmit() {
        if (this.isSubmitting) return;

        this.isSubmitting = true;
        this.errorMessage = ''; // Clear any previous error

        try {
            await sendHelpRequestEmail({
                firstName: this.editedFirstName || '',
                lastName: this.editedLastName || '',
                company: this.editedCompany || '',
                email: this.editedEmail || '',
                comments: this.comments || '',
                sessionId: this.sessionId || '',
                emailRecipients: JSON.stringify(this.emailRecipients),
                emailSender: this.emailSender
            });

            // Show success message
            this.showSuccess = true;
            this.isSubmitting = false;

        } catch (error) {
            console.error('Error sending help request:', error);
            this.isSubmitting = false;

            // Show error message in the modal
            this.errorMessage = error?.body?.message || 'Failed to send message. Please try again.';
        }
    }

    handleDismissError() {
        this.errorMessage = '';
    }

    get hasError() {
        return this.errorMessage && this.errorMessage.length > 0;
    }

    // Keyboard handling for accessibility
    connectedCallback() {
        this._handleKeyDown = this.handleKeyDown.bind(this);
        window.addEventListener('keydown', this._handleKeyDown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._handleKeyDown);
    }

    handleKeyDown(event) {
        if (!this.isOpen) return;

        if (event.key === 'Escape') {
            this.handleClose();
        }
    }
}