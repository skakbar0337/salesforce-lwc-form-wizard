import { ONSITE_FORM_CONFIGS } from './onsiteFormConfigs';
export { TEST_STATE } from './constants';
import { apexMethods } from './apexMethods';
export { apexMethods };

/**
 * Get onsite form configuration by form type
 * @param {string} formType - The form type (e.g., 'ClientF On-site Form', 'ABA SF On-site', 'ClientE Research')
 * @returns {Object|null} Configuration object with contactEmail, confirmationMessage, signatureName
 */
export function getOnsiteFormConfig(formType) {
    if (!formType) {
        console.error('getOnsiteFormConfig: formType is required');
        return null;
    }
    
    const formTypeLower = formType.toLowerCase();
    
    // First, try direct key match (normalized)
    const normalizedKey = formTypeLower.replace(/[^a-z0-9]/g, '_');
    if (ONSITE_FORM_CONFIGS[normalizedKey]) {
        return ONSITE_FORM_CONFIGS[normalizedKey];
    }
    
    // Second, try keyword matching for forms with matchKeywords
    for (const [key, config] of Object.entries(ONSITE_FORM_CONFIGS)) {
        if (config.matchKeywords) {
            // Check if ALL keywords match in the formType
            const allMatch = config.matchKeywords.every(keyword => 
                formTypeLower.includes(keyword.toLowerCase())
            );
            if (allMatch) {
                return config;
            }
        }
    }
    
    // Third, try simple key matching (clientb_sf matches 'aba' or 'sf')
    for (const [key, config] of Object.entries(ONSITE_FORM_CONFIGS)) {
        if (key !== 'default' && formTypeLower.includes(key.toLowerCase())) {
            return config;
        }
    }
    
    // Return default config if no match found
    return ONSITE_FORM_CONFIGS.default || null;
}

// Main debug function
export function debug(label, data, options = {}) {
    const {
        collapsed = true,
        color = '#4A90E2',
        showTimestamp = false,
        showType = true
    } = options;

    const timestamp = showTimestamp ? new Date().toLocaleTimeString() : '';
    const typeInfo = showType ? `[${getType(data)}]` : '';
    const header = `${timestamp} ${label} ${typeInfo}`.trim();

    // Use console group for better organization
    if (collapsed) {
        console.groupCollapsed(`%c${header}`, `color: ${color}; font-weight: bold;`);
    } else {
        console.group(`%c${header}`, `color: ${color}; font-weight: bold;`);
    }

    // Format and output the data
    formatAndLog(data);
    console.groupEnd();
}

// Quick debug functions for common use cases
export function debugInfo(label, data) {
    debug(label, data, { color: '#4A90E2' }); // Blue
}

export function debugSuccess(label, data) {
    debug(label, data, { color: '#5CB85C' }); // Green
}

export function debugWarning(label, data) {
    debug(label, data, { color: '#F0AD4E' }); // Orange
}

export function debugError(label, data) {
    debug(label, reduceErrors(data), { color: '#D9534F', showType: true }); // Red
}

// Helper function to format and log data
function formatAndLog(data) {
    const type = getType(data);

    switch (type) {
        case 'null':
            console.log('%cnull', 'color: #999; font-style: italic;');
            break;
        
        case 'undefined':
            console.log('%cundefined', 'color: #999; font-style: italic;');
            break;
        
        case 'string':
            // Format multi-line strings nicely
            if (data.includes('\n')) {
                console.log('%cMulti-line String:', 'color: #666; font-size: 11px;');
                console.log(data);
            } else {
                console.log('test');
                console.log(`"${data}"`);
            }
            break;
        
        case 'number':
        case 'boolean':
            console.log(data);
            break;
        
        case 'array':
            console.log(`Array(${data.length}):`);
            if (data.length > 0) {
                // Pretty print the array
                console.log(JSON.stringify(data, null, 2));
            }
            break;
        
        case 'object':
            // Check if it's an error object
            if (data instanceof Error) {
                console.error('Error:', data.message);
                if (data.stack) {
                    console.log('%cStack Trace:', 'color: #666; font-size: 11px;');
                    console.log(data.stack);
                }
            } else {
                // Pretty print the object
                try {
                    console.log('Object:');
                    const formatted = JSON.stringify(data, null, 2);
                    console.log(formatted);
                } catch (e) {
                    // Handle circular references
                    console.log('Object with circular reference:');
                    console.log(data);
                }
            }
            break;
        
        case 'function':
            console.log(`Function: ${data.name || 'anonymous'}`);
            console.log(data.toString());
            break;
        
        case 'date':
            console.log(`Date: ${data.toISOString()}`);
            break;
        
        default:
            console.log(data);
    }
}

