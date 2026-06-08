import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getSessionById from '@salesforce/apex/FormWizardController.getSessionById';
import updateSessionAnswers from '@salesforce/apex/FormWizardController.updateSessionAnswers';
import submitFinal from '@salesforce/apex/FormWizardController.submitFinal';

export default class FormSessionEditor extends LightningElement {
    @api recordId;

    @track sessionData = null;
    @track editedJson = '';
    @track originalJson = '';
    @track isLoading = false;
    @track isValidJson = true;
    @track jsonError = '';
    @track submissionResult = null;

    connectedCallback() {
        this.loadSessionData();
    }

    async loadSessionData() {
        this.isLoading = true;
        this.submissionResult = null;
        try {
            this.sessionData = await getSessionById({ sessionId: this.recordId });
            this.originalJson = this.sessionData.Answers_JSON__c || '{}';
            this.editedJson = this.beautifyJson(this.originalJson);
            this.validateJson();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    beautifyJson(jsonString) {
        try {
            const parsed = JSON.parse(jsonString);
            return JSON.stringify(parsed, null, 2);
        } catch (e) {
            return jsonString;
        }
    }

    validateJson() {
        try {
            JSON.parse(this.editedJson);
            this.isValidJson = true;
            this.jsonError = '';
        } catch (e) {
            this.isValidJson = false;
            this.jsonError = e.message;
        }
    }

    handleJsonChange(event) {
        this.editedJson = event.target.value;
        this.validateJson();
    }

    async handleSaveJson() {
        if (!this.isValidJson) {
            this.showToast('Error', 'Cannot save invalid JSON', 'error');
            return;
        }

        this.isLoading = true;
        try {
            const minifiedJson = JSON.stringify(JSON.parse(this.editedJson));
            await updateSessionAnswers({
                sessionId: this.recordId,
                answersJson: minifiedJson
            });
            this.originalJson = minifiedJson;
            this.showToast('Success', 'JSON saved successfully', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleResubmit() {
        if (!this.isValidJson) {
            this.showToast('Error', 'Cannot submit invalid JSON', 'error');
            return;
        }

        this.isLoading = true;
        this.submissionResult = null;

        try {
            const answers = JSON.parse(this.editedJson);
            const stateJson = {
                primaryEmail: this.sessionData.Guest_Email__c,
                sessionToken: this.sessionData.Session_Token__c,
                sessionRecordId: this.sessionData.Id,
                formType: this.sessionData.Wizard_Type__c,
                currentStep: String(this.sessionData.Current_Step__c || 1),
                answers: JSON.stringify(answers),
                sessionName: this.sessionData.Name
            };

            const result = await submitFinal({ state: JSON.stringify(stateJson) });
            const parsedResult = JSON.parse(result);

            this.submissionResult = parsedResult;

            if (parsedResult.success) {
                this.showToast('Success', parsedResult.message, 'success');
                await this.loadSessionData();
            } else {
                this.showToast('Error', parsedResult.message, 'error');
            }
        } catch (error) {
            const errorMsg = this.getErrorMessage(error);
            this.showToast('Error', errorMsg, 'error');
            this.submissionResult = { success: false, message: errorMsg };
        } finally {
            this.isLoading = false;
        }
    }

    handleReset() {
        this.editedJson = this.beautifyJson(this.originalJson);
        this.validateJson();
        this.showToast('Info', 'JSON reset to original', 'info');
    }

    handleRefresh() {
        this.loadSessionData();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unexpected error occurred';
    }

    // Getters for template
    get sessionName() {
        return this.sessionData?.Name || '';
    }

    get sessionStatus() {
        return this.sessionData?.Status__c || '';
    }

    get guestEmail() {
        return this.sessionData?.Guest_Email__c || '';
    }

    get wizardType() {
        return this.sessionData?.Wizard_Type__c || '';
    }

    get currentStep() {
        return this.sessionData?.Current_Step__c || '';
    }

    get validationClass() {
        return this.isValidJson ? 'slds-text-color_success' : 'slds-text-color_error';
    }

    get validationMessage() {
        return this.isValidJson ? 'Valid JSON' : `Invalid JSON: ${this.jsonError}`;
    }

    get isSaveDisabled() {
        return !this.isValidJson || this.isLoading;
    }

    get isResubmitDisabled() {
        return !this.isValidJson || this.isLoading;
    }

    get hasSubmissionResult() {
        return this.submissionResult !== null;
    }

    get submissionSuccess() {
        return this.submissionResult?.success === true;
    }

    get submissionMessage() {
        return this.submissionResult?.message || '';
    }

    get submissionSessionName() {
        return this.submissionResult?.sessionName || '';
    }

    get hasSessionData() {
        return this.sessionData !== null;
    }

    get statusBadgeClass() {
        const status = this.sessionStatus;
        if (status === 'Submitted') return 'slds-badge slds-theme_success';
        if (status === 'In Progress') return 'slds-badge slds-theme_warning';
        if (status === 'Expired' || status === 'Abandoned') return 'slds-badge slds-theme_error';
        return 'slds-badge';
    }
}