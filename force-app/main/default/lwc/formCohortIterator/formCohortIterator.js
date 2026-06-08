import { LightningElement, api, track } from 'lwc';
import { debugInfo } from 'c/formUtils';

/**
 * form-specific component that handles iterative pages for a single cohort
 * This component is instantiated once per cohort step in the main wizard
 * It manages the internal page navigation within a cohort's multi-page form
 */
export default class FormCohortIterator extends LightningElement {
    // ===== Input from parent =====
    @api cohortIndex = 0;           // Which cohort (0-based)
    @api cohortName = '';           // Display name for this cohort
    @api totalCohorts = 1;          // Total number of cohorts
    
    _state;
    @api 
    get state() {
        return this._state;
    }
    set state(value) {
        this._state = value;
        // Force reactivity for checkbox getters when state changes
        this._stateVersion = (this._stateVersion || 0) + 1;
    }
    
    @track _stateVersion = 0; // Used to trigger getter re-evaluation
    
    // Backward compatibility: support both state and answers
    get _answers() {
        // Reference _stateVersion to ensure this getter recalculates when state changes
        const version = this._stateVersion; // eslint-disable-line no-unused-vars
        
        // If state.answers exists and has data, use it; otherwise use state root level
        const stateAnswers = this._state?.answers || {};
        const hasAnswers = Object.keys(stateAnswers).length > 0;
        if (hasAnswers) {
            return stateAnswers;
        }
        // Fall back to state root level or legacy answers prop
        return this._state || this.answers || {};
    }
    
    _legacyAnswers = {};
    
    @api 
    get answers() {
        return this._legacyAnswers;
    }
    set answers(value) {
        this._legacyAnswers = value;
    }

    // ===== Internal page state =====
    @track currentPageIndex = 0;    // 0-based within cohort
    
    // ===== Biospecimen assignment tracking =====
    @track biospecimenAssignments = {}; // { addressIndex: [biospecimenValues] }
    
    // ===== Copy configuration tracking =====
    @track selectedCohortToCopyFrom = '';
    @track _forceRerender = 0;

    // ===== Validation error tracking for Leukopak fields =====
    @track leukoFieldErrors = {
        leuko_quantity: '',
        leuko_condition: '',
        leuko_type: '',
        leuko_size: ''
    };

    // ===== Validation error tracking for Biospecimen Page 3 fields =====
    @track biospecimenFieldErrors = {
        // Nasal Swabs
        nasalSwabs_collection_materials: '',
        nasalSwabs_temperature: '',
        nasalSwabs_number: '',
        // Buccal Swabs
        buccalSwabs_collection_materials: '',
        buccalSwabs_temperature: '',
        buccalSwabs_number: '',
        // Synovial Fluid (except details)
        synovialFluid_volume: '',
        synovialFluid_temperature: '',
        synovialFluid_aliquot_size: '',
        // Skin Punch Biopsy (except details)
        skinPunchBiopsy_number: '',
        skinPunchBiopsy_size: '',
        skinPunchBiopsy_temperature: '',
        // Skin Tape Strips
        skinTapeStrips_collection_materials: '',
        skinTapeStrips_number: '',
        skinTapeStrips_temperature: '',
        skinTapeStrips_regions: '',
        // Sputum
        sputum_collection_materials: '',
        sputum_temperature: '',
        // Fingernails
        fingernails_collection_materials: '',
        fingernails_temperature: '',
        // Hair
        hair_collection_materials: '',
        hair_temperature: ''
    };

    // ===== Biospecimen selection error (at least one must be selected) =====
    @track biospecimenSelectionError = '';

    connectedCallback() {
        
        const savedPageIndex = this.getAnswer(`cohort${this.cohortIndex}_currentPageIndex`);
        
        if (savedPageIndex !== '' && savedPageIndex !== null && savedPageIndex !== undefined) {
            debugInfo('⚠️ Found saved page index, but ignoring to start at page 0', { 
                savedPageIndex: savedPageIndex,
                cohortIndex: this.cohortIndex
            });
        }
        
        // Always start at page 0
        this.currentPageIndex = 0;
        
        debugInfo('formCohortIterator connected', {
            cohortIndex: this.cohortIndex,
            cohortName: this.cohortName,
            currentPageIndex: this.currentPageIndex,
            studyType: this.studyType,
            isProspective: this.isProspective,
            isLeukopak: this.isLeukopak
        });
    }
    
    renderedCallback() {
        // Restore dropdowns and inputs from state
        this.restoreInputValues();
        this.restoreDropdownValues();
    }
    
    /**
     * Restore dropdown selected values from state
     * LWC doesn't support value binding on select elements, so we set them programmatically
     */
    restoreDropdownValues() {
        const selects = this.template.querySelectorAll('select[data-question]');
        selects.forEach(select => {
            const question = select.dataset.question;
            const questionKey = `cohort${this.cohortIndex}_${question}`;
            const savedValue = this.getAnswer(questionKey);
            
            if (savedValue && select.value !== savedValue) {
                select.value = savedValue;
            }
        });
    }
    
    /**
     * Restore input field values from state
     * Only restores if the field is not currently focused (to avoid interrupting user input)
     */
    restoreInputValues() {
        const activeElement = this.template.activeElement || document.activeElement;

        const inputs = this.template.querySelectorAll('input[data-question][type="number"], input[data-question][type="text"]');
        inputs.forEach(input => {
            // Skip if this input is currently focused (user is typing)
            if (input === activeElement) {
                return;
            }

            const question = input.dataset.question;
            const questionKey = `cohort${this.cohortIndex}_${question}`;
            const savedValue = this.getAnswer(questionKey);

            if (savedValue && input.value !== savedValue) {
                input.value = savedValue;
            }
        });

        // Restore textareas
        const textareas = this.template.querySelectorAll('textarea[data-question]');
        textareas.forEach(textarea => {
            // Skip if this textarea is currently focused (user is typing)
            if (textarea === activeElement) {
                return;
            }

            const question = textarea.dataset.question;
            const questionKey = `cohort${this.cohortIndex}_${question}`;
            const savedValue = this.getAnswer(questionKey);

            if (savedValue && textarea.value !== savedValue) {
                textarea.value = savedValue;
            }
        });
    }

    /**
     * Synchronize all UI elements with the current state after copy operation
     * This ensures dropdowns, checkboxes, and inputs reflect copied values
     */
    syncUIWithState() {
        debugInfo('Syncing UI with state after copy', { cohortIndex: this.cohortIndex });

        // Sync all select elements
        const selects = this.template.querySelectorAll('select[data-question]');
        selects.forEach(select => {
            const question = select.dataset.question;
            const key = `cohort${this.cohortIndex}_${question}`;
            const value = this.getAnswer(key);
            if (value !== '' && value !== null && value !== undefined) {
                select.value = value;
            }
        });

        // Sync all checkboxes
        const checkboxes = this.template.querySelectorAll('input[type="checkbox"][data-question]');
        checkboxes.forEach(checkbox => {
            const question = checkbox.dataset.question;
            const key = `cohort${this.cohortIndex}_${question}`;
            const savedValue = this.getAnswer(key);
            checkbox.checked = savedValue === true || savedValue === 'true';
        });

        // Sync text/number inputs
        const inputs = this.template.querySelectorAll('input[type="text"][data-question], input[type="number"][data-question]');
        inputs.forEach(input => {
            const question = input.dataset.question;
            const key = `cohort${this.cohortIndex}_${question}`;
            const value = this.getAnswer(key);
            if (value !== undefined && value !== null && value !== '') {
                input.value = value;
            }
        });

        // Sync textareas
        const textareas = this.template.querySelectorAll('textarea[data-question]');
        textareas.forEach(textarea => {
            const question = textarea.dataset.question;
            const key = `cohort${this.cohortIndex}_${question}`;
            const value = this.getAnswer(key);
            if (value !== undefined && value !== null && value !== '') {
                textarea.value = value;
            }
        });

        debugInfo('UI sync completed');
    }
    