// Helper function to get detailed type
function getType(obj) {
    if (obj === null) return 'null';
    if (obj === undefined) return 'undefined';
    if (obj instanceof Date) return 'date';
    if (obj instanceof Error) return 'error';
    if (Array.isArray(obj)) return 'array';
    
    return typeof obj;
}

/**
 * Validates if a value is not empty
 * @param {*} value - The value to validate
 * @returns {boolean} True if value is not empty
 */
export function isNotEmpty(value) {
    if (value === null || value === undefined) {
        return false;
    }
    if (typeof value === 'string') {
        return value.trim().length > 0;
    }
    if (Array.isArray(value)) {
        return value.length > 0;
    }
    if (typeof value === 'boolean') {
        return value; // false (unchecked) fails required validation
    }
    return !!value;
}

/**
 * Validates email format
 * @param {string} email - The email address to validate
 * @returns {boolean} True if email format is valid
 */
export function isValidEmail(email) {
    if (!email || typeof email !== 'string') {
        return false;
    }
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email.trim());
}

/**
 * Validates phone number format (US format)
 * @param {string} phone - The phone number to validate
 * @returns {boolean} True if phone format is valid
 */
export function isValidPhone(phone) {
    if (!phone || typeof phone !== 'string') {
        return false;
    }
    // Accept formats: (123) 456-7890, 123-456-7890, 1234567890, etc.
    const phoneRegex = /^[\d\s()+-]{10,}$/;
    return phoneRegex.test(phone.trim());
}

/**
 * Validates if value is a valid number
 * @param {*} value - The value to validate
 * @returns {boolean} True if value is a valid number
 */
export function isValidNumber(value) {
    if (value === null || value === undefined || value === '') {
        return false;
    }
    return !isNaN(value) && isFinite(value);
}

/**
 * Validates if date is in valid format and not in the past
 * @param {string} date - The date string to validate
 * @param {boolean} allowPast - Whether to allow past dates (default: true)
 * @returns {boolean} True if date is valid
 */
export function isValidDate(date, allowPast = true) {
    if (!date || typeof date !== 'string') {
        return false;
    }
    const dateObj = new Date(date);
    if (isNaN(dateObj.getTime())) {
        return false;
    }
    if (!allowPast) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return dateObj >= today;
    }
    return true;
}

/**
 * Get validation error message based on field type and validation rule
 * @param {Object} config - Configuration object
 * @param {string} config.label - Field label
 * @param {string} config.type - Field type (text, email, number, date, etc.)
 * @param {boolean} config.required - Whether field is required
 * @param {*} config.value - Field value
 * @param {number} config.min - Minimum value for number type
 * @param {number} config.max - Maximum value for number type
 * @param {number} config.step - Step value for number type (for decimal validation)
 * @returns {string} Error message or empty string if valid
 */
