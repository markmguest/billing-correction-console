import { createElement } from 'lwc';
import BillingCorrectionConsole from 'c/billingCorrectionConsole';
import loadReview from '@salesforce/apex/BillingCorrectionController.loadReview';
import calculateAndSave from '@salesforce/apex/BillingCorrectionController.calculateAndSave';

jest.mock(
    '@salesforce/apex/BillingCorrectionController.loadReview',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingCorrectionController.calculateAndSave',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BillingCorrectionController.duplicateAndZeroSelected',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setImmediate(resolve));

const reviewPayload = {
    quoteId: 'a66Em000008X5E1IAK',
    quoteName: 'Q-114630',
    quoteStatus: 'Draft',
    currencyIsoCode: 'USD',
    suggestedEndDate: '2027-02-17',
    totalMrr: -3,
    lines: [
        {
            id: 'reversal-1',
            name: 'QL-Reversal',
            productName: 'Business Plan',
            role: 'Reversal',
            original: true,
            editable: false,
            quantity: 0,
            mrr: -63,
            effectiveQuantity: -3,
            startDate: '2026-03-19',
            endDate: '2027-03-18',
            netPrice: 252,
            netTotal: -756
        },
        {
            id: 'replacement-1',
            name: 'QL-Replacement',
            productName: 'Business Plan',
            role: 'New line',
            original: false,
            editable: true,
            quantity: 3,
            additionalDiscount: 0,
            additionalDiscountAmount: null,
            discountUnit: 'Percent',
            mrr: 60,
            effectiveQuantity: 3,
            startDate: '2026-03-19',
            endDate: '2027-02-17',
            netPrice: 219.73,
            netTotal: 659.19
        }
    ]
};

describe('c-billing-correction-console', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads a review and does not calculate before explicit confirmation', async () => {
        loadReview.mockResolvedValue(JSON.stringify(reviewPayload));
        calculateAndSave.mockResolvedValue(JSON.stringify({
            quoteId: reviewPayload.quoteId,
            status: 'Calculation queued.'
        }));

        const element = createElement('c-billing-correction-console', {
            is: BillingCorrectionConsole
        });
        element.recordId = reviewPayload.quoteId;
        document.body.appendChild(element);
        await flushPromises();

        expect(loadReview).toHaveBeenCalledWith({ quoteId: reviewPayload.quoteId });
        const lineCheckbox = element.shadowRoot.querySelector('lightning-input[data-line-id="replacement-1"]');
        lineCheckbox.checked = true;
        lineCheckbox.dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
        await flushPromises();

        const reviewButton = element.shadowRoot.querySelector('lightning-button');
        reviewButton.click();
        await flushPromises();

        expect(calculateAndSave).not.toHaveBeenCalled();
        const confirmation = element.shadowRoot.querySelector('lightning-input[name="confirmation"]');
        confirmation.checked = true;
        confirmation.dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
        await flushPromises();

        const saveButton = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((button) => button.label === 'Calculate and save draft');
        saveButton.click();
        await flushPromises();

        expect(calculateAndSave).toHaveBeenCalledWith({
            quoteId: reviewPayload.quoteId,
            quoteEndDate: reviewPayload.suggestedEndDate,
            changesJson: JSON.stringify([{
                id: 'replacement-1',
                quantity: 3,
                startDate: '2026-03-19',
                endDate: '2027-02-17',
                discountMode: 'Percent',
                additionalDiscountPercent: 0,
                additionalDiscountAmount: 0,
                targetNetTotal: ''
            }])
        });
    });
});
