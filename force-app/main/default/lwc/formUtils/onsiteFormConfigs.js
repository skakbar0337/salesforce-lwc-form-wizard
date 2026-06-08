/**
 * @description Configuration constants for onsite form submission messages
 * @author BioRequest Corp
 * @date 2025-12-09
 * @workItem WI-000316
 */

// Form configuration mapping by form type keywords
export const ONSITE_FORM_CONFIGS = {
    'clientf': {
        displayName: 'ClientF',
        contactEmail: 'onsite1@company.com',
        alternateContact: 'onsite2@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ClientF On-site Program! You will receive a Smartsheet\'s email notification with the scheduled Donor ID(s) once their appointment is confirmed.'
    },
    'clientb_chicago': {
        displayName: 'ClientB Chicago',
        contactEmail: 'clientb.onsite@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ClientB (Chicago) On-site Program! You will receive a Smartsheet email notification letting you know when your request has been scheduled. Samples can be picked up outside of the phlebotomy room at AP9A-L-L813.',
        matchKeywords: ['clientb', 'chicago']
    },
    'clientb_ma': {
        displayName: 'ClientB MA',
        contactEmail: 'clientb.onsite@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ClientB On-site Program! You will receive a Smartsheet\'s email notification with the scheduled Donor ID(s) when they are scheduled.',
        matchKeywords: ['clientb', 'ma']
    },
    'clientb_sf': {
        displayName: 'ABA SF',
        contactEmail: 'clientb.onsite@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ABA SF On-site Program! You will receive a Smartsheet email notification with the scheduled Donor ID(s) when they are scheduled.',
        matchKeywords: ['aba', 'sf']
    },
    'bi': {
        displayName: 'Boehringer Ingelheim',
        contactEmail: 'onsite@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the BI On-site Program! You will receive an email notification with confirmation details.'
    },
    'clienta': {
        displayName: 'ClientA',
        contactEmail: 'clienta.onsite@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ClientA on-site programs! We will send you a confirmation email with the scheduled Request ID(s) at least 24 hours before the sample delivery date and time.\n\nIf you need to cancel or reschedule your request, please email clienta.onsite@company.com with your request details (number of donors, date and time of delivery).'
    },
    'clientc': {
        displayName: 'ClientC Norwood',
        contactEmail: 'clientc.onsite@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ClientC (Norwood) On-site Program! You will receive a Smartsheet email notification letting you know your request has been scheduled 48 hours prior to your requested delivery date.',
        matchKeywords: ['clientc', 'location1']
    },
    'clientd': {
        displayName: 'ClientD',
        contactEmail: 'onsite2@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ClientD On-site Program! You will receive a Smartsheet\'s email notification with the scheduled Donor ID(s) once their appointment is confirmed.'
    },
    'cliente_research': {
        displayName: 'ClientE Research',
        contactEmail: 'onsite2@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'You have successfully submitted a request to the ClientE Research On-site Program! You will receive a Smartsheet email notification letting you know your request has been scheduled 48 hours prior to your requested delivery date.',
        matchKeywords: ['cliente', 'research']
    },
    'default': {
        displayName: 'Onsite Services',
        contactEmail: 'onsite@company.com',
        signatureName: 'BioRequest On-Site Team',
        confirmationMessage: 'Thank you for your submission. Our team will review your request and contact you with next steps.'
    }
};

// BioRequest branding constants
export const COMPANY_BRANDING = {
    logoUrl: '/resource/CompanyLogo',
    companyName: 'BioRequest Corp',
    website: 'www.company.com',
    supportEmail: 'support@company.com'
};