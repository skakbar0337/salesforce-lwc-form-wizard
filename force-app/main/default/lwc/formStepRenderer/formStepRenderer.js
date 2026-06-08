import { LightningElement, api } from 'lwc';
import { debugInfo  } from 'c/formUtils';

export default class FormStepRenderer extends LightningElement {
    @api stepData;
    @api visibleSections;
    @api state;
    @api wizardConfig; // For passing to sections (especially review)

    connectedCallback() {
         debugInfo('Step Data: ', this.stepData);
    }

    renderedCallback() {
        if (!this.isHtmlType) {
            return;
        }
        const container = this.template.querySelector('.html-content');
        if (container) {
            container.innerHTML = this.getHtmlContent();
        }
    }

    getHtmlContent() {
        let html = this.stepData?.content?.html || '';
        
        // Find all {{fieldName}} patterns and replace with values from state
        // Use a more flexible regex that handles various field name formats
        html = html.replace(/\{\{([^}]+)\}\}/g, (match, fieldName) => {
            const trimmedFieldName = fieldName.trim();
            // Check in state directly
            if (this.state?.[trimmedFieldName] !== undefined) {
                return this.state[trimmedFieldName];
            }
            // Check in state.answers
            if (this.state?.answers?.[trimmedFieldName] !== undefined) {
                return this.state.answers[trimmedFieldName];
            }
            // Return original match if not found
            return match;
        });

        debugInfo('Generated HTML content:', html);
        
        return html;
    }

    /**
     * Public method to validate all sections in this step
     * @param {boolean} silent - If true, don't show error messages
     * @returns {Object} { isValid: boolean, errors: Array }
     */
    @api
    validateStep(silent = false) {
        const allErrors = [];
        
        // Query all section components
        const sections = this.template.querySelectorAll('c-form-section');
        
        sections.forEach(section => {
            try {
                const sectionResults = section.validateSection(silent);
                // Filter out valid results, keep only errors
                const errors = sectionResults.filter(result => !result.isValid);
                allErrors.push(...errors);
            } catch (error) {
                console.error('Error validating section:', error);
            }
        });

        const isValid = allErrors.length === 0;

        debugInfo(`Step ${this.stepData?.number} validation:`, {
            isValid,
            errorCount: allErrors.length,
            errors: allErrors
        });

        return {
            isValid,
            errors: allErrors
        };
    }

    /**
     * Legacy validate method for backward compatibility
     * @returns {boolean} True if all sections are valid
     */
    @api
    validate() {
        const result = this.validateStep();
        return result.isValid;
    }

    get sections() {
        // Safe fallback: empty array if stepData or sections is missing
        return this.stepData?.sections || [];
    }

    handleValueChange(event) {
        // Add step context to the event detail
        const detail = {
            ...event.detail,
            step: this.stepData?.number || this.stepData?.name
        };
        
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: detail,
            bubbles: true,
            composed: true
        }));
    }

    handleValueChange2(event) {
        // Same idea, but preserve the valuechange2 name
        const detail = {
            ...event.detail,
            step: this.stepData?.number || this.stepData?.name
        };

        this.dispatchEvent(new CustomEvent('valuechange2', {
            detail,
            bubbles: true,
            composed: true
        }));
    }

    handleAnswerChange(event) {
        this.dispatchEvent(new CustomEvent('answerchange', {
            detail: event.detail
        }));
    }
    
    handleAddSection(event) {
        const index = event.target.dataset.index;
        const insertIndex = index === 'last' ? this.sections.length : parseInt(index, 10);
        
        this.dispatchEvent(new CustomEvent('addsection', {
            detail: { 
                stepNumber: this.stepData.number,
                insertIndex: insertIndex
            }
        }));
    }
    
    handleRemoveSection(event) {
        const sectionName = event.target.dataset.name;
        
        this.dispatchEvent(new CustomEvent('removesection', {
            detail: { 
                stepNumber: this.stepData.number,
                sectionName: sectionName
            }
        }));
    }

    handleDeleteField(event) {
        this.dispatchEvent(new CustomEvent('deletefield', {
            detail: { ...event.detail, stepNumber: this.stepData.number }
        }));
    }

    handleAddField(event) {
        this.dispatchEvent(new CustomEvent('addfield', {
            detail: { ...event.detail, stepNumber: this.stepData.number }
        }));
    }

    get isHtmlType() {
        return this.stepData?.type === 'html-only';
    }

    // TODO: REMOVE
    get isCohortStep() {
        // Step 4 is the Study Cohorts step
        return this.stepData && this.stepData.number === 4;
    }

    handleCohortConfigChange(event) {
        // Just re-dispatch upwards so formWizardContainer can listen.
        this.dispatchEvent(
            new CustomEvent('cohortconfigchange', {
                detail: event.detail,
                bubbles: true,
                composed: true
            })
        );
    }


    handleReorderFields(event) {
        this.dispatchEvent(new CustomEvent('reorderfields', {
            detail: { ...event.detail, stepNumber: this.stepData.number }
        }));
    }

    // Public API methods for cohort navigation
    @api
    getCohortComponent() {
        if (this.isCohortStep) {
            return this.template.querySelector('c-form-cohort-section');
        }
        return null;
    }

    @api
    async handleCohortNext() {
        // First check for cohort setup component (Step 4)
        const cohortCmp = this.getCohortComponent();
        if (cohortCmp && typeof cohortCmp.handleNext === 'function') {
            return cohortCmp.handleNext();
        }
        
        // Then check for page iterator component (dynamically injected cohort steps)
        const sections = this.template.querySelectorAll('c-form-section');
        for (const section of sections) {
            const iteratorCmp = section.getCustomComponent();
            if (iteratorCmp && typeof iteratorCmp.handleNext === 'function') {
                return iteratorCmp.handleNext();
            }
        }
        
        return true; // Allow advancement if no cohort component
    }

    @api
    async handleCohortPrevious() {
        // First check for cohort setup component (Step 4)
        const cohortCmp = this.getCohortComponent();
        if (cohortCmp && typeof cohortCmp.handlePrevious === 'function') {
            return cohortCmp.handlePrevious();
        }
        
        // Then check for page iterator component (dynamically injected cohort steps)
        const sections = this.template.querySelectorAll('c-form-section');
        for (const section of sections) {
            const iteratorCmp = section.getCustomComponent();
            if (iteratorCmp && typeof iteratorCmp.handlePrevious === 'function') {
                return iteratorCmp.handlePrevious();
            }
        }
        
        return true; // Allow going back if no cohort component
    }

    get step() {
        // Always return an object so template can safely read step.label, etc.
        return this.stepData || {};
    }

    get answers() {
        return this.state?.answers || {};
    }

}