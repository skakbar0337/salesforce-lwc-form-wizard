import { LightningElement, api } from 'lwc';
import { debugInfo, debugError, debugWarning } from 'c/formUtils';

/**
 * Navigation component for multi-step wizard.
 * Provides Previous and Next/Complete buttons with customizable visibility and state.
 * Bubbles events to parent components for handling navigation logic.
 * 
 * @alias FormNavigation
 * @extends LightningElement
 */
export default class FormNavigation extends LightningElement {
    
    /**
     * Controls visibility of the Previous button.
     * @type {boolean}
     * @default false
     */
    @api showPrevious = false;

    /**
     * Controls visibility of the Next/Complete button.
     * @type {boolean}
     * @default false
     */
    @api showNext = false;

    /**
     * Controls visibility of the Submit button.
     * @type {boolean}
     * @default false
     */
    @api showSubmit = false;

    /**
     * Disables the Previous button when true.
     * @type {boolean}
     * @default false
     */
    @api disablePrevious = false;

    /**
     * Disables the Next/Complete button when true.
     * @type {boolean}
     * @default false
     */
    @api disableNext = false;

    /**
     * Disables the Submit button when true.
     * @type {boolean}
     * @default false
     */
    @api disableSubmit = false;

    /**
     * When true, changes the Next button label to "Complete" and applies complete styling.
     * @type {boolean}
     * @default false
     */
    @api isLastStep = false;

    /**
     * Custom label for the Next button (overrides default "Next" or "Complete").
     * @type {string}
     */
    @api customNextLabel;

    /**
     * Custom label for the Previous button (overrides default "Previous").
     * @type {string}
     */
    @api customPreviousLabel;

    /**
     * Custom label for the Submit button (overrides default "Submit").
     * @type {string}
     */
    @api customSubmitLabel;

    /**
     * Type of wizard form (e.g., 'Dynamic Request Form', 'Generic Forms', 'Onsite Form').
     * @type {string}
     */
    @api wizardType;

    /**
     * Computes the label for the Next button.
     * @returns {string} Button label
     */
    get nextButtonLabel() {
        if (this.customNextLabel) {
            return this.customNextLabel;
        }
        return this.isLastStep ? 'Complete' : 'Next';
    }

    /**
     * Computes the label for the Previous button.
     * @returns {string} Button label
     */
    get previousButtonLabel() {
        return this.customPreviousLabel || 'Previous';
    }

    /**
     * Computes the label for the Submit button.
     * @returns {string} Button label
     */
    get submitButtonLabel() {
        return this.customSubmitLabel || 'Submit';
    }

    /**
     * Computes CSS classes for the Next button based on its state.
     * @returns {string} CSS class string
     */
    get nextButtonClass() {
        const baseClass = 'srf-nav-button srf-nav-button_next';
        return this.isLastStep 
            ? `${baseClass} srf-nav-button_complete`
            : baseClass;
    }
    
    /**
     * Computes CSS classes for the navigation content container.
     * Adjusts layout based on which buttons are visible.
     * @returns {string} CSS class string
     */
    get navContentClass() {
        return this.showPrevious 
            ? 'srf-nav-content srf-nav-content_has-previous'
            : 'srf-nav-content';
    }

    /**
     * Computes aria-label for the Next button.
     * @returns {string} Aria label
     */
    get nextButtonAriaLabel() {
        return this.isLastStep 
            ? 'Complete and submit form'
            : 'Go to next step';
    }

    /**
     * Handles Previous button click.
     * Dispatches a 'previous' event that bubbles up to parent components.
     * @param {Event} event - Click event
     */
    handlePreviousClick(event) {
        event.preventDefault();
        
        if (this.disablePrevious) {
            debugWarning('formNavigation: Previous button clicked while disabled');
            return;
        }
        
        try {
            debugInfo('formNavigation: Previous button clicked');
            
            // Dispatch custom event that bubbles to parent components
            this.dispatchEvent(new CustomEvent('previous', {
                bubbles: true,
                composed: true,
                detail: {
                    action: 'previous',
                    timestamp: new Date().toISOString()
                }
            }));
        } catch (error) {
            debugError('formNavigation: Error dispatching previous event', {
                error: error.message,
                stack: error.stack
            });
        }
    }

    /**
     * Handles Next/Complete button click.
     * Dispatches either 'next' or 'complete' event based on isLastStep.
     * Events bubble up to parent components.
     * @param {Event} event - Click event
     */
    handleNextClick(event) {
        event.preventDefault();
        
        if (this.disableNext) {
            debugWarning('formNavigation: Next button clicked while disabled');
            return;
        }
        
        try {
            const eventName = this.isLastStep ? 'complete' : 'next';
            
            debugInfo(`formNavigation: ${eventName} button clicked`, {
                isLastStep: this.isLastStep
            });
            
            // Dispatch custom event that bubbles to parent components
            this.dispatchEvent(new CustomEvent(eventName, {
                bubbles: true,
                composed: true,
                detail: {
                    action: eventName,
                    isLastStep: this.isLastStep,
                    timestamp: new Date().toISOString()
                }
            }));
        } catch (error) {
            debugError('formNavigation: Error dispatching navigation event', {
                error: error.message,
                stack: error.stack,
                isLastStep: this.isLastStep
            });
        }
    }

    /**
     * Handles Submit button click.
     * Dispatches a 'submit' event that bubbles up to parent components.
     * @param {Event} event - Click event
     */
    handleSubmitClick(event) {
        event.preventDefault();
        
        if (this.disableSubmit) {
            debugWarning('formNavigation: Submit button clicked while disabled');
            return;
        }
        
        try {
            debugInfo('formNavigation: Submit button clicked');
            
            // Dispatch custom event that bubbles to parent components
            this.dispatchEvent(new CustomEvent('submit', {
                bubbles: true,
                composed: true,
                detail: {
                    action: 'submit',
                    timestamp: new Date().toISOString()
                }
            }));
        } catch (error) {
            debugError('formNavigation: Error dispatching submit event', {
                error: error.message,
                stack: error.stack
            });
        }
    }
}