import { LightningElement, track, api } from 'lwc';
import { apexMethods, debugInfo, debugError, debugSuccess, debugWarning, handleStudyRequestFormSubmission } from 'c/formUtils';

// TODO: Remove after testing
import debugSession from '@salesforce/apex/FormWizardController.debugSession';

export default class FormWizardContainer extends LightningElement {
    @api staticFormType;
    @api isStudyRequestForm;

    // TODO: Remove after testing
    DEBUG_MODE = false;

    @track wizardConfig;
    @track currentStepNumber = 1;
    @track state = {
        primaryEmail: '',
        sessionRecordId: '',
        formType: '',
        sessionName: '',
        sessionToken: '',
        steps: {},
        answers: {}
    };

    @track isLoading = true;
    @track isSaving = false;
    @track isAutoSaving = false;
    @track isEmailVerified = false; 
    
    @track isOnsiteSubmitted = false; 
    @track submissionConfirmationId = ''; 

    @track showValidationBanner = false;
    @track validationMessage = '';

    @track hasUnexpectedError = false;

    // Help modal state
    @track showHelpModal = false;

    // Animation state for step transitions
    @track isAnimating = false;
    @track animationPhase = 'idle'; // 'idle', 'exiting', 'entering'
    @track animationDirection = 'next'; // 'next' or 'previous' 
    
    // Debouncing properties for auto-save
    saveTimeout;
    pendingSave = false;
    SAVE_DEBOUNCE_MS = 1500; // Wait 1.5 seconds after last field change

    async loadDebugSession() {
        if (!this.DEBUG_MODE) return;
       
        const session = await debugSession();
        debugInfo('Loaded debug session for email:', session);

        this.sessionRecordId = session.sessionData.Id; // Store the record Id
        this.state.sessionToken = session.sessionData.Session_Token__c;
        this.state.sessionRecordId = session.sessionData.Id;
        this.state.primaryEmail = session.sessionData.Guest_Email__c;
        this.state.sessionName = session.sessionData.Name;
        this.currentStepNumber = 1;
        const loadedAnswers = JSON.parse(session.sessionData.Answers_JSON__c);
                       
        this.state = {
            ...this.state,
            ...loadedAnswers,
            answers: loadedAnswers 
        };
        debugInfo('Debug session answers loaded', loadedAnswers);
        this.wizardConfig.emailSessionRequired = false;
        this.isLoading = false;
        debugSuccess('Debug session loaded', this.state);
    }

    connectedCallback() {
        if (this.isStudyRequestForm) {
            this.staticFormType = 'Dynamic_Request_Form';
        }
        if (!this.staticFormType) {
            this.state.formType = this.getFormTypeFromUrl();
        } else {
            this.state.formType = this.staticFormType;
        }
        this.initializeWizard();
    }
    
