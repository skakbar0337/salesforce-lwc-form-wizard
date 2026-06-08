List<Form_Wizard_Config__c> configs = [SELECT Id FROM Form_Wizard_Config__c];
System.debug('Found ' + configs.size() + ' records to delete');
delete configs;
System.debug('Successfully deleted all Form_Wizard_Config__c records');
