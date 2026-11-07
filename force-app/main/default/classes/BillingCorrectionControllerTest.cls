@IsTest
private class BillingCorrectionControllerTest {
    @IsTest
    static void acceptsMatchedLinesWithDifferentQuantities() {
        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIMM3QAP',
                SBQQ__Existing__c = true,
                SBQQ__Quantity__c = 0
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIMM3QAP',
                SBQQ__Existing__c = false,
                SBQQ__Quantity__c = 2
            )
        };
        BillingCorrectionController.validateLinePairs(lines);
        System.assert(true, 'A correction may change the replacement quantity.');
    }

    @IsTest
    static void acceptsZeroQuantityOnNewLineToRemoveIt() {
        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIMM3QAP',
                SBQQ__Existing__c = true,
                SBQQ__Quantity__c = 0
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIMM3QAP',
                SBQQ__Existing__c = false,
                SBQQ__Quantity__c = 0
            )
        };
        BillingCorrectionController.validateLinePairs(lines);
        System.assert(true, 'A replacement quantity may be set to zero.');
    }

    @IsTest
    static void acceptsOriginalLineWithPersistedSubscriptionQuantity() {
        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIMM3QAP',
                SBQQ__Existing__c = true,
                SBQQ__Quantity__c = 1
            )
        };
        BillingCorrectionController.validateLinePairs(lines);
        System.assert(true, 'CPQ can retain the original quantity on a locked existing line.');
    }

    @IsTest
    static void rejectsReplacementWithoutMatchingOriginalProduct() {
        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIMM3QAP',
                SBQQ__Existing__c = true,
                SBQQ__Quantity__c = 0
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIT30QAH',
                SBQQ__Existing__c = false,
                SBQQ__Quantity__c = 1
            )
        };
        Boolean rejected = false;
        try {
            BillingCorrectionController.validateLinePairs(lines);
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'A new line must match a product with an original line.');
    }

    @IsTest
    static void duplicatesMatchingPositiveBundleAndLeavesLockedReversalsAlone() {
        Id lockedParentId = 'a62Em000007UCR7IAO';
        Id lockedChildId = 'a62Em000007UCR8IAO';
        Id positiveParentId = 'a62Em000007UCR9IAO';
        Id positiveChildId = 'a62Em000007UCRaIAO';
        Map<String, Object> lockedParentRecord = new Map<String, Object>{
            'Id' => lockedParentId,
            'SBQQ__Product__c' => '01t1M00000NIMM3QAP',
            'SBQQ__Quantity__c' => 2,
            'SBQQ__Existing__c' => true,
            'SBQQ__Bundle__c' => true
        };
        Map<String, Object> lockedChildRecord = new Map<String, Object>{
            'Id' => lockedChildId,
            'SBQQ__Product__c' => '01t1M00000NIT30QAH',
            'SBQQ__ProductOption__c' => 'a5kEm0000000001IAA',
            'SBQQ__Quantity__c' => 3,
            'SBQQ__Existing__c' => true,
            'SBQQ__RequiredBy__c' => lockedParentId
        };
        Map<String, Object> positiveParentRecord = new Map<String, Object>{
            'Id' => positiveParentId,
            'SBQQ__Product__c' => '01t1M00000NIMM3QAP',
            'SBQQ__Quantity__c' => 2,
            'SBQQ__Existing__c' => false,
            'SBQQ__Bundle__c' => true
        };
        Map<String, Object> positiveChildRecord = new Map<String, Object>{
            'Id' => positiveChildId,
            'SBQQ__Product__c' => '01t1M00000NIT30QAH',
            'SBQQ__ProductOption__c' => 'a5kEm0000000001IAA',
            'SBQQ__Quantity__c' => 3,
            'SBQQ__Existing__c' => false,
            'SBQQ__RequiredBy__c' => positiveParentId
        };
        Map<String, Object> lockedParentModel = new Map<String, Object>{
            'key' => 7, 'parentItemKey' => null, 'record' => lockedParentRecord
        };
        Map<String, Object> lockedChildModel = new Map<String, Object>{
            'key' => 8, 'parentItemKey' => 7, 'record' => lockedChildRecord
        };
        Map<String, Object> positiveParentModel = new Map<String, Object>{
            'key' => 9, 'parentItemKey' => null, 'record' => positiveParentRecord
        };
        Map<String, Object> positiveChildModel = new Map<String, Object>{
            'key' => 10, 'parentItemKey' => 9, 'record' => positiveChildRecord
        };
        Map<String, Object> quoteModel = new Map<String, Object>{
            'nextKey' => 11,
            'lineItems' => new List<Object>{
                lockedParentModel, lockedChildModel, positiveParentModel, positiveChildModel
            }
        };
        Map<Id, SBQQ__QuoteLine__c> persistedById = new Map<Id, SBQQ__QuoteLine__c>{
            lockedParentId => new SBQQ__QuoteLine__c(Id = lockedParentId, SBQQ__Existing__c = true, SBQQ__Quantity__c = 2),
            lockedChildId => new SBQQ__QuoteLine__c(Id = lockedChildId, SBQQ__Existing__c = true, SBQQ__Quantity__c = 3),
            positiveParentId => new SBQQ__QuoteLine__c(Id = positiveParentId, SBQQ__Existing__c = false, SBQQ__Quantity__c = 2),
            positiveChildId => new SBQQ__QuoteLine__c(Id = positiveChildId, SBQQ__Existing__c = false, SBQQ__Quantity__c = 3)
        };

        Integer copiedCount = BillingCorrectionController.duplicateAndZeroInModel(
            quoteModel, new Set<Id>{ lockedParentId }, persistedById
        );

        List<Object> updatedLines = (List<Object>) quoteModel.get('lineItems');
        System.assertEquals(6, updatedLines.size());
        System.assertEquals(2, copiedCount);
        System.assertEquals(2, lockedParentRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(3, lockedChildRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(0, positiveParentRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(0, positiveChildRecord.get('SBQQ__Quantity__c'));
        Map<String, Object> copiedParent = (Map<String, Object>) updatedLines[4];
        Map<String, Object> copiedChild = (Map<String, Object>) updatedLines[5];
        Map<String, Object> copiedParentRecord = (Map<String, Object>) copiedParent.get('record');
        Map<String, Object> copiedChildRecord = (Map<String, Object>) copiedChild.get('record');
        System.assertEquals(2, copiedParentRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(3, copiedChildRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(11, copiedParent.get('key'));
        System.assertEquals(11, copiedChild.get('parentItemKey'));
        System.assertEquals(false, copiedParentRecord.containsKey('Id'));
        System.assertEquals(false, copiedChildRecord.containsKey('Id'));
        System.assertEquals(String.valueOf(positiveParentId), copiedParentRecord.get('Billing_Correction_Clone_Source_Id__c'));
        System.assertEquals(String.valueOf(positiveChildId), copiedChildRecord.get('Billing_Correction_Clone_Source_Id__c'));
        System.assertEquals(13, quoteModel.get('nextKey'));
    }

    @IsTest
    static void rejectsToolCreatedCopyAsZeroSource() {
        Id copyId = 'a62Em000007UCR7IAO';
        Id sourceId = 'a62Em000007UAfSIAW';
        Map<String, Object> lineRecord = new Map<String, Object>{
            'Id' => copyId,
            'SBQQ__Quantity__c' => 1,
            'SBQQ__Existing__c' => false
        };
        Map<String, Object> lineModel = new Map<String, Object>{
            'key' => 1,
            'parentItemKey' => null,
            'record' => lineRecord
        };
        Map<String, Object> quoteModel = new Map<String, Object>{
            'nextKey' => 2,
            'lineItems' => new List<Object>{ lineModel }
        };
        Map<Id, SBQQ__QuoteLine__c> persistedById = new Map<Id, SBQQ__QuoteLine__c>{
            copyId => new SBQQ__QuoteLine__c(
                Id = copyId,
                SBQQ__Existing__c = false,
                SBQQ__Quantity__c = 1,
                Billing_Correction_Clone_Source_Id__c = String.valueOf(sourceId)
            )
        };
        Boolean rejected = false;
        try {
            BillingCorrectionController.duplicateAndZeroInModel(
                quoteModel, new Set<Id>{ copyId }, persistedById
            );
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'A tool-created copy must not be eligible as a source to zero.');
    }
}