    async initializeWizard() {
        try {
            await this.loadWizardConfiguration();

            if (this.DEBUG_MODE) {
                await this.loadDebugSession();
                return;
            }

            // If email verification is not required, mark it as verified automatically
            if (!this.requiresEmailVerification) {
                this.isEmailVerified = true;
            }
            this.isEmailVerified = false;
            debugInfo('Email verification required:', this.requiresEmailVerification);
            
        } catch (error) {
            debugError('Error initializing wizard', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async loadWizardConfiguration() {
        const configStr = await apexMethods.fetchWizardConfig(this.state.formType);
        this.wizardConfig = configStr;

        if(configStr && this.DEBUG_MODE) {
            this.wizardConfig.emailSessionRequired = false;
        }
    }

    setErrorCondition() {
        this.hasUnexpectedError = true;
    }

    /**
     * Extracts the form query parameter from the current URL
     * @returns {string|null} The form parameter value or null if not found
     */
    getFormTypeFromUrl() {
        try {
            const urlParams = new URLSearchParams(window.location.search);
            const formParam = urlParams.get('form');
            
            if (formParam) {
                debugInfo('Form type extracted from URL:', formParam);
                return formParam;
            } 
            debugWarning('No form type found in URL');
            return null;
        } catch (error) {
            debugError('Error extracting form parameter from URL', error);
            return null;
        }
    }

    /**
     * Debounced auto-save: waits 1.5s after last change,
     * batches all field updates into a single API call
     */
    debouncedAutoSave() {
        // Clear existing timeout
        if (this.saveTimeout) {
            clearTimeout(this.saveTimeout);
        }

        // Mark that we have pending changes and show indicator immediately
        this.pendingSave = true;
        this.isAutoSaving = true;

        // Set new timeout
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.saveTimeout = setTimeout(() => {
            this.autoSaveSession();
        }, this.SAVE_DEBOUNCE_MS);
    }
    
    /**
     * Auto-saves the current session
     */
    async autoSaveSession() {
        if (!this.state.sessionToken || !this.pendingSave) {
            this.isAutoSaving = false;
            return;
        }

        this.pendingSave = false;

        debugInfo('Auto-saving session...', {
            sessionToken: this.state.sessionToken,
            currentStep: this.currentStepNumber,
            answerCount: Object.keys(this.state).length
        });

        try {
            await apexMethods.updateSession(
                this.state,
                this.currentStepNumber,
                'In Progress'
            );
        } finally {
            this.isAutoSaving = false;
        }
    }

    // TODO: Move to utils
    //search wizard steps for question by name
    findQuestion(name) {
        debugInfo('Finding question in wizard config:', name);
        if (!this.wizardConfig || !this.wizardConfig.steps) {
            return null;
        }
        debugInfo('Searching for question:', name);

        for (const step of this.wizardConfig.steps) {
            if (!step.sections || !Array.isArray(step.sections)) {
                continue;
            }
            for (const section of step.sections) {
                if (!section.questions || !Array.isArray(section.questions)) {
                    continue;
                }
                const question = section.questions.find(q => q.name === name);
                if (question) {
                    return question;
                }
            }
        }
        return null;
    }

    applyAnswerChange(event) {
        const { question, value } = event.detail;

        // Update both state root AND state.answers to keep them in sync
        this.state = {
            ...this.state,
            answers: {
                ...this.state.answers,
                [question]: value
            },
            [question]: value  // Also at root for backward compatibility
        };

    
        // Capture primary email if applicable
        if (this.findQuestion(question)) {
            const questionConfig = this.findQuestion(question);
            if (questionConfig.primaryEmail === true) {
                debugInfo('Updating primary email from question:', question, value);
                this.state.primaryEmail = value;
            }
        }

        debugInfo('state updated', this.state);

        // Check if validation banner should be hidden
        if (this.showValidationBanner) {
            this.checkAndDismissValidationBanner();
        }

        // Auto-save if enabled in configuration
        if (this.state.sessionToken && this.allowSaveResume) {
            this.debouncedAutoSave();
        }
    }

    handleValueChange(event) {
        this.applyAnswerChange(event);
    }

    handleValueChange2(event) {
        this.applyAnswerChange(event);
    }
    
    /**
     * Handle email verification complete event
     * Create new session or load existing session
     * TODO: Refactor to separate methods for clarity and testability
     */
    async handleEmailVerified(event) {
        try {
            debugInfo('Email verification complete', event.detail);
            
            const { email, sessionData, sessionToken } = event.detail;
            this.state.primaryEmail = email;

            // CASE 1: Returning user with In Progress session
            if (sessionData && sessionToken) {
                debugInfo('Loading existing session', sessionData);

                this.state.sessionRecordId = sessionData.Id; // Store the record Id from existing session
                this.state.sessionToken = sessionToken;
                this.state.sessionName = sessionData.Name;
                this.currentStepNumber = sessionData.Current_Step__c || 1;

                if (sessionData.Answers_JSON__c) {
                    try {
                        const loadedAnswers = JSON.parse(sessionData.Answers_JSON__c);
                        // Spread answers into state root for backward compatibility
                        this.state = {
                            ...this.state,
                            ...loadedAnswers,
                            sessionRecordId: sessionData.Id,
                            answers: loadedAnswers  // Also keep in answers for consistency
                        };
                        
                        // 🔥 INJECT COHORT STEPS IMMEDIATELY AFTER LOADING STATE
                        // Don't wait for Step 4 to render - inject now so progress bar is correct
                        const cohortCount = loadedAnswers.cohortCount || loadedAnswers.numberOfCohorts;
                        const cohortNames = loadedAnswers.cohortNames;
                        
                        if (cohortCount && cohortNames && Array.isArray(cohortNames) && cohortNames.length > 0) {
                            debugInfo('🚀 Session resume detected - injecting cohort steps immediately', {
                                cohortCount: cohortCount,
                                cohortNames: cohortNames,
                                currentSteps: this.wizardConfig?.steps?.length || 0
                            });
                            
                            // Inject steps synchronously - we have all the data we need
                            this.handleCohortConfigChange({
                                detail: {
                                    cohortCount: cohortCount,
                                    cohortNames: cohortNames
                                }
                            });
                            
                            debugSuccess('✅ Cohort steps injected during session load', {
                                totalSteps: this.wizardConfig.total_steps,
                                steps: this.wizardConfig.steps.map(s => s.label)
                            });
                        } else {
                            debugInfo('ℹ️ No cohort data in session or invalid format', {
                                cohortCount: cohortCount,
                                cohortNames: cohortNames,
                                isArray: Array.isArray(cohortNames),
                                length: cohortNames?.length
                            });
                        }
                    } catch (e) {
                        debugError('Failed to parse sessionData', e);
                    }
                }

                debugSuccess('Existing session loaded', {
                    sessionRecordId: this.state.sessionRecordId,
                    sessionToken: this.state.sessionToken,
                    currentStep: this.currentStepNumber,
                    answerCount: Object.keys(this.state).length
                });

            // CASE 2: First-time user or non In-Progress session
            } else {
                debugInfo('Creating new session for:', email);

                this.isLoading = true;
                const srs = await apexMethods.createSession(email, this.state.formType);

                // srs is Form_Session__c from Apex
                this.state.sessionRecordId = srs.Id; // Store the record Id
                this.state.sessionToken = srs.Session_Token__c;
                this.currentStepNumber = srs.Current_Step__c || 1;
                this.state.sessionName = srs.Name;

                if (srs.Answers_JSON__c) {
                    try {
                        const loadedAnswers = JSON.parse(srs.Answers_JSON__c);
                        // Spread answers into state root for backward compatibility
                        this.state = {
                            ...this.state,
                            ...loadedAnswers,
                            sessionRecordId: srs.Id,
                            answers: loadedAnswers  // Also keep in answers for consistency
                        };
                        
                        // 🔥 INJECT COHORT STEPS IMMEDIATELY IF NEW SESSION HAS COHORT DATA
                        // (This handles edge case where new session was created with pre-filled data)
                        const cohortCount = loadedAnswers.cohortCount || loadedAnswers.numberOfCohorts;
                        const cohortNames = loadedAnswers.cohortNames;
                        
                        if (cohortCount && cohortNames && Array.isArray(cohortNames) && cohortNames.length > 0) {
                            debugInfo('🚀 New session with cohort data - injecting steps immediately', {
                                cohortCount: cohortCount,
                                cohortNames: cohortNames,
                                currentSteps: this.wizardConfig?.steps?.length || 0
                            });
                            
                            this.handleCohortConfigChange({
                                detail: {
                                    cohortCount: cohortCount,
                                    cohortNames: cohortNames
                                }
                            });
                            
                            debugSuccess('✅ Cohort steps injected for new session', {
                                totalSteps: this.wizardConfig.total_steps
                            });
                        }
                    } catch (e) {
                        debugError('Failed to parse initial Answers_JSON__c', e);
                    }
                }

                debugSuccess('New session created', {
                    sessionRecordId: this.state.sessionRecordId,
                    sessionToken: this.state.sessionToken
                });
            }

            // At this point, we are ready to show the wizard
            this.isEmailVerified = true;

        } catch (error) {
            debugError('Error handling email verification', {
                error: error.body ? error.body.message : error.message,
                stack: error.stack
            });
        } finally {
            this.isLoading = false;
        }
    }
    
    handleStepAdd(event) {
        const { steps, insertPosition } = event.detail;
        
        debugInfo('Adding steps:', {
            steps,
            insertPosition
        });

        if (!steps || !Array.isArray(steps) || steps.length === 0) {
            console.error('Invalid steps provided for addition');
            return;
        }

        // Clone the current wizard config to maintain reactivity
        const updatedConfig = { ...this.wizardConfig };
        const currentSteps = [...updatedConfig.steps];

        // Insert the new steps at the specified position
        const insertIndex = insertPosition || currentSteps.length;
        currentSteps.splice(insertIndex, 0, ...steps);

        // Renumber all steps to maintain sequence
        currentSteps.forEach((step, index) => {
            step.number = index + 1;
        });

        // Update the total steps count
        updatedConfig.steps = currentSteps;
        updatedConfig.total_steps = currentSteps.length;

        // Update the wizard config
        this.wizardConfig = updatedConfig;

        debugInfo('Steps added successfully. New config:', {
            totalSteps: this.wizardConfig.total_steps,
            steps: this.wizardConfig.steps.map(s => ({ number: s.number, label: s.label }))
        });
    }

    handleStepRemove(event) {
        const { stepNumbers } = event.detail;

        debugInfo('Removing steps:', {
            stepNumbers
        });

        if (!stepNumbers || !Array.isArray(stepNumbers) || stepNumbers.length === 0) {
            console.error('Invalid step numbers provided for removal');
            return;
        }

        // Clone the current wizard config to maintain reactivity
        const updatedConfig = { ...this.wizardConfig };
        let currentSteps = [...updatedConfig.steps];

        // Filter out the steps to be removed
        currentSteps = currentSteps.filter(step => !stepNumbers.includes(step.number));

        // Renumber remaining steps to maintain sequence
        currentSteps.forEach((step, index) => {
            step.number = index + 1;
        });

        // Update the total steps count
        updatedConfig.steps = currentSteps;
        updatedConfig.total_steps = currentSteps.length;

        // Update the wizard config
        this.wizardConfig = updatedConfig;

        // Adjust current step if it was removed or is now out of bounds
        if (stepNumbers.includes(this.currentStepNumber) || this.currentStepNumber > currentSteps.length) {
            this.currentStepNumber = Math.min(this.currentStepNumber, currentSteps.length);
            if (this.currentStepNumber < 1 && currentSteps.length > 0) {
                this.currentStepNumber = 1;
            }
        }

        debugInfo('Steps removed successfully. New config:', {
            totalSteps: this.wizardConfig.total_steps,
            currentStep: this.currentStepNumber,
            steps: this.wizardConfig.steps.map(s => ({ number: s.number, label: s.label }))
        });
    }

    /**
     * form-specific: Handle cohort configuration change and inject cohort steps
     * Triggered when user completes Step 4 cohort setup
     * @param {CustomEvent} event - Contains cohortCount and cohortNames
     */
    handleCohortConfigChange(event) {
        const { cohortCount, cohortNames } = event.detail;
        
        debugInfo('Cohort config change received', {
            cohortCount,
            cohortNames,
            currentSteps: this.wizardConfig.steps.length
        });
        
        // Clone the current wizard config to maintain reactivity
        const updatedConfig = { ...this.wizardConfig };
        let currentSteps = [...updatedConfig.steps];
        
        // Remove any existing cohort steps (isCohortStep flag)
        currentSteps = currentSteps.filter(step => !step.isCohortStep);
        
        // Find the cohort setup step (should be step 4)
        const setupStepIndex = currentSteps.findIndex(s => 
            s.sections && s.sections.some(sec => sec.lwcName === 'form-cohort-section')
        );
        
        if (setupStepIndex === -1) {
            debugError('Could not find cohort setup step');
            return;
        }
        
        // Create N cohort steps to insert after the setup step
        const cohortSteps = [];
        for (let i = 0; i < cohortCount; i++) {
            const cohortName = cohortNames[i] || `Cohort ${i + 1}`;
            cohortSteps.push({
                number: 0, // Will be renumbered below
                label: cohortName,
                progressLabel: cohortName,
                description: `Configure details for ${cohortName}`,
                isCohortStep: true,
                hideHeader: false,
                sections: [
                    {
                        name: `cohort_${i}_details`,
                        label: '',
                        isCustom: true,
                        lwcName: 'form-cohort-iterator',
                        cohortIndex: i,
                        cohortName: cohortName,
                        totalCohorts: cohortCount
                    }
                ]
            });
        }
        
        // Insert cohort steps after the setup step
        currentSteps.splice(setupStepIndex + 1, 0, ...cohortSteps);
        
        // Renumber all steps
        currentSteps.forEach((step, index) => {
            step.number = index + 1;
        });
        
        // Update config
        updatedConfig.steps = currentSteps;
        updatedConfig.total_steps = currentSteps.length;
        this.wizardConfig = updatedConfig;
        
        debugSuccess('Cohort steps injected successfully', {
            totalSteps: this.wizardConfig.total_steps,
            cohortSteps: cohortSteps.length,
            stepLabels: this.wizardConfig.steps.map(s => `${s.number}: ${s.label}`)
        });
    }

    // TODO: Refactor this to use a more generic approach for all forms
    // This is a temporary solution for Dynamic Request Forms only
    // Navigation handlers
    async handlePrevious(event) {

        const stepRenderer = this.template.querySelector('c-form-step-renderer');
        
        // Check if this form has cohort steps and is not an onsite form
        const hasCohortSteps = this.wizardConfig?.steps?.some(s => s.isCohortStep === true);
        const isOnsite = this.wizardConfig?.customProperties?.isOnsite === true;
        
        // Priority 1: Check for form cohort-specific navigation (Step 4)
        // Only applies to forms with cohort steps, not onsite forms
        if (!isOnsite && hasCohortSteps && stepRenderer && typeof stepRenderer.handleCohortPrevious === 'function') {
            try {
                const allowStepBack = await stepRenderer.handleCohortPrevious();
                debugInfo('Cohort handlePrevious result:', { allowStepBack });
                
                if (allowStepBack && this.canGoPrevious) {
                    this.moveToPreviousStep();
                } else if (!allowStepBack) {
                    debugInfo('Staying on current step - cohort mini-wizard navigation active');
                }
                return;
            } catch (error) {
                debugError('Error in cohort handlePrevious', error);
            }
        }
        
        // Priority 2: Check for generic custom component navigation (future forms)
        // Skip for onsite forms which use standard navigation
        if (!isOnsite && stepRenderer && typeof stepRenderer.handleCustomPrevious === 'function') {
            try {
                const allowStepBack = await stepRenderer.handleCustomPrevious();
                debugInfo('Custom handlePrevious result:', { allowStepBack });
                
                if (allowStepBack && this.canGoPrevious) {
                    this.moveToPreviousStep();
                } else if (!allowStepBack) {
                    debugInfo('Staying on current step - custom component navigation active');
                }
                return;
            } catch (error) {
                debugError('Error in custom handlePrevious', error);
            }
        }

        // Default behavior when no custom handlers exist
        if (this.canGoPrevious) {
            this.moveToPreviousStep();
            debugInfo('Navigated to previous step');
        }
    }

    async handleNext(event) {
        const stepRenderer = this.template.querySelector('c-form-step-renderer');
        
        // VALIDATION: Validate current step before proceeding
        if (stepRenderer && typeof stepRenderer.validateStep === 'function') {
            const validationResult = stepRenderer.validateStep();
            
            if (!validationResult.isValid) {
                debugWarning('Validation failed - preventing navigation', {
                    errorCount: validationResult.errors.length,
                    errors: validationResult.errors
                });
                
                // Show user-friendly notification
                this.showValidationError(validationResult.errors);
                return; // Stop navigation
            }
            
            // Hide validation banner if visible
            this.hideValidationError();
        }
        
        // Priority 1: Check for form cohort-specific navigation (Step 4)
        // This handles the cohort mini-wizard with multiple internal pages per cohort
        // Only applies to forms with cohort steps (Dynamic Request Form), not onsite forms
        const hasCohortSteps = this.wizardConfig?.steps?.some(s => s.isCohortStep === true);
        const isOnsite = this.wizardConfig?.customProperties?.isOnsite === true;
        
        if (!isOnsite && hasCohortSteps && stepRenderer && typeof stepRenderer.handleCohortNext === 'function') {
            try {
                const allowStepAdvance = await stepRenderer.handleCohortNext();
                debugInfo('Cohort handleNext result:', { allowStepAdvance });
                
                if (allowStepAdvance && this.canGoNext) {
                    this.moveToNextStep();
                } else if (!allowStepAdvance) {
                    debugInfo('Staying on current step - cohort mini-wizard navigation active');
                }
                return;
            } catch (error) {
                debugError('Error in cohort handleNext', error);
            }
        }

        // Priority 2: Check for generic custom component navigation (future forms)
        // Skip for onsite forms which use standard navigation
        if (!isOnsite && stepRenderer && typeof stepRenderer.handleCustomNext === 'function') {
            try {
                const allowStepAdvance = await stepRenderer.handleCustomNext();
                debugInfo('Custom handleNext result:', { allowStepAdvance });
                
                if (allowStepAdvance && this.canGoNext) {
                    this.moveToNextStep();
                } else if (!allowStepAdvance) {
                    debugInfo('Staying on current step - custom component navigation active');
                }
                return;
            } catch (error) {
                debugError('Error in custom handleNext', error);
            }
        }

        // Default behavior when no custom handlers exist
        if (this.canGoNext) {
            this.moveToNextStep();
        }
    }

    moveToNextStep() {
        this.animateStepTransition('next', () => {
            this.currentStepNumber++;
        });
    }

    moveToPreviousStep() {
        this.animateStepTransition('previous', () => {
            this.currentStepNumber--;
        });
    }

    /**
     * Animates the step transition with a slide effect
     * @param {string} direction - 'next' or 'previous'
     * @param {Function} callback - Function to execute after exit animation
     */
    animateStepTransition(direction, callback) {
        this.animationDirection = direction;
        this.isAnimating = true;
        this.animationPhase = 'exiting';

        // Wait for exit animation to complete, then change step
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.animationPhase = 'entering';
            callback();
            // Reset animation state after enter animation completes
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.isAnimating = false;
                this.animationPhase = 'idle';
            }, 350);
        }, 300);
    }

    /**
     * @description Handles Complete button click (last step using Next/Complete flow)
     */
    async handleComplete(event) {
        await this.handleSubmit(event);
    }

    runValidation() {
        const stepRenderer = this.template.querySelector('c-form-step-renderer');
        if (stepRenderer && typeof stepRenderer.validateStep === 'function') {
            const validationResult = stepRenderer.validateStep();
            
            if (!validationResult.isValid) {
                debugWarning('Validation failed', {
                    errorCount: validationResult.errors.length,
                    errors: validationResult.errors
                });
                this.showValidationError(validationResult.errors);
                return false;
            }          
            this.hideValidationError();
        }
        return true;
    }

    async handleSubmit(event) {
        if (this.isSaving) return;

        // Validate before submission
        this.runValidation();

        // Use unified submission handler for all form types
        this.isSaving = true;
        try {
            const result = await apexMethods.submitForm(this.state);

            // Parse response and update sessionName for confirmation page
            if (result) {
                try {
                    const response = typeof result === 'string' ? JSON.parse(result) : result;
                    if (response.sessionName) {
                        this.state.sessionName = response.sessionName;
                        debugInfo('Session name updated from submit response:', response.sessionName);
                    }
                } catch (parseError) {
                    debugError('Error parsing submit response', parseError);
                }
            }

            this.currentStepNumber++;
        } catch (error) {
            debugError('Error submitting form', error);
            this.setErrorCondition();
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * @description Show validation errors to user
     * @param errors Array of validation error objects

     */
    showValidationError(errors) {
        if (!errors || errors.length === 0) {
            return;
        }

        // Log all errors for debugging
        debugError('Validation Errors:', errors);

        // Simple message - no field list
        this.validationMessage = 'Please fill in the required fields before submitting your response.';
        this.showValidationBanner = true;
        
        // Scroll to validation banner (at top of form)
        this.scrollToValidationBanner();
        
        // Also scroll to first error field after banner scroll
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            return Promise.resolve();
        }).then(() => {
            this.scrollToFirstError();
        });
    }
    
    /**
     * @description Hide validation error banner
     */
    hideValidationError() {
        this.showValidationBanner = false;
        this.validationMessage = '';
    }
    
    /**
     * @description Check if all required fields are valid and dismiss banner
     */
    checkAndDismissValidationBanner() {
        const stepRenderer = this.template.querySelector('c-form-step-renderer');
        if (stepRenderer && typeof stepRenderer.validateStep === 'function') {
            const validationResult = stepRenderer.validateStep(true); // true = silent mode
            
            // If all fields are now valid, hide the banner
            if (validationResult.isValid) {
                this.hideValidationError();
            }
        }
    }
    
    /**
     * @description Scroll to validation banner
     */
    scrollToValidationBanner() {
        Promise.resolve().then(() => {
            const banner = this.template.querySelector('.validation-error-banner');
            if (banner) {
                banner.scrollIntoView({ 
                    behavior: 'smooth', 
                    block: 'start' 
                });
            }
        });
    }

    scrollToFirstError() {
        Promise.resolve().then(() => {
            const firstErrorContainer = this.template.querySelector('.has-error');
            if (firstErrorContainer) {
                firstErrorContainer.scrollIntoView({ 
                    behavior: 'smooth', 
                    block: 'center' 
                });
            }
        });
    }

    get currentStep() {
        return this.wizardConfig?.steps 
               ? this.wizardConfig.steps.find(step => step.number === this.currentStepNumber)
               : null;
    }

    get totalSteps() {
        return this.wizardConfig?.steps?.length || 0;
    }

    get isFirstStep() {
        return this.currentStepNumber === 1;
    }

    get isLastStep() {
        return this.currentStepNumber === this.totalSteps;
    }

    get canGoNext() {
        // Hide Next button on review steps (show Submit instead)
        if (this.currentStep?.isReview || this.currentStep?.sections?.some(s => s.isReview)) {
            return false;
        }
        
        // Hide Next on submission confirmation steps
        if (this.currentStep?.isSubmissionMessage) {
            return false;
        }
        
        // Standard navigation: show Next if not on last step
        return this.currentStepNumber < this.totalSteps;
    }

    get canGoPrevious() {
        return this.currentStepNumber > 1;
    }

    get requiresEmailVerification() {
        if (!this.wizardConfig) return false;
        return this.wizardConfig.emailSessionRequired === true;
    }
    
    get allowSaveResume() {
        if (!this.wizardConfig) return false;
        return this.wizardConfig.allow_save_resume === true;
    }

    get showWizardContent() {
        // Show wizard if email verification is not required OR if it's verified
        return !this.requiresEmailVerification || this.isEmailVerified;
    }

    get showProgressBar() {
        return this.wizardConfig?.showProgressBar === true;
    }

    get showSubmit() {
        // Check if current step is a review step
        return this.currentStep?.isReview === true || 
               this.currentStep?.sections?.some(s => s.isReview === true);
    }

    get showNavigation() {
        return this.currentStep?.showNavigation === true || this.currentStep?.showNavigation === undefined;
    }

    get autoSaveIndicatorClass() {
        return this.isAutoSaving
            ? 'auto-save-indicator auto-save-indicator_visible'
            : 'auto-save-indicator';
    }

    get wizardWrapperClass() {
        return this.hasUnexpectedError ? 'wizard-wrapper wizard-wrapper_blurred' : 'wizard-wrapper';
    }

    handleReloadPage() {
        window.location.reload();
    }

    get stepContentClass() {
        if (!this.isAnimating || this.animationPhase === 'idle') {
            return 'step-content step-content_visible';
        }

        if (this.animationPhase === 'exiting') {
            // Exit: slide out in the direction of travel
            return this.animationDirection === 'next'
                ? 'step-content step-content_slide-out-left'
                : 'step-content step-content_slide-out-right';
        }

        if (this.animationPhase === 'entering') {
            // Enter: slide in from the opposite side
            return this.animationDirection === 'next'
                ? 'step-content step-content_slide-in-from-right'
                : 'step-content step-content_slide-in-from-left';
        }

        return 'step-content step-content_visible';
    }

    // ==========================================
    // Help Modal Methods
    // ==========================================

    /**
     * @description Get the help modal configuration from wizard config
     * @returns {Object} Help modal config or empty object
     */
    get helpModalConfig() {
        return this.wizardConfig?.helpModal || {};
    }

    /**
     * @description Check if the help button should be shown
     * @returns {Boolean} True if help button should be displayed
     */
    get showHelpButton() {
        return this.helpModalConfig?.enabled === true;
    }

    /**
     * @description Get the help button label
     * @returns {String} Button label text
     */
    get helpButtonLabel() {
        return this.helpModalConfig?.buttonLabel || 'Need Help?';
    }

    /**
     * @description Get contact information for the help modal
     * @returns {Object} Contact info object with firstName, lastName, company, email
     */
    get contactInfoForModal() {
        return {
            firstName: this.state.answers?.firstName || '',
            lastName: this.state.answers?.lastName || '',
            company: this.state.answers?.organization || '',
            email: this.state.answers?.email || this.state.primaryEmail || ''
        };
    }

    /**
     * @description Open the help modal
     */
    handleOpenHelp() {
        this.showHelpModal = true;
        debugInfo('Help modal opened');
    }

    /**
     * @description Close the help modal
     */
    handleCloseHelp() {
        this.showHelpModal = false;
        debugInfo('Help modal closed');
    }

}