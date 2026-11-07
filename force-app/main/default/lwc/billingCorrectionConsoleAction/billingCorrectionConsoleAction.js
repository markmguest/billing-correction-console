import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import BillingCorrectionConsoleModal from 'c/billingCorrectionConsoleModal';

export default class BillingCorrectionConsoleAction extends LightningElement {
    @api recordId;

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleOpenConsole() {
        BillingCorrectionConsoleModal.open({
            size: 'full',
            label: 'Billing Correction Console',
            recordId: this.recordId
        });
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
