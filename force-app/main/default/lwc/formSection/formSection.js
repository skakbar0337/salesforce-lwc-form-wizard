import { LightningElement, api, track } from 'lwc';
import { debugInfo } from 'c/formUtils';
import formCohortSection from 'c/formCohortSection';
import formShippingSection from 'c/formShippingSection';
import formCohortIterator from 'c/formCohortIterator';

export default class FormSection extends LightningElement {
    @api state;
    @api wizardConfig; // For review section
    @api sectionIndex = 0; // Index for repeatable sections
    componentConstructor;
    @track _sectionData;
    _hiddenQuestions = []; // Store hidden questions for default value initialization
    
    @api
    get sectionData() {
        return this._sectionData;
    }
    set sectionData(value) {
        if (value && value.questions) {
            // Process questions to add column class, filter out hidden questions
            const processedQuestions = value.questions
                .filter(question => !question.hidden) // Filter out hidden questions
                .map(question => {
                    const numColumns = question.num_columns || 2;
                    // For single-checkbox, don't show separate label (it's inline with checkbox)
                    const showLabel = question.type !== 'single-checkbox';
                    return {
                        ...question,
                        columnClass: `grid-item col-span-${numColumns}`,
                        showLabel: showLabel,
                        disabled: question.disabled || false
                    };
                });

            // Store hidden questions separately for default value initialization
            this._hiddenQuestions = value.questions.filter(question => question.hidden);

            // Create a new object to avoid proxy mutation issues
            this._sectionData = {
                ...value,
                questions: processedQuestions
            };
        } else {
            this._sectionData = value;
        }
    }

    connectedCallback() {
        debugInfo('Section Data: ', this.sectionData);

        // if sectionData contains isCustom true and lwcName, dynamically import the component
        if (this.sectionData?.isCustom)
        {
            this.loadCustomComponent();
        }

        // Initialize hidden questions with default values
        this.initializeHiddenQuestions();
    }

    /**
     * Initialize hidden questions with their default values
     * These questions are not rendered but their values need to be stored in answers
     */
    initializeHiddenQuestions() {
        if (!this._hiddenQuestions || this._hiddenQuestions.length === 0) {
            return;
        }

        this._hiddenQuestions.forEach(question => {
            // Only initialize if there's a defaultValue and no existing answer
            if (question.defaultValue !== undefined && question.defaultValue !== null) {
                const existingAnswer = this.answers?.[question.name];
                if (existingAnswer === undefined || existingAnswer === null) {
                    // Dispatch event to store the default value in answers
                    this.dispatchEvent(new CustomEvent('valuechange2', {
                        detail: {
                            question: question.name,
                            value: question.defaultValue,
                            type: question.type,
                            section: this.sectionData?.name
                        },
                        bubbles: true,
                        composed: true
                    }));
                }
            }
        });
    }

    renderedCallback() {
        // Initialize exclusions checkboxes state on first render
        if (this.sectionData?.name === 'exclusions' && this.answers) {
            this.initializeExclusionsState();
        }
    }

    get answers() {
        // If state.answers exists and has data, use it; otherwise use state root level
        const stateAnswers = this.state?.answers || {};
        const hasAnswers = Object.keys(stateAnswers).length > 0;
        return hasAnswers ? stateAnswers : (this.state || {});
    }

    get customComponentProps() {
        return {
            state: this.state,
            answers: this.answers,
            cohortIndex: this.sectionData?.cohortIndex,
            cohortName: this.sectionData?.cohortName,
            totalCohorts: this.sectionData?.totalCohorts
        };
    }

    /**
     * Initialize the state of exclusion checkboxes based on current answers
     * Disable checkboxes if "No" is selected in the radio button
     */
    initializeExclusionsState() {
        const exclusionsRadioValue = this.state['exclusionsRadio'];
        
        if (exclusionsRadioValue === 'no' && this._sectionData && this._sectionData.questions) {
            const checkboxes = ['exclusionA', 'exclusionB', 'exclusionC'];
           // Guard: skip if checkboxes are already disabled to avoid infinite re-render loop
            const alreadyDisabled = this._sectionData.questions
                .filter(q => checkboxes.includes(q.name))
                .every(q => q.disabled === true);

            if (alreadyDisabled) {
                return;
            } 
            // Update the questions array with disabled state
            this._sectionData = {
                ...this._sectionData,
                questions: this._sectionData.questions.map(q => {
                    if (checkboxes.includes(q.name)) {
                        return {
                            ...q,
                            disabled: true
                        };
                    }
                    return q;
                })
            };
        }
    }