export function getValidationMessage(config) {
    const { label, type, required, value, min, max, step } = config;
    
    // Check required validation first
    if (required && !isNotEmpty(value)) {
        return `${label} is required.`;
    }
    
    // If not required and empty, no error
    if (!isNotEmpty(value)) {
        return '';
    }
    
    // Type-specific validations
    switch (type) {
        case 'email':
            if (!isValidEmail(value)) {
                return `Please enter a valid email address for ${label}.`;
            }
            break;
        
        case 'phone':
            if (!isValidPhone(value)) {
                return `Please enter a valid phone number for ${label}.`;
            }
            break;

        case 'tel':
            // Strict numeric validation - only digits allowed
            if (!/^\d+$/.test(value)) {
                return `${label} must contain only numbers.`;
            }
            break;

        case 'number':
            if (!isValidNumber(value)) {
                return `${label} must be a valid number.`;
            }
            // Min/max validation for numbers
            const numValue = Number(value);
            if (min !== undefined && min !== null && numValue < Number(min)) {
                return `${label} must be at least ${min}.`;
            }
            if (max !== undefined && max !== null && numValue > Number(max)) {
                return `${label} must be at most ${max}.`;
            }
            // Step validation (for decimal precision)
            if (step !== undefined && step !== null) {
                const stepNum = Number(step);
                if (stepNum > 0) {
                    // Check if value is a valid step increment from min (or 0)
                    const baseValue = min !== undefined && min !== null ? Number(min) : 0;
                    const remainder = Math.abs((numValue - baseValue) % stepNum);
                    // Allow for floating point precision issues
                    if (remainder > 0.0001 && Math.abs(remainder - stepNum) > 0.0001) {
                        return `${label} must be in increments of ${step}.`;
                    }
                }
            }
            break;
        
        case 'date':
            if (!isValidDate(value)) {
                return `Please enter a valid date for ${label}.`;
            }
            break;
        
        default:
            // No specific validation for other types
            break;
    }
    
    return '';
}

/**
 * Validate a single field
 * @param {Object} fieldConfig - Field configuration
 * @returns {Object} Validation result { isValid: boolean, errorMessage: string }
 */
export function validateField(fieldConfig) {
    const errorMessage = getValidationMessage(fieldConfig);
    return {
        isValid: errorMessage === '',
        errorMessage: errorMessage
    };
}

/**
 * TODO: REMOVE
 */
export async function handleStudyRequestFormSubmission(params) {
    debugInfo('deprecated: handleStudyRequestFormSubmission called');
    return;
}

/**
 * Reduces one or more LDS errors into a string[] of error messages.
 * @param {FetchResponse|FetchResponse[]} errors
 * @return {String[]} Error messages
 */
