class InvoiceActionPolicy {
  const InvoiceActionPolicy._();

  static bool canEditSalesDraft({
    required String documentType,
    required int docStatus,
    bool isReturn = false,
  }) =>
      documentType == 'Sales Invoice' && docStatus == 0 && !isReturn;

  static bool canSubmitSalesDraft({
    required String documentType,
    required int docStatus,
  }) =>
      documentType == 'Sales Invoice' && docStatus == 0;

  static bool canReceiveCustomerPayment({
    required String documentType,
    required int docStatus,
    required double outstandingAmount,
    bool isReturn = false,
  }) =>
      documentType == 'Sales Invoice' &&
      docStatus == 1 &&
      outstandingAmount > 0 &&
      !isReturn;

  static bool canCancelSalesInvoice({
    required String documentType,
    required int docStatus,
  }) =>
      documentType == 'Sales Invoice' && docStatus == 1;

  static bool canCreateSalesReturn({
    required String documentType,
    required int docStatus,
    required bool isReturn,
  }) =>
      documentType == 'Sales Invoice' && docStatus == 1 && !isReturn;
}
