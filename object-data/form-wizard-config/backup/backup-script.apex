List<Form_Wizard_Config__c> configs = [SELECT Id, Title__c, Label__c, Form_Config__c FROM Form_Wizard_Config__c];
System.debug('=== BACKUP START ===');
for (Form_Wizard_Config__c config : configs) {
    System.debug(JSON.serializePretty(config));
}
System.debug('=== BACKUP END ===');
System.debug('Total records: ' + configs.size());
