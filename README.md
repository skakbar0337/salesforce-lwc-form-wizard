# Salesforce LWC Dynamic Form Wizard

A **configuration-driven multi-step form wizard** built on Salesforce Lightning Web Components (LWC). The entire form structure — steps, sections, fields, validation rules, field mappings, and submission behavior — is defined in JSON records stored in a custom Salesforce object. No code changes are needed to add or modify forms.

---

## Key Features

- **Zero-code form building** — add new forms by inserting a JSON config record; no deployment required
- **Multi-step wizard** with progress bar, step validation, and previous/next navigation
- **Email OTP verification** — users verify their email before starting; sessions persist across devices
- **Auto-save** — debounced state persistence (1.5s) so no data is lost on accidental close
- **Dynamic field mapping** — config maps form fields to any Salesforce object field via dot-notation (`Contact.FirstName`, `Opportunity.Amount__c`)
- **Repeatable custom sections** — shipping addresses (multi-location), cohort setup with per-cohort pagination
- **Extensible submission handlers** — Apex interface pattern; swap submission logic without touching the wizard
- **Apex logging** — structured logging to a custom object + platform events for real-time observability

---

## Architecture

```
User
 └── formWizardSelector          (form picker — loads available configs)
      └── formWizardContainer    (orchestrator — session state, auto-save, step flow)
           ├── emailVerification  (OTP email gate)
           ├── sessionChoiceModal (resume existing session or start fresh)
           ├── formProgressBar    (visual step indicator)
           ├── formStepRenderer   (renders one step)
           │    └── formSection   (renders one section)
           │         ├── dynamicInput            (all standard field types)
           │         ├── formShippingSection     (custom: multi-location shipping)
           │         └── formCohortSection       (custom: study cohort setup)
           │              └── formCohortIterator (per-cohort pagination)
           └── formNavigation     (prev / next / submit buttons)
```

**Data flow:**

```
JSON Config (Dynamic_Form_Config__c)
    → FormWizardController (Apex)
    → formWizardContainer (LWC state)
    → step-by-step rendering
    → answers saved to Form_Session__c (auto-save)
    → on submit → FormSubmissionHandler (Apex)
    → creates Account, Contact, Opportunity, Research_Proposal__c, Site_Code__c
```

---

## Form Configuration

Forms are stored as JSON in the `Form_Config__c` long text field on `Dynamic_Form_Config__c` records. Example:

