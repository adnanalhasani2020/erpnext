import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/sales_overview_page.dart';

void main() {
  testWidgets('opens independent sales, customer and supplier directories', (tester) async {
    var invoicesOpened = 0;
    var customersOpened = 0;
    var suppliersOpened = 0;

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: SalesOverviewPage(
          guest: false,
          salesLoading: false,
          purchaseLoading: false,
          inventoryLoading: false,
          companiesAvailable: true,
          salesInvoices: const [],
          customers: const [],
          purchaseInvoices: const [],
          suppliers: const [],
          salesInvoiceSearch: '',
          customerSearch: '',
          purchaseInvoiceSearch: '',
          supplierSearch: '',
          salesInvoiceSearchController: TextEditingController(),
          customerSearchController: TextEditingController(),
          purchaseInvoiceSearchController: TextEditingController(),
          supplierSearchController: TextEditingController(),
          searchingSalesInvoices: false,
          searchingCustomers: false,
          searchingPurchaseInvoices: false,
          searchingSuppliers: false,
          salesInvoicesHasMore: false,
          customersHasMore: false,
          purchaseInvoicesHasMore: false,
          suppliersHasMore: false,
          loadingMoreSalesInvoices: false,
          loadingMoreCustomers: false,
          loadingMorePurchaseInvoices: false,
          loadingMoreSuppliers: false,
          onLoadSales: () {},
          onLoadPurchases: () {},
          onOpenSalesInvoices: () => invoicesOpened++,
          onOpenCustomers: () => customersOpened++,
          onOpenSuppliers: () => suppliersOpened++,
          onOpenSalesWorkflow: ({String? doctype}) {},
          onOpenPurchaseWorkflow: ({String? section, String? initialInvoiceName}) async {},
          onOpenStockWorkflow: ({String? initialItemCode, String? section}) async {},
          onOpenSalesDashboard: () {},
          onOpenBankReconciliation: () {},
          onOpenPayroll: () {},
          onOpenHrWorkflows: ({String? doctype}) {},
          onOpenPaymentReconciliation: () {},
          onOpenSalesPricing: () {},
          onOpenChartOfAccounts: () {},
          onOpenJournalEntries: () {},
          onOpenMasterData: () {},
          onOpenSalesCommissions: () {},
          onOpenSalesInvoiceComposer: () {},
          onSearchSalesInvoices: (_) {},
          onSearchCustomers: (_) {},
          onSearchPurchaseInvoices: (_) {},
          onSearchSuppliers: (_) {},
          onLoadMoreSalesInvoices: () {},
          onLoadMoreCustomers: () {},
          onLoadMorePurchaseInvoices: () {},
          onLoadMoreSuppliers: () {},
          onShowInvoiceDetails: (_, __) {},
          onEditCustomer: (_) {},
          onShowCustomerLedger: (_) {},
          onShowSupplierLedger: (_) {},
        ),
      ),
    ));

    await tester.tap(find.text('فواتير المبيعات'));
    await tester.tap(find.text('دليل العملاء'));
    await tester.tap(find.text('دليل الموردين'));

    expect(invoicesOpened, 1);
    expect(customersOpened, 1);
    expect(suppliersOpened, 1);
  });
}
