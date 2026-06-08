import { LightningElement, api } from 'lwc';
import { debugError, debugWarning } from 'c/formUtils';

/**
 * Horizontal step progress bar component for multi-step wizards.
 * Displays a visual indicator of progress through a series of steps.
 *
 * @alias FormProgressBar
 * @extends LightningElement
 */
export default class FormProgressBar extends LightningElement {
    /** @type {Array} Internal steps array */
    _steps = [];
    
    /** @type {number} Internal active step index (1-based) */
    _active = 1;
    
    /** @type {boolean} Flag to track if there was a parsing error */
    _hasError = false;

    /**
     * Gets the steps configuration.
     * @returns {Array} Array of step objects
     * @public
     */
    @api
    get steps() {
        return this._steps;
    }

    /**
     * Sets the steps configuration.
     * Accepts an array of step objects, a JSON string, or an object.
     * Each step should have a 'label' or 'name' property.
     *
     * @param {Array|string|Object} value - Steps configuration
     * @example
     * // As array
     * [{label: 'Step 1'}, {label: 'Step 2'}]
     * // As JSON string
     * '[{"label": "Step 1"}, {"label": "Step 2"}]'
     * @public
     */
    set steps(value) {
        this._hasError = false;
        let parsed = [];

        if (!value) {
            this._steps = [];
            return;
        }

        try {
            if (typeof value === 'string') {
                const trimmed = value.trim();
                if (trimmed) {
                    parsed = JSON.parse(trimmed);
                }
            } else if (Array.isArray(value)) {
                parsed = value;
            } else if (typeof value === 'object') {
                parsed = Object.values(value);
            }

            if (!Array.isArray(parsed)) {
                throw new Error('Parsed value is not an array');
            }

            // Validate step structure
            if (parsed.length === 0) {
                debugWarning('formProgressBar: Empty steps array provided', { value });
            }

        } catch (e) {
            this._hasError = true;
            debugError('formProgressBar: Invalid steps configuration', {
                error: e.message,
                providedValue: value,
                stack: e.stack
            });
            parsed = [];
        }

        const lastIdx = parsed.length - 1;

        // Create new array to avoid reactivity issues
        this._steps = parsed.map((step, idx) => ({
            label: step?.label || step?.name || `Step ${idx + 1}`,
            index: idx + 1,
            hasConnector: idx < lastIdx,
            key: `step-${idx}` // Add unique key for template iteration
        }));

        this.updateStepStates();
    }

    /**
     * Gets the current active step index (1-based).
     * @returns {number} Active step index
     * @public
     */
    @api
    get activeStep() {
        return this._active;
    }

    /**
     * Sets the active step index (1-based).
     * Value will be clamped between 1 and the total number of steps.
     *
     * @param {number|string} value - Active step index (1-based)
     * @public
     */
    set activeStep(value) {
        const numeric = Number(value);
        
        if (!Number.isFinite(numeric) || numeric <= 0) {
            debugWarning('formProgressBar: Invalid activeStep value, defaulting to 1', {
                providedValue: value,
                type: typeof value
            });
            this._active = 1;
        } else {
            this._active = numeric;
        }
        
        this.updateStepStates();
    }


    /**
     * Checks if there are any steps to display.
     * @returns {boolean} True if steps exist
     * @public
     */
    get hasSteps() {
        return Array.isArray(this._steps) && this._steps.length > 0;
    }

    /**
     * Updates the state and styling classes for all steps based on the active step.
     * Creates a new array to ensure proper reactivity.
     * @private
     */
    updateStepStates() {
        if (!this.hasSteps) {
            return;
        }

        // Clamp active index between 1 and last step index
        const maxIndex = this._steps.length;
        const requested = Number(this._active) || 1;
        const activeIndex = Math.min(Math.max(1, requested), maxIndex);

        // Create new array to trigger reactivity
        this._steps = this._steps.map((step) => {
            const status = this.getStepStatus(step.index, activeIndex);

            // ✔ = show tick for completed steps, number otherwise
            const displayValue = status === 'complete'
                ? '✔'
                : String(step.index);

            return {
                ...step,
                status,
                displayValue,
                ariaLabel: `Step ${step.index}: ${step.label}, ${status}`,
                circleClass: this.getCircleClass(status),
                labelClass: this.getLabelClass(status),
                connectorClass: this.getConnectorClass(status)
            };
        });
    }

    /**
     * Determines the status of a step based on its index.
     * @param {number} stepIndex - The step's index
     * @param {number} activeIndex - The current active step index
     * @returns {string} Status: 'complete', 'active', or 'upcoming'
     * @private
     */
    getStepStatus(stepIndex, activeIndex) {
        if (stepIndex < activeIndex) {
            return 'complete';
        } else if (stepIndex === activeIndex) {
            return 'active';
        }
        return 'upcoming';
    }

    /**
     * Gets CSS classes for the step circle based on status.
     * @param {string} status - Step status
     * @returns {string} CSS class string
     * @private
     */
    getCircleClass(status) {
        const baseClass = 'form-step__circle';
        switch (status) {
            case 'active':
                return `${baseClass} form-step__circle_active`;
            case 'complete':
                return `${baseClass} form-step__circle_complete`;
            default:
                return baseClass;
        }
    }

    /**
     * Gets CSS classes for the step label based on status.
     * @param {string} status - Step status
     * @returns {string} CSS class string
     * @private
     */
    getLabelClass(status) {
        const baseClass = 'form-step__label';
        switch (status) {
            case 'active':
                return `${baseClass} form-step__label_active`;
            case 'complete':
                return `${baseClass} form-step__label_complete`;
            default:
                return baseClass;
        }
    }

    /**
     * Gets CSS classes for the connector line based on status.
     * The connector should be colored based on whether the CURRENT step is complete.
     * @param {string} status - Step status
     * @returns {string} CSS class string
     * @private
     */
    getConnectorClass(status) {
        const baseClass = 'form-step__connector';
        // Connector is complete if the step it originates from is complete
        return status === 'complete'
            ? `${baseClass} form-step__connector_complete`
            : `${baseClass} form-step__connector_default`;
    }

    /**
     * Lifecycle hook called when component is inserted into DOM.
     * Used for initialization and debugging in Experience Cloud.
     * @private
     */
    connectedCallback() {
        // Ensure steps are updated on initial render
        this.updateStepStates();
    }

}