export function reduceErrors(errors) {
    if (!Array.isArray(errors)) {
        errors = [errors];
    }

    return (
        errors
            // Remove null/undefined items
            .filter((error) => !!error)
            // Extract an error message
            .map((error) => {
                // UI API read errors
                if (Array.isArray(error.body)) {
                    return error.body.map((e) => e.message);
                }
                // Page level errors
                else if (
                    error?.body?.pageErrors &&
                    error.body.pageErrors.length > 0
                ) {
                    return error.body.pageErrors.map((e) => e.message);
                }
                // Field level errors
                else if (
                    error?.body?.fieldErrors &&
                    Object.keys(error.body.fieldErrors).length > 0
                ) {
                    const fieldErrors = [];
                    Object.values(error.body.fieldErrors).forEach(
                        (errorArray) => {
                            fieldErrors.push(
                                ...errorArray.map((e) => e.message)
                            );
                        }
                    );
                    return fieldErrors;
                }
                // UI API DML page level errors
                else if (
                    error?.body?.output?.errors &&
                    error.body.output.errors.length > 0
                ) {
                    return error.body.output.errors.map((e) => e.message);
                }
                // UI API DML field level errors
                else if (
                    error?.body?.output?.fieldErrors &&
                    Object.keys(error.body.output.fieldErrors).length > 0
                ) {
                    const fieldErrors = [];
                    Object.values(error.body.output.fieldErrors).forEach(
                        (errorArray) => {
                            fieldErrors.push(
                                ...errorArray.map((e) => e.message)
                            );
                        }
                    );
                    return fieldErrors;
                }
                // UI API DML, Apex and network errors
                else if (error.body && typeof error.body.message === 'string') {
                    return error.body.message;
                }
                // JS errors
                else if (typeof error.message === 'string') {
                    return error.message;
                }
                // Unknown error shape so try HTTP status text
                return error.statusText;
            })
            // Flatten
            .reduce((prev, curr) => prev.concat(curr), [])
            // Remove empty strings
            .filter((message) => !!message)
    );
}
    /*
    const {
        sessionRecordId,
        answers,
        formType,
        wizardConfig,
        email,
        onSuccess,
        onError
    } = params;
    
    // Determine if this is an onsite form from customProperties in wizard config
    const isOnsite = wizardConfig?.customProperties?.isOnsite === true;

    try {
        let sessionId = sessionRecordId;
        
        // For onsite forms, create a session first using existing createSession method
        if (isOnsite && !sessionId) {
            debugInfo('Onsite form submission - creating session', {
                email,
                formType,
                answerKeys: answers ? Object.keys(answers).length : 0
            });
            
            // Use existing createSession method for onsite forms
            const sessionResult = await apexMethods.createSession(
                email || 'onsite-submission@company.com',
                formType,
                null, // ipAddress
                1 // startingStep
            );
            
            if (!sessionResult || !sessionResult.Id) {
                throw new Error('Failed to create session for onsite form submission.');
            }
            
            sessionId = sessionResult.Id;
            debugSuccess('Onsite session created', { sessionId });
        }
        
        // Prepare state object for apex method
        const state = {
            sessionId: sessionId,
            answers: answers
        };
        
        // Call apex method with state object
        // Apex signature: submitForm(Id sessionId, String answersJson, String wizardType)
        const result = await apexMethods.submitForm(state, formType);
        
        if (result && result.success) {
            // Prefer postSubmit config from wizardConfig (SRF JSON). If present, inject confirmation step.
            try {
                const cfgPayload = wizardConfig?.postSubmit;
                const payload = cfgPayload || result.postSubmit;

                if (payload && payload.showConfirmationPage === true && wizardConfig) {
                    const alreadyHas = (wizardConfig.steps || []).some(s => s.isSubmissionMessage === true);
                    if (!alreadyHas) {
                        const newStep = {
                            number: (wizardConfig.total_steps || (wizardConfig.steps || []).length) + 1,
                            label: 'Confirmation',
                            progressLabel: 'Complete',
                            description: '',
                            isSubmissionMessage: true,
                            sections: []
                        };

                        // Ensure steps array exists
                        wizardConfig.steps = wizardConfig.steps || [];
                        wizardConfig.steps.push(newStep);
                        wizardConfig.total_steps = wizardConfig.steps.length;

                        // Expose the postSubmit payload to the submission message component via window
                        try {
                            window.__FORM_POST_SUBMIT_PAYLOAD = payload;
                        } catch (e) {
                            // Ignore if window not writable
                        }
                    }
                }
            } catch (e) {
                debugError('Failed to inject submission step or set global postSubmit payload', e);
            }

            // Call success callback with message and session data
            if (onSuccess) {
                onSuccess(result.message || 'Form submitted successfully!', {
                    sessionId: sessionId,
                    recordId: result.recordId,
                    data: result.data,
                    postSubmit: wizardConfig?.postSubmit || null
                });
            }
        } else {
            // Call error callback with error message
            const errorMsg = result?.error || result?.message || 'Submission failed. Please try again.';
            if (onError) {
                onError(errorMsg);
            }
        }
        
        // Return result for callers that need session data (include postSubmit from wizard config if present)
        return { success: result?.success, sessionId, result, postSubmit: wizardConfig?.postSubmit || null };
        
    } catch (error) {
        // Handle unexpected errors
        const errorMsg = error.message || 
                        (error.body && error.body.message) || 
                        'An unexpected error occurred. Please try again.';
        
        debugError('Form submission error', { error, formType, isOnsite });
        
        if (onError) {
            onError(errorMsg);
        }
        
        return { success: false, error: errorMsg };
        */