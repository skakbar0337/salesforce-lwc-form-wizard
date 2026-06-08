export const TEST_STATE = {
    "sessionToken": "test123",
    "steps": {},
    "answers": {
        "firstName": "Bob",
        "lastName": "Smith",
        "email": "user3@company.com",
        "phone": "1231231234",
        "organization": "bioquest",
        "role": "scientist",
        "multipleLocations": "single",
        "company": "bioquest",
        "fullName": "ertye",
        "address": "tryerty",
        "city": "ert",
        "state": "erty",
        "zipCode": "12345",
        "studyType": "Cohort_Standard",
        "numberOfCohorts": 1,
        "cohortCount": 1,
        "cohortNames": [
        "sfdsfdg"
        ],
        "cohortName_0": "sfdsfdg",
        "cohort0_currentPageIndex": 4,
        "cohort0_biospecimens": "[]",
        "cohort0_shipping_comments": "sdfgsfdgsfgd",
        "budgetEstimate": "345345345"
    },
    "firstName": "Bob",
    "lastName": "Smith",
    "email": "user3@company.com",
    "phone": "1231231234",
    "organization": "bioquest",
    "role": "scientist",
    "multipleLocations": "single",
    "company": "bioquest",
    "fullName": "ertye",
    "address": "tryerty",
    "city": "ert",
    "state": "erty",
    "zipCode": "12345",
    "studyType": "Cohort_Standard",
    "numberOfCohorts": 1,
    "cohortCount": 1,
    "cohortNames": [
        "sfdsfdg"
    ],
    "cohortName_0": "sfdsfdg",
    "cohort0_currentPageIndex": 4,
    "cohort0_biospecimens": "[]",
    "cohort0_shipping_comments": "sdfgsfdgsfgd",
    "budgetEstimate": "345345345"
}

export const TEST_CONFIG = {
            title: "Dynamic Request Form",
            total_steps : 3,
            show_progress_bar: true,
            allow_save_resume: true,
            emailSessionRequired: true,
            postSubmit: {
                showConfirmationPage: true,
                messageBody: [
                    "Thank you for your biospecimen request. We are reviewing the details of your project and preparing a quote.",
                    "What’s Next?\n\n• A BioRequest team member will reach out within 1 business day to confirm any additional details about your study or donor requirements.\n• A summary of your request has been sent to your email (check spam if it is not in your inbox).\n• Your quote will follow shortly after we verify feasibility, donor availability, and any required clinical metadata.",
                    "While you wait, check out our available inventory. If you have any questions, please contact contact@company.com."
                ],
                inventoryUrl: 'https://www.company.com/products/?pro_inventory=inventory',
                contactEmail: 'contact@company.com'
            },
            steps: [
                { number: 1,
                  label: "Contact Information",
                  progressLabel: "Contact",
                  description: "Tell us about yourself",
                  sections: [
                    {
                        name: "contactInfo",
                        label: "",
                        is_repeatable: "false",
                        min_instances: 0,
                        max_instances: 0,
                        visibility_Logic: {
                            field: "",
                            operator: "",
                            value: ""
                        },
                        questions: [
                            {
                                name: "firstName",
                                label: "First Name",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "John",
                            },
                            {
                                name: "lastName",
                                label: "Last Name",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "Smith"
                            },
                            {
                                name: "email",
                                label: "Email",
                                type: "text",
                                readOnly: "true",
                                isRequired: "true",
                                num_columns: 1,
                                visibility_Logic: {
                                    field: "",
                                    operator: "",
                                    value: ""
                                },
                            },
                            {
                                name: "phone",
                                label: "Phone",
                                type: "text",
                                isRequired: "false",
                                num_columns: 1,
                            },
                            {
                                name: "organization",
                                label: "Organization",
                                type: "text",
                                isRequired: "true",
                            },
                                                    {
                                name: "role",
                                label: "Role/Title",
                                type: "text",
                                isRequired: "false",
                            }
                        ]
                    }
                  ]
                },
                { 
                    number: 2,
                    label: "Shipping Information",
                    progressLabel: "Shipping",
                    description: "Where should we ship your biospecimens?",
                    sections: [
                        {
                            name: "shippingInfo",
                            label: "",
                            is_repeatable: "false",
                            min_instances: 0,
                            max_instances: 0,
                            visibility_Logic: {
                                field: "",
                                operator: "",
                                value: ""
                            },
                            questions: [
                                {
                                    name: "multipleLocations",
                                    label: "Do you need biospecimens shipped to multiple locations?",
                                    type: "radio",
                                    isRequired: "true",
                                    num_columns: 2,
                                    options: [
                                        { label: 'Single location', value: 'single' },
                                        { label: 'Multiple locations', value: 'multiple' }
                                    ]
                                }                                                    
                            ]
                        },
                        {
                            name: "mainAddress",
                            label: "Shipping Address",
                            is_repeatable: "true",
                            min_instances: 1,
                            max_instances: 10,
                            questions: [
                                {
                                    name: "company",
                                    label: "Company",
                                    type: "text",
                                    placeholder: "Company Name",
                                    isRequired: "true",
                                    num_columns: 2
                                },
                                {
                                    name: "fullName",
                                    label: "Full Name",
                                    type: "text",
                                    placeholder: "Contact person's full name",
                                    isRequired: "true",
                                    num_columns: 2
                                },                             
                                {
                                    name: "address",
                                    label: "Address",
                                    type: "text",
                                    placeholder: "Street address",
                                    isRequired: "true",
                                    num_columns: 2
                                }                                         
                            ]
                        }
                  ]
                },
                { 
                    number: 3,
                    label: "Study Cohorts",
                    progressLabel: "Cohorts",
                    description: "How many cohorts does your study include?",
                    sections: [
                        {
                            isCustom: true,
                            lwcName: "form-cohort-section"
                        }
                    ]
                },
                { 
                    number: 4,
                    label: "Study Type",
                    progressLabel: "Study Type",
                    description: "Select your study type",
                    sections: []
                },
                { 
                    number: 5,
                    label: "Budget",
                    progressLabel: "Budget",
                    description: "Budget information",
                    sections: []
                },
                { 
                    number: 6,
                    label: "Review",
                    progressLabel: "Review",
                    description: "Review your information",
                    sections: []
                }
            ]
        }
          