    loadCustomComponent() { 
        const lwcName = this.sectionData.lwcName;
        
        // Map of custom component names - using static imports
        const componentMap = {
            'form-cohort-section': formCohortSection,
            'form-shipping-section': formShippingSection,
            'form-cohort-iterator': formCohortIterator
        };

        const ctor = componentMap[lwcName];
        
        if (ctor) {
            this.componentConstructor = ctor;
        } else {
            console.error('Unknown custom component:', lwcName);
        }
    }

    get isReviewSection() {
        return this.sectionData?.isReview === true;
    }

    get reviewData() {
        if (!this.isReviewSection || !this.wizardConfig?.steps) {
            return [];
        }

        const reviewSteps = [];
        
        // Iterate through all steps except Review step
        this.wizardConfig.steps.forEach(step => {
            if (step.label === 'Review' || !step.sections || step.sections.length === 0) {
                return;
            }

            const stepReview = {
                stepLabel: step.label,
                sections: []
            };

            step.sections.forEach(section => {
                // Handle custom sections (e.g., cohort data)
                if (section.isCustom) {
                    // Check if this is the Study Cohorts section
                    if (section.lwcName === 'form-cohort-section') {
                        const cohortSections = this.buildCohortReviewData();
                        stepReview.sections.push(...cohortSections);
                    }
                    // Check if this is shipping section
                    else if (section.lwcName === 'form-shipping-section') {
                        const shippingSections = this.buildShippingReviewData();
                        if (shippingSections.length > 0) {
                            stepReview.sections.push(...shippingSections);
                        }
                    }
                    return;
                }

                if (!section.questions || section.questions.length === 0) {
                    return;
                }

                const sectionReview = {
                    sectionLabel: section.label || '',
                    fields: []
                };

                section.questions.forEach(question => {
                    // Skip display-only fields, hidden fields, and read-only fields with no targetField
                    if (question.type === 'display-text' ||
                        question.hidden ||
                        (question.readOnly && !question.targetField)) {
                        return;
                    }

                    const fieldValue = this.answers[question.name];
                    const displayValue = this.formatFieldValue(fieldValue, question);

                    sectionReview.fields.push({
                        label: question.label,
                        value: displayValue,
                        isEmpty: !fieldValue || fieldValue === ''
                    });
                });

                if (sectionReview.fields.length > 0) {
                    stepReview.sections.push(sectionReview);
                }
            });

            if (stepReview.sections.length > 0) {
                reviewSteps.push(stepReview);
            }
        });

        return reviewSteps;
    }

