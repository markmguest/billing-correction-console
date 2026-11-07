@IsTest
private class BillingCorrectionControllerTest {
    @IsTest
    static void calculatesNegativePercentForTargetAboveProratedList() {
        System.assertEquals(
            -20,
            BillingCorrectionController.targetAdditionalDiscountPercent(120, 1, 1, 100)
        );
        System.assertEquals(
            20,
            BillingCorrectionController.targetAdditionalDiscountPercent(80, 1, 1, 100)
        );
    }
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
    static void acceptsReplacementBundleWithDifferentProducts() {
        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIMM3QAP',
                SBQQ__Existing__c = true,
                SBQQ__Quantity__c = 1
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Product__c = '01t1M00000NIT30QAH',
                SBQQ__Existing__c = false,
                SBQQ__Quantity__c = 1
            )
        };
        BillingCorrectionController.validateLinePairs(lines);
        System.assert(true, 'A new plan bundle may replace an existing product bundle.');
    }

    @IsTest
    static void rejectsNewLinesWithoutAnyExistingAmendmentLine() {
        Boolean rejected = false;
        try {
            BillingCorrectionController.validateLinePairs(new List<SBQQ__QuoteLine__c>{
                new SBQQ__QuoteLine__c(
                    SBQQ__Product__c = '01t1M00000NIT30QAH',
                    SBQQ__Existing__c = false,
                    SBQQ__Quantity__c = 1
                )
            });
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'New replacement lines still require a locked existing line on the amendment.');
    }

    @IsTest
    static void duplicatesLockedBundleAndZeroesItsOriginalQuantities() {
        Id lockedParentId = 'a62Em000007UCR7IAO';
        Id lockedChildId = 'a62Em000007UCR8IAO';
        Id upgradedSubscriptionId = 'a6FQi000000nsvOMAQ';
        Map<String, Object> lockedParentRecord = new Map<String, Object>{
            'Id' => lockedParentId,
            'SBQQ__Product__c' => '01t1M00000NIMM3QAP',
            'SBQQ__Quantity__c' => 2,
            'SBQQ__EffectiveQuantity__c' => 0,
            'SBQQ__Existing__c' => true,
            'SBQQ__Bundle__c' => true,
            'SBQQ__UpgradedSubscription__c' => upgradedSubscriptionId
        };
        Map<String, Object> lockedChildRecord = new Map<String, Object>{
            'Id' => lockedChildId,
            'SBQQ__Product__c' => '01t1M00000NIT30QAH',
            'SBQQ__ProductOption__c' => 'a5kEm0000000001IAA',
            'SBQQ__Quantity__c' => 3,
            'SBQQ__EffectiveQuantity__c' => 0,
            'SBQQ__Existing__c' => true,
            'SBQQ__RequiredBy__c' => lockedParentId,
            'SBQQ__UpgradedSubscription__c' => upgradedSubscriptionId
        };
        Map<String, Object> lockedParentModel = new Map<String, Object>{
            'key' => 7, 'parentItemKey' => null, 'record' => lockedParentRecord
        };
        Map<String, Object> lockedChildModel = new Map<String, Object>{
            'key' => 8, 'parentItemKey' => 7, 'record' => lockedChildRecord
        };
        Map<String, Object> quoteModel = new Map<String, Object>{
            'nextKey' => 9,
            'lineItems' => new List<Object>{ lockedParentModel, lockedChildModel }
        };
        Map<Id, SBQQ__QuoteLine__c> persistedById = new Map<Id, SBQQ__QuoteLine__c>{
            lockedParentId => new SBQQ__QuoteLine__c(
                Id = lockedParentId, SBQQ__Existing__c = true,
                SBQQ__Quantity__c = 2
            ),
            lockedChildId => new SBQQ__QuoteLine__c(
                Id = lockedChildId, SBQQ__Existing__c = true,
                SBQQ__Quantity__c = 3
            )
        };

        Integer copiedCount = BillingCorrectionController.duplicateAndZeroInModel(
            quoteModel, new Set<Id>{ lockedParentId }, persistedById
        );

        List<Object> updatedLines = (List<Object>) quoteModel.get('lineItems');
        System.assertEquals(4, updatedLines.size());
        System.assertEquals(2, copiedCount);
        System.assertEquals(0, lockedParentRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(0, lockedChildRecord.get('SBQQ__Quantity__c'));
        Map<String, Object> copiedParent = (Map<String, Object>) updatedLines[2];
        Map<String, Object> copiedChild = (Map<String, Object>) updatedLines[3];
        Map<String, Object> copiedParentRecord = (Map<String, Object>) copiedParent.get('record');
        Map<String, Object> copiedChildRecord = (Map<String, Object>) copiedChild.get('record');
        System.assertEquals(2, copiedParentRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(3, copiedChildRecord.get('SBQQ__Quantity__c'));
        System.assertEquals(false, copiedParentRecord.get('SBQQ__Existing__c'));
        System.assertEquals(false, copiedChildRecord.get('SBQQ__Existing__c'));
        System.assertEquals(null, copiedParentRecord.get('SBQQ__UpgradedSubscription__c'));
        System.assertEquals(null, copiedChildRecord.get('SBQQ__UpgradedSubscription__c'));
        System.assertEquals(null, copiedChildRecord.get('SBQQ__RequiredBy__c'));
        System.assertEquals(9, copiedParent.get('key'));
        System.assertEquals(9, copiedChild.get('parentItemKey'));
        System.assertEquals(String.valueOf(lockedParentId), copiedParentRecord.get('Billing_Correction_Clone_Source_Id__c'));
        System.assertEquals(String.valueOf(lockedChildId), copiedChildRecord.get('Billing_Correction_Clone_Source_Id__c'));
        System.assertEquals(11, quoteModel.get('nextKey'));
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