export const TEST_CONFIG2 = {
            title: "Onsite Form",
            total_steps : 1,
            show_progress_bar: false,
            allow_save_resume: false,
            steps: [
                { number: 1,
                  label: "Onsite Information",
                  progressLabel: "Onsite Information",
                  description: "Tell us about yourself",
                  sections: [
                    {
                        name: "contactInfo",
                        label: "",
                        is_repeatable: "false",
                        min_instances: 0,
                        max_instances: 0,
                        visibility_Logic: {
                            field: "",
                            operator: "",
                            value: ""
                        },
                        questions: [
                            {
                                name: "firstName",
                                label: "First Name",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "John",
                            },                      
                            {
                                name: "email",
                                label: "Email",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                visibility_Logic: {
                                    field: "",
                                    operator: "",
                                    value: ""
                                },
                            },
                            {
                                name: "organization",
                                label: "Organization",
                                type: "text",
                                isRequired: "true",
                            },
                            {
                                name: "role",
                                label: "Role/Title",
                                type: "text",
                                isRequired: "false",
                            }
                        ]
                    }
                  ]
                }
            ]
        }

export const TEST_ONSITE = {
        title: "Onsite Form",
        emailSessionRequired: false,
        total_steps : 1,
        show_progress_bar: false,
        allow_save_resume: false,
        steps: [
            { number: 1,
                label: "",
                progressLabel: "Contact",
                description: "",
                sections: [
                    {
                        name: "contactInfo",
                        label: "Researcher Information",
                        is_repeatable: "false",
                        min_instances: 0,
                        max_instances: 0,
                        questions: [
                            {
                                name: "firstName",
                                label: "Researcher Name",
                                type: "text",
                                isRequired: "true",
                                num_columns: 2,
                                placeholder: "John",
                            },
                            {
                                name: "email",
                                label: "Researcher Email",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "John@example.com",
                            },
                            {
                                name: "phone",
                                label: "Researcher Phone Number",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "John@example.com",
                            }
                        ]
                    },
                    {
                        name: "contactInfo2",
                        label: "General Request Information",
                        is_repeatable: "false",
                        min_instances: 0,
                        max_instances: 0,
                        questions: [
                            {
                                name: "del",
                                label: "Date of Delivery",
                                type: "date",
                                isRequired: "true",
                                num_columns: 1,
                            },
                            {
                                name: "ttt",
                                label: "Time if Delivery",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "7:00 a.m.",
                            },
                            {
                                name: "donors",
                                label: "How many donors? (QTY)",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1
                            },
                            {
                                name: "sub",
                                label: "Requested Subject ID(s)",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1
                            },
                            {
                                name: "sub2",
                                label: "Excluded Subject ID(s)",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1
                            }
                        ]
                    },
                                        {
                        name: "contactInfo3",
                        label: "Specimen Details",
                        is_repeatable: "false",
                        min_instances: 0,
                        max_instances: 0,
                        questions: [
                            {
                                name: "tubes",
                                label: "Tubes Types and Quantity Needed",
                                type: "textarea",
                                isRequired: "true",
                                num_columns: 2,
                            },
                            {
                                name: "volume",
                                label: "Total Blood Volume (mL) Needed per Donor",
                                type: "text",
                                isRequired: "true",
                                num_columns: 2,
                            },
                            {
                                name: "nonStandard",
                                label: "Non-Standard Tube (Provided by Researcher)",
                                type: "text",
                                isRequired: "true",
                                num_columns: 2
                            },
                            {
                                name: "addlcomm",
                                label: "Additional Comments:",
                                type: "textarea",
                                isRequired: "true",
                                num_columns: 2
                            },
                            {
                                name: "sendmedetails",
                                label: "Do you want to receive a confirmation email",
                                type: "radio",
                                options: [
                                    { label: 'Yes, send me a copy of my responses', value: 'yes' },
                                    { label: 'No, do not send me a copy of my responses', value: 'no' }
                                ],
                                isRequired: "true",
                                num_columns: 2
                            }
                        ]
                    }
                ]
            }
        ]
}