```json
{
  "title": "Research Request Form",
  "total_steps": 5,
  "showProgressBar": true,
  "allow_save_resume": true,
  "emailSessionRequired": true,
  "submissionController": "FormSubmissionHandler",
  "steps": [
    {
      "number": 1,
      "label": "Contact Information",
      "sections": [
        {
          "name": "contactInfo",
          "questions": [
            {
              "name": "firstName",
              "label": "First Name",
              "type": "text",
              "isRequired": true,
              "targetField": "Contact.FirstName"
            },
            {
              "name": "studyType",
              "label": "Study Type",
              "type": "radio",
              "variant": "study-type-cards",
              "options": [
                { "label": "Prospective", "value": "prospective" },
                { "label": "Standard",    "value": "standard"    }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

### Supported Field Types

| Type | Description |
|------|-------------|
| `text` | Single-line text input |
| `textarea` | Multi-line text (configurable rows) |
| `date` | Date picker |
| `dropdown` | Select / picklist |
| `radio` | Radio group (supports card layout variant) |
| `checkbox` | Multi-select checkboxes |
| `single-checkbox` | Single boolean toggle |
| `file` | File attachment upload |
| `display-text` | Read-only label / instructions block |

### Dynamic Field Mapping

The `targetField` property maps any form answer directly to a Salesforce object field:

```
"targetField": "Contact.FirstName"         → Contact.FirstName
"targetField": "Opportunity.Amount__c"     → Opportunity custom field
"targetField": "Research_Proposal__c.Notes__c" → custom object field
```

Supported target objects out of the box: `Contact`, `Account`, `Opportunity`, `Research_Proposal__c`, `Site_Code__c`, `IE_Criterion__c`.

---

## Component Inventory

### LWC Components

| Component | Purpose |
|-----------|---------|
| `formWizardContainer` | Main orchestrator — wizard state, session management, auto-save, step transitions |
| `formStepRenderer` | Renders a single step; handles `html-only` type steps with `{{field}}` interpolation |
| `formSection` | Renders a section's questions or delegates to a custom component |
| `formNavigation` | Previous / Next / Submit buttons with configurable labels |
| `formProgressBar` | Step progress indicator (completed / current / upcoming) |
| `dynamicInput` | Reusable input for all supported field types |
| `emailVerification` | OTP email flow; handles session resume and new session creation |
| `formShippingSection` | Multi-location shipping address manager (up to 10 sites) |
| `formCohortSection` | Cohort count and naming; manages study type branching |
| `formCohortIterator` | Per-cohort paginated form (biospecimen, timeline, criteria) |
| `formWizardSelector` | Entry-point form picker; loads all available `Dynamic_Form_Config__c` records |
| `formHelpModal` | Contextual help/contact modal |
| `sessionChoiceModal` | Prompts returning users to resume or start fresh |
| `formSessionEditor` | Admin utility to inspect and edit session state |
| `formUtils` | Shared utilities — debug logging, validation helpers, Apex wrappers |

### Apex Classes

| Class | Purpose |
|-------|---------|
| `FormWizardController` | Main `@AuraEnabled` controller — session CRUD, OTP flow, config retrieval, submission routing |
| `FormWizardService` | Utilities — SHA-256 token generation, 6-digit OTP, session helpers |
| `FormWizardStateModel` | DTO for serializing/deserializing wizard state from `Form_Session__c` |
| `I_FormSubmissionHandler` | Interface — `submitForm(sessionId, answersJson, wizardType)` |
| `FormSubmissionHandler` | Main handler — dynamic field mapping → creates CRM records on submission |
| `DirectSubmissionHandler` | Lightweight handler for on-site / direct submission forms |
| `FormEmailService` | Centralised email service with sandbox redirect and allow-list logic |
| `PublicFormSelector` | FLS-safe SOQL selector for guest/public site queries |
| `ApexLog` | Structured logging to `Apex_Log__c` + `Apex_Logs__e` platform event |

### Custom Objects

| Object | Purpose |
|--------|---------|
| `Dynamic_Form_Config__c` | Stores JSON form configurations (`Title__c`, `Label__c`, `Form_Config__c`) |
| `Form_Session__c` | Persists user session state — answers, current step, OTP, status |
| `Research_Proposal__c` | Stores cohort/proposal records created on form submission |
| `Apex_Log__c` | Structured log storage (level, class, method, message, stack trace) |
| `Apex_Logs__e` | Platform event for real-time log streaming |

---

## Session & Security Model

- Sessions identified by **SHA-256 token** sent to user's email — no passwords
- OTP codes expire after **10 minutes**; sessions expire after **30 days** of inactivity
- All controllers run `without sharing` to support **Guest Site** (public form access)
- Sandbox email redirect — all outbound emails route to an allow-list in non-production orgs

---

## Validation Flow

```
User clicks Next / Submit
 └── formWizardContainer.handleNext()
      └── formStepRenderer.validateStep()
           └── formSection.validateSection()
                └── dynamicInput.validate()    ← per-field rules
                └── customComponent.validate() ← custom section rules
      If valid   → save session → advance step
      If invalid → display inline errors, block navigation
```

---

## Setup & Deployment

> This project was built for a specific Salesforce org. To run it in a new org, the following setup is required.

### Prerequisites

- Salesforce CLI (`sf`) installed
- API version 65.0+ org

### 1. Deploy metadata

```bash
sf project deploy start --source-dir force-app --target-org <your-org-alias>
```

### 2. Create form config records

Insert `Dynamic_Form_Config__c` records with your JSON config. Sample configs are in `object-data/`.

```bash
# Using Salesforce CLI data import
sf data import tree --files object-data/Form_Wizard_Config__c.json --target-org <your-org-alias>
```

### 3. Assign permission set

```bash
sf org assign permset --name Public_Request_Form --target-org <your-org-alias>
```

### 4. Add the component to a page

Open **App Builder**, add `formWizardContainer` or `formWizardSelector` to any Lightning page or Experience Cloud site.

---

## Project Structure

```
force-app/main/default/
├── classes/           # Apex controllers, services, handlers, tests
├── lwc/               # Lightning Web Components
│   ├── formWizardContainer/
│   ├── formStepRenderer/
│   ├── formSection/
│   ├── dynamicInput/
│   ├── emailVerification/
│   ├── formShippingSection/
│   ├── formCohortSection/
│   ├── formCohortIterator/
│   ├── formNavigation/
│   ├── formProgressBar/
│   ├── formWizardSelector/
│   └── formUtils/
├── objects/           # Custom object metadata
├── email/             # Email templates
├── flexipages/        # Lightning page configurations
├── permissionsets/    # Permission set definitions
└── tabs/              # Custom tab definitions

object-data/
└── form-wizard-config/   # Sample JSON form configuration records
```

---

## Technical Highlights

- **Interface-based handler pattern** — adding a new form type only requires implementing `I_FormSubmissionHandler`; the wizard instantiates handlers dynamically by class name from config
- **Configuration-driven rendering** — `dynamicInput` handles 9 field types from a single template using conditional rendering; no per-field LWC needed
- **Debounced auto-save** — 1.5s debounce on every `answerchange` event prevents excessive Apex calls while ensuring no data loss
- **Token-based resumption** — SHA-256 session token delivered by email; stateless URL — users can resume from any device/browser
- **Embedded HTML step type** — `html-only` steps support `{{fieldName}}` interpolation from session answers (e.g. confirmation page with application number)
