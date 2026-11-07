import LightningModal from 'lightning/modal';
import { api } from 'lwc';

export default class BillingCorrectionConsoleModal extends LightningModal {
    @api recordId;

    handleClose() {
        this.close();
    }
}
