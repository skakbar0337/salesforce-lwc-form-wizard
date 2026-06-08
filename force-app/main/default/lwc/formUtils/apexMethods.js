import createSession from '@salesforce/apex/FormWizardController.createSession';
import getWizardConfig from '@salesforce/apex/FormWizardController.getWizardConfiguration';
import updateSession from '@salesforce/apex/FormWizardController.updateSession';
import submitForm from '@salesforce/apex/FormWizardController.submitForm';
import getAllWizardConfigurations from '@salesforce/apex/FormWizardController.getAllWizardConfigurations';
import submitFinal from '@salesforce/apex/FormWizardController.submitFinal';
import { debugInfo, debugError, debugSuccess } from './formUtils';

export const apexMethods = {
    async createSession(email, formType, ipAddress = null, startingStep = 1) {
        try {
            const request = {
                email: email,
                wizardType: formType,
                ipAddress: ipAddress,
                startingStep: startingStep
            };
            debugInfo('createSession request', request);
            // Apex signature: createSession(String email, String wizardType, String ipAddress, Integer startingStep)
            const apexResult = await createSession(request);
            debugSuccess('createSession success', apexResult);
            // Apex returns Form_Session__c record (not JSON string)
            return apexResult;
        } catch (error) {
            debugError('createSession error', error);
            throw error;
        }
    },

    async updateSession(state, currentStep, status) {
        try {
            console.log('💾 updateSession - Full state received:', state);
            
            // Extract answers: if state.answers has data, use it; otherwise extract from state root
            let answersToSerialize = {};
            
            if (state?.answers && Object.keys(state.answers).length > 0) {
                // Use state.answers if it contains data
                answersToSerialize = state.answers;

            } else if (state) {
                // Extract answers from state root, excluding system fields
                const systemFields = ['sessionToken', 'steps', 'answers', 'userEmail', 'sessionId'];
                answersToSerialize = Object.keys(state)
                    .filter(key => !systemFields.includes(key))
                    .reduce((obj, key) => {
                        obj[key] = state[key];
                        return obj;
                    }, {});
            }
            
            const answersJson = JSON.stringify(answersToSerialize);

            const request = {
                sessionToken: state?.sessionToken,
                currentStep: currentStep,
                answersJson: answersJson,
                status: status
            };
            
            debugInfo('updateSession request', {
                hasSessionToken: !!state?.sessionToken,
                sessionToken: state?.sessionToken,
                currentStep: currentStep,
                answerKeys: Object.keys(answersToSerialize),
                answersPreview: answersToSerialize,
                answersJsonLength: answersJson.length,
                status: status
            });
            
            // Apex signature: updateSession(String sessionToken, Integer currentStep, String answersJson, String status)
            const apexResult = await updateSession(request);
            debugSuccess('updateSession success', apexResult);
            // Apex returns Form_Session__c record (not JSON string)
            return apexResult;
        } catch (error) {
            debugError('updateSession error', {
                error: error,
                errorMessage: error.message,
                errorBody: error.body
            });
            throw error;
        }
    },

    async fetchWizardConfig(formType) {
        try {
            const request = {
                wizardTitle: formType
            };
            debugInfo('fetchWizardConfig request', request);
            // Apex signature: getWizardConfiguration(String wizardTitle)
            // Returns: String (JSON config)
            const apexResult = await getWizardConfig(request);

            // Defensive: some orgs or environments may return null/empty or malformed JSON.
            debugInfo('fetchWizardConfig raw apexResult', apexResult);

            if (apexResult === null || apexResult === undefined || apexResult === '') {
                const msg = 'fetchWizardConfig: Apex returned empty configuration for ' + formType;
                debugError('fetchWizardConfig error', msg);
                throw new Error(msg);
            }

            let parsedResult;
            try {
                parsedResult = JSON.parse(apexResult);
            } catch (parseErr) {
                debugError('fetchWizardConfig parse error', { error: parseErr, raw: apexResult });
                throw parseErr;
            }

            debugSuccess('fetchWizardConfig success', parsedResult);
            return parsedResult;
        } catch (error) {
            debugError('fetchWizardConfig error', error);
            throw error;
        }
    },

    async getAllWizardConfigurations() {
        try {
            debugInfo('getAllWizardConfigurations request');
            const apexResult = await getAllWizardConfigurations();
            const parsedResult = JSON.parse(apexResult);
            debugSuccess('getAllWizardConfigurations success', parsedResult);
            return parsedResult;
        } catch (error) {
            debugError('getAllWizardConfigurations error', error);
            throw error;
        }
    },

    async submitForm(stateJson) {
        debugInfo('submitForm called with state', stateJson);
         try {
             if (stateJson.primaryEmail === undefined || stateJson.primaryEmail  === null || stateJson.primaryEmail === '') {
                throw new Error('submitForm error: primaryEmail is required in state');
            }

            const request = {
                state: JSON.stringify({
                    primaryEmail: stateJson.primaryEmail,
                    sessionToken: stateJson.sessionToken,
                    sessionRecordId: stateJson.sessionRecordId,
                    formType: stateJson.formType,
                    currentStep: String(stateJson.currentStep),
                    answers: JSON.stringify(stateJson.answers),
                    sessionName: stateJson.sessionName
                })
            };

            debugInfo('submitForm request payload', request);
            const apexResult = await submitFinal(request);
            debugSuccess('submitForm success', apexResult);
            return apexResult;
        } catch (error) {
            debugError('apexMethods submitForm error', error);
            throw error;
        }
    }
}