    buildCohortReviewData() {
        const cohortSections = [];
        const cohortData = {};
        
        // Parse all cohort-prefixed answers
        Object.keys(this.answers).forEach(key => {
            const match = key.match(/^cohort(\d+)_(.+)$/);
            if (match) {
                const cohortIndex = parseInt(match[1], 10);
                const fieldName = match[2];
                
                if (!cohortData[cohortIndex]) {
                    cohortData[cohortIndex] = {};
                }
                cohortData[cohortIndex][fieldName] = this.answers[key];
            }
        });
        
        // Build review sections for each cohort
        Object.keys(cohortData).sort((a, b) => parseInt(a) - parseInt(b)).forEach(cohortIndex => {
            const cohort = cohortData[cohortIndex];
            // Get cohort name from various possible answer keys
            const rawCohortName = this.answers[`cohortName_${cohortIndex}`] ||
                                  this.answers[`cohort_${cohortIndex}_name`] ||
                                  cohort.cohortName ||
                                  '';
            // Format as "Cohort N - Name" or just "Cohort N" if no name provided
            const cohortNumber = parseInt(cohortIndex) + 1;
            const cohortName = rawCohortName
                ? `Cohort ${cohortNumber} - ${rawCohortName}`
                : `Cohort ${cohortNumber}`;
            
            const fields = [];
            
            // Number of participants
            if (cohort.num_participants) {
                fields.push({
                    label: 'Number of Participants',
                    value: cohort.num_participants,
                    isEmpty: false
                });
            }
            
            // Inclusion/Exclusion Criteria
            if (cohort.incl_diag) {
                fields.push({
                    label: 'Inclusion Criteria - Diagnosis',
                    value: cohort.incl_diag,
                    isEmpty: false
                });
            }
            if (cohort.incl_med) {
                fields.push({
                    label: 'Inclusion Criteria - Medications',
                    value: cohort.incl_med,
                    isEmpty: false
                });
            }
            if (cohort.incl_other) {
                fields.push({
                    label: 'Inclusion Criteria - Other',
                    value: cohort.incl_other,
                    isEmpty: false
                });
            }
            if (cohort.excl_diag) {
                fields.push({
                    label: 'Exclusion Criteria - Diagnosis',
                    value: cohort.excl_diag,
                    isEmpty: false
                });
            }
            if (cohort.excl_med) {
                fields.push({
                    label: 'Exclusion Criteria - Medications',
                    value: cohort.excl_med,
                    isEmpty: false
                });
            }
            if (cohort.excl_other) {
                fields.push({
                    label: 'Exclusion Criteria - Other',
                    value: cohort.excl_other,
                    isEmpty: false
                });
            }
            
            // Biospecimens - extract names and details
            const biospecimenData = this.extractBiospecimensWithDetails(cohort);
            if (biospecimenData.length > 0) {
                // Add each biospecimen as a section with its details
                biospecimenData.forEach(bio => {
                    // Add biospecimen name as a header field
                    fields.push({
                        label: bio.name,
                        value: bio.details.length > 0 ? bio.details.join(' | ') : 'Selected',
                        isEmpty: false
                    });
                });
            }
            
            // Viral Screening
            if (cohort.viral_screening) {
                const viralScreeningValue = cohort.viral_screening === 'custom_testing' ? 'Custom Testing' : 'No testing';
                fields.push({
                    label: 'Viral Screening',
                    value: viralScreeningValue,
                    isEmpty: false
                });
                
                if (cohort.viral_screening === 'custom_testing' && cohort.custom_viral_screening) {
                    fields.push({
                        label: 'Custom Viral Screening Details',
                        value: cohort.custom_viral_screening,
                        isEmpty: false
                    });
                }
            }
            
            // Timeline (for Prospective cohorts)
            if (cohort.prosp_timeline_start) {
                fields.push({
                    label: 'Start Date',
                    value: cohort.prosp_timeline_start,
                    isEmpty: false
                });
            }
            if (cohort.prosp_timeline_end) {
                fields.push({
                    label: 'End Date',
                    value: cohort.prosp_timeline_end,
                    isEmpty: false
                });
            }
            
            // Leukopak specific fields
            if (cohort.leuko_condition) {
                fields.push({
                    label: 'Condition',
                    value: cohort.leuko_condition,
                    isEmpty: false
                });
            }
            if (cohort.leuko_disease) {
                fields.push({
                    label: 'Disease Type',
                    value: cohort.leuko_disease,
                    isEmpty: false
                });
            }
            if (cohort.leuko_quantity) {
                fields.push({
                    label: 'Quantity',
                    value: cohort.leuko_quantity,
                    isEmpty: false
                });
            }
            
            if (fields.length > 0) {
                cohortSections.push({
                    sectionLabel: cohortName,
                    fields: fields
                });
            }
        });
        
        return cohortSections;
    }

    extractBiospecimens(cohort) {
        const bioMap = {
            wholeBlood: 'Whole Blood',
            rna: 'RNA',
            dna: 'DNA',
            plasma: 'Plasma',
            serum: 'Serum',
            nkCell: 'NK Cell',
            tCell: 'T Cell',
            bCell: 'B Cell',
            pbmc: 'PBMC',
            rbc: 'RBC',
            bulkPlasma: 'Bulk Plasma',
            buffyCoat: 'Buffy Coat',
            nasalSwabs: 'Nasal Swabs',
            buccalSwabs: 'Buccal Swabs',
            saliva: 'Saliva',
            semen: 'Semen',
            stool: 'Stool',
            urine: 'Urine',
            synovialFluid: 'Synovial Fluid',
            skinPunchBiopsy: 'Skin Punch Biopsy',
            skinTapeStrips: 'Skin Tape Strips',
            sputum: 'Sputum',
            fingernails: 'Fingernails',
            hair: 'Hair',
            other: 'Other'
        };

        const selected = [];
        Object.keys(cohort).forEach(key => {
            const match = key.match(/^(prosp_bio_|leuko_add_)(.+)$/);
            if (match && cohort[key] === true) {
                const bioType = match[2];
                if (bioMap[bioType]) {
                    selected.push(bioMap[bioType]);
                }
            }
        });

        return selected;
    }

