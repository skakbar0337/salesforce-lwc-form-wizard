import { LightningElement, wire, track } from 'lwc';
import getAllWizardConfigurations from '@salesforce/apex/FormWizardController.getAllWizardConfigurations';

export default class FormWizardSelector extends LightningElement {
    @track selectedConfig = '';
    @track showContainer = false;
    @track wizardOptions = [];

    @wire(getAllWizardConfigurations)
    wiredConfigs({ error, data }) {
        if (data) {
            this.wizardOptions = data.map(config => {
                return { label: config.Label__c, value: config.Title__c };
            });
        } else if (error) {
            console.error('Error loading wizard configurations', error);
        }
    }

    handleConfigChange(event) {
        this.selectedConfig = event.detail.value;
    }

    handleContinue() {
        if (this.selectedConfig) {
            this.showContainer = true;
        }
    }

    handleBack() {
        this.showContainer = false;
        // Optional: clear selection
        // this.selectedConfig = '';
    }

    get showSelection() {
        return !this.showContainer;
    }

    get isContinueDisabled() {
        return !this.selectedConfig;
    }
}