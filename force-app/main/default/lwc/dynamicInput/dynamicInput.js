import { debugInfo, validateField } from 'c/formUtils';
import { LightningElement, api, track } from 'lwc';

export default class DynamicInput extends LightningElement {
    // Private backing fields
    _value = '';
    _checked = false;
    _errorMessage = '';
    // Public properties
    @api name;
    @api label;
    @api type = 'text'; // text, textarea, date, dropdown, radio, checkbox, single-checkbox, number, tel
    @api placeholder = '';
    @api required = false;
    @api disabled = false;

    // Number input properties
    @api min;
    @api max;
    @api step;

    // Default value for pre-populated fields (used for hidden fields like form title)
    @api defaultValue;

    // File upload support
    @api parentRecordId; // Set by parent if needed for file upload context
    @api acceptedFormats = '.pdf'; // Default, can be set by config

    get isFileInput() {
        return this.type === 'file';
    }

    // Handle file upload event
    handleFileUpload(event) {
        // Only single file supported for now
        const files = event.detail.files;
        if (files && files.length > 0) {
            const fileId = files[0].documentId;
            this._value = fileId;
            // Dispatch change event to parent, store ContentDocumentId in answers
            this.dispatchEvent(new CustomEvent('valuechange2', {
                detail: {
                    question: this.name,
                    value: fileId,
                    type: this.type
                },
                bubbles: true,
                composed: true
            }));
        }
    }
    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val;
    }
    @api helpText;
        @api
    get errorMessage() {
        return this._errorMessage;
    }
    set errorMessage(val) {
        this._errorMessage = val;
    }

    @api showLabel = false;
    @api labelClass = 'input-label';
    @api inputClass = 'input-field';
    @api radioLayout = 'horizontal'; // horizontal or vertical
    @api checkboxLayout = 'grid'; // grid or vertical
    @api gridColumns = 4; // Number of columns for grid layout
    @api rows = 3; // Number of rows for textarea
    @api maxLength; // Maximum character length for text/textarea inputs
    @api variant;  
    
    // Answers object from parent
    @api 
    get state() {
        return this._answers;
    }
    set state(value) {
        this._answers = value;
        this.populateFromAnswers();
    }
    
    // Alias for backward compatibility
    @api
    get answers() {
        return this._answers;
    }
    set answers(value) {
        this._answers = value;
        this.populateFromAnswers();
    }
    
    _answers = {};

    // Options for dropdown, radio, and checkbox
    @api 
    get options() {
        return this._options || [];
    }
    set options(value) {
        this._options = this.processOptions(value);
    }

    // For single checkbox
        // For single checkbox
    @api
    get checked() {
        return this._checked;
    }
    set checked(val) {
        this._checked = val;
    }


    @track _options = [];
    @track selectedValues = [];

    // Unique ID for accessibility
    uniqueId = `input-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    // Populate value from answers object
    populateFromAnswers() {
        if (this._answers && this.name && this._answers[this.name] !== undefined) {
            const answerValue = this._answers[this.name];

            if (this.type === 'checkbox' && Array.isArray(answerValue)) {
                this.selectedValues = [...answerValue];
                this._options = this.processOptions(this._options);
                        } else if (this.type === 'single-checkbox') {
                this._checked = answerValue;
            } else {
                this._value = answerValue;
                if (this.type === 'radio') {
                    this._options = this.processOptions(this._options);
                }
            }
        } else if (this.defaultValue !== undefined && this.defaultValue !== null && !this._value) {
            // If no answer exists but defaultValue is provided, use it and dispatch event
            this._value = this.defaultValue;
            // Dispatch event to update parent's answers map
            Promise.resolve().then(() => {
                this.dispatchEvent(new CustomEvent('valuechange2', {
                    detail: {
                        question: this.name,
                        value: this._value,
                        type: this.type
                    },
                    bubbles: true,
                    composed: true
                }));
            });
        }
    }

    // Computed properties for input types
    get isTextInput() {
        return this.type === 'text';
    }

    get isTextarea() {
        return this.type === 'textarea';
    }

    get isDateInput() {
        return this.type === 'date';
    }

    get isDropdown() {
        return this.type === 'dropdown' || this.type === 'select';
    }

    get isRadio() {
        return this.type === 'radio';
    }

    get isCheckbox() {
        return this.type === 'checkbox';
    }

    get isSingleCheckbox() {
        return this.type === 'single-checkbox';
    }

    get isNumberInput() {
        return this.type === 'number';
    }

    get isTelInput() {
        return this.type === 'tel';
    }

    get isPlaceholderSelected() {
        return !this._value;
    }

        get radioGroupClass() {
        // Default for all other radios (Shipping etc.)
        let base = 'radio-group';

        // Wider layout just for Step 3 variant
        if (this.variant === 'study-type-cards') {
            base += ' study-type-group';
        }
        return base;
    }

        get getRadioButtonClass() {
        let base =
            this.radioLayout === 'horizontal'
                ? 'radio-button horizontal'
                : 'radio-button vertical';

        // Optional extra hook in case you ever want variant-specific tweaks
        if (this.variant === 'study-type-cards') {
            base += ' study-type-card-wrapper';
        }
        return base;
    }

    get radioLabelBaseClass() {
        // Used by radio labels
        return this.variant === 'study-type-cards'
            ? 'radio-label study-type-label'
            : 'radio-label';
    }

    get checkboxGroupClass() {
        let baseClass = 'checkbox-group';
        if (this.checkboxLayout === 'grid') {
            baseClass += ` grid-layout columns-${this.gridColumns}`;
        } else {
            baseClass += ' vertical-layout';
        }
        return baseClass;
    }

    // Process options to ensure they have proper structure
    processOptions(options) {
        if (!options || !Array.isArray(options)) {
            return [];
        }

        return options.map((option, index) => {
            // If option is a string, convert to object
            if (typeof option === 'string') {
                option = { label: option, value: option };
            }

            // Ensure required properties exist
            const processedOption = {
                label: option.label || option.value || '',
                value: option.value || option.label || '',
                subLabel: option.subLabel || '', 
                checked: option.checked || false,
                selected: option.selected || false,
                id: `${this.uniqueId}-option-${index}`
            };

            // For radio buttons, check if this option matches the current value
            if (this.type === 'radio' && this._value === processedOption.value) {
                processedOption.checked = true;
            }
            // For checkboxes, check if this option is in selectedValues
            if (this.type === 'checkbox' && this.selectedValues.includes(processedOption.value)) {
                processedOption.checked = true;
            }

            return processedOption;
        });
    }

    // Event handlers
    handleChange(event) {
        const value = event.target.value;
        this._value = value;
        debugInfo('Value changed:', value);

        // Clear error when user starts typing
        if (this._errorMessage) {
            this.clearError();
        }

        // Dispatch change event to parent
        this.dispatchEvent(new CustomEvent('valuechange2', {
            detail: {
                question: this.name,
                value: value,
                type: this.type
            },
            bubbles: true,
            composed: true
        }));
    }

    // Handle tel input - strip non-numeric characters and show error
    handleTelInput(event) {
        const input = event.target;
        const originalValue = input.value;
        // Strip any non-numeric characters
        const numericValue = originalValue.replace(/[^0-9]/g, '');

        // If the value changed (non-numeric chars were entered), update and show feedback
        if (originalValue !== numericValue) {
            input.value = numericValue;
            this._value = numericValue;
            // Show validation error for non-numeric input
            this._errorMessage = 'Only numbers are allowed in this field.';
        } else {
            this._value = numericValue;
            // Clear error if user is typing valid numbers
            if (this._errorMessage === 'Only numbers are allowed in this field.') {
                this._errorMessage = '';
            }
        }

        // Dispatch change event to parent
        this.dispatchEvent(new CustomEvent('valuechange2', {
            detail: {
                question: this.name,
                value: numericValue,
                type: this.type
            },
            bubbles: true,
            composed: true
        }));
    }

    handleBlur(event) {
        // Dispatch blur event to parent for validation
        this.dispatchEvent(new CustomEvent('blur', {
            detail: {
                name: this.name,
                value: event.target.value,
                type: this.type
            }
        }));
    }

    handleRadioChange(event) {
        const value = event.target.value;
        this._value = value;

        // Clear error when user makes a selection
        if (this._errorMessage) {
            this.clearError();
        }

        // Update checked state in options
        this._options = this._options.map(option => ({
            ...option,
            checked: option.value === value
        }));

        // Dispatch change event to parent
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                question: this.name,
                value: value,
                type: this.type
            },
            bubbles: true,
            composed: true
        }));
    }

    handleCheckboxChange(event) {
        const value = event.target.value;
        const isChecked = event.target.checked;

        // Update selected values array
        if (isChecked) {
            if (!this.selectedValues.includes(value)) {
                this.selectedValues.push(value);
            }
        } else {
            this.selectedValues = this.selectedValues.filter(v => v !== value);
        }

        // Clear error when user makes a selection
        if (this._errorMessage && this.selectedValues.length > 0) {
            this.clearError();
        }

        // Update checked state in options
        this._options = this._options.map(option => ({
            ...option,
            checked: option.value === value ? isChecked : option.checked
        }));

        // Dispatch change event to parent
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                question: this.name,
                value: this.selectedValues,
                type: this.type,
                selectedValue: value,
                isChecked: isChecked
            },
            bubbles: true,
            composed: true
        }));
    }

    handleSingleCheckboxChange(event) {
        const isChecked = event.target.checked;
        this._checked = isChecked;

        // Clear error when user checks the box
        if (this._errorMessage && isChecked) {
            this.clearError();
        }

        // Dispatch change event to parent
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                question: this.name,
                value: isChecked,
                checked: isChecked,
                type: this.type
            },
            bubbles: true,
            composed: true
        }));
    }

    // Public method to set error
    @api
    setError(message) {
        this._errorMessage = message;
    }

    // Public method to clear error
    @api
    clearError() {
        this._errorMessage = '';
    }

    // Public method to get current value
    @api
    getValue() {
        if (this.type === 'checkbox') {
            return this.selectedValues;
        } else if (this.type === 'single-checkbox') {
            return this._checked;
        }
        return this._value;
    }

    get computedRadioClass() {
        return this.variant === 'study-type-cards'
            ? 'study-type-card'
            : 'radio-option';
    }

    // Public method to set value
    @api
    setValue(value) {
        if (this.type === 'checkbox' && Array.isArray(value)) {
            this.selectedValues = value;
            this._options = this.processOptions(this._options);
        } else if (this.type === 'single-checkbox') {
            this._checked = value;
        } else {
            this._value = value;
            if (this.type === 'radio') {
                this._options = this.processOptions(this._options);
            }
        }
    }

    // Public method to reset the input
    @api
    reset() {
        this._value = '';
        this._checked = false;
        this.selectedValues = [];
        this._errorMessage = '';
        this._options = this.processOptions(this._options);
    }

    /**
     * Public method to validate the field
     * Returns validation result with isValid flag and errorMessage
     * @param {boolean} silent - If true, don't show error messages (just return result)
     * @returns {Object} { isValid: boolean, errorMessage: string }
     */
    @api
    validate(silent = false) {
        // Get current value based on field type
        let currentValue;
        if (this.type === 'checkbox') {
            currentValue = this.selectedValues;
        } else if (this.type === 'single-checkbox') {
            currentValue = this._checked;
        } else {
            currentValue = this._value;
        }

        // Prepare validation config
        const validationConfig = {
            label: this.label,
            type: this.type,
            required: this.required,
            value: currentValue,
            // Number validation properties
            min: this.min,
            max: this.max,
            step: this.step
        };

        // Validate using utility function
        const result = validateField(validationConfig);

        // Update error message and styling only if not silent
        if (!silent) {
            if (!result.isValid) {
                this.setError(result.errorMessage);
            } else {
                this.clearError();
            }
        }

        debugInfo(`Validation result for ${this.name}:`, result);

        return result;
    }

    /**
     * Computed class for input container to show error state
     */
    get containerClass() {
        return this._errorMessage ? 'dynamic-input-container has-error' : 'dynamic-input-container';
    }

    /**
     * Computed class for input field to show error state
     */
    get inputFieldClass() {
        return this._errorMessage ? 'input-field error' : 'input-field';
    }

    /**
     * Check if there's an error message to display
     */
    get hasError() {
        return !!this._errorMessage;
    }
}