    /**
     * Extract biospecimens with their detailed configuration fields
     * Returns array of objects: { name: 'Plasma', bioType: 'plasma', details: ['Volume: 5mL', 'Temp: Ambient'] }
     */
    extractBiospecimensWithDetails(cohort) {
        const bioMap = {
            wholeBlood: 'Whole Blood',
            rna: 'RNA',
            dna: 'DNA',
            plasma: 'Plasma',
            serum: 'Serum',
            nkCell: 'NK Cell',
            tCell: 'T Cell',
            bCell: 'B Cell',
            pbmc: 'PBMC',
            rbc: 'RBC',
            bulkPlasma: 'Bulk Plasma',
            buffyCoat: 'Buffy Coat',
            nasalSwabs: 'Nasal Swabs',
            buccalSwabs: 'Buccal Swabs',
            saliva: 'Saliva',
            semen: 'Semen',
            stool: 'Stool',
            urine: 'Urine',
            synovialFluid: 'Synovial Fluid',
            skinPunchBiopsy: 'Skin Punch Biopsy',
            skinTapeStrips: 'Skin Tape Strips',
            sputum: 'Sputum',
            fingernails: 'Fingernails',
            hair: 'Hair',
            other: 'Other'
        };

        // Field suffixes and their display labels
        const detailFieldMap = {
            '_collection_materials': 'Collection Materials',
            '_volume': 'Volume (mL)',
            '_aliquot_size': 'Aliquot Size',
            '_temperature': 'Temperature',
            '_processing_location': 'Processing Location',
            '_shipping_temp': 'Shipping Temp',
            '_shipping_temperature': 'Shipping Temp',
            '_wb_shipment_temp': 'WB Shipment Temp',
            '_selection_method': 'Selection Method',
            '_blood_volume': 'Blood Volume (mL)',
            '_temperature_options': 'Temperature',
            '_custom_materials': 'Custom Materials',
            '_number': 'Number',
            '_requirements': 'Requirements',
            '_first_void': 'First Void',
            '_processing_required': 'Processing Required',
            '_separate_supernatant': 'Separate Supernatant',
            '_discard_pellet': 'Discard Pellet',
            '_collection_details': 'Collection Details',
            '_details': 'Details',
            '_size': 'Size',
            '_regions': 'Regions',
            '_sample_volume': 'Sample Volume',
            '_materials': 'Materials',
            '_shipping_requirements': 'Shipping Requirements',
            '_collection_type': 'Collection Type'
        };

        const result = [];
        const processedBioTypes = new Set();

        // Find all selected biospecimens
        Object.keys(cohort).forEach(key => {
            const match = key.match(/^(prosp_bio_|leuko_add_)(.+)$/);
            if (match && cohort[key] === true) {
                const bioType = match[2];
                if (bioMap[bioType] && !processedBioTypes.has(bioType)) {
                    processedBioTypes.add(bioType);

                    // Collect details for this biospecimen
                    const details = [];

                    // Look for detail fields in cohort data
                    Object.keys(cohort).forEach(detailKey => {
                        // Check if this key starts with the biospecimen type
                        if (detailKey.startsWith(`${bioType}_`)) {
                            const suffix = detailKey.substring(bioType.length);
                            const label = detailFieldMap[suffix];
                            const value = cohort[detailKey];

                            if (label && value && value !== '' && value !== null && value !== undefined) {
                                details.push(`${label}: ${value}`);
                            }
                        }
                    });

                    result.push({
                        name: bioMap[bioType],
                        bioType: bioType,
                        details: details
                    });
                }
            }
        });

        return result;
    }

    buildShippingReviewData() {
        const sections = [];
        const multipleLocations = this.answers.multipleLocations;

        if (!multipleLocations) {
            return sections;
        }

        if (multipleLocations === 'single') {
            // Single location - add address fields to main section
            const fields = [{
                label: 'Shipping Option',
                value: 'Single Location',
                isEmpty: false
            }];

            this.addAddressFields(fields, this.answers, '');

            if (fields.length > 0) {
                sections.push({
                    sectionLabel: 'Shipping Information',
                    fields: fields
                });
            }
        } else if (multipleLocations === 'multiple') {
            // Multiple locations - discover addresses dynamically (same approach as formShippingSection)
            let addressIndex = 0;

            while (this.hasShippingAddressData(addressIndex)) {
                const prefix = addressIndex === 0 ? '' : `_${addressIndex}`;
                const addressFields = [];
                this.addAddressFields(addressFields, this.answers, prefix);

                if (addressFields.length > 0) {
                    sections.push({
                        sectionLabel: `Shipping Address ${addressIndex + 1}`,
                        fields: addressFields
                    });
                }
                addressIndex++;

                // Safety limit to prevent infinite loops
                if (addressIndex > 10) {
                    break;
                }
            }

            // If no addresses found but multiple was selected, show that info
            if (sections.length === 0) {
                sections.push({
                    sectionLabel: 'Shipping Information',
                    fields: [{
                        label: 'Shipping Option',
                        value: 'Multiple Locations',
                        isEmpty: false
                    }]
                });
            }
        }

        return sections;
    }

    /**
     * Check if shipping address data exists at given index
     */
    hasShippingAddressData(index) {
        const prefix = index === 0 ? '' : `_${index}`;
        return this.answers[`company${prefix}`] ||
               this.answers[`fullName${prefix}`] ||
               this.answers[`address${prefix}`];
    }

    addAddressFields(fields, answers, prefix) {
        const addressFields = [
            { key: `company${prefix}`, label: 'Company Name' },
            { key: `fullName${prefix}`, label: 'Full Name' },
            { key: `address${prefix}`, label: 'Address' },
            { key: `city${prefix}`, label: 'City' },
            { key: `state${prefix}`, label: 'State' },
            { key: `zip${prefix}`, label: 'ZIP Code' },
            { key: `country${prefix}`, label: 'Country' },
            { key: `phone${prefix}`, label: 'Phone' }
        ];

        addressFields.forEach(field => {
            const value = answers[field.key];
            if (value) {
                fields.push({
                    label: field.label,
                    value: value,
                    isEmpty: false
                });
            }
        });
    }

    formatFieldValue(value, question) {
        if (!value || value === '') {
            return '(Not provided)';
        }

        if (Array.isArray(value)) {
            return value.join(', ');
        }

        if (question.type === 'radio' && question.options) {
            const option = question.options.find(opt => opt.value === value);
            return option ? option.label : value;
        }

        if (question.type === 'single-checkbox') {
            return value ? 'Yes' : 'No';
        }

        return value;
    }

    /**
     * Public API to get reference to custom component if this section is custom
     * @returns {Object|null} Custom component instance or null
     */
    @api
    getCustomComponent() {
        if (this.sectionData?.isCustom && this.componentConstructor) {
            return this.template.querySelector('[data-custom-component]');
        }
        return null;
    }