/**
 */
export const TEST_ONSITE_3_STEP_EXAMPLE = {
        title: "Onsite Form (3-Step Example)",
        emailSessionRequired: false,
        total_steps: 3,
        show_progress_bar: true,
        allow_save_resume: false,
        steps: [
            // STEP 1: Form Entry
            { 
                number: 1,
                label: "Request Information",
                progressLabel: "Form",
                description: "Enter your onsite request details",
                sections: [
                    {
                        name: "contactInfo",
                        label: "Researcher Information",
                        is_repeatable: "false",
                        questions: [
                            {
                                name: "firstName",
                                label: "Researcher Name",
                                type: "text",
                                isRequired: "true",
                                num_columns: 2,
                                placeholder: "John Doe"
                            },
                            {
                                name: "email",
                                label: "Researcher Email",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "john@example.com"
                            },
                            {
                                name: "phone",
                                label: "Researcher Phone Number",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "555-1234"
                            }
                        ]
                    },
                    {
                        name: "requestInfo",
                        label: "General Request Information",
                        is_repeatable: "false",
                        questions: [
                            {
                                name: "deliveryDate",
                                label: "Date of Delivery",
                                type: "date",
                                isRequired: "true",
                                num_columns: 1
                            },
                            {
                                name: "deliveryTime",
                                label: "Time of Delivery",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1,
                                placeholder: "7:00 a.m."
                            },
                            {
                                name: "donorCount",
                                label: "How many donors? (QTY)",
                                type: "text",
                                isRequired: "true",
                                num_columns: 1
                            }
                        ]
                    },
                    {
                        name: "specimenDetails",
                        label: "Specimen Details",
                        is_repeatable: "false",
                        questions: [
                            {
                                name: "tubeTypes",
                                label: "Tube Types and Quantity Needed",
                                type: "textarea",
                                isRequired: "true",
                                num_columns: 2
                            },
                            {
                                name: "bloodVolume",
                                label: "Total Blood Volume (mL) Needed per Donor",
                                type: "text",
                                isRequired: "true",
                                num_columns: 2
                            },
                            {
                                name: "confirmationEmail",
                                label: "Do you want to receive a confirmation email?",
                                type: "radio",
                                options: [
                                    { label: 'Yes, send me a copy of my responses', value: 'yes' },
                                    { label: 'No, do not send me a copy of my responses', value: 'no' }
                                ],
                                isRequired: "true",
                                num_columns: 2
                            }
                        ]
                    }
                ]
            },
            // STEP 2: Review (dynamically added in production, shown here for reference)
            { 
                number: 2,
                label: "Review",
                progressLabel: "Review",
                description: "Please review your information before submitting",
                isReview: true,  // Special flag for step-level review
                sections: [
                    {
                        name: "reviewSection",
                        label: "",
                        isReview: true,  // Triggers reviewData getter in c-form-section
                        questions: []    // Empty - content generated from Step 1 answers
                    }
                ]
            },
            // STEP 3: Submission Message (dynamically added after submit, shown here for reference)
            { 
                number: 3,
                label: "Confirmation",
                progressLabel: "Complete",
                description: "",
                isSubmissionMessage: true,  // Special flag to render c-onsite-submission-message
                sections: []  // No sections - uses dedicated submission message component
            }
        ]
}