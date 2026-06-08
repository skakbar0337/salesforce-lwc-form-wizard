import { LightningElement, api, track } from 'lwc';

export default class SessionChoiceModal extends LightningElement {
    @api sessionInfo;
    @track isProcessing = false;

    get formattedLastModified() {
        if (this.sessionInfo && this.sessionInfo.LastModifiedDate) {
            const date = new Date(this.sessionInfo.LastModifiedDate);
            return date.toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'long',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
            });
        }
        return 'Unknown';
    }

    handleStartNew() {
        this.isProcessing = true;
        this.dispatchEvent(new CustomEvent('startnew', {
            bubbles: true,
            composed: true
        }));
    }

    handleResume() {
        this.isProcessing = true;
        this.dispatchEvent(new CustomEvent('resume', {
            bubbles: true,
            composed: true
        }));
    }
}