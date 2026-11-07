import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadReview from '@salesforce/apex/BillingCorrectionController.loadReview';
import calculateAndSave from '@salesforce/apex/BillingCorrectionController.calculateAndSave';
import duplicateAndZeroSelected from '@salesforce/apex/BillingCorrectionController.duplicateAndZeroSelected';

export default class BillingCorrectionConsole extends LightningElement {
    _recordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) this.refreshReview();
    }

    review;
    quoteEndDate;
    lineDrafts = {};
    selectedLineIds = [];
    zeroSourceLineIds = [];
    bulkStartDate = '';
    bulkEndDate = '';
    bulkDiscountMode = '';
    bulkDiscountValue = '';
    isLoading = false;
    isSaving = false;
    showReview = false;
    showDuplicateReview = false;
    reviewed = false;
    confirmed = false;
    errorMessage;
    completionMessage;

    get lineRows() {
        if (!this.review) return [];
        return this.review.lines.map((line) => {
            const selected = this.selectedLineIds.includes(line.id);
            const draft = this.lineDrafts[line.id] || {};
            const defaultDiscountMode = line.discountUnit === 'Amount' ? 'Amount' : 'Percent';
            const discountMode = this.valueFor(line.id, 'discountMode', draft.discountMode || defaultDiscountMode);
            return {
                ...line,
                selected,
                selectedEditable: line.editable && selected,
                zeroSourceSelected: this.zeroSourceLineIds.includes(line.id),
                canZeroSource: line.canZeroSource,
                displayQuantity: line.quantity,
                displayEffectiveQuantity: line.effectiveQuantity,
                proposedQuantity: this.valueFor(line.id, 'quantity', line.quantity),
                proposedStartDate: this.valueFor(line.id, 'startDate', line.startDate),
                proposedEndDate: this.valueFor(line.id, 'endDate', line.endDate),
                discountMode,
                proposedDiscountPercent: this.valueFor(line.id, 'additionalDiscountPercent', line.additionalDiscount || 0),
                proposedDiscountAmount: this.valueFor(line.id, 'additionalDiscountAmount', line.additionalDiscountAmount || 0),
                proposedTargetNetTotal: this.valueFor(line.id, 'targetNetTotal', ''),
                isPercentMode: discountMode === 'Percent',
                isAmountMode: discountMode === 'Amount',
                isTargetMode: discountMode === 'Target Net Total',
                discountSummary: line.discountUnit === 'Amount'
                    ? `$${line.additionalDiscountAmount || 0} per unit`
                    : `${line.additionalDiscount || 0}%`
            };
        });
    }

    get allEditableSelected() {
        const newLines = (this.review?.lines || []).filter((line) => line.editable);
        return newLines.length > 0 && newLines.every((line) => this.selectedLineIds.includes(line.id));
    }

    get allZeroSourcesSelected() {
        const sources = (this.review?.lines || []).filter((line) => line.canZeroSource);
        return sources.length > 0 && sources.every((line) => this.zeroSourceLineIds.includes(line.id));
    }

    get hasSelectedLines() {
        return this.selectedLineIds.length > 0;
    }

    get hasNewLines() {
        return (this.review?.lines || []).some((line) => line.editable);
    }

    get hasZeroSourceSelection() {
        return this.zeroSourceLineIds.length > 0;
    }

    get zeroSourceSelectedCount() {
        return this.zeroSourceLineIds.length;
    }

    get selectedCount() {
        return this.selectedLineIds.length;
    }

    get reviewButtonDisabled() {
        return this.isLoading || this.isSaving || !this.quoteEndDate;
    }

    get refreshButtonDisabled() {
        return this.isLoading || this.isSaving;
    }

    get bulkApplyDisabled() {
        if (!this.hasSelectedLines || (!this.bulkStartDate && !this.bulkEndDate && !this.bulkDiscountMode)) return true;
        return Boolean(this.bulkDiscountMode) && this.bulkDiscountValue === '';
    }

    get bulkDiscountOptions() {
        return [
            { label: 'Percent', value: 'Percent' },
            { label: 'Dollar amount per unit', value: 'Amount' }
        ];
    }

    get discountOptions() {
        return [
            { label: 'Percent', value: 'Percent' },
            { label: 'Dollar amount per unit', value: 'Amount' },
            { label: 'Target Net Total', value: 'Target Net Total' }
        ];
    }

    get bulkDiscountMax() {
        return this.bulkDiscountMode === 'Percent' ? 100 : undefined;
    }

    get bulkDiscountValueDisabled() {
        return !this.bulkDiscountMode;
    }

    get saveButtonDisabled() {
        return this.isLoading || this.isSaving || !this.reviewed || !this.confirmed;
    }

    get duplicateButtonDisabled() {
        return this.isLoading || this.isSaving || !this.hasZeroSourceSelection;
    }

    get duplicateSaveButtonDisabled() {
        return this.isLoading || this.isSaving || !this.showDuplicateReview || !this.confirmed;
    }

    valueFor(id, field, fallback) {
        const value = this.lineDrafts[id]?.[field];
        return value === undefined || value === null ? fallback : value;
    }

    async refreshReview() {
        if (!this.recordId) return;
        this.isLoading = true;
        this.errorMessage = undefined;
        this.completionMessage = undefined;
        this.showReview = false;
        this.showDuplicateReview = false;
        this.reviewed = false;
        this.confirmed = false;
        try {
            const payload = await loadReview({ quoteId: this.recordId });
            this.review = JSON.parse(payload);
            this.quoteEndDate = this.review.suggestedEndDate;
            this.lineDrafts = {};
            this.selectedLineIds = [];
            this.zeroSourceLineIds = [];
            this.bulkStartDate = '';
            this.bulkEndDate = '';
            this.bulkDiscountMode = '';
            this.bulkDiscountValue = '';
        } catch (error) {
            this.review = undefined;
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleQuoteEndDateChange(event) {
        this.quoteEndDate = event.target.value;
        this.invalidateReview();
    }

    handleSelectLine(event) {
        const lineId = event.target.dataset.lineId;
        const groupIds = this.getBundleGroupIds(lineId);
        this.selectedLineIds = event.target.checked
            ? [...new Set([...this.selectedLineIds, ...groupIds])]
            : this.selectedLineIds.filter((id) => !groupIds.includes(id));
        this.invalidateReview();
    }

    getBundleGroupIds(lineId) {
        const lines = this.review?.lines || [];
        let root = lines.find((line) => line.id === lineId);
        if (!root) return [lineId];
        while (root.parentLineId) {
            const parent = lines.find((line) => line.id === root.parentLineId);
            if (!parent) break;
            root = parent;
        }
        const groupIds = new Set([root.id]);
        let foundChild = true;
        while (foundChild) {
            foundChild = false;
            for (const line of lines) {
                if (line.parentLineId && groupIds.has(line.parentLineId) && !groupIds.has(line.id)) {
                    groupIds.add(line.id);
                    foundChild = true;
                }
            }
        }
        return [...groupIds];
    }

    handleSelectAll(event) {
        const ids = (this.review?.lines || []).filter((line) => line.editable).map((line) => line.id);
        this.selectedLineIds = event.target.checked ? ids : [];
        this.invalidateReview();
    }

    handleSelectZeroSources(event) {
        const ids = (this.review?.lines || []).filter((line) => line.canZeroSource).map((line) => line.id);
        this.zeroSourceLineIds = event.target.checked ? ids : [];
        this.invalidateReview();
    }

    handleSelectZeroSourceLine(event) {
        const lineId = event.target.dataset.lineId;
        const groupIds = this.getBundleGroupIds(lineId)
            .filter((id) => this.review?.lines.find((line) => line.id === id)?.canZeroSource);
        this.zeroSourceLineIds = event.target.checked
            ? [...new Set([...this.zeroSourceLineIds, ...groupIds])]
            : this.zeroSourceLineIds.filter((id) => !groupIds.includes(id));
        this.invalidateReview();
    }

    handleLineChange(event) {
        const { lineId, field } = event.target.dataset;
        const raw = event.target.value;
        const value = ['quantity', 'additionalDiscountPercent', 'additionalDiscountAmount', 'targetNetTotal'].includes(field)
            ? (raw === '' ? '' : Number(raw))
            : raw;
        this.lineDrafts = {
            ...this.lineDrafts,
            [lineId]: { ...this.lineDrafts[lineId], [field]: value }
        };
        this.invalidateReview();
    }

    handleBulkChange(event) {
        this[event.target.name] = event.target.value;
        this.invalidateReview();
    }

    handleApplyBulk() {
        const nextDrafts = { ...this.lineDrafts };
        for (const id of this.selectedLineIds) {
            const draft = { ...nextDrafts[id] };
            if (this.bulkStartDate) draft.startDate = this.bulkStartDate;
            if (this.bulkEndDate) draft.endDate = this.bulkEndDate;
            if (this.bulkDiscountMode) {
                draft.discountMode = this.bulkDiscountMode;
                if (this.bulkDiscountMode === 'Percent') draft.additionalDiscountPercent = Number(this.bulkDiscountValue);
                if (this.bulkDiscountMode === 'Amount') draft.additionalDiscountAmount = Number(this.bulkDiscountValue);
            }
            nextDrafts[id] = draft;
        }
        this.lineDrafts = nextDrafts;
        this.bulkStartDate = '';
        this.bulkEndDate = '';
        this.bulkDiscountMode = '';
        this.bulkDiscountValue = '';
        this.invalidateReview();
    }

    invalidateReview() {
        this.showReview = false;
        this.showDuplicateReview = false;
        this.reviewed = false;
        this.confirmed = false;
        this.completionMessage = undefined;
        this.errorMessage = undefined;
    }

    handleReview() {
        const inputs = [...this.template.querySelectorAll('lightning-input[data-validate]')]
            .filter((input) => !input.disabled);
        const valid = inputs.reduce((allValid, input) => input.reportValidity() && allValid, true);
        if (!valid) return;
        for (const line of this.lineRows.filter((item) => item.selectedEditable)) {
            if (line.proposedStartDate > line.proposedEndDate) {
                this.errorMessage = `Start date must be on or before end date for ${line.productName}.`;
                return;
            }
            if (line.discountMode === 'Target Net Total' && line.proposedQuantity <= 0) {
                this.errorMessage = `Set a positive quantity before targeting Net Total for ${line.productName}.`;
                return;
            }
        }
        this.errorMessage = undefined;
        this.showDuplicateReview = false;
        this.showReview = true;
        this.reviewed = true;
        this.confirmed = false;
    }

    handleConfirm(event) {
        this.confirmed = event.target.checked;
    }

    handlePrepareDuplicate() {
        if (!this.hasZeroSourceSelection) {
            this.errorMessage = 'Select one or more locked reversal lines in the second column as bundle references.';
            return;
        }
        const hasUnsavedEdits = this.lineRows
            .some((line) => Object.keys(this.lineDrafts[line.id] || {}).length > 0);
        if (hasUnsavedEdits) {
            this.errorMessage = 'Save or refresh the line edits first. Duplication copies the currently saved quantities, dates, and discounts.';
            return;
        }
        this.errorMessage = undefined;
        this.showReview = false;
        this.reviewed = false;
        this.showDuplicateReview = true;
        this.confirmed = false;
    }

    async handleDuplicateAndZero() {
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const previousTimestamp = this.review.lastCalculatedOn;
            const selectedIdsJson = JSON.stringify(this.zeroSourceLineIds);
            const result = JSON.parse(await duplicateAndZeroSelected({
                quoteId: this.recordId,
                zeroSourceLineIdsJson: selectedIdsJson
            }));
            this.completionMessage = 'CPQ is copying the matching positive lines and setting their Qty to zero; locked reversal lines will remain unchanged…';
            const firstPass = await this.waitForCalculation(previousTimestamp);
            this.review = firstPass;

            await calculateAndSave({
                quoteId: this.recordId,
                quoteEndDate: firstPass.suggestedEndDate || this.quoteEndDate,
                changesJson: '[]'
            });
            this.completionMessage = 'The first CPQ calculation finished. Applying final copied line prices and MRR…';
            const finalReview = await this.waitForCalculation(firstPass.lastCalculatedOn);
            this.review = finalReview;
            this.quoteEndDate = finalReview.suggestedEndDate;
            this.lineDrafts = {};
            this.selectedLineIds = [];
            this.zeroSourceLineIds = [];
            this.showDuplicateReview = false;
            this.confirmed = false;
            this.completionMessage = `CPQ completed both calculations. It copied ${result.duplicatedLineCount} matched positive lines and zeroed those positive Qty values. Locked reversal lines remain unchanged. Review the saved Qty, Effective Quantity, Net Total, and MRR below.`;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Matched positive lines copied and zeroed',
                message: this.completionMessage,
                variant: 'success'
            }));
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Could not duplicate selected lines', message: this.errorMessage, variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    async handleCalculateAndSave() {
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const changes = this.lineRows.filter((line) => line.selectedEditable).map((line) => ({
                id: line.id,
                quantity: line.proposedQuantity,
                startDate: line.proposedStartDate,
                endDate: line.proposedEndDate,
                discountMode: line.discountMode,
                additionalDiscountPercent: line.proposedDiscountPercent,
                additionalDiscountAmount: line.proposedDiscountAmount,
                targetNetTotal: line.proposedTargetNetTotal
            }));
            const originalLastCalculatedOn = this.review.lastCalculatedOn;
            this.showReview = false;
            this.reviewed = false;
            this.confirmed = false;
            const resultJson = await calculateAndSave({
                quoteId: this.recordId,
                quoteEndDate: this.quoteEndDate,
                changesJson: JSON.stringify(changes)
            });
            const result = JSON.parse(resultJson);
            this.completionMessage = 'CPQ is calculating the quote, then will apply the final line prices…';
            const firstPass = await this.waitForCalculation(originalLastCalculatedOn);
            this.review = firstPass;

            const secondResultJson = await calculateAndSave({
                quoteId: this.recordId,
                quoteEndDate: this.quoteEndDate,
                changesJson: JSON.stringify(changes)
            });
            const secondResult = JSON.parse(secondResultJson);
            this.completionMessage = 'The first CPQ calculation finished. Applying final line prices and MRR…';
            const finalReview = await this.waitForCalculation(firstPass.lastCalculatedOn);
            this.review = finalReview;
            this.quoteEndDate = finalReview.suggestedEndDate;
            this.lineDrafts = {};
            this.selectedLineIds = [];
            const resultLines = changes
                .filter((line) => line.discountMode === 'Target Net Total')
                .map((change) => {
                    const savedLine = finalReview.lines.find((line) => line.id === change.id);
                    const target = Number(change.targetNetTotal);
                    const actual = Number(savedLine?.netTotal || 0);
                    return { target, actual, productName: savedLine?.productName || change.id };
                });
            if (resultLines.length && resultLines.every((line) => Math.abs(line.target - line.actual) <= 0.01)) {
                this.completionMessage = `CPQ completed both calculations. The selected target Net Total${resultLines.length > 1 ? 's' : ''} matched: ${resultLines.map((line) => `${line.productName} $${line.actual.toFixed(2)}`).join('; ')}.`;
            } else if (resultLines.length) {
                this.completionMessage = `CPQ completed both calculations. Review the saved totals: ${resultLines.map((line) => `${line.productName} target $${line.target.toFixed(2)}, saved $${line.actual.toFixed(2)}`).join('; ')}.`;
            } else if (changes.some((line) => line.discountMode === 'Amount')) {
                const savedLineTotals = changes
                    .filter((change) => change.discountMode === 'Amount')
                    .map((change) => {
                        const savedLine = finalReview.lines.find((line) => line.id === change.id);
                        return `${savedLine?.productName || change.id} $${Number(savedLine?.netTotal || 0).toFixed(2)}`;
                    });
                this.completionMessage = `CPQ completed both calculations. Saved Net Totals: ${savedLineTotals.join('; ')}.`;
            } else {
                this.completionMessage = `CPQ completed both calculations. ${secondResult.status}`;
            }
            this.dispatchEvent(new ShowToastEvent({
                title: 'CPQ calculation complete',
                message: this.completionMessage,
                variant: 'success'
            }));
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Could not calculate amendment', message: this.errorMessage, variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    async waitForCalculation(previousLastCalculatedOn) {
        let latestReview;
        for (let attempt = 0; attempt < 20; attempt += 1) {
            await new Promise((resolve) => setTimeout(resolve, 3000));
            const payload = await loadReview({ quoteId: this.recordId });
            latestReview = JSON.parse(payload);
            const timestampChanged = latestReview.lastCalculatedOn &&
                latestReview.lastCalculatedOn !== previousLastCalculatedOn;
            if (!latestReview.uncalculated && timestampChanged) return latestReview;
        }
        if (latestReview) this.review = latestReview;
        throw new Error('CPQ is still calculating. Refresh saved quote data after it finishes before trying again.');
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}
