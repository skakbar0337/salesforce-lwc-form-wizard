import { LightningElement, api, track } from 'lwc';
import { debugInfo, debugError } from 'c/formUtils';

export default class FormCohortSection extends LightningElement {
    // ===== Input from parent =====
    @api state;                     // State object containing answers
    _sessionRestoreEventDispatched = false;

    // Backward compatibility: support both state and answers
    get _answers() {
        return this.state?.answers || this.answers || {};
    }
    
    _legacyAnswers = {};
    
    @api 
    get answers() {
        return this._legacyAnswers;
    }
    set answers(value) {
        const previousStudyType = this._legacyAnswers && this._legacyAnswers.studyType;
        this._legacyAnswers = value;
        
        // Detect study type change and clear cohort data
        if (previousStudyType && this._legacyAnswers && previousStudyType !== this._legacyAnswers.studyType) {
            console.log('Study type changed from', previousStudyType, 'to', this._legacyAnswers.studyType);
            this.clearCohortData();
            // Reset to setup view
            this.setupComplete = false;
            this.currentCohortIndex = 0;
            this.currentPageIndex = 0;
        }
    }

    // ===== Setup view state =====
    @track numberOfCohorts = 1;   // default 1
    @track customCohortNumber = '';
    @track cohortNames = [];
    @track validationError = '';  // Error message for setup validation

    // ===== Internal setup state =====
    @track setupComplete = false;     // false => "Study Cohorts" page
    @track currentCohortIndex = 0;    // Which cohort we're iterating through (0-based)
    @track currentPageIndex = 0;      // Which page within current cohort (0-based)

    // Phase 1: Setup view (cohort count and names)
    // Phase 2: Cohort iteration (internal page navigation)
    
    _isInitialized = false;
    
    connectedCallback() {
        debugInfo('formCohortSection connected', {
            state: this.state,
            answers: this._answers
        });
        
        this.restoreCohortStateFromSession();
    }
    
    renderedCallback() {
        if (!this._isInitialized && this.state) {
            this.restoreCohortStateFromSession();
            this._isInitialized = true;
        }
    }
    
    /**
     * Restore cohort count and names from saved session data
     */
    restoreCohortStateFromSession() {
        // Check for saved cohort count
        const savedCohortCount = this._answers?.numberOfCohorts || this._answers?.cohortCount;
        if (savedCohortCount && savedCohortCount > 0) {
            this.numberOfCohorts = parseInt(savedCohortCount, 10);
            debugInfo('✅ Restored cohort count from session:', this.numberOfCohorts);
        }
        
        // Check for saved cohort names
        const savedCohortNames = this._answers?.cohortNames;
        if (savedCohortNames && Array.isArray(savedCohortNames)) {
            this.cohortNames = [...savedCohortNames];
            debugInfo('✅ Restored cohort names from session:', this.cohortNames);
        } else {
            // Try to restore individual cohort names
            const names = [];
            for (let i = 0; i < this.numberOfCohorts; i++) {
                const name = this._answers[`cohortName_${i}`] || '';
                names.push(name);
            }
            if (names.some(n => n !== '')) {
                this.cohortNames = names;
                debugInfo('✅ Restored individual cohort names:', this.cohortNames);
            }
        }
    }

    // ------------------------------
    // Study type helpers
    // ------------------------------
    get studyType() {
        // studyType can be in state root or in state.answers
        return this.state?.studyType || this.state?.answers?.studyType || this._answers?.studyType;
    }
    get isProspective() {
        const type = this.studyType;
        return type === 'Cohort_Standard' || type === 'Prospective';
    }
    get isLeukopak() {
        const type = this.studyType;
        return type === 'Leukopak';
    }

    // Prospective = 5 pages, Leukopak = 4 pages
    get totalPagesForStudyType() {
        if (this.isProspective) return 5;
        if (this.isLeukopak) return 4;
        // fallback
        return 4;
    }

    get currentCohortNumber() {
        return this.currentCohortIndex + 1;
    }

    get currentCohortName() {
        if (this.cohortNames && this.cohortNames[this.currentCohortIndex]) {
            return this.cohortNames[this.currentCohortIndex];
        }
        return `Cohort ${this.currentCohortNumber}`;
    }

    get showCohortProgress() {
        return this.numberOfCohorts > 1;
    }

    get viralScreeningName() {
        return `viral_screening_cohort_${this.currentCohortIndex}`;
    }
    
    // ------------------------------
    // Shipping assignment helpers
    // ------------------------------
    get isSingleShippingLocation() {
        return this._answers && this._answers.multipleLocations === 'single';
    }
    
    get isMultipleShippingLocations() {
        return this._answers && this._answers.multipleLocations === 'multiple';
    }
    
    /**
     * Get selected biospecimens for current cohort
     */
    get selectedBiospecimenLabels() {
        return this.getSelectedBiospecimensForCohort().map(b => b.label);
    }
    
    get selectedBiospecimenSummary() {
        return this.selectedBiospecimenLabels.join(', ');
    }
    
    /**
     * Get shipping addresses from answers
     */
    get shippingAddresses() {
        const addresses = [];
        let addressIndex = 0;
        
        // Build addresses from saved data
        while (this.hasShippingAddressData(addressIndex)) {
            const suffix = addressIndex === 0 ? '' : `_${addressIndex}`;
            const address = {
                index: addressIndex,
                key: `address-${addressIndex}`,
                title: `Shipping Address ${addressIndex + 1}`,
                company: this.getAnswer(`company${suffix}`) || '',
                fullName: this.getAnswer(`fullName${suffix}`) || '',
                address: this.getAnswer(`address${suffix}`) || '',
                city: this.getAnswer(`city${suffix}`) || '',
                state: this.getAnswer(`state${suffix}`) || '',
                zipCode: this.getAnswer(`zipCode${suffix}`) || '',
                commentsField: `cohort${this.currentCohortIndex}_shipping_comments${suffix}`,
                availableBiospecimens: this.getBiospecimensForAddress(addressIndex)
            };
            
            // Build full address string
            address.fullAddress = [address.address, address.city, address.state, address.zipCode]
                .filter(Boolean).join(', ');
            
            addresses.push(address);
            addressIndex++;
        }
        
        return addresses;
    }
    
    /**
     * Check if shipping address data exists at index
     */
    hasShippingAddressData(index) {
        const suffix = index === 0 ? '' : `_${index}`;
        return this.getAnswer(`company${suffix}`) || 
               this.getAnswer(`fullName${suffix}`) || 
               this.getAnswer(`address${suffix}`);
    }
    
    /**
     * Get available biospecimens for specific address
     */
    getBiospecimensForAddress(addressIndex) {
        const selectedBiospecimens = this.getSelectedBiospecimensForCohort();
        const cohortAssignments = this.biospecimenAssignments[this.currentCohortIndex] || {};
        const assignedToThisAddress = cohortAssignments[addressIndex] || [];
        
        return selectedBiospecimens.map(bio => {
            const isAssignedHere = assignedToThisAddress.includes(bio.value);
            const isAssignedElsewhere = !isAssignedHere && this.isBiospecimenAssignedToOtherAddress(bio.value, addressIndex);
            
            return {
                ...bio,
                key: `bio-${addressIndex}-${bio.value}`,
                checked: isAssignedHere,
                disabled: isAssignedElsewhere,
                containerClass: `biospecimen-checkbox-container ${isAssignedElsewhere ? 'disabled' : ''}`
            };
        });
    }
    
    /**
     * Check if biospecimen is assigned to different address in current cohort
     */
    isBiospecimenAssignedToOtherAddress(biospecimenValue, currentAddressIndex) {
        const cohortAssignments = this.biospecimenAssignments[this.currentCohortIndex] || {};
        
        return Object.entries(cohortAssignments).some(([addressIdx, assignments]) => 
            parseInt(addressIdx, 10) !== currentAddressIndex && 
            assignments && 
            assignments.includes(biospecimenValue)
        );
    }
    
    /**
     * Get selected biospecimens for current cohort from answers
     */
    getSelectedBiospecimensForCohort() {
        const selected = [];
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
        
        // Check biospecimen selections for current cohort
        const prefix = `cohort${this.currentCohortIndex}_`;
        Object.keys(this._answers || {}).forEach(key => {
            if (key.startsWith(prefix) && (key.includes('_prosp_bio_') || key.includes('_leuko_add_'))) {
                const value = this._answers[key];
                // Only include if the value is explicitly TRUE (strict boolean)
                if (value === true) {
                    const bioType = key.split('_').pop();
                    if (bioMap[bioType] && !selected.find(b => b.value === bioType)) {
                        selected.push({
                            value: bioType,
                            label: bioMap[bioType]
                        });
                    }
                } else {
                    debugInfo(`Skipping biospecimen ${key} with value:`, value);
                }
            }
        });
        
        debugInfo('Selected biospecimens for cohort:', {
            cohort: this.currentCohortIndex,
            selected: selected,
            totalAnswerKeys: Object.keys(this._answers || {}).length,
            bioAnswerKeys: Object.keys(this._answers || {}).filter(k => k.startsWith(prefix) && (k.includes('_prosp_bio_') || k.includes('_leuko_add_'))),
            bioAnswerValues: Object.keys(this._answers || {})
                .filter(k => k.startsWith(prefix) && (k.includes('_prosp_bio_') || k.includes('_leuko_add_')))
                .map(k => ({ key: k, value: this._answers[k] }))
        });
        
        return selected;
    }

    // ------------------------------
    // Which big view?
    // ------------------------------
    get showSetupView() {
        return !this.setupComplete;
    }

    get showCohortPages() {
        return this.setupComplete;
    }

    // ------------------------------
    // Biospecimen checkbox getters (for current cohort)
    // ------------------------------
    get prospBioWholeBloodChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_wholeBlood`) === true;
    }
    get prospBioRnaChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_rna`) === true;
    }
    get prospBioDnaChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_dna`) === true;
    }
    get prospBioTCellChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_tCell`) === true;
    }
    get prospBioBCellChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_bCell`) === true;
    }
    get prospBioNkCellChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_nkCell`) === true;
    }
    get prospBioPbmcChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_pbmc`) === true;
    }
    get prospBioRbcChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_rbc`) === true;
    }
    get prospBioPlasmaChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_plasma`) === true;
    }
    get prospBioSerumChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_serum`) === true;
    }
    get prospBioBulkPlasmaChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_bulkPlasma`) === true;
    }
    get prospBioBuffyCoatChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_buffyCoat`) === true;
    }
    get prospBioNasalSwabsChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_nasalSwabs`) === true;
    }
    get prospBioBuccalSwabsChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_buccalSwabs`) === true;
    }
    get prospBioSalivaChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_saliva`) === true;
    }
    get prospBioSemenChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_semen`) === true;
    }
    get prospBioStoolChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_stool`) === true;
    }
    get prospBioUrineChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_urine`) === true;
    }
    get prospBioSynovialFluidChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_synovialFluid`) === true;
    }
    get prospBioSkinPunchBiopsyChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_skinPunchBiopsy`) === true;
    }
    get prospBioSkinTapeStripsChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_skinTapeStrips`) === true;
    }
    get prospBioSputumChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_sputum`) === true;
    }
    get prospBioFingernailsChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_fingernails`) === true;
    }
    get prospBioHairChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_hair`) === true;
    }
    get prospBioOtherChecked() {
        return this.getAnswer(`cohort${this.currentCohortIndex}_prosp_bio_other`) === true;
    }

    // ------------------------------
    // Page helpers
    // ------------------------------
    get isPage1() {
        return this.currentPageIndex === 0;
    }

    get isPage2Prospective() {
        return this.isProspective && this.currentPageIndex === 1;
    }

    get isPage2Leukopak() {
        return this.isLeukopak && this.currentPageIndex === 1;
    }

    get isPage3() {
        // Common ΓÇ£Biospecimen TypesΓÇ¥ page
        return this.currentPageIndex === 2;
    }

    get isPage4Prospective() {
        // Timeline for Prospective only
        return this.isProspective && this.currentPageIndex === 3;
    }

    get isShippingAssignmentPage() {
        // Leukopak: page index 3 (4th page)
        // Prospective: page index 4 (5th page)
        return (this.isLeukopak && this.currentPageIndex === 3)
            || (this.isProspective && this.currentPageIndex === 4);
    }

    // ------------------------------
    // Radio options & cohort inputs
    // ------------------------------
    get cohortOptions() {
        const currentValue = String(this.numberOfCohorts);
        return [
            { label: '1 cohort', value: '1', checked: currentValue === '1' },
            { label: '2 cohorts', value: '2', checked: currentValue === '2' },
            { label: '3 cohorts', value: '3', checked: currentValue === '3' },
            { label: '4 cohorts', value: '4', checked: currentValue === '4' }
        ];
    }

    get showCohortNames() {
        return this.numberOfCohorts > 0;
    }

    get cohortInputs() {
        const inputs = [];
        for (let i = 0; i < this.numberOfCohorts; i++) {
            inputs.push({
                number: i + 1,
                index: i,
                value: this.cohortNames[i] || '',
                placeholder: 'e.g., Healthy Controls, Disease Group'
            });
        }
        return inputs;
    }

    // =====================================================
    // PUBLIC API: called from formWizardContainer via Step 4
    // =====================================================

    @api
    async handleNext() {
        debugInfo('formCohortSection.handleNext - Setup phase', {
            setupComplete: this.setupComplete,
            numberOfCohorts: this.numberOfCohorts,
            cohortNames: this.cohortNames
        });

        // This component now only handles the setup view (Phase 1)
        // Validate setup and allow progression to next step
        if (!this.setupComplete) {
            const valid = this.validateSetup();
            debugInfo('Setup validation result:', {
                valid,
                numberOfCohorts: this.numberOfCohorts,
                cohortNames: this.cohortNames,
                cohortNamesLength: this.cohortNames.length
            });
            
            if (!valid) {
                debugError('Cohort setup validation failed - please ensure all cohort names are filled in');
                this.validationError = 'Please provide a name for each cohort before continuing.';
                return false; // stay on setup step
            }

            debugInfo('Validation passed - setup complete, triggering cohort step injection');
            this.validationError = ''; // Clear any previous errors
            this.setupComplete = true;
            
            // Emit event to trigger dynamic cohort step injection
            this.dispatchCohortConfigChange();
            
            debugInfo('Setup complete, allowing step progression');
            
            // Allow progression to first cohort step
            return true;
        }

        // If setup already complete, allow progression
        return true;
    }

    /**
     * Public validation method called by formSection
     * Validates cohort names are filled in
     * @returns {Object} { isValid: boolean, errorMessage: string }
     */
    @api
    validate() {
        // Only validate if setup is not complete (user is on cohort naming step)
        if (this.setupComplete) {
            return { isValid: true, errorMessage: '' };
        }

        const valid = this.validateSetup();

        if (!valid) {
            this.validationError = 'Please provide a name for each cohort before continuing.';
            return {
                isValid: false,
                errorMessage: 'Please provide a name for each cohort.'
            };
        }

        this.validationError = '';
        return { isValid: true, errorMessage: '' };
    }

    @api
    async handlePrevious() {
        debugInfo('formCohortSection.handlePrevious', {
            setupComplete: this.setupComplete,
            currentCohortIndex: this.currentCohortIndex,
            currentPageIndex: this.currentPageIndex
        });

        // If still on setup page, let outer step go back normally
        if (!this.setupComplete) {
            return true;
        }

        // If weΓÇÖre not on the first page of this cohort, just go back one page
        if (this.currentPageIndex > 0) {
            this.currentPageIndex--;
            return false;
        }

        // We are at first page for current cohort
        if (this.currentCohortIndex > 0) {
            // Go back to previous cohort, last page
            this.currentCohortIndex--;
            this.currentPageIndex = this.totalPagesForStudyType - 1;
            return false;
        }

        // We are at Cohort 1, Page 1 ΓåÆ go back to setup screen
        this.setupComplete = false;
        return false;
    }

    // =====================================================
    // Setup logic (number of cohorts & names)
    // =====================================================

    handleCohortNumberChange(event) {
        const value = parseInt(event.detail.value, 10) || 1;
        this.numberOfCohorts = value;
        this.customCohortNumber = '';
        this.updateCohortNames();
    }

    handleCustomNumberInput(event) {
        let value = parseInt(event.target.value, 10);

        if (isNaN(value) || value < 1) {
            this.customCohortNumber = '';
            return;
        }

        if (value > 10) {
            value = 10;
            event.target.value = 10;
        }

        this.customCohortNumber = value;
        this.numberOfCohorts = value;
        this.updateCohortNames();
    }

    handleCohortNameInput(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = event.target.value;

        this.cohortNames = [...this.cohortNames];
        this.cohortNames[index] = value;
        this.updateCohortNames();
        
        // Clear validation error when user starts typing
        if (this.validationError) {
            this.validationError = '';
        }
    }

    updateCohortNames() {
        // Ensure cohortNames array has exactly numberOfCohorts elements
        const newCohortNames = [];
        for (let i = 0; i < this.numberOfCohorts; i++) {
            newCohortNames[i] = this.cohortNames[i] || '';
        }
        this.cohortNames = newCohortNames;
        
        debugInfo('Cohort names updated', {
            numberOfCohorts: this.numberOfCohorts,
            cohortNames: this.cohortNames
        });
        
        this.dispatchChangeEvent();
        
        // Only dispatch cohort config change if we have valid data
        if (this.numberOfCohorts > 0 && this.cohortNames.length > 0) {
            this.dispatchCohortConfigChange();
        }
    }

    validateSetup() {
        if (!this.numberOfCohorts || this.numberOfCohorts < 1) {
            this.numberOfCohorts = 1;
        }
        if (this.numberOfCohorts > 10) {
            this.numberOfCohorts = 10;
        }

        debugInfo('Validating setup:', {
            numberOfCohorts: this.numberOfCohorts,
            cohortNames: this.cohortNames,
            cohortNamesLength: this.cohortNames ? this.cohortNames.length : 0
        });

        // Simple validation: require a name for each cohort
        for (let i = 0; i < this.numberOfCohorts; i++) {
            const name = (this.cohortNames[i] || '').trim();
            debugInfo(`Validating cohort ${i + 1}:`, { name, isEmpty: !name });
            if (!name) {
                debugError(`Cohort ${i + 1} has no name - validation failed`);
                return false;
            }
        }
        
        debugInfo('All cohort names validated successfully');
        return true;
    }

    dispatchChangeEvent() {
        // Save cohort count
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                question: 'numberOfCohorts',
                value: this.numberOfCohorts
            },
            bubbles: true,
            composed: true
        }));
        
        // Save cohort count (alternative key)
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                question: 'cohortCount',
                value: this.numberOfCohorts
            },
            bubbles: true,
            composed: true
        }));
        
        // Save cohort names array
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                question: 'cohortNames',
                value: this.cohortNames
            },
            bubbles: true,
            composed: true
        }));
        
        // Save individual cohort names for backward compatibility
        for (let i = 0; i < this.numberOfCohorts; i++) {
            this.dispatchEvent(new CustomEvent('valuechange', {
                detail: {
                    question: `cohortName_${i}`,
                    value: this.cohortNames[i] || ''
                },
                bubbles: true,
                composed: true
            }));
        }
        
        // Also dispatch cohortchange event for other listeners
        this.dispatchEvent(new CustomEvent('cohortchange', {
            detail: {
                numberOfCohorts: this.numberOfCohorts,
                cohortNames: this.cohortNames
            },
            bubbles: true,
            composed: true
        }));
    }

    // =====================================================
    // Answer helpers for per-cohort pages
    // =====================================================

    getAnswer(key) {
        return this._answers && this._answers[key] ? this._answers[key] : '';
    }

    clearCohortData() {
        console.log('Clearing all cohort-related data');
        
        // Clear all cohort fields for all possible cohorts (0-9)
        const cohortFields = [
            // Common fields
            'incl_diag', 'incl_med', 'incl_other',
            'excl_diag', 'excl_med', 'excl_other',
            // Biospecimen types
            'prosp_bio_ma', 'prosp_bio_rbc', 'prosp_bio_wholeBlood', 'prosp_bio_nkCell',
            'prosp_bio_bCell', 'prosp_bio_pbmc', 'prosp_bio_nasalSwabs', 'prosp_bio_urine',
            'prosp_bio_stool', 'prosp_bio_fingernails', 'prosp_bio_other',
            // Timeline (Prospective only)
            'timeline_start', 'timeline_end',
            // Viral screening
            'viral_screening'
        ];
        
        for (let cohortIdx = 0; cohortIdx < 10; cohortIdx++) {
            cohortFields.forEach(field => {
                const questionKey = `cohort${cohortIdx}_${field}`;
                this.dispatchEvent(new CustomEvent('valuechange2', {
                    detail: {
                        question: questionKey,
                        value: ''
                    },
                    bubbles: true,
                    composed: true
                }));
            });
        }
    }

    // Generic text input handler for inner pages
    handleFieldInput(event) {
        const question = event.target.dataset.question;
        const value = event.target.value;
        
        // Include cohort index in question key to prevent data collision
        const questionKey = `cohort${this.currentCohortIndex}_${question}`;

        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                step: 4,
                section: 'cohortDetails',
                question: questionKey,
                value,
                cohortIndex: this.currentCohortIndex,
                cohortName: this.currentCohortName
            },
            bubbles: true,
            composed: true
        }));
    }

    handleCheckboxChange(event) {
        const question = event.target.dataset.question;
        const value = event.target.checked;
        
        // Include cohort index in question key to prevent data collision
        const questionKey = `cohort${this.currentCohortIndex}_${question}`;
        
        // Only dispatch if the value actually changed from what's stored
        const currentValue = this.getAnswer(questionKey);
        if (currentValue === value) {
            // Value hasn't changed, this is likely a programmatic update, skip
            console.log('Checkbox change ignored (no value change):', questionKey, value);
            return;
        }

        console.log('Field changed:', questionKey, value);

        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                step: 4,
                section: 'cohortDetails',
                question: questionKey,
                value,
                cohortIndex: this.currentCohortIndex,
                cohortName: this.currentCohortName
            },
            bubbles: true,
            composed: true
        }));
    }

    dispatchCohortConfigChange() {
        const cohortCount = this.numberOfCohorts;      // 1–10
        const cohortNames = this.cohortNames || [];    // ['hh', 'hgds', ...]

        debugInfo('🔔 Dispatching cohortconfigchange event', {
            cohortCount,
            cohortNames,
            isSessionRestore: !this._sessionRestoreEventDispatched && this._isInitialized
        });

        this.dispatchEvent(
            new CustomEvent('cohortconfigchange', {
                detail: {
                    cohortCount,
                    cohortNames
                },
                bubbles: true,
                composed: true
            })
        );
        
        // Mark that we've dispatched the session restore event
        if (!this._sessionRestoreEventDispatched) {
            this._sessionRestoreEventDispatched = true;
            debugInfo('✅ Session restore event dispatched - flag set');
        }
    }
    
    /**
     * Handle biospecimen assignment to shipping addresses
     */
    handleBiospecimenAssignment(event) {
        const addressIndex = parseInt(event.target.dataset.addressIndex, 10);
        const biospecimenValue = event.target.dataset.biospecimen;
        const isChecked = event.target.checked;
        
        debugInfo('Biospecimen assignment:', {
            cohort: this.currentCohortIndex,
            address: addressIndex,
            biospecimen: biospecimenValue,
            checked: isChecked
        });
        
        // Initialize structures if needed
        if (!this.biospecimenAssignments[this.currentCohortIndex]) {
            this.biospecimenAssignments[this.currentCohortIndex] = {};
        }
        if (!this.biospecimenAssignments[this.currentCohortIndex][addressIndex]) {
            this.biospecimenAssignments[this.currentCohortIndex][addressIndex] = [];
        }
        
        const cohortAssignments = this.biospecimenAssignments[this.currentCohortIndex];
        
        if (isChecked) {
            // Add to this address's assignments
            if (!cohortAssignments[addressIndex].includes(biospecimenValue)) {
                cohortAssignments[addressIndex].push(biospecimenValue);
            }
        } else {
            // Remove from this address's assignments
            cohortAssignments[addressIndex] = cohortAssignments[addressIndex].filter(b => b !== biospecimenValue);
        }
        
        // Save to answers
        const suffix = addressIndex === 0 ? '' : `_${addressIndex}`;
        const fieldName = `cohort${this.currentCohortIndex}_biospecimens${suffix}`;
        
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                step: 4,
                section: 'cohortDetails',
                question: fieldName,
                value: JSON.stringify(cohortAssignments[addressIndex]),
                cohortIndex: this.currentCohortIndex
            },
            bubbles: true,
            composed: true
        }));
        
        // Force re-render to update disabled states
        this.biospecimenAssignments = { ...this.biospecimenAssignments };
    }
    
    /**
     * Handle shipping comments for specific address
     */
    handleShippingComments(event) {
        const value = event.target.value;
        const question = event.target.dataset.question;
        
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                step: 4,
                section: 'cohortDetails',
                question: question,
                value: value,
                cohortIndex: this.currentCohortIndex
            },
            bubbles: true,
            composed: true
        }));
    }
    
    /**
     * Auto-assign all biospecimens to single location
     */
    autoAssignBiospecimensForSingleLocation() {
        if (!this.isSingleShippingLocation) {
            return;
        }
        
        const selectedBiospecimens = this.getSelectedBiospecimensForCohort();
        const biospecimenValues = selectedBiospecimens.map(b => b.value);
        
        // Initialize if needed
        if (!this.biospecimenAssignments[this.currentCohortIndex]) {
            this.biospecimenAssignments[this.currentCohortIndex] = {};
        }
        
        // Assign all to address 0
        this.biospecimenAssignments[this.currentCohortIndex][0] = biospecimenValues;
        
        // Save to answers
        const fieldName = `cohort${this.currentCohortIndex}_biospecimens`;
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                step: 4,
                section: 'cohortDetails',
                question: fieldName,
                value: JSON.stringify(biospecimenValues),
                cohortIndex: this.currentCohortIndex
            },
            bubbles: true,
            composed: true
        }));
        
        debugInfo('Auto-assigned all biospecimens to single location', {
            cohort: this.currentCohortIndex,
            biospecimens: biospecimenValues
        });
    }
}