    // ------------------------------
    // Study type helpers
    // ------------------------------
    get studyType() {
        // studyType_state?.studyType || this._in state.answers
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

    // Prospective = 4 pages (Timeline moved to separate step), Leukopak = 4 pages
    get totalPagesForStudyType() {
        if (this.isProspective) return 4;
        if (this.isLeukopak) return 4;
        // fallback
        return 4;
    }

    /**
     * Returns a state object scoped to this cohort for c-dynamic-input binding
     * Keys are short names (e.g., 'num_donors') that map to cohort-prefixed values
     * @returns {Object} State object with cohort-scoped answers
     */
    get cohortScopedState() {
        // Reference _stateVersion to ensure this getter recalculates when state changes
        const version = this._stateVersion; // eslint-disable-line no-unused-vars

        const prefix = `cohort${this.cohortIndex}_`;
        const scopedState = {};
        const answers = this._answers || {};

        // Extract cohort-specific answers and remove the prefix from keys
        Object.keys(answers).forEach(key => {
            if (key.startsWith(prefix)) {
                const shortKey = key.substring(prefix.length);
                scopedState[shortKey] = answers[key];
            }
        });

        return scopedState;
    }

    get currentCohortNumber() {
        return this.cohortIndex + 1;
    }

    // =====================================================
    // Options arrays for c-dynamic-input dropdowns
    // =====================================================

    get leukoConditionOptions() {
        return [
            { label: 'Allergies', value: 'Allergies' },
            { label: 'Asthma', value: 'Asthma' },
            { label: 'Atopic Dermatitis', value: 'Atopic Dermatitis' },
            { label: 'Celiac Disease', value: 'Celiac Disease' },
            { label: "Crohn's Disease", value: "Crohn's Disease" },
            { label: 'Healthy', value: 'Healthy' },
            { label: 'Hepatitis B', value: 'Hepatitis B' },
            { label: 'Hidradenitis Suppurativa', value: 'Hidradenitis Suppurativa' },
            { label: 'HIV', value: 'HIV' },
            { label: 'IBD', value: 'IBD' },
            { label: 'Lupus (SLE)', value: 'Lupus (SLE)' },
            { label: 'Multiple Sclerosis', value: 'Multiple Sclerosis' },
            { label: 'Myasthenia Gravis', value: 'Myasthenia Gravis' },
            { label: 'Other', value: 'Other' },
            { label: 'Psoriasis', value: 'Psoriasis' },
            { label: 'Rheumatoid Arthritis', value: 'Rheumatoid Arthritis' },
            { label: 'Scleroderma (Systemic Sclerosis)', value: 'Scleroderma (Systemic Sclerosis)' },
            { label: 'Type 1 Diabetes', value: 'Type 1 Diabetes' },
            { label: 'Ulcerative Colitis', value: 'Ulcerative Colitis' }
        ];
    }

    get leukoSizeOptions() {
        return [
            { label: 'Full (8-10B TNC)', value: 'Full (8-10B TNC)' },
            { label: 'Half (4-6B TNC)', value: 'Half (4-6B TNC)' }
        ];
    }

    get leukoTypeOptions() {
        return [
            { label: 'Overnight fresh leukopak', value: 'Overnight fresh leukopak' },
            { label: 'Cryopreserved leukopak', value: 'Cryopreserved leukopak' }
        ];
    }

    get leukoIsolationTypeOptions() {
        return [
            { label: 'PBMC', value: 'PBMC' },
            { label: 'T-Cell', value: 'T-Cell' },
            { label: 'B-Cell', value: 'B-Cell' },
            { label: 'NK-Cell', value: 'NK-Cell' }
        ];
    }

    get wholeBloodCollectionMaterialsOptions() {
        return [
            { label: 'ACD', value: 'ACD' },
            { label: 'CPT Sodium Citrate', value: 'CPT Sodium Citrate' },
            { label: 'CPT Sodium Heparin', value: 'CPT Sodium Heparin' },
            { label: 'EDTA', value: 'EDTA' },
            { label: 'Lithium Heparin', value: 'Lithium Heparin' },
            { label: 'Sodium Citrate', value: 'Sodium Citrate' },
            { label: 'Sodium Heparin', value: 'Sodium Heparin' },
            { label: 'SST', value: 'SST' },
            { label: 'Custom Blood Materials', value: 'Custom Blood Materials' }
        ];
    }

    get temperatureOptions() {
        return [
            { label: 'Room Temperature', value: 'Room Temperature' },
            { label: 'Refrigerated (2-8°C)', value: 'Refrigerated (2-8°C)' },
            { label: 'Frozen (-20°C)', value: 'Frozen (-20°C)' },
            { label: 'Frozen (-80°C)', value: 'Frozen (-80°C)' },
            { label: 'Dry Ice', value: 'Dry Ice' },
            { label: 'Liquid Nitrogen', value: 'Liquid Nitrogen' }
        ];
    }

    get simpleTemperatureOptions() {
        return [
            { label: 'Ambient', value: 'Ambient' },
            { label: 'Refrigerated', value: 'Refrigerated' },
            { label: 'Frozen (Dry Ice)', value: 'Frozen (Dry Ice)' }
        ];
    }

    get buccalSwabsCollectionMaterialsOptions() {
        return [
            { label: 'Whatman Omni Swabs', value: 'Whatman Omni Swabs' },
            { label: 'Custom Buccal', value: 'Custom Buccal' }
        ];
    }

    get skinPunchBiopsySizeOptions() {
        return [
            { label: '2MM', value: '2mm' },
            { label: '3MM', value: '3mm' }
        ];
    }

    get skinTapeStripsCollectionMaterialsOptions() {
        return [
            { label: 'D-Squame', value: 'D-Squame' },
            { label: 'Custom Tape', value: 'Custom Tape' }
        ];
    }

    get sputumCollectionMaterialsOptions() {
        return [
            { label: 'Urine Collection Cup', value: 'Urine Collection Cup' },
            { label: 'Custom Sputum Collection Materials', value: 'Custom Sputum Collection Mats' }
        ];
    }

    get fingernailsCollectionMaterialsOptions() {
        return [
            { label: 'Standard Collection', value: 'Standard Collection' },
            { label: 'Custom Fingernails', value: 'Custom Fingernails' }
        ];
    }

    get hairCollectionMaterialsOptions() {
        return [
            { label: 'Standard Collection', value: 'Standard Collection' },
            { label: 'Custom Hair', value: 'Custom Hair' }
        ];
    }

    get showCohortProgress() {
        return this.totalCohorts > 1;
    }

    get viralScreeningName() {
        return `viral_screening_cohort_${this.cohortIndex}`;
    }
    
    get isCustomTestingSelected() {
        const viralScreeningValue = this.getAnswer(`cohort${this.cohortIndex}_viral_screening`);
        return viralScreeningValue === 'custom_testing';
    }
    
    get customViralScreeningValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_custom_viral_screening`);
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
                commentsField: `cohort${this.cohortIndex}_shipping_comments${suffix}`,
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
     * Updated: Removed greying logic - same biospecimen can be selected for multiple addresses
     */
    getBiospecimensForAddress(addressIndex) {
        const selectedBiospecimens = this.getSelectedBiospecimensForCohort();
        const assignedToThisAddress = this.biospecimenAssignments[addressIndex] || [];
        
        return selectedBiospecimens.map(bio => {
            const isAssignedHere = assignedToThisAddress.includes(bio.value);
            
            return {
                ...bio,
                key: `bio-${addressIndex}-${bio.value}`,
                checked: isAssignedHere,
                disabled: false,  // Always enabled - allow same biospecimen for multiple addresses
                containerClass: 'biospecimen-checkbox-container'  // No 'disabled' class
            };
        });
    }
    
    /**
     * Check if biospecimen is assigned to different address in current cohort
     */
    isBiospecimenAssignedToOtherAddress(biospecimenValue, currentAddressIndex) {
        return Object.entries(this.biospecimenAssignments).some(([addressIdx, assignments]) => 
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
            leukopak: 'Leukopak',
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

        // For Leukopak study type, always include Leukopak as a shipping option
        if (this.isLeukopak) {
            selected.push({
                value: 'leukopak',
                label: 'Leukopak'
            });
        }

        // Check biospecimen selections for current cohort
        const prefix = `cohort${this.cohortIndex}_`;
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
                }
            }
        });

        return selected;
    }

    // ------------------------------
    // Biospecimen checkbox getters (for current cohort)
    // ------------------------------
    get prospBioWholeBloodChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_wholeBlood`) === true;
    }
    get prospBioRnaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_rna`) === true;
    }
    get prospBioDnaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_dna`) === true;
    }
    get prospBioTCellChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_tCell`) === true;
    }
    get prospBioBCellChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_bCell`) === true;
    }
    get prospBioNkCellChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_nkCell`) === true;
    }
    get prospBioPbmcChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_pbmc`) === true;
    }
    get prospBioRbcChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_rbc`) === true;
    }
    get prospBioPlasmaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_plasma`) === true;
    }
    get prospBioSerumChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_serum`) === true;
    }
    get prospBioBulkPlasmaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_bulkPlasma`) === true;
    }
    get prospBioBuffyCoatChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_buffyCoat`) === true;
    }
    get prospBioNasalSwabsChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_nasalSwabs`) === true;
    }
    get prospBioBuccalSwabsChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_buccalSwabs`) === true;
    }
    get prospBioSalivaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_saliva`) === true;
    }
    get prospBioSemenChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_semen`) === true;
    }
    get prospBioStoolChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_stool`) === true;
    }
    get prospBioUrineChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_urine`) === true;
    }
    get prospBioSynovialFluidChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_synovialFluid`) === true;
    }
    get prospBioSkinPunchBiopsyChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_skinPunchBiopsy`) === true;
    }
    get prospBioSkinTapeStripsChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_skinTapeStrips`) === true;
    }
    get prospBioSputumChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_sputum`) === true;
    }
    get prospBioFingernailsChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_fingernails`) === true;
    }
    get prospBioHairChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_hair`) === true;
    }
    get prospBioOtherChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_prosp_bio_other`) === true;
    }

    // Leukopak additional biospecimen getters
    get leukoAddWholeBloodChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_add_wholeBlood`) === true;
    }

    // Conditional card visibility getters
    get showWholeBloodCardProspective() {
        return this.prospBioWholeBloodChecked;
    }
    
    get showWholeBloodCardLeukopak() {
        return this.leukoAddWholeBloodChecked;
    }

    // Whole Blood field value getters
    get wholeBloodCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_wholeBlood_collection_materials`);
    }
    get wholeBloodVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_wholeBlood_volume`);
    }
    get wholeBloodTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_wholeBlood_temperature`);
    }
    get wholeBloodCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_wholeBlood_custom_materials`);
    }
    get showWholeBloodCustomMaterials() {
        return this.wholeBloodCollectionMaterialsValue === 'Custom Blood Materials';
    }

    // RNA card visibility and field getters
    get showRNACardProspective() {
        return this.prospBioRnaChecked;
    }
    
    get rnaCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rna_collection_materials`);
    }
    get rnaVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rna_volume`);
    }
    get rnaTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rna_temperature`);
    }
    get rnaCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rna_custom_materials`);
    }
    get showRNACustomMaterials() {
        return this.rnaCollectionMaterialsValue === 'Custom RNA Materials';
    }

    // DNA card visibility and field getters
    get showDNACardProspective() {
        return this.prospBioDnaChecked;
    }
    
    get dnaCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_dna_collection_materials`);
    }
    get dnaVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_dna_volume`);
    }
    get dnaTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_dna_temperature`);
    }
    get dnaCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_dna_custom_materials`);
    }
    get showDNACustomMaterials() {
        return this.dnaCollectionMaterialsValue === 'Custom DNA Materials';
    }

    // T Cell card visibility and field getters
    get showTCellCardProspective() {
        return this.prospBioTCellChecked;
    }
    
    get tCellCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_tCell_collection_materials`);
    }
    get tCellVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_tCell_volume`);
    }
    get tCellAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_tCell_aliquot_size`);
    }
    get tCellSelectionMethodValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_tCell_selection_method`);
    }
    get tCellCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_tCell_custom_materials`);
    }
    get showTCellCustomMaterials() {
        return this.tCellCollectionMaterialsValue === 'Custom T Cell Material';
    }
    get showTCellCustomAliquot() {
        return this.tCellAliquotSizeValue === 'Custom T Cell Aliquot Size';
    }
    get tCellCustomAliquotValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_tCell_custom_aliquot_size`);
    }

    // B Cell card visibility and field getters
    get showBCellCardProspective() {
        return this.prospBioBCellChecked;
    }
    
    get bCellCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bCell_collection_materials`);
    }
    get bCellVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bCell_volume`);
    }
    get bCellAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bCell_aliquot_size`);
    }
    get bCellSelectionMethodValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bCell_selection_method`);
    }
    get bCellCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bCell_custom_materials`);
    }
    get showBCellCustomMaterials() {
        return this.bCellCollectionMaterialsValue === 'Custom B Cell Material';
    }
    get showBCellCustomAliquot() {
        return this.bCellAliquotSizeValue === 'Custom B Cell Aliquot Size';
    }
    get bCellCustomAliquotValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bCell_aliquot_size`);
    }

    // NK Cell card visibility and field getters
    get showNKCellCardProspective() {
        return this.prospBioNkCellChecked;
    }
    
    get nkCellCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nkCell_collection_materials`);
    }
    get nkCellVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nkCell_volume`);
    }
    get nkCellAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nkCell_aliquot_size`);
    }
    get nkCellCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nkCell_custom_materials`);
    }
    get showNKCellCustomMaterials() {
        return this.nkCellCollectionMaterialsValue === 'Custom NK Cell Material';
    }
    get showNKCellCustomAliquot() {
        return this.nkCellAliquotSizeValue === 'Custom NK Cell Aliquot Size';
    }
    get nkCellCustomAliquotValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nkCell_aliquot_size`);
    }

    // Leukopak additional PBMC getter
    get leukoAddPBMCChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_add_pbmc`) === true;
    }

    // PBMC card visibility getters
    get showPBMCCardProspective() {
        return this.prospBioPbmcChecked;
    }
    
    get showPBMCCardLeukopak() {
        return this.leukoAddPBMCChecked;
    }
    
    // RBC card visibility getter (Prospective only)
    get showRBCCardProspective() {
        return this.prospBioRbcChecked;
    }

    // PBMC field value getters
    get pbmcCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_pbmc_collection_materials`);
    }
    get pbmcVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_pbmc_volume`);
    }
    get pbmcAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_pbmc_aliquot_size`);
    }
    get pbmcShippingTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_pbmc_shipping_temperature`);
    }
    get pbmcWbShipmentTempValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_pbmc_wb_shipment_temp`);
    }
    get showPBMCCustomMaterial() {
        return this.pbmcCollectionMaterialsValue === 'Custom PBMC Material';
    }
    get pbmcCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_pbmc_custom_materials`);
    }
    get showPBMCCustomAliquot() {
        return this.pbmcAliquotSizeValue === 'Custom PBMC Aliquot';
    }
    get pbmcCustomAliquotValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_pbmc_custom_aliquot_size`);
    }

    // RBC field value getters
    get rbcCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rbc_collection_materials`);
    }
    get rbcBloodVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rbc_blood_volume`);
    }
    get rbcTemperatureOptionsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rbc_temperature_options`);
    }
    get rbcAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rbc_aliquot_size`);
    }
    get rbcCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_rbc_custom_materials`);
    }
    
    // Conditional display for custom RBC materials field
    get showRbcCustomMaterials() {
        const collectionMats = this.rbcCollectionMaterialsValue;
        return collectionMats === 'Custom RBC Material';
    }

    // Plasma checkbox and card visibility
    get leukoAddPlasmaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_add_plasma`) === true;
    }
    get showPlasmaCardProspective() {
        return this.prospBioPlasmaChecked;
    }
    get showPlasmaCardLeukopak() {
        return this.leukoAddPlasmaChecked;
    }

    // Plasma field value getters
    get plasmaCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_plasma_collection_materials`);
    }
    get plasmaVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_plasma_volume`);
    }
    get plasmaAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_plasma_aliquot_size`);
    }
    get plasmaTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_plasma_temperature`);
    }
    get plasmaProcessingLocationValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_plasma_processing_location`);
    }
    get plasmaShippingTempValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_plasma_shipping_temp`);
    }
    get plasmaCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_plasma_custom_materials`);
    }
    get showPlasmaCustomMaterials() {
        return this.plasmaCollectionMaterialsValue === 'Custom Plasma Materials';
    }

    // Serum checkbox and card visibility
    get leukoAddSerumChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_add_serum`) === true;
    }
    get showSerumCardProspective() {
        return this.prospBioSerumChecked;
    }
    get showSerumCardLeukopak() {
        return this.leukoAddSerumChecked;
    }

    // Serum field value getters
    get serumCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_serum_collection_materials`);
    }
    get serumVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_serum_volume`);
    }
    get serumAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_serum_aliquot_size`);
    }
    get serumTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_serum_temperature`);
    }
    get serumProcessingLocationValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_serum_processing_location`);
    }
    get serumShippingTempValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_serum_shipping_temp`);
    }
    get serumCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_serum_custom_materials`);
    }
    get showSerumCustomMaterials() {
        return this.serumCollectionMaterialsValue === 'Custom Serum Materials';
    }

    // Bulk Plasma checkbox and card visibility
    get leukoAddBulkPlasmaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_add_bulkPlasma`) === true;
    }
    get showBulkPlasmaCardProspective() {
        return this.prospBioBulkPlasmaChecked;
    }
    get showBulkPlasmaCardLeukopak() {
        return this.leukoAddBulkPlasmaChecked;
    }

    // Bulk Plasma field value getters
    get bulkPlasmaVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bulkPlasma_volume`);
    }
    get bulkPlasmaTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_bulkPlasma_temperature`);
    }

    // Buffy Coat card visibility (Prospective only)
    get showBuffyCoatCardProspective() {
        return this.prospBioBuffyCoatChecked;
    }

    // Buffy Coat field value getters
    get buffyCoatCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buffyCoat_collection_materials`);
    }
    get buffyCoatTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buffyCoat_temperature`);
    }
    get buffyCoatVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buffyCoat_volume`);
    }
    get buffyCoatCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buffyCoat_custom_materials`);
    }
    get showBuffyCoatCustomMaterials() {
        return this.buffyCoatCollectionMaterialsValue === 'Custom Buffy Coat Materials';
    }

    // Nasal Swabs card visibility (Prospective only)
    get showNasalSwabsCardProspective() {
        return this.prospBioNasalSwabsChecked;
    }

    // Nasal Swabs field value getters
    get nasalSwabsCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nasalSwabs_collection_materials`);
    }
    get nasalSwabsTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nasalSwabs_temperature`);
    }
    get nasalSwabsNumberValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_nasalSwabs_number`);
    }

    // Buccal Swabs card visibility (Prospective only)
    get showBuccalSwabsCardProspective() {
        return this.prospBioBuccalSwabsChecked;
    }

    // Buccal Swabs field value getters
    get buccalSwabsCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buccalSwabs_collection_materials`);
    }
    get buccalSwabsTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buccalSwabs_temperature`);
    }
    get buccalSwabsNumberValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buccalSwabs_number`);
    }
    get buccalCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_buccal_custom_materials`);
    }
    get showBuccalCustomMaterials() {
        return this.buccalSwabsCollectionMaterialsValue === 'Custom Buccal';
    }

    // Saliva card visibility (Prospective only)
    get showSalivaCardProspective() {
        return this.prospBioSalivaChecked;
    }

    // Saliva field value getters
    get salivaCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_saliva_collection_materials`);
    }
    get salivaVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_saliva_volume`);
    }
    get salivaTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_saliva_temperature`);
    }

    // Semen card visibility (Prospective only)
    get showSemenCardProspective() {
        return this.prospBioSemenChecked;
    }

    // Semen field value getters
    get semenCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_semen_collection_materials`);
    }
    get semenTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_semen_temperature`);
    }
    get semenCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_semen_custom_materials`);
    }
    get showSemenCustomMaterials() {
        return this.semenCollectionMaterialsValue === 'Custom Semen Materials';
    }

    // Stool card visibility (Prospective only)
    get showStoolCardProspective() {
        return this.prospBioStoolChecked;
    }

    // Stool field value getters
    get stoolCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_stool_collection_materials`);
    }
    get stoolTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_stool_temperature`);
    }
    get stoolRequirementsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_stool_requirements`);
    }
    get stoolCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_stool_custom_materials`);
    }
    get showStoolCustomMaterials() {
        return this.stoolCollectionMaterialsValue === 'Custom Stool Collection Mats';
    }

    // Urine card visibility (Prospective only)
    get showUrineCardProspective() {
        return this.prospBioUrineChecked;
    }

    // Urine field value getters
    get urineCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_collection_materials`);
    }
    get urineTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_temperature`);
    }
    get urineAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_aliquot_size`);
    }
    get urineFirstVoidValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_first_void`);
    }
    get urineProcessingRequiredValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_processing_required`);
    }
    get urineSeparateSupernatantValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_separate_supernatant`);
    }
    get urineDiscardPelletValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_discard_pellet`);
    }
    get urineCollectionDetailsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_collection_details`);
    }
    get urineCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_custom_materials`);
    }
    get showUrineCustomMaterials() {
        return this.urineCollectionMaterialsValue === 'Custom Urine Collection Mats';
    }
    get showUrineCustomAliquot() {
        return this.urineAliquotSizeValue === 'Custom Urine Aliquot';
    }
    get urineCustomAliquotValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_urine_custom_aliquot_size`);
    }

    // Synovial Fluid card visibility (Prospective only)
    get showSynovialFluidCardProspective() {
        return this.prospBioSynovialFluidChecked;
    }

    // Synovial Fluid field value getters
    get synovialFluidDetailsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_synovialFluid_details`);
    }
    get synovialFluidVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_synovialFluid_volume`);
    }
    get synovialFluidTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_synovialFluid_temperature`);
    }
    get synovialFluidAliquotSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_synovialFluid_aliquot_size`);
    }

    // Skin Punch Biopsy card visibility (Prospective only)
    get showSkinPunchBiopsyCardProspective() {
        return this.prospBioSkinPunchBiopsyChecked;
    }

    // Skin Punch Biopsy field value getters
    get skinPunchBiopsyNumberValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinPunchBiopsy_number`);
    }
    get skinPunchBiopsySizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinPunchBiopsy_size`);
    }
    get skinPunchBiopsyTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinPunchBiopsy_temperature`);
    }
    get skinPunchBiopsyDetailsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinPunchBiopsy_details`);
    }

    // Skin Tape Strips card visibility (Prospective only)
    get showSkinTapeStripsCardProspective() {
        return this.prospBioSkinTapeStripsChecked;
    }

    // Skin Tape Strips field value getters
    get skinTapeStripsCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinTapeStrips_collection_materials`);
    }
    get skinTapeStripsNumberValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinTapeStrips_number`);
    }
    get skinTapeStripsTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinTapeStrips_temperature`);
    }
    get skinTapeStripsRegionsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_skinTapeStrips_regions`);
    }

    // Sputum card visibility (Prospective only)
    get showSputumCardProspective() {
        return this.prospBioSputumChecked;
    }

    // Sputum field value getters
    get sputumCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_sputum_collection_materials`);
    }
    get sputumTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_sputum_temperature`);
    }
    get sputumCustomMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_sputum_custom_materials`);
    }
    get showSputumCustomMaterials() {
        return this.sputumCollectionMaterialsValue === 'Custom Sputum Collection Mats';
    }

    // Fingernails card visibility (Prospective only)
    get showFingernailsCardProspective() {
        return this.prospBioFingernailsChecked;
    }

    // Fingernails field value getters
    get fingernailsCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_fingernails_collection_materials`);
    }
    get fingernailsTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_fingernails_temperature`);
    }

    // Hair card visibility (Prospective only)
    get showHairCardProspective() {
        return this.prospBioHairChecked;
    }

    // Hair field value getters
    get hairCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_hair_collection_materials`);
    }
    get hairTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_hair_temperature`);
    }

    // Other (Custom Biospecimen) card visibility (Prospective only)
    get showOtherCardProspective() {
        return this.prospBioOtherChecked;
    }

    // Other field value getters
    get otherSampleVolumeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_other_sample_volume`);
    }
    get otherCollectionMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_other_collection_materials`);
    }
    get otherTemperatureValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_other_temperature`);
    }
    get otherMaterialsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_other_materials`);
    }
    get otherShippingRequirementsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_other_shipping_requirements`);
    }
    get otherCollectionTypeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_other_collection_type`);
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
        // Common "Biospecimen Types" page
        return this.currentPageIndex === 2;
    }

    get isShippingAssignmentPage() {
        // Both Leukopak and Prospective: page index 3 (4th page)
        // Timeline is now a separate step in the wizard, not part of cohort pages
        return this.currentPageIndex === 3;
    }

    // =====================================================
    // PUBLIC API: called from formWizardContainer
    // =====================================================

    /**
     * Position at the last page when entering this cohort from a later step (via Previous button)
     * This is called by the parent when navigating backward into this cohort step
     */
    @api
    positionAtLastPage() {
        const lastPageIndex = this.totalPagesForStudyType - 1;
        if (this.currentPageIndex !== lastPageIndex) {
            this.currentPageIndex = lastPageIndex;
            
            // Save to state
            this.dispatchEvent(new CustomEvent('valuechange', {
                detail: {
                    section: 'cohortDetails',
                    question: `cohort${this.cohortIndex}_currentPageIndex`,
                    value: this.currentPageIndex,
                    cohortIndex: this.cohortIndex,
                    cohortName: this.cohortName
                },
                bubbles: true,
                composed: true
            }));
            
            debugInfo('Positioned at last page for backward navigation', { currentPageIndex: this.currentPageIndex });
        }
    }

    @api
    async handleNext() {
        debugInfo('formCohortIterator.handleNext', {
            cohortIndex: this.cohortIndex,
            cohortName: this.cohortName,
            currentPageIndex: this.currentPageIndex,
            totalPages: this.totalPagesForStudyType,
            isPage1: this.isPage1,
            isPage2Prospective: this.isPage2Prospective,
            isPage2Leukopak: this.isPage2Leukopak,
            isPage3: this.isPage3,
            isShippingAssignmentPage: this.isShippingAssignmentPage
        });

        // Validate Page 1 (Inclusion/Exclusion Criteria) - Number of Donors Required
        if (this.isPage1) {
            if (!this.validatePage1Fields()) {
                debugInfo('Validation failed for Page 1 - blocking navigation');
                return false;
            }
        }

        // Validate Leukopak Page 2 required fields before advancing
        if (this.isPage2Leukopak) {
            if (!this.validateLeukoPage2Fields()) {
                debugInfo('Validation failed for Leukopak Page 2 - blocking navigation');
                return false;
            }
        }

        // Validate Prospective Page 2 - Biospecimen Types and details
        if (this.isPage2Prospective) {
            if (!this.validatePage2ProspectiveFields()) {
                debugInfo('Validation failed for Prospective Page 2 - blocking navigation');
                return false;
            }
        }

        // Validate Testing & Screening Page 3 - Viral Screening selection
        if (this.isPage3) {
            if (!this.validatePage3TestingFields()) {
                debugInfo('Validation failed for Testing & Screening Page 3 - blocking navigation');
                return false;
            }
        }

        const lastPageIndex = this.totalPagesForStudyType - 1;

        if (this.currentPageIndex < lastPageIndex) {
            // Move to next page within this cohort
            this.currentPageIndex++;

            // Save currentPageIndex to state
            this.dispatchEvent(new CustomEvent('valuechange', {
                detail: {
                    section: 'cohortDetails',
                    question: `cohort${this.cohortIndex}_currentPageIndex`,
                    value: this.currentPageIndex,
                    cohortIndex: this.cohortIndex,
                    cohortName: this.cohortName
                },
                bubbles: true,
                composed: true
            }));

            debugInfo('After incrementing currentPageIndex', {
                currentPageIndex: this.currentPageIndex,
                isPage1: this.isPage1,
                isPage2Prospective: this.isPage2Prospective,
                isPage2Leukopak: this.isPage2Leukopak,
                isPage3: this.isPage3,
                isShippingAssignmentPage: this.isShippingAssignmentPage
            });
            
            // Auto-assign biospecimens when entering shipping assignment page for single location
            if (this.isShippingAssignmentPage && this.isSingleShippingLocation) {
                this.autoAssignBiospecimensForSingleLocation();
            }
            
            debugInfo('Advanced to next page within cohort', { currentPageIndex: this.currentPageIndex });
            return false; // Stay on current cohort step
        }

        // All pages complete for this cohort → allow progression to next step
        debugInfo('All pages complete for cohort - allowing step progression');
        return true;
    }

    @api
    async handlePrevious() {
        debugInfo('formCohortIterator.handlePrevious', {
            cohortIndex: this.cohortIndex,
            currentPageIndex: this.currentPageIndex
        });

        // If we're not on the first page, go back one page
        if (this.currentPageIndex > 0) {
            this.currentPageIndex--;
            
            // Save currentPageIndex to state
            this.dispatchEvent(new CustomEvent('valuechange', {
                detail: {
                    section: 'cohortDetails',
                    question: `cohort${this.cohortIndex}_currentPageIndex`,
                    value: this.currentPageIndex,
                    cohortIndex: this.cohortIndex,
                    cohortName: this.cohortName
                },
                bubbles: true,
                composed: true
            }));
            
            debugInfo('📄 Moved to previous page within cohort', { 
                cohortIndex: this.cohortIndex,
                cohortName: this.cohortName,
                currentPageIndex: this.currentPageIndex,
                totalPages: this.totalPagesForStudyType
            });
            return false; // Stay on current cohort step
        }

        // We're at the first page of this cohort → allow going back to previous step
        debugInfo('At first page - allowing step back');
        return true;
    }

    // =====================================================
    // Leukopak Page 2 Validation
    // =====================================================

    /**
     * Validate required Leukopak fields on Page 2
     * Uses c-dynamic-input validate() method for converted fields
     * @returns {boolean} True if all required fields are valid
     */
    validateLeukoPage2Fields() {
        let isValid = true;

        // Get all c-dynamic-input components for Leukopak required fields
        const leukoRequiredFields = ['leuko_condition', 'leuko_size', 'leuko_quantity', 'leuko_type'];

        leukoRequiredFields.forEach(fieldName => {
            const inputComponent = this.template.querySelector(`c-dynamic-input[data-question="${fieldName}"]`);
            if (inputComponent && typeof inputComponent.validate === 'function') {
                const result = inputComponent.validate();
                if (!result.isValid) {
                    isValid = false;
                    debugInfo(`Validation failed for ${fieldName}:`, result.errorMessage);
                }
            }
        });

        return isValid;
    }

    // =====================================================
    // Page 1 Validation (Inclusion/Exclusion Criteria)
    // =====================================================

    /**
     * Validate Page 1 fields - Number of Donors Required
     * @returns {boolean} True if all required fields are valid
     */
    validatePage1Fields() {
        let isValid = true;

        // Validate Number of Donors Required field
        const numDonorsInput = this.template.querySelector('c-dynamic-input[data-question="num_donors"]');
        if (numDonorsInput && typeof numDonorsInput.validate === 'function') {
            const result = numDonorsInput.validate();
            if (!result.isValid) {
                isValid = false;
                debugInfo('Validation failed for num_donors:', result.errorMessage);
            }
        }

        return isValid;
    }

    // =====================================================
    // Page 2 Prospective Validation (Biospecimen Types)
    // =====================================================

    /**
     * Validate Page 2 Prospective - at least one biospecimen type selected
     * and all required detail fields for selected types
     * @returns {boolean} True if validation passes
     */
    validatePage2ProspectiveFields() {
        let isValid = true;

        // Check if at least one biospecimen type is selected
        const anyBiospecimenSelected = this.hasAnyBiospecimenSelected;

        if (!anyBiospecimenSelected) {
            // Show error - need to select at least one biospecimen type
            this.biospecimenSelectionError = 'Please select at least one biospecimen type.';
            isValid = false;
            debugInfo('Validation failed: No biospecimen type selected');
        } else {
            this.biospecimenSelectionError = '';
        }

        // Validate detail fields for selected biospecimen types
        if (!this.validateBiospecimenPage3Fields()) {
            isValid = false;
        }

        return isValid;
    }

    /**
     * Check if any biospecimen type is selected
     */
    get hasAnyBiospecimenSelected() {
        return this.prospBioWholeBloodChecked ||
               this.prospBioRnaChecked ||
               this.prospBioDnaChecked ||
               this.prospBioTCellChecked ||
               this.prospBioBCellChecked ||
               this.prospBioNkCellChecked ||
               this.prospBioPbmcChecked ||
               this.prospBioRbcChecked ||
               this.prospBioPlasmaChecked ||
               this.prospBioSerumChecked ||
               this.prospBioBulkPlasmaChecked ||
               this.prospBioBuffyCoatChecked ||
               this.prospBioNasalSwabsChecked ||
               this.prospBioBuccalSwabsChecked ||
               this.prospBioSalivaChecked ||
               this.prospBioSemenChecked ||
               this.prospBioStoolChecked ||
               this.prospBioUrineChecked ||
               this.prospBioSynovialFluidChecked ||
               this.prospBioSkinPunchBiopsyChecked ||
               this.prospBioSkinTapeStripsChecked ||
               this.prospBioSputumChecked ||
               this.prospBioFingernailsChecked ||
               this.prospBioHairChecked ||
               this.prospBioOtherChecked;
    }

    // =====================================================
    // Page 3 Validation (Testing & Screening)
    // =====================================================

    /**
     * Validate Page 3 - Testing & Screening
     * Viral Screening has a default value so this is always valid
     * @returns {boolean} True if validation passes
     */
    validatePage3TestingFields() {
        // Viral Screening has default "no_testing" checked, so always valid
        // Custom Viral Screening textarea is optional per requirements
        return true;
    }

    // =====================================================
    // Biospecimen Detail Fields Validation
    // =====================================================

    /**
     * Validate required biospecimen fields on Page 3
     * Only validates fields for biospecimen types that are selected
     * @returns {boolean} True if all required fields are valid
     */
    validateBiospecimenPage3Fields() {
        let isValid = true;

        // Helper function to validate a c-dynamic-input component by its data-question attribute
        const validateDynamicInput = (fieldName) => {
            const inputComponent = this.template.querySelector(`c-dynamic-input[data-question="${fieldName}"]`);
            if (inputComponent && typeof inputComponent.validate === 'function') {
                const result = inputComponent.validate();
                if (!result.isValid) {
                    isValid = false;
                }
            }
        };

        // Validate Nasal Swabs (if selected)
        if (this.prospBioNasalSwabsChecked) {
            validateDynamicInput('nasalSwabs_collection_materials');
            validateDynamicInput('nasalSwabs_temperature');
            validateDynamicInput('nasalSwabs_number');
        }

        // Validate Buccal Swabs (if selected)
        if (this.prospBioBuccalSwabsChecked) {
            validateDynamicInput('buccalSwabs_collection_materials');
            validateDynamicInput('buccalSwabs_temperature');
            validateDynamicInput('buccalSwabs_number');
            // Validate conditional custom materials field
            if (this.showBuccalCustomMaterials) {
                validateDynamicInput('buccal_custom_materials');
            }
        }

        // Validate Synovial Fluid (if selected)
        if (this.prospBioSynovialFluidChecked) {
            validateDynamicInput('synovialFluid_volume');
            validateDynamicInput('synovialFluid_temperature');
            validateDynamicInput('synovialFluid_aliquot_size');
            // synovialFluid_details is optional, no validation needed
        }

        // Validate Skin Punch Biopsy (if selected)
        if (this.prospBioSkinPunchBiopsyChecked) {
            validateDynamicInput('skinPunchBiopsy_number');
            validateDynamicInput('skinPunchBiopsy_size');
            validateDynamicInput('skinPunchBiopsy_temperature');
            // skinPunchBiopsy_details is optional, no validation needed
        }

        // Validate Skin Tape Strips (if selected)
        if (this.prospBioSkinTapeStripsChecked) {
            validateDynamicInput('skinTapeStrips_collection_materials');
            validateDynamicInput('skinTapeStrips_number');
            validateDynamicInput('skinTapeStrips_temperature');
            validateDynamicInput('skinTapeStrips_regions');
        }

        // Validate Sputum (if selected)
        if (this.prospBioSputumChecked) {
            validateDynamicInput('sputum_collection_materials');
            validateDynamicInput('sputum_temperature');
            // Validate conditional custom materials field
            if (this.showSputumCustomMaterials) {
                validateDynamicInput('sputum_custom_materials');
            }
        }

        // Validate Fingernails (if selected)
        if (this.prospBioFingernailsChecked) {
            validateDynamicInput('fingernails_collection_materials');
            validateDynamicInput('fingernails_temperature');
        }

        // Validate Hair (if selected)
        if (this.prospBioHairChecked) {
            validateDynamicInput('hair_collection_materials');
            validateDynamicInput('hair_temperature');
        }

        return isValid;
    }

    // =====================================================
    // Copy Configuration Feature
    // =====================================================
    
    /**
     * Check if copy feature should be shown (only after first cohort)
     */
    get showCopyConfiguration() {
        return this.cohortIndex > 0 && this.availableCohortsForCopy.length > 0;
    }
    
    /**
     * Get list of previously completed cohorts with same workflow type
     */
    get availableCohortsForCopy() {
        const cohorts = [];
        const currentWorkflowType = this.studyType;
        
        // Loop through cohorts before current one
        for (let i = 0; i < this.cohortIndex; i++) {
            const cohortName = this._answers[`cohortName_${i}`] || `Cohort ${i + 1}`;
            cohorts.push({
                value: i.toString(),
                label: `${cohortName} (${currentWorkflowType === 'Leukopak' ? 'Leukopak' : 'Prospective'})`
            });
        }
        
        return cohorts;
    }
    
    /**
     * Check if copy button should be disabled
     */
    get isCopyButtonDisabled() {
        return !this.selectedCohortToCopyFrom || this.selectedCohortToCopyFrom === '';
    }
    
    /**
     * Handle cohort selection from dropdown
     */
    handleCohortSelectionForCopy(event) {
        this.selectedCohortToCopyFrom = event.target.value;
    }
    
    /**
     * Copy biospecimen configuration from selected cohort
     */
    handleCopyConfiguration() {
        if (!this.selectedCohortToCopyFrom) {
            return;
        }
        
        const sourceCohortIndex = parseInt(this.selectedCohortToCopyFrom, 10);
        const targetCohortIndex = this.cohortIndex;
        
        debugInfo('Copying configuration', {
            from: sourceCohortIndex,
            to: targetCohortIndex,
            page: this.currentPageIndex,
            isLeukopak: this.isLeukopak,
            isProspective: this.isProspective
        });
        
        // Define fields to copy based on page
        let fieldsToCopy = [];
        
        if (this.isPage2Leukopak) {
            // Leukopak Information page fields
            fieldsToCopy = [
                'leuko_condition',
                'leuko_donor_hla',
                'leuko_donor_medical',
                'leuko_donor_counts',
                'leuko_isolation_type',
                'leuko_size',
                'leuko_quantity',
                'leuko_type',
                'leuko_usage',
                'leuko_aliquot',
                // Additional biospecimen types
                'leuko_add_wholeBlood',
                'leuko_add_rna',
                'leuko_add_dna',
                'leuko_add_tCell',
                'leuko_add_bCell',
                'leuko_add_nkCell',
                'leuko_add_pbmc',
                'leuko_add_rbc',
                'leuko_add_plasma',
                'leuko_add_serum',
                'leuko_add_bulkPlasma',
                'leuko_add_buffyCoat',
                'leuko_add_nasalSwabs',
                'leuko_add_buccalSwabs',
                'leuko_add_saliva',
                'leuko_add_semen',
                'leuko_add_stool',
                'leuko_add_urine',
                'leuko_add_synovialFluid',
                'leuko_add_skinPunchBiopsy',
                'leuko_add_skinTapeStrips',
                'leuko_add_sputum',
                'leuko_add_fingernails',
                'leuko_add_hair',
                'leuko_add_other'
            ];
            
            // Copy detailed configuration for selected biospecimens
            this.copyBiospecimenDetailFields(sourceCohortIndex, targetCohortIndex, 'leuko_add_');
            
        } else if (this.isPage2Prospective) {
            // Prospective Biospecimen Types page fields
            fieldsToCopy = [
                'prosp_bio_wholeBlood',
                'prosp_bio_rna',
                'prosp_bio_dna',
                'prosp_bio_tCell',
                'prosp_bio_bCell',
                'prosp_bio_nkCell',
                'prosp_bio_pbmc',
                'prosp_bio_rbc',
                'prosp_bio_plasma',
                'prosp_bio_serum',
                'prosp_bio_bulkPlasma',
                'prosp_bio_buffyCoat',
                'prosp_bio_nasalSwabs',
                'prosp_bio_buccalSwabs',
                'prosp_bio_saliva',
                'prosp_bio_semen',
                'prosp_bio_stool',
                'prosp_bio_urine',
                'prosp_bio_synovialFluid',
                'prosp_bio_skinPunchBiopsy',
                'prosp_bio_skinTapeStrips',
                'prosp_bio_sputum',
                'prosp_bio_fingernails',
                'prosp_bio_hair',
                'prosp_bio_other'
            ];
            
            // Copy detailed configuration for selected biospecimens
            this.copyBiospecimenDetailFields(sourceCohortIndex, targetCohortIndex, 'prosp_bio_');
        }
        
        // Copy each field
        fieldsToCopy.forEach(field => {
            const sourceKey = `cohort${sourceCohortIndex}_${field}`;
            const targetKey = `cohort${targetCohortIndex}_${field}`;
            const value = this.getAnswer(sourceKey);
            
            if (value !== '' && value !== null && value !== undefined) {
                this.dispatchEvent(new CustomEvent('valuechange', {
                    detail: {
                        section: 'cohortDetails',
                        question: targetKey,
                        value: value,
                        cohortIndex: targetCohortIndex,
                        cohortName: this.cohortName
                    },
                    bubbles: true,
                    composed: true
                }));
            }
        });
        
        debugInfo('Configuration copied successfully', {
            fieldCount: fieldsToCopy.length,
            from: sourceCohortIndex,
            to: targetCohortIndex
        });

        // Force a re-render to restore all field values
        this._forceRerender++;

        // Clear selection
        this.selectedCohortToCopyFrom = '';

        // Use setTimeout to allow state propagation before syncing UI
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.syncUIWithState();
        }, 150);
    }
    
    /**
     * Copy detailed biospecimen configuration fields
     */
    copyBiospecimenDetailFields(sourceCohortIndex, targetCohortIndex, prefix) {
        // List of biospecimen types that have detail fields
        const biospecimenTypes = [
            'wholeBlood', 'plasma', 'serum', 'pbmc', 'rbc', 'tCell', 'bCell', 'nkCell',
            'bulkPlasma', 'buffyCoat', 'rna', 'dna', 'nasalSwabs', 'buccalSwabs',
            'saliva', 'semen', 'stool', 'urine', 'synovialFluid', 'skinPunchBiopsy',
            'skinTapeStrips', 'sputum', 'fingernails', 'hair', 'other'
        ];

        // Detail field suffixes for each biospecimen (must match data-question attributes in HTML)
        const detailFields = [
            '_collection_materials',    // e.g., plasma_collection_materials
            '_volume',                  // e.g., plasma_volume
            '_aliquot_size',            // e.g., plasma_aliquot_size
            '_temperature',             // e.g., plasma_temperature
            '_processing_location',     // e.g., plasma_processing_location
            '_shipping_temp',           // e.g., plasma_shipping_temp
            '_shipping_temperature',    // e.g., pbmc_shipping_temperature
            '_wb_shipment_temp',        // e.g., pbmc_wb_shipment_temp
            '_selection_method',        // e.g., tCell_selection_method
            '_blood_volume',            // e.g., rbc_blood_volume
            '_temperature_options',     // e.g., rbc_temperature_options
            '_custom_materials',        // e.g., rbc_custom_materials
            '_custom_aliquot_size',     // e.g., urine_custom_aliquot_size
            '_number',                  // e.g., nasalSwabs_number
            '_requirements',            // e.g., stool_requirements
            '_first_void',              // e.g., urine_first_void
            '_processing_required',     // e.g., urine_processing_required
            '_separate_supernatant',    // e.g., urine_separate_supernatant
            '_discard_pellet',          // e.g., urine_discard_pellet
            '_collection_details',      // e.g., urine_collection_details
            '_details',                 // e.g., synovialFluid_details
            '_size',                    // e.g., skinPunchBiopsy_size
            '_regions',                 // e.g., skinTapeStrips_regions
            '_sample_volume',           // e.g., other_sample_volume
            '_materials',               // e.g., other_materials
            '_shipping_requirements',   // e.g., other_shipping_requirements
            '_collection_type'          // e.g., other_collection_type
        ];
        
        biospecimenTypes.forEach(bioType => {
            // Check if this biospecimen was selected in source cohort
            const bioCheckKey = `cohort${sourceCohortIndex}_${prefix}${bioType}`;
            if (this.getAnswer(bioCheckKey) === true) {
                // Copy all detail fields for this biospecimen
                detailFields.forEach(detailSuffix => {
                    const sourceDetailKey = `cohort${sourceCohortIndex}_${bioType}${detailSuffix}`;
                    const targetDetailKey = `cohort${targetCohortIndex}_${bioType}${detailSuffix}`;
                    const detailValue = this.getAnswer(sourceDetailKey);
                    
                    if (detailValue !== '' && detailValue !== null && detailValue !== undefined) {
                        this.dispatchEvent(new CustomEvent('valuechange', {
                            detail: {
                                section: 'cohortDetails',
                                question: targetDetailKey,
                                value: detailValue,
                                cohortIndex: targetCohortIndex,
                                cohortName: this.cohortName
                            },
                            bubbles: true,
                            composed: true
                        }));
                    }
                });
            }
        });
    }

    // =====================================================
    // Answer helpers
    // =====================================================

    getAnswer(key) {
        const value = this._answers && this._answers[key] ? this._answers[key] : '';
        return value;
    }

    // Getters for Page 1 fields (Study Details and Inclusion/Exclusion Criteria)
    get numDonorsValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_num_donors`);
    }
    get inclDiagValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_incl_diag`);
    }
    get inclMedValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_incl_med`);
    }
    get inclOtherValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_incl_other`);
    }
    get exclDiagValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_excl_diag`);
    }
    get exclMedValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_excl_med`);
    }
    get exclOtherValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_excl_other`);
    }
    
    // Getters for Page 2 Leukopak fields
    get leukoConditionValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_condition`);
    }
    get leukoIsolationTypeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_isolation_type`);
    }
    get leukoSizeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_size`);
    }
    get leukoQuantityValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_quantity`);
    }
    get leukoTypeValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_type`);
    }
    get leukoUsageValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_usage`);
    }
    get leukoAliquotValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_aliquot`);
    }
    get leukoAliquotCustomValue() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_aliquot_custom`);
    }
    get showLeukoAliquotCustom() {
        return this.leukoAliquotValue === 'Other';
    }

    // ===== Error state getters for Leukopak required fields =====
    get leukoQuantityHasError() {
        return !!this.leukoFieldErrors?.leuko_quantity;
    }
    get leukoConditionHasError() {
        return !!this.leukoFieldErrors?.leuko_condition;
    }
    get leukoTypeHasError() {
        return !!this.leukoFieldErrors?.leuko_type;
    }
    get leukoSizeHasError() {
        return !!this.leukoFieldErrors?.leuko_size;
    }

    // ===== CSS class getters for Leukopak required fields =====
    get leukoQuantityInputClass() {
        return this.leukoQuantityHasError ? 'text-input error' : 'text-input';
    }
    get leukoConditionSelectClass() {
        return this.leukoConditionHasError ? 'select-input error' : 'select-input';
    }
    get leukoTypeSelectClass() {
        return this.leukoTypeHasError ? 'select-input error' : 'select-input';
    }
    get leukoSizeSelectClass() {
        return this.leukoSizeHasError ? 'select-input error' : 'select-input';
    }

    // ===== Error message getters for Leukopak required fields =====
    get leukoQuantityErrorMessage() {
        return this.leukoFieldErrors?.leuko_quantity || '';
    }
    get leukoConditionErrorMessage() {
        return this.leukoFieldErrors?.leuko_condition || '';
    }
    get leukoTypeErrorMessage() {
        return this.leukoFieldErrors?.leuko_type || '';
    }
    get leukoSizeErrorMessage() {
        return this.leukoFieldErrors?.leuko_size || '';
    }

    // ===== Error state getters for Biospecimen Page 3 required fields =====
    // Nasal Swabs
    get nasalSwabsCollectionMaterialsHasError() {
        return !!this.biospecimenFieldErrors?.nasalSwabs_collection_materials;
    }
    get nasalSwabsTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.nasalSwabs_temperature;
    }
    get nasalSwabsNumberHasError() {
        return !!this.biospecimenFieldErrors?.nasalSwabs_number;
    }
    // Buccal Swabs
    get buccalSwabsCollectionMaterialsHasError() {
        return !!this.biospecimenFieldErrors?.buccalSwabs_collection_materials;
    }
    get buccalSwabsTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.buccalSwabs_temperature;
    }
    get buccalSwabsNumberHasError() {
        return !!this.biospecimenFieldErrors?.buccalSwabs_number;
    }
    // Synovial Fluid
    get synovialFluidVolumeHasError() {
        return !!this.biospecimenFieldErrors?.synovialFluid_volume;
    }
    get synovialFluidTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.synovialFluid_temperature;
    }
    get synovialFluidAliquotSizeHasError() {
        return !!this.biospecimenFieldErrors?.synovialFluid_aliquot_size;
    }
    // Skin Punch Biopsy
    get skinPunchBiopsyNumberHasError() {
        return !!this.biospecimenFieldErrors?.skinPunchBiopsy_number;
    }
    get skinPunchBiopsySizeHasError() {
        return !!this.biospecimenFieldErrors?.skinPunchBiopsy_size;
    }
    get skinPunchBiopsyTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.skinPunchBiopsy_temperature;
    }
    // Skin Tape Strips
    get skinTapeStripsCollectionMaterialsHasError() {
        return !!this.biospecimenFieldErrors?.skinTapeStrips_collection_materials;
    }
    get skinTapeStripsNumberHasError() {
        return !!this.biospecimenFieldErrors?.skinTapeStrips_number;
    }
    get skinTapeStripsTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.skinTapeStrips_temperature;
    }
    get skinTapeStripsRegionsHasError() {
        return !!this.biospecimenFieldErrors?.skinTapeStrips_regions;
    }
    // Sputum
    get sputumCollectionMaterialsHasError() {
        return !!this.biospecimenFieldErrors?.sputum_collection_materials;
    }
    get sputumTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.sputum_temperature;
    }
    // Fingernails
    get fingernailsCollectionMaterialsHasError() {
        return !!this.biospecimenFieldErrors?.fingernails_collection_materials;
    }
    get fingernailsTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.fingernails_temperature;
    }
    // Hair
    get hairCollectionMaterialsHasError() {
        return !!this.biospecimenFieldErrors?.hair_collection_materials;
    }
    get hairTemperatureHasError() {
        return !!this.biospecimenFieldErrors?.hair_temperature;
    }

    // ===== CSS class getters for Biospecimen Page 3 required fields =====
    // Nasal Swabs
    get nasalSwabsCollectionMaterialsInputClass() {
        return this.nasalSwabsCollectionMaterialsHasError ? 'text-input error' : 'text-input';
    }
    get nasalSwabsTemperatureSelectClass() {
        return this.nasalSwabsTemperatureHasError ? 'select-input error' : 'select-input';
    }
    get nasalSwabsNumberInputClass() {
        return this.nasalSwabsNumberHasError ? 'text-input error' : 'text-input';
    }
    // Buccal Swabs
    get buccalSwabsCollectionMaterialsSelectClass() {
        return this.buccalSwabsCollectionMaterialsHasError ? 'select-input error' : 'select-input';
    }
    get buccalSwabsTemperatureSelectClass() {
        return this.buccalSwabsTemperatureHasError ? 'select-input error' : 'select-input';
    }
    get buccalSwabsNumberInputClass() {
        return this.buccalSwabsNumberHasError ? 'text-input error' : 'text-input';
    }
    // Synovial Fluid
    get synovialFluidVolumeInputClass() {
        return this.synovialFluidVolumeHasError ? 'text-input error' : 'text-input';
    }
    get synovialFluidTemperatureSelectClass() {
        return this.synovialFluidTemperatureHasError ? 'select-input error' : 'select-input';
    }
    get synovialFluidAliquotSizeInputClass() {
        return this.synovialFluidAliquotSizeHasError ? 'text-input error' : 'text-input';
    }
    // Skin Punch Biopsy
    get skinPunchBiopsyNumberInputClass() {
        return this.skinPunchBiopsyNumberHasError ? 'text-input error' : 'text-input';
    }
    get skinPunchBiopsySizeSelectClass() {
        return this.skinPunchBiopsySizeHasError ? 'select-input error' : 'select-input';
    }
    get skinPunchBiopsyTemperatureSelectClass() {
        return this.skinPunchBiopsyTemperatureHasError ? 'select-input error' : 'select-input';
    }
    // Skin Tape Strips
    get skinTapeStripsCollectionMaterialsInputClass() {
        return this.skinTapeStripsCollectionMaterialsHasError ? 'text-input error' : 'text-input';
    }
    get skinTapeStripsNumberInputClass() {
        return this.skinTapeStripsNumberHasError ? 'text-input error' : 'text-input';
    }
    get skinTapeStripsTemperatureSelectClass() {
        return this.skinTapeStripsTemperatureHasError ? 'select-input error' : 'select-input';
    }
    get skinTapeStripsRegionsInputClass() {
        return this.skinTapeStripsRegionsHasError ? 'text-input error' : 'text-input';
    }
    // Sputum
    get sputumCollectionMaterialsSelectClass() {
        return this.sputumCollectionMaterialsHasError ? 'select-input error' : 'select-input';
    }
    get sputumTemperatureSelectClass() {
        return this.sputumTemperatureHasError ? 'select-input error' : 'select-input';
    }
    // Fingernails
    get fingernailsCollectionMaterialsInputClass() {
        return this.fingernailsCollectionMaterialsHasError ? 'text-input error' : 'text-input';
    }
    get fingernailsTemperatureSelectClass() {
        return this.fingernailsTemperatureHasError ? 'select-input error' : 'select-input';
    }
    // Hair
    get hairCollectionMaterialsInputClass() {
        return this.hairCollectionMaterialsHasError ? 'text-input error' : 'text-input';
    }
    get hairTemperatureSelectClass() {
        return this.hairTemperatureHasError ? 'select-input error' : 'select-input';
    }

    // ===== Error message getters for Biospecimen Page 3 required fields =====
    // Nasal Swabs
    get nasalSwabsCollectionMaterialsErrorMessage() {
        return this.biospecimenFieldErrors?.nasalSwabs_collection_materials || '';
    }
    get nasalSwabsTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.nasalSwabs_temperature || '';
    }
    get nasalSwabsNumberErrorMessage() {
        return this.biospecimenFieldErrors?.nasalSwabs_number || '';
    }
    // Buccal Swabs
    get buccalSwabsCollectionMaterialsErrorMessage() {
        return this.biospecimenFieldErrors?.buccalSwabs_collection_materials || '';
    }
    get buccalSwabsTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.buccalSwabs_temperature || '';
    }
    get buccalSwabsNumberErrorMessage() {
        return this.biospecimenFieldErrors?.buccalSwabs_number || '';
    }
    // Synovial Fluid
    get synovialFluidVolumeErrorMessage() {
        return this.biospecimenFieldErrors?.synovialFluid_volume || '';
    }
    get synovialFluidTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.synovialFluid_temperature || '';
    }
    get synovialFluidAliquotSizeErrorMessage() {
        return this.biospecimenFieldErrors?.synovialFluid_aliquot_size || '';
    }
    // Skin Punch Biopsy
    get skinPunchBiopsyNumberErrorMessage() {
        return this.biospecimenFieldErrors?.skinPunchBiopsy_number || '';
    }
    get skinPunchBiopsySizeErrorMessage() {
        return this.biospecimenFieldErrors?.skinPunchBiopsy_size || '';
    }
    get skinPunchBiopsyTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.skinPunchBiopsy_temperature || '';
    }
    // Skin Tape Strips
    get skinTapeStripsCollectionMaterialsErrorMessage() {
        return this.biospecimenFieldErrors?.skinTapeStrips_collection_materials || '';
    }
    get skinTapeStripsNumberErrorMessage() {
        return this.biospecimenFieldErrors?.skinTapeStrips_number || '';
    }
    get skinTapeStripsTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.skinTapeStrips_temperature || '';
    }
    get skinTapeStripsRegionsErrorMessage() {
        return this.biospecimenFieldErrors?.skinTapeStrips_regions || '';
    }
    // Sputum
    get sputumCollectionMaterialsErrorMessage() {
        return this.biospecimenFieldErrors?.sputum_collection_materials || '';
    }
    get sputumTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.sputum_temperature || '';
    }
    // Fingernails
    get fingernailsCollectionMaterialsErrorMessage() {
        return this.biospecimenFieldErrors?.fingernails_collection_materials || '';
    }
    get fingernailsTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.fingernails_temperature || '';
    }
    // Hair
    get hairCollectionMaterialsErrorMessage() {
        return this.biospecimenFieldErrors?.hair_collection_materials || '';
    }
    get hairTemperatureErrorMessage() {
        return this.biospecimenFieldErrors?.hair_temperature || '';
    }

    // Getters for checkboxes (return boolean)
    get leukoDonorHlaChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_donor_hla`) === true;
    }
    get leukoDonorMedicalChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_donor_medical`) === true;
    }
    get leukoDonorCountsChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_donor_counts`) === true;
    }
    get leukoFurtherProcessingChecked() {
        return this.getAnswer(`cohort${this.cohortIndex}_leuko_further_processing`) === true;
    }

    // Processing section visibility
    get showProcessingSection() {
        return this.isPage2Leukopak && this.leukoFurtherProcessingChecked;
    }

    // Show aliquot size field only when isolation type is selected
    get showAliquotSizeField() {
        const isolationType = this.leukoIsolationTypeValue;
        return isolationType && isolationType !== '';
    }

    // Dependent picklist options for Aliquot Size based on Isolation Type
    get aliquotSizeOptions() {
        const isolationType = this.leukoIsolationTypeValue;
        const optionsMap = {
            'PBMC': [
                { value: '100M (standard)', label: '100M (standard)' },
                { value: '50M', label: '50M' },
                { value: 'Other', label: 'Other' }
            ],
            'T-Cell': [
                { value: '50M', label: '50M' },
                { value: '25M', label: '25M' },
                { value: 'Other', label: 'Other' }
            ],
            'B-Cell': [
                { value: '25M', label: '25M' },
                { value: '10M', label: '10M' },
                { value: 'Other', label: 'Other' }
            ],
            'NK-Cell': [
                { value: '10M', label: '10M' },
                { value: '5M', label: '5M' },
                { value: 'Other', label: 'Other' }
            ]
        };
        return optionsMap[isolationType] || [];
    }

    // Handler for isolation type change - clears aliquot size when type changes
    handleIsolationTypeChange(event) {
        // Clear aliquot size when isolation type changes
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                section: 'cohortDetails',
                question: `cohort${this.cohortIndex}_leuko_aliquot`,
                value: '',
                cohortIndex: this.cohortIndex,
                cohortName: this.cohortName
            },
            bubbles: true,
            composed: true
        }));
        // Then handle normal field input
        this.handleFieldInput(event);
    }

    // Handler for Whole Blood volume with 60mL max validation for Leukopak
    handleWholeBloodVolumeInput(event) {
        const value = parseInt(event.target.value, 10);
        if (this.isLeukopak && value > 60) {
            event.target.setCustomValidity('Maximum volume is 60mL for Leukopak additional biospecimens');
            event.target.reportValidity();
            return;
        }
        event.target.setCustomValidity('');
        this.handleFieldInput(event);
    }

    // Generic text input handler
    handleFieldInput(event) {
        const question = event.target.dataset.question;
        const value = event.target.value;

        // Clear validation error for this field if it exists (Leukopak fields)
        if (this.leukoFieldErrors && this.leukoFieldErrors[question]) {
            this.leukoFieldErrors = {
                ...this.leukoFieldErrors,
                [question]: ''
            };
        }

        // Clear validation error for biospecimen fields
        if (this.biospecimenFieldErrors && this.biospecimenFieldErrors[question] !== undefined) {
            this.biospecimenFieldErrors = {
                ...this.biospecimenFieldErrors,
                [question]: ''
            };
        }

        // Include cohort index in question key to prevent data collision
        const questionKey = `cohort${this.cohortIndex}_${question}`;

        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                section: 'cohortDetails',
                question: questionKey,
                value,
                cohortIndex: this.cohortIndex,
                cohortName: this.cohortName
            },
            bubbles: true,
            composed: true
        }));
    }

    handleCheckboxChange(event) {
        const question = event.target.dataset.question;
        const value = event.target.checked;

        // Include cohort index in question key to prevent data collision
        const questionKey = `cohort${this.cohortIndex}_${question}`;

        // Only dispatch if the value actually changed from what's stored
        const currentValue = this.getAnswer(questionKey);
        if (currentValue === value) {
            return;
        }

        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                section: 'cohortDetails',
                question: questionKey,
                value,
                cohortIndex: this.cohortIndex,
                cohortName: this.cohortName
            },
            bubbles: true,
            composed: true
        }));
    }

    /**
     * Handle value changes from c-dynamic-input components
     * Converts the dynamicInput event format to the cohort-prefixed format expected by parent
     * @param {CustomEvent} event - The valuechange2 event from c-dynamic-input
     */
    handleDynamicInputChange(event) {
        event.stopPropagation(); // Prevent bubbling of the original event

        const { question, value } = event.detail;

        // Clear validation error for this field if it exists (Leukopak fields)
        if (this.leukoFieldErrors && this.leukoFieldErrors[question]) {
            this.leukoFieldErrors = {
                ...this.leukoFieldErrors,
                [question]: ''
            };
        }

        // Clear validation error for biospecimen fields
        if (this.biospecimenFieldErrors && this.biospecimenFieldErrors[question] !== undefined) {
            this.biospecimenFieldErrors = {
                ...this.biospecimenFieldErrors,
                [question]: ''
            };
        }

        // Include cohort index in question key to prevent data collision
        const questionKey = `cohort${this.cohortIndex}_${question}`;

        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                section: 'cohortDetails',
                question: questionKey,
                value,
                cohortIndex: this.cohortIndex,
                cohortName: this.cohortName
            },
            bubbles: true,
            composed: true
        }));
    }

    /**
     * Handle biospecimen assignment to shipping addresses
     */
    handleBiospecimenAssignment(event) {
        const addressIndex = parseInt(event.target.dataset.addressIndex, 10);
        const biospecimenValue = event.target.dataset.biospecimen;
        const isChecked = event.target.checked;
        
        // Initialize structures if needed
        if (!this.biospecimenAssignments[addressIndex]) {
            this.biospecimenAssignments[addressIndex] = [];
        }
        
        if (isChecked) {
            // Add to this address's assignments
            if (!this.biospecimenAssignments[addressIndex].includes(biospecimenValue)) {
                this.biospecimenAssignments[addressIndex].push(biospecimenValue);
            }
        } else {
            // Remove from this address's assignments
            this.biospecimenAssignments[addressIndex] = this.biospecimenAssignments[addressIndex].filter(b => b !== biospecimenValue);
        }
        
        // Save to answers
        const suffix = addressIndex === 0 ? '' : `_${addressIndex}`;
        const fieldName = `cohort${this.cohortIndex}_biospecimens${suffix}`;
        
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                section: 'cohortDetails',
                question: fieldName,
                value: JSON.stringify(this.biospecimenAssignments[addressIndex]),
                cohortIndex: this.cohortIndex
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
                section: 'cohortDetails',
                question: question,
                value: value,
                cohortIndex: this.cohortIndex
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
        
        // Assign all to address 0
        this.biospecimenAssignments[0] = biospecimenValues;
        
        // Save to answers
        const fieldName = `cohort${this.cohortIndex}_biospecimens`;
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                section: 'cohortDetails',
                question: fieldName,
                value: JSON.stringify(biospecimenValues),
                cohortIndex: this.cohortIndex
            },
            bubbles: true,
            composed: true
        }));
        
        debugInfo('Auto-assigned all biospecimens to single location', {
            cohort: this.cohortIndex,
            biospecimens: biospecimenValues
        });
    }
}