public with sharing class BillingCorrectionController {
    @AuraEnabled
    public static String loadReview(String quoteId) {
        SBQQ__Quote__c quote = getDraftAmendment(quoteId);
        List<SBQQ__QuoteLine__c> lines = getQuoteLines(quote.Id);
        validateLinePairs(lines);

        List<Object> rows = new List<Object>();
        Decimal totalMrr = 0;
        for (SBQQ__QuoteLine__c line : lines) {
            Boolean original = line.SBQQ__Existing__c == true;
            Boolean isToolCopy = String.isNotBlank(line.Billing_Correction_Clone_Source_Id__c);
            Date startDate = line.SBQQ__EffectiveStartDate__c != null
                ? line.SBQQ__EffectiveStartDate__c : line.SBQQ__StartDate__c;
            Date endDate = line.SBQQ__EffectiveEndDate__c != null
                ? line.SBQQ__EffectiveEndDate__c : line.SBQQ__EndDate__c;
            Decimal lineMrr = line.SBCF_MRR__c == null ? 0 : line.SBCF_MRR__c;
            totalMrr += lineMrr;
            rows.add(new Map<String, Object>{
                'id' => line.Id,
                'name' => line.Name,
                'productName' => line.SBQQ__Product__r == null ? 'Unknown product' : line.SBQQ__Product__r.Name,
                'role' => original ? 'Reversal' : (isToolCopy ? 'Copied line' : 'New line'),
                'original' => original,
                'editable' => !original,
                'isToolCopy' => isToolCopy,
                'cloneSourceId' => line.Billing_Correction_Clone_Source_Id__c,
                'canZeroSource' => original,
                'quantity' => line.SBQQ__Quantity__c,
                'effectiveQuantity' => line.SBQQ__EffectiveQuantity__c,
                'parentLineId' => line.SBQQ__RequiredBy__c,
                'isBundle' => line.SBQQ__Bundle__c,
                'startDate' => startDate,
                'endDate' => endDate,
                'additionalDiscount' => line.SBQQ__Discount__c,
                'additionalDiscountAmount' => line.SBQQ__AdditionalDiscountAmount__c,
                'discountUnit' => line.AdditionalDiscountUnit__c,
                'netPrice' => line.SBQQ__NetPrice__c,
                'netTotal' => line.SBQQ__NetTotal__c,
                'mrr' => lineMrr,
                'customerPrice' => line.SBQQ__CustomerPrice__c,
                'proratedListPrice' => line.SBQQ__ProratedListPrice__c
            });
        }
        return JSON.serialize(new Map<String, Object>{
            'quoteId' => quote.Id,
            'quoteName' => quote.Name,
            'quoteStatus' => quote.SBQQ__Status__c,
            'currencyIsoCode' => 'USD',
            'suggestedEndDate' => quote.SBQQ__EndDate__c,
            'uncalculated' => quote.SBQQ__Uncalculated__c,
            'lastCalculatedOn' => quote.SBQQ__LastCalculatedOn__c,
            'totalMrr' => totalMrr,
            'lines' => rows
        });
    }

    @AuraEnabled
    public static String calculateAndSave(String quoteId, Date quoteEndDate, String changesJson) {
        if (quoteEndDate == null) {
            throw new AuraHandledException('Enter a quote end date.');
        }
        SBQQ__Quote__c quote = getDraftAmendment(quoteId);
        if (quote.SBQQ__StartDate__c != null && quoteEndDate < quote.SBQQ__StartDate__c) {
            throw new AuraHandledException('The quote end date cannot be before its start date.');
        }
        List<SBQQ__QuoteLine__c> persistedLines = getQuoteLines(quote.Id);
        validateLinePairs(persistedLines);
        Map<Id, Map<String, Object>> changesById = parseChanges(changesJson);

        Map<Id, SBQQ__QuoteLine__c> persistedById = new Map<Id, SBQQ__QuoteLine__c>(persistedLines);
        if (!persistedById.keySet().containsAll(changesById.keySet())) {
            throw new AuraHandledException('A submitted line does not belong to this quote. Refresh and try again.');
        }

        Map<String, Object> quoteModel = (Map<String, Object>) JSON.deserializeUntyped(
            SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', String.valueOf(quote.Id))
        );
        Map<String, Object> quoteRecord = (Map<String, Object>) quoteModel.get('record');
        quoteRecord.put('SBQQ__EndDate__c', String.valueOf(quoteEndDate));

        Integer updatedNewLines = 0;
        List<Object> modelLines = (List<Object>) quoteModel.get('lineItems');
        for (Object lineObject : modelLines) {
            Map<String, Object> lineModel = (Map<String, Object>) lineObject;
            Map<String, Object> record = (Map<String, Object>) lineModel.get('record');
            Id lineId = (Id) record.get('Id');
            if (!changesById.containsKey(lineId)) continue;

            SBQQ__QuoteLine__c persisted = persistedById.get(lineId);
            if (persisted.SBQQ__Existing__c == true) {
                throw new AuraHandledException('Original reversal lines are locked. Only new lines can be changed.');
            }
            Map<String, Object> change = changesById.get(lineId);
            Decimal quantity = asDecimal(change.get('quantity'));
            Date startDate = asDate(change.get('startDate'));
            Date endDate = asDate(change.get('endDate'));
            String discountMode = String.valueOf(change.get('discountMode'));
            if (quantity == null || quantity < 0 || startDate == null || endDate == null || startDate > endDate) {
                throw new AuraHandledException('Each selected new line needs a nonnegative quantity and valid dates.');
            }

            record.put('SBQQ__Quantity__c', quantity);
            record.put('SBQQ__StartDate__c', String.valueOf(startDate));
            record.put('SBQQ__EndDate__c', String.valueOf(endDate));
            if (discountMode == 'Percent') {
                Decimal discountPercent = asDecimal(change.get('additionalDiscountPercent'));
                if (discountPercent == null || discountPercent > 100)
                    throw new AuraHandledException('Enter an additional discount of 100% or less. A negative percentage increases the price.');
                record.put('SBQQ__Discount__c', discountPercent);
                record.put('SBQQ__AdditionalDiscountAmount__c', null);
                record.put('AdditionalDiscountUnit__c', 'Percent');
            } else if (discountMode == 'Amount') {
                Decimal discountAmount = asDecimal(change.get('additionalDiscountAmount'));
                if (discountAmount == null || discountAmount < 0)
                    throw new AuraHandledException('Enter a nonnegative dollar discount per unit.');
                Decimal regularPrice = persisted.SBQQ__RegularPrice__c;
                if (regularPrice == null || discountAmount > regularPrice)
                    throw new AuraHandledException('The per-unit dollar discount cannot exceed the line’s current regular unit price.');
                Decimal amountModePercent = (discountAmount / regularPrice) * 100;
                record.put('SBQQ__Discount__c', amountModePercent);
                record.put('SBQQ__AdditionalDiscountAmount__c', null);
                // Convert the requested dollar-per-unit reduction to percent before CPQ calculates.
                record.put('AdditionalDiscountUnit__c', 'Percent');
            } else if (discountMode == 'Target Net Total') {
                Decimal targetNetTotal = asDecimal(change.get('targetNetTotal'));
                if (targetNetTotal == null || targetNetTotal < 0 || quantity <= 0)
                    throw new AuraHandledException('A target Net Total requires a nonnegative target and a positive quantity.');
                Decimal priorCustomerPrice = persisted.SBQQ__CustomerPrice__c;
                Decimal priorNetPrice = persisted.SBQQ__NetPrice__c;
                if (priorCustomerPrice == null || priorCustomerPrice <= 0 || priorNetPrice == null || priorNetPrice <= 0)
                    throw new AuraHandledException('This line has no positive saved customer price to use as a target basis. Choose a discount directly for this line.');
                Decimal netToCustomerRatio = priorNetPrice / priorCustomerPrice;
                Decimal targetCustomerPrice = (targetNetTotal / quantity) / netToCustomerRatio;
                Decimal priorProratedListPrice = persisted.SBQQ__ProratedListPrice__c;
                if (priorProratedListPrice == null || priorProratedListPrice <= 0)
                    throw new AuraHandledException('This line has no positive prorated list price to use as a target basis.');
                Decimal targetDiscountPercent = targetAdditionalDiscountPercent(
                    targetNetTotal, quantity, netToCustomerRatio, priorProratedListPrice
                );

                record.put('SBQQ__Discount__c', targetDiscountPercent);
                record.put('SBQQ__AdditionalDiscountAmount__c', null);
                record.put('AdditionalDiscountUnit__c', 'Percent');
            } else {
                throw new AuraHandledException('Choose a valid discount method for every selected new line.');
            }
            updatedNewLines++;
        }
        if (updatedNewLines != changesById.size()) {
            throw new AuraHandledException('A requested new line could not be found in the CPQ quote model. Refresh and retry.');
        }

        String calculatedJson = SBQQ.ServiceRouter.load(
            'SBQQ.QuoteAPI.QuoteCalculator', null,
            JSON.serialize(new Map<String, Object>{ 'quote' => quoteModel, 'callbackClass' => 'QuoteCalculatorCallback' })
        );
        Map<String, Object> calculated = (Map<String, Object>) JSON.deserializeUntyped(calculatedJson);
        List<Object> calculatedLines = (List<Object>) calculated.get('lineItems');
        return JSON.serialize(new Map<String, Object>{
            'quoteId' => quote.Id,
            'quoteName' => quote.Name,
            'lineCount' => calculatedLines == null ? 0 : calculatedLines.size(),
            'status' => 'Calculation queued. CPQ will calculate and save the draft quote. Reversal lines were left unchanged; additional discount was applied only to new lines.'
        });
    }

    @AuraEnabled
    public static String duplicateAndZeroSelected(String quoteId, String zeroSourceLineIdsJson) {
        SBQQ__Quote__c quote = getDraftAmendment(quoteId);
        List<SBQQ__QuoteLine__c> persistedLines = getQuoteLines(quote.Id);
        validateLinePairs(persistedLines);
        Map<Id, SBQQ__QuoteLine__c> persistedById = new Map<Id, SBQQ__QuoteLine__c>(persistedLines);
        Set<Id> selectedIds = parseSelectedLineIds(zeroSourceLineIdsJson);
        if (!persistedById.keySet().containsAll(selectedIds)) {
            throw new AuraHandledException('A selected line is not on this quote. Refresh and try again.');
        }

        Map<String, Object> quoteModel = (Map<String, Object>) JSON.deserializeUntyped(
            SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', String.valueOf(quote.Id))
        );
        Integer copiedLineCount = duplicateAndZeroInModel(quoteModel, selectedIds, persistedById);
        String calculatedJson = SBQQ.ServiceRouter.load(
            'SBQQ.QuoteAPI.QuoteCalculator', null,
            JSON.serialize(new Map<String, Object>{ 'quote' => quoteModel, 'callbackClass' => 'QuoteCalculatorCallback' })
        );
        Map<String, Object> calculated = (Map<String, Object>) JSON.deserializeUntyped(calculatedJson);
        List<Object> calculatedLines = (List<Object>) calculated.get('lineItems');
        return JSON.serialize(new Map<String, Object>{
            'quoteId' => quote.Id,
            'quoteName' => quote.Name,
            'lineCount' => calculatedLines == null ? 0 : calculatedLines.size(),
            'duplicatedLineCount' => copiedLineCount,
            'zeroedLineCount' => copiedLineCount,
            'status' => 'CPQ queued copies of the matched new lines and set those matched source quantities to zero. Existing locked reversal lines were left unchanged; the draft quote is not ordered.'
        });
    }

    private static SBQQ__Quote__c getDraftAmendment(String quoteId) {
        if (String.isBlank(quoteId)) throw new AuraHandledException('Open a draft CPQ amendment quote first.');
        List<SBQQ__Quote__c> quotes;
        try {
            quotes = [SELECT Id, Name, SBQQ__Status__c, SBQQ__Type__c, SBQQ__Ordered__c,
                SBQQ__StartDate__c, SBQQ__EndDate__c, SBQQ__Uncalculated__c,
                SBQQ__LastCalculatedOn__c
                FROM SBQQ__Quote__c WHERE Id = :quoteId WITH USER_MODE LIMIT 1];
        } catch (Exception ex) {
            throw new AuraHandledException('You do not have access to read this quote.');
        }
        if (quotes.isEmpty()) throw new AuraHandledException('The quote was not found or is not available to you.');
        SBQQ__Quote__c quote = quotes[0];
        if (quote.SBQQ__Type__c != 'Amendment') throw new AuraHandledException('This tool only works on CPQ amendment quotes.');
        if (quote.SBQQ__Status__c != 'Draft' || quote.SBQQ__Ordered__c == true)
            throw new AuraHandledException('Only a draft, unordered amendment can be changed.');
        return quote;
    }

    private static List<SBQQ__QuoteLine__c> getQuoteLines(Id quoteId) {
        try {
            return [SELECT Id, Name, SBQQ__Product__c, SBQQ__Product__r.Name, SBQQ__Existing__c,
                SBQQ__Quantity__c, SBQQ__EffectiveQuantity__c, SBQQ__RequiredBy__c, SBQQ__Bundle__c,
                Billing_Correction_Clone_Source_Id__c,
                SBQQ__StartDate__c, SBQQ__EndDate__c,
                SBQQ__EffectiveStartDate__c, SBQQ__EffectiveEndDate__c, SBQQ__Discount__c,
                SBQQ__AdditionalDiscountAmount__c, AdditionalDiscountUnit__c,
                SBQQ__NetPrice__c, SBQQ__NetTotal__c, SBQQ__CustomerPrice__c,
                SBQQ__RegularPrice__c, SBQQ__ProratedListPrice__c, SBCF_MRR__c
                FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quoteId WITH USER_MODE ORDER BY Name];
        } catch (Exception ex) {
            throw new AuraHandledException('You do not have access to read the quote lines.');
        }
    }

    private static Map<Id, Map<String, Object>> parseChanges(String changesJson) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        List<Object> rawChanges = (List<Object>) JSON.deserializeUntyped(changesJson);
        for (Object raw : rawChanges) {
            Map<String, Object> item = (Map<String, Object>) raw;
            Id lineId = (Id) item.get('id');
            if (lineId == null || result.containsKey(lineId)) throw new AuraHandledException('The submitted line changes are invalid.');
            result.put(lineId, item);
        }
        return result;
    }

    private static Decimal asDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static Set<Id> parseSelectedLineIds(String selectedLineIdsJson) {
        if (String.isBlank(selectedLineIdsJson)) {
            throw new AuraHandledException('Select one or more new quote lines first.');
        }
        Set<Id> selectedIds = new Set<Id>();
        for (Object rawId : (List<Object>) JSON.deserializeUntyped(selectedLineIdsJson)) {
            Id lineId = rawId == null ? null : Id.valueOf(String.valueOf(rawId));
            if (lineId != null) selectedIds.add(lineId);
        }
        if (selectedIds.isEmpty()) throw new AuraHandledException('Select one or more new quote lines first.');
        return selectedIds;
    }

    private static Integer asInteger(Object value) {
        return value == null ? null : Integer.valueOf(String.valueOf(value));
    }

    @TestVisible
    private static Integer duplicateAndZeroInModel(
        Map<String, Object> quoteModel,
        Set<Id> selectedIds,
        Map<Id, SBQQ__QuoteLine__c> persistedById
    ) {
        List<Object> lineItems = (List<Object>) quoteModel.get('lineItems');
        Map<Integer, Map<String, Object>> linesByKey = new Map<Integer, Map<String, Object>>();
        Map<Id, Map<String, Object>> linesById = new Map<Id, Map<String, Object>>();
        for (Object rawLine : lineItems) {
            Map<String, Object> line = (Map<String, Object>) rawLine;
            Map<String, Object> record = (Map<String, Object>) line.get('record');
            Integer key = asInteger(line.get('key'));
            Id lineId = record.get('Id') == null ? null : Id.valueOf(String.valueOf(record.get('Id')));
            if (key != null) linesByKey.put(key, line);
            if (lineId != null) linesById.put(lineId, line);
        }

        Set<Integer> selectedLockedRootKeys = new Set<Integer>();
        for (Id selectedId : selectedIds) {
            SBQQ__QuoteLine__c persisted = persistedById.get(selectedId);
            if (persisted == null || persisted.SBQQ__Existing__c != true) {
                throw new AuraHandledException('For this action, select only the locked existing reversal lines in the second selector column.');
            }
            Map<String, Object> line = linesById.get(selectedId);
            if (line == null) throw new AuraHandledException('A selected line was not found in the CPQ quote model. Refresh and try again.');
            Integer rootKey = asInteger(line.get('key'));
            Integer parentKey = asInteger(line.get('parentItemKey'));
            while (parentKey != null) {
                Map<String, Object> parent = linesByKey.get(parentKey);
                if (parent == null) throw new AuraHandledException('The selected bundle is missing its parent line.');
                rootKey = parentKey;
                parentKey = asInteger(parent.get('parentItemKey'));
            }
            Map<String, Object> rootRecord = (Map<String, Object>) linesByKey.get(rootKey).get('record');
            if (rootRecord.get('SBQQ__Existing__c') != true) {
                throw new AuraHandledException('The selected locked line is not part of an existing reversal group.');
            }
            selectedLockedRootKeys.add(rootKey);
        }

        Set<Integer> positiveTargetKeys = new Set<Integer>();
        for (Integer lockedRootKey : selectedLockedRootKeys) {
            Set<Integer> lockedGroup = collectGroupKeys(lockedRootKey, lineItems, linesByKey, true);
            String lockedSignature = groupSignature(lockedGroup, linesByKey);
            Set<Integer> matchingPositiveRoots = new Set<Integer>();
            for (Object rawLine : lineItems) {
                Map<String, Object> candidate = (Map<String, Object>) rawLine;
                if (asInteger(candidate.get('parentItemKey')) != null) continue;
                Map<String, Object> candidateRecord = (Map<String, Object>) candidate.get('record');
                if (candidateRecord.get('SBQQ__Existing__c') == true) continue;
                Integer candidateRootKey = asInteger(candidate.get('key'));
                Set<Integer> candidateGroup = collectGroupKeys(candidateRootKey, lineItems, linesByKey, false);
                if (groupSignature(candidateGroup, linesByKey) != lockedSignature) continue;
                Boolean allPositive = true;
                for (Integer groupKey : candidateGroup) {
                    Map<String, Object> groupRecord = (Map<String, Object>) linesByKey.get(groupKey).get('record');
                    if (asDecimal(groupRecord.get('SBQQ__Quantity__c')) == null ||
                        asDecimal(groupRecord.get('SBQQ__Quantity__c')) <= 0) {
                        allPositive = false;
                        break;
                    }
                }
                if (allPositive) matchingPositiveRoots.add(candidateRootKey);
            }
            if (matchingPositiveRoots.isEmpty()) {
                throw new AuraHandledException('No positive new product or bundle matches the selected locked lines.');
            }
            if (matchingPositiveRoots.size() > 1) {
                throw new AuraHandledException('More than one positive new bundle matches these locked lines. Resolve the duplicate positive groups first, then retry.');
            }
            Integer matchingRootKey = matchingPositiveRoots.iterator().next();
            positiveTargetKeys.addAll(collectGroupKeys(matchingRootKey, lineItems, linesByKey, false));
        }

        List<Map<String, Object>> sourceLines = new List<Map<String, Object>>();
        for (Object rawLine : lineItems) {
            Map<String, Object> line = (Map<String, Object>) rawLine;
            if (positiveTargetKeys.contains(asInteger(line.get('key')))) sourceLines.add(line);
        }
        if (sourceLines.isEmpty()) throw new AuraHandledException('No eligible new quote lines were found.');

        Integer nextKey = asInteger(quoteModel.get('nextKey'));
        if (nextKey == null) throw new AuraHandledException('The CPQ quote model is missing its next line key.');
        Map<Integer, Integer> copiedKeys = new Map<Integer, Integer>();
        for (Map<String, Object> sourceLine : sourceLines) {
            copiedKeys.put(asInteger(sourceLine.get('key')), nextKey++);
        }

        List<Object> copies = new List<Object>();
        for (Map<String, Object> sourceLine : sourceLines) {
            Map<String, Object> sourceRecord = (Map<String, Object>) sourceLine.get('record');
            Decimal sourceQuantity = asDecimal(sourceRecord.get('SBQQ__Quantity__c'));
            sourceRecord.put('SBQQ__Quantity__c', 0);

            Map<String, Object> copyLine = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(sourceLine));
            Map<String, Object> copyRecord = (Map<String, Object>) copyLine.get('record');
            copyRecord.remove('Id');
            copyRecord.remove('Name');
            copyRecord.remove('SBQQ__Number__c');
            copyRecord.remove('SBQQ__RequiredBy__r');
            copyRecord.put('SBQQ__Existing__c', false);
            copyRecord.put('SBQQ__Quantity__c', sourceQuantity);
            copyRecord.put('Billing_Correction_Clone_Source_Id__c', String.valueOf(sourceRecord.get('Id')));
            if (copyRecord.containsKey('SBQQ__RequiredBy__c')) copyRecord.put('SBQQ__RequiredBy__c', null);

            Integer oldKey = asInteger(sourceLine.get('key'));
            Integer oldParentKey = asInteger(sourceLine.get('parentItemKey'));
            copyLine.put('key', copiedKeys.get(oldKey));
            copyLine.put('parentItemKey', oldParentKey == null ? null : copiedKeys.get(oldParentKey));
            copies.add(copyLine);
        }
        lineItems.addAll(copies);
        quoteModel.put('nextKey', nextKey);
        return copies.size();
    }

    private static Set<Integer> collectGroupKeys(
        Integer rootKey,
        List<Object> lineItems,
        Map<Integer, Map<String, Object>> linesByKey,
        Boolean existing
    ) {
        Set<Integer> groupKeys = new Set<Integer>{ rootKey };
        Boolean addedLine = true;
        while (addedLine) {
            addedLine = false;
            for (Object rawLine : lineItems) {
                Map<String, Object> line = (Map<String, Object>) rawLine;
                Integer key = asInteger(line.get('key'));
                Integer parentKey = asInteger(line.get('parentItemKey'));
                if (parentKey == null || !groupKeys.contains(parentKey) || groupKeys.contains(key)) continue;
                Map<String, Object> record = (Map<String, Object>) line.get('record');
                if ((record.get('SBQQ__Existing__c') == true) != existing) continue;
                groupKeys.add(key);
                addedLine = true;
            }
        }
        return groupKeys;
    }

    private static String groupSignature(
        Set<Integer> groupKeys,
        Map<Integer, Map<String, Object>> linesByKey
    ) {
        List<String> components = new List<String>();
        for (Integer key : groupKeys) {
            Map<String, Object> line = linesByKey.get(key);
            Map<String, Object> record = (Map<String, Object>) line.get('record');
            List<String> ancestry = new List<String>();
            Integer parentKey = asInteger(line.get('parentItemKey'));
            while (parentKey != null) {
                Map<String, Object> parent = linesByKey.get(parentKey);
                Map<String, Object> parentRecord = (Map<String, Object>) parent.get('record');
                ancestry.add(String.valueOf(parentRecord.get('SBQQ__Product__c')));
                parentKey = asInteger(parent.get('parentItemKey'));
            }
            String path = '';
            for (Integer index = ancestry.size() - 1; index >= 0; index--) {
                path += (path == '' ? '' : '/') + ancestry[index];
            }
            String productId = String.valueOf(record.get('SBQQ__Product__c'));
            String optionId = record.get('SBQQ__ProductOption__c') == null
                ? '' : String.valueOf(record.get('SBQQ__ProductOption__c'));
            String isBundle = String.valueOf(record.get('SBQQ__Bundle__c'));
            components.add(path + '>' + productId + ':' + optionId + ':' + isBundle);
        }
        components.sort();
        return String.join(components, '|');
    }
    @TestVisible
    private static Decimal targetAdditionalDiscountPercent(
        Decimal targetNetTotal,
        Decimal quantity,
        Decimal netToCustomerRatio,
        Decimal proratedListPrice
    ) {
        if (targetNetTotal == null || targetNetTotal < 0 ||
            quantity == null || quantity <= 0 ||
            netToCustomerRatio == null || netToCustomerRatio <= 0 ||
            proratedListPrice == null || proratedListPrice <= 0) {
            throw new AuraHandledException('A valid target, quantity, price ratio, and prorated list price are required.');
        }
        Decimal targetCustomerPrice = (targetNetTotal / quantity) / netToCustomerRatio;
        return ((proratedListPrice - targetCustomerPrice) / proratedListPrice) * 100;
    }
    private static Date asDate(Object value) {
        return value == null ? null : Date.valueOf(String.valueOf(value));
    }

    @TestVisible
    private static void validateLinePairs(List<SBQQ__QuoteLine__c> lines) {
        Set<String> originalProducts = new Set<String>();
        Set<String> newProducts = new Set<String>();
        for (SBQQ__QuoteLine__c line : lines) {
            if (line.SBQQ__Product__c == null) throw new AuraHandledException('Every amendment line must have a product.');
            String productId = String.valueOf(line.SBQQ__Product__c);
            if (line.SBQQ__Existing__c == true) {
                // CPQ keeps the source subscription quantity on existing amendment lines.
                // The reversal is represented by EffectiveQuantity, not necessarily Quantity = 0.
                originalProducts.add(productId);
            } else {
                if (line.SBQQ__Quantity__c == null || line.SBQQ__Quantity__c < 0)
                    throw new AuraHandledException('A new line cannot have a negative effective quantity.');
                newProducts.add(productId);
            }
        }
        if (originalProducts.isEmpty() || !originalProducts.containsAll(newProducts))
            throw new AuraHandledException('New lines must match products that have an original reversal line.');
    }
}