    handleDynamicStepsChange(event) {
        this.dispatchEvent(new CustomEvent('dynamicstepschange', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    /**
     * Handle cohort configuration change and bubble it up
     * Triggered when formCohortSection dispatches cohortconfigchange
     */
    handleCohortConfigChange(event) {
        this.dispatchEvent(new CustomEvent('cohortconfigchange', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    handleValueChange(event) {
        // This is for radio / checkbox / single-checkbox (= valuechange)
        const detail = {
            ...event.detail,
            section: this.sectionData?.name
        };

        // Special handling for BI form exclusions logic
        if (detail.question === 'exclusionsRadio') {
            this.handleExclusionsRadioChange(detail.value);
        }

        this.dispatchEvent(new CustomEvent('valuechange', {
            detail,
            bubbles: true,
            composed: true
        }));
    }

    /**
     * Handle exclusions radio button change for BI form
     * When "no" is selected, disable and uncheck all exclusion checkboxes
     * When "yes" is selected, enable the checkboxes for user selection
     */
    handleExclusionsRadioChange(value) {
        const isYes = value === 'yes';
        
        // Find the checkbox questions and update their disabled state
        const checkboxes = ['exclusionA', 'exclusionB', 'exclusionC'];
        
        if (this._sectionData && this._sectionData.questions) {
            // Update the questions array with new disabled state
            this._sectionData = {
                ...this._sectionData,
                questions: this._sectionData.questions.map(q => {
                    if (checkboxes.includes(q.name)) {
                        return {
                            ...q,
                            disabled: !isYes
                        };
                    }
                    return q;
                })
            };
            
            // If "No" is selected, clear the checkbox values
            if (!isYes) {
                checkboxes.forEach(checkboxName => {
                    // Dispatch event to clear the answer
                    this.dispatchEvent(new CustomEvent('valuechange', {
                        detail: {
                            question: checkboxName,
                            value: false,
                            checked: false,
                            type: 'single-checkbox',
                            section: this.sectionData?.name
                        },
                        bubbles: true,
                        composed: true
                    }));
                });
            }
        }
    }

    handleValueChange2(event) {
        // This is for text / textarea / date / dropdown (= valuechange2)
        const detail = {
            ...event.detail,
            section: this.sectionData?.name
        };

        this.dispatchEvent(new CustomEvent('valuechange2', {
            detail,
            bubbles: true,
            composed: true
        }));
    }

    handleDeleteField(event) {
        const fieldName = event.target.dataset.name;
        this.dispatchEvent(new CustomEvent('deletefield', {
            detail: { 
                fieldName,
                sectionName: this.sectionData.name 
            }
        }));
    }

    get isRepeatable() {
        return this.sectionData?.is_repeatable === 'true' || this.sectionData?.is_repeatable === true;
    }

    get canRemove() {
        return this.isRepeatable && this.sectionIndex > 0;
    }

    get sectionTitle() {
        if (!this.isRepeatable || this.sectionIndex === 0) {
            return this.sectionData?.label || '';
        }
        return `${this.sectionData?.label || 'Address'} ${this.sectionIndex + 1}`;
    }


    /**
     * Public method to validate all dynamic inputs in this section
     * Returns array of validation results
     * @param {boolean} silent - If true, don't show error messages
     * @returns {Array} Array of validation results { isValid: boolean, fieldName: string, errorMessage: string }
     */
    @api
    validateSection(silent = false) {
        // Skip validation for review sections
        if (this.isReviewSection) {
            return [];
        }

        const validationResults = [];

        // For custom sections, call the custom component's validate method if available
        if (this.sectionData?.isCustom) {
            const customComponent = this.getCustomComponent();
            if (customComponent && typeof customComponent.validate === 'function') {
                try {
                    const result = customComponent.validate();
                    if (!result.isValid) {
                        validationResults.push({
                            isValid: false,
                            fieldName: 'customSection',
                            fieldLabel: this.sectionData?.label || 'Section',
                            errorMessage: result.errorMessage || 'Please complete all required fields.'
                        });
                    }
                } catch (error) {
                    console.error('Error validating custom section:', error);
                    validationResults.push({
                        isValid: false,
                        fieldName: 'customSection',
                        fieldLabel: this.sectionData?.label || 'Section',
                        errorMessage: 'Validation error occurred'
                    });
                }
            }
            return validationResults;
        }

        // Query all dynamic input components in this section
        const dynamicInputs = this.template.querySelectorAll('c-dynamic-input');

        dynamicInputs.forEach(input => {
            try {
                const result = input.validate(silent);
                validationResults.push({
                    isValid: result.isValid,
                    fieldName: input.name,
                    fieldLabel: input.label,
                    errorMessage: result.errorMessage
                });
            } catch (error) {
                console.error(`Error validating field ${input.name}:`, error);
                validationResults.push({
                    isValid: false,
                    fieldName: input.name,
                    fieldLabel: input.label,
                    errorMessage: 'Validation error occurred'
                });
            }
        });

        debugInfo(`Section "${this.sectionData?.label}" validation results:`, validationResults);

        return validationResults;
    }

    /**
     * Public method to check if this section has all valid inputs
     * @returns {boolean} True if all inputs are valid
     */
    @api
    isValid() {
        const results = this.validateSection();
        return results.every(result => result.isValid);
    }
}