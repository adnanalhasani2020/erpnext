import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/invoice_action_policy.dart';

void main() {
  group('InvoiceActionPolicy', () {
    test('keeps sales-only actions unavailable for Purchase Invoice documents', () {
      expect(
        InvoiceActionPolicy.canEditSalesDraft(
          documentType: 'Purchase Invoice',
          docStatus: 0,
        ),
        isFalse,
      );
      expect(
        InvoiceActionPolicy.canSubmitSalesDraft(
          documentType: 'Purchase Invoice',
          docStatus: 0,
        ),
        isFalse,
      );
      expect(
        InvoiceActionPolicy.canReceiveCustomerPayment(
          documentType: 'Purchase Invoice',
          docStatus: 1,
          outstandingAmount: 250,
        ),
        isFalse,
      );
      expect(
        InvoiceActionPolicy.canCancelSalesInvoice(
          documentType: 'Purchase Invoice',
          docStatus: 1,
        ),
        isFalse,
      );
      expect(
        InvoiceActionPolicy.canCreateSalesReturn(
          documentType: 'Purchase Invoice',
          docStatus: 1,
          isReturn: false,
        ),
        isFalse,
      );
    });

    test('allows eligible sales invoice actions only in the correct states', () {
      expect(
        InvoiceActionPolicy.canEditSalesDraft(
          documentType: 'Sales Invoice',
          docStatus: 0,
        ),
        isTrue,
      );
      expect(
        InvoiceActionPolicy.canSubmitSalesDraft(
          documentType: 'Sales Invoice',
          docStatus: 0,
        ),
        isTrue,
      );
      expect(
        InvoiceActionPolicy.canReceiveCustomerPayment(
          documentType: 'Sales Invoice',
          docStatus: 1,
          outstandingAmount: 250,
        ),
        isTrue,
      );
      expect(
        InvoiceActionPolicy.canCancelSalesInvoice(
          documentType: 'Sales Invoice',
          docStatus: 1,
        ),
        isTrue,
      );
      expect(
        InvoiceActionPolicy.canCreateSalesReturn(
          documentType: 'Sales Invoice',
          docStatus: 1,
          isReturn: false,
        ),
        isTrue,
      );
    });

    test('hides payment, cancellation, and return actions for ineligible states', () {
      expect(
        InvoiceActionPolicy.canReceiveCustomerPayment(
          documentType: 'Sales Invoice',
          docStatus: 1,
          outstandingAmount: 0,
        ),
        isFalse,
      );
      expect(
        InvoiceActionPolicy.canCancelSalesInvoice(
          documentType: 'Sales Invoice',
          docStatus: 0,
        ),
        isFalse,
      );
      expect(
        InvoiceActionPolicy.canCreateSalesReturn(
          documentType: 'Sales Invoice',
          docStatus: 1,
          isReturn: true,
        ),
        isFalse,
      );
    });
  });
}
