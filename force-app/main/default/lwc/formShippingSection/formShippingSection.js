import { LightningElement, api, track } from 'lwc';

export default class FormShippingSection extends LightningElement {
    @api answers = {};
    @track localMultipleLocations = '';
    
    @track addressInstances = [{ id: 0, index: 0 }];
    nextId = 1;

    connectedCallback() {
        console.log('connectedCallback - incoming answers:', this.answers);

        // Initialize local state from answers
        if (this.answers.multipleLocations) {
            this.localMultipleLocations = this.answers.multipleLocations;
            console.log('Loading existing session with multipleLocations:', this.localMultipleLocations);
            // Load existing addresses if available
            this.loadExistingAddresses();
        } else {
            // Set default to 'single' if not already set
            console.log('Setting default to single');
            this.localMultipleLocations = 'single';

            // Dispatch event to sync with parent
            this.dispatchEvent(new CustomEvent('valuechange', {
                detail: {
                    question: 'multipleLocations',
                    value: 'single'
                },
                bubbles: true,
                composed: true
            }));
        }

        // Set default country to United States for first address if not already set
        if (!this.answers.country) {
            this.dispatchEvent(new CustomEvent('valuechange2', {
                detail: {
                    question: 'country',
                    value: 'United States'
                },
                bubbles: true,
                composed: true
            }));
        }

        console.log('connectedCallback - after init, localMultipleLocations:', this.localMultipleLocations);
    }

    loadExistingAddresses() {
        const instances = [];
        let index = 0;
        
        // Check for existing address data
        while (this.hasAddressData(index)) {
            instances.push({ id: index, index: index });
            index++;
        }
        
        if (instances.length > 0) {
            this.addressInstances = instances;
            this.nextId = index;
        }
    }

    hasAddressData(index) {
        const suffix = index === 0 ? '' : `_${index}`;
        return this.answers[`company${suffix}`] || 
               this.answers[`fullName${suffix}`] || 
               this.answers[`address${suffix}`];
    }

    get showAddresses() {
        // Show addresses when any radio option is selected
        const result = Boolean(this.localMultipleLocations);
        console.log('showAddresses getter:', {
            localMultipleLocations: this.localMultipleLocations,
            result: result
        });
        return result;
    }

    get showAddButton() {
        // Show add button only when multiple locations is selected
        return this.localMultipleLocations === 'multiple';
    }

    get canAddMore() {
        return this.addressInstances.length < 10; // max 10 addresses
    }

    get addressSections() {
        console.log('addressSections getter:', {
            addressInstances: this.addressInstances,
            localMultipleLocations: this.localMultipleLocations
        });
        return this.addressInstances.map((instance, idx) => {
            const suffix = idx === 0 ? '' : `_${idx}`;
            const isMultiple = this.localMultipleLocations === 'multiple';
            let title;
            if (isMultiple) {
                title = `Shipping Address ${idx + 1}`;
            } else {
                title = 'Shipping Address';
            }
            // Determine if this address is US or International
            const countryValue = this.answers[`country${suffix}`] || 'United States';
            const isUS = countryValue === 'United States';
            const isInternational = countryValue === 'International';

            return {
                ...instance,
                key: `address-${instance.id}`,
                isFirst: idx === 0,
                canRemove: idx > 0 && isMultiple,
                title: title,
                companyField: `company${suffix}`,
                fullNameField: `fullName${suffix}`,
                countryField: `country${suffix}`,
                addressField: `address${suffix}`,
                cityField: `city${suffix}`,
                stateField: `state${suffix}`,
                zipCodeField: `zipCode${suffix}`,
                phoneField: `phone${suffix}`,
                isUS: isUS,
                isInternational: isInternational
            };
        });
    }

    get isSingleLocation() {
        return this.localMultipleLocations === 'single';
    }

    get isMultipleLocations() {
        return this.localMultipleLocations === 'multiple';
    }

    get singleLocationClass() {
        return `radio-option-card ${this.isSingleLocation ? 'selected' : ''}`;
    }

    get multipleLocationClass() {
        return `radio-option-card ${this.isMultipleLocations ? 'selected' : ''}`;
    }

    handleRadioChange(event) {
        const value = event.target.value;
        
        console.log('handleRadioChange - value:', value);
        console.log('handleRadioChange - localMultipleLocations before:', this.localMultipleLocations);
        
        // Update local state immediately for UI reactivity
        this.localMultipleLocations = value;
        
        console.log('handleRadioChange - localMultipleLocations after:', this.localMultipleLocations);
        
        // Reset to single address when switching to single location
        if (value === 'single' && this.addressInstances.length > 1) {
            this.addressInstances = [{ id: 0, index: 0 }];
            this.nextId = 1;
            // Clear additional address data from answers
            this.clearAdditionalAddresses();
        }
        
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                question: 'multipleLocations',
                value: value
            },
            bubbles: true,
            composed: true
        }));
    }

    clearAdditionalAddresses() {
        // Dispatch events to clear additional address fields
        for (let i = 1; i < 10; i++) {
            const fields = ['company', 'fullName', 'country', 'address', 'city', 'state', 'zipCode', 'phone'];
            fields.forEach(field => {
                const fieldName = `${field}_${i}`;
                console.log('Clearing field:', fieldName);
                this.dispatchEvent(new CustomEvent('valuechange2', {
                    detail: {
                        question: fieldName,
                        value: ''
                    },
                    bubbles: true,
                    composed: true
                }));
            });
        }
    }

    handleAddAddress() {
        if (this.canAddMore) {
            const newIndex = this.addressInstances.length;
            this.addressInstances = [
                ...this.addressInstances,
                { id: this.nextId, index: newIndex }
            ];
            this.nextId++;

            // Set default country to United States for new address
            const suffix = `_${newIndex}`;
            this.dispatchEvent(new CustomEvent('valuechange2', {
                detail: {
                    question: `country${suffix}`,
                    value: 'United States'
                },
                bubbles: true,
                composed: true
            }));
        }
    }

    handleRemoveAddress(event) {
        const indexToRemove = parseInt(event.target.dataset.index, 10);
        
        if (indexToRemove > 0) {
            // Remove the instance
            this.addressInstances = this.addressInstances
                .filter((_, idx) => idx !== indexToRemove)
                .map((instance, idx) => ({ ...instance, index: idx }));
            
            // Clear the removed address data
            this.clearAddressData(indexToRemove);
            
            // Reorganize remaining addresses
            this.reorganizeAddresses(indexToRemove);
        }
    }

    clearAddressData(index) {
        const suffix = index === 0 ? '' : `_${index}`;
        const fields = ['company', 'fullName', 'country', 'address', 'city', 'state', 'zipCode', 'phone'];

        fields.forEach(field => {
            const fieldName = `${field}${suffix}`;
            console.log('Clearing address field:', fieldName);
            this.dispatchEvent(new CustomEvent('valuechange2', {
                detail: {
                    question: fieldName,
                    value: ''
                },
                bubbles: true,
                composed: true
            }));
        });
    }

    reorganizeAddresses(removedIndex) {
        // Shift all addresses after the removed one
        for (let i = removedIndex + 1; i < 10; i++) {
            const oldSuffix = `_${i}`;
            const newSuffix = i === 1 ? '' : `_${i - 1}`;
            const fields = ['company', 'fullName', 'country', 'address', 'city', 'state', 'zipCode', 'phone'];

            fields.forEach(field => {
                const oldValue = this.answers[`${field}${oldSuffix}`];
                if (oldValue) {
                    // Copy to new position
                    console.log(`Reorganizing: ${field}${oldSuffix} -> ${field}${newSuffix}`);
                    this.dispatchEvent(new CustomEvent('valuechange2', {
                        detail: {
                            question: `${field}${newSuffix}`,
                            value: oldValue
                        },
                        bubbles: true,
                        composed: true
                    }));

                    // Clear old position
                    this.dispatchEvent(new CustomEvent('valuechange2', {
                        detail: {
                            question: `${field}${oldSuffix}`,
                            value: ''
                        },
                        bubbles: true,
                        composed: true
                    }));
                }
            });
        }
    }

    handleCountryChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const suffix = index === 0 ? '' : `_${index}`;
        const value = event.target.value;

        console.log('Country changed:', { index, value });

        // Clear city, state, zipCode when switching to International
        if (value === 'International') {
            ['city', 'state', 'zipCode'].forEach(field => {
                this.dispatchEvent(new CustomEvent('valuechange2', {
                    detail: {
                        question: `${field}${suffix}`,
                        value: ''
                    },
                    bubbles: true,
                    composed: true
                }));
            });
        }

        // Dispatch the country change
        this.dispatchEvent(new CustomEvent('valuechange2', {
            detail: {
                question: `country${suffix}`,
                value: value
            },
            bubbles: true,
            composed: true
        }));
    }

    handleFieldChange(event) {
        this.dispatchEvent(new CustomEvent('valuechange2', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    @api
    validate() {
        let isValid = true;
        let errorMessages = [];
        const inputs = this.template.querySelectorAll('c-dynamic-input');

        inputs.forEach(input => {
            if (input.validate) {
                const result = input.validate();
                if (!result.isValid) {
                    isValid = false;
                    if (result.errorMessage) {
                        errorMessages.push(result.errorMessage);
                    }
                }
            }
        });

        return {
            isValid: isValid,
            errorMessage: isValid ? '' : 'Please complete all required shipping fields.'
        };
    }
}