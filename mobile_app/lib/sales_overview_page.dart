import 'package:flutter/material.dart';

import 'models/erp_models.dart';
import 'widgets/load_more_button.dart';
import 'widgets/server_search_field.dart';

class SalesOverviewPage extends StatelessWidget {
  const SalesOverviewPage({
    super.key,
    required this.guest, this.guestBanner,
    required this.salesLoading, required this.purchaseLoading, required this.inventoryLoading,
    this.salesError, this.purchaseError,
    required this.salesInvoices, required this.customers, required this.purchaseInvoices, required this.suppliers,
    required this.salesInvoiceSearch, required this.customerSearch, required this.purchaseInvoiceSearch, required this.supplierSearch,
    required this.salesInvoiceSearchController, required this.customerSearchController, required this.purchaseInvoiceSearchController, required this.supplierSearchController,
    required this.searchingSalesInvoices, required this.searchingCustomers, required this.searchingPurchaseInvoices, required this.searchingSuppliers,
    required this.salesInvoicesHasMore, required this.customersHasMore, required this.purchaseInvoicesHasMore, required this.suppliersHasMore,
    required this.loadingMoreSalesInvoices, required this.loadingMoreCustomers, required this.loadingMorePurchaseInvoices, required this.loadingMoreSuppliers,
    required this.companiesAvailable,
    required this.onLoadSales, required this.onLoadPurchases,
    required this.onOpenSalesWorkflow, required this.onOpenPurchaseWorkflow, required this.onOpenStockWorkflow,
    required this.onOpenSalesDashboard, required this.onOpenBankReconciliation, required this.onOpenPayroll, required this.onOpenHrWorkflows,
    required this.onOpenPaymentReconciliation, required this.onOpenSalesPricing, required this.onOpenChartOfAccounts, required this.onOpenJournalEntries,
    required this.onOpenMasterData, required this.onOpenSalesCommissions, required this.onOpenSalesInvoiceComposer,
    required this.onSearchSalesInvoices, required this.onSearchCustomers, required this.onSearchPurchaseInvoices, required this.onSearchSuppliers,
    required this.onLoadMoreSalesInvoices, required this.onLoadMoreCustomers, required this.onLoadMorePurchaseInvoices, required this.onLoadMoreSuppliers,
    required this.onShowInvoiceDetails, required this.onEditCustomer, required this.onShowCustomerLedger, required this.onShowSupplierLedger,
  });

  final bool guest, salesLoading, purchaseLoading, inventoryLoading, companiesAvailable;
  final Widget? guestBanner;
  final String? salesError, purchaseError;
  final List<ErpSalesInvoice> salesInvoices;
  final List<ErpCustomer> customers;
  final List<ErpPurchaseInvoice> purchaseInvoices;
  final List<ErpSupplier> suppliers;
  final String salesInvoiceSearch, customerSearch, purchaseInvoiceSearch, supplierSearch;
  final TextEditingController salesInvoiceSearchController, customerSearchController, purchaseInvoiceSearchController, supplierSearchController;
  final bool searchingSalesInvoices, searchingCustomers, searchingPurchaseInvoices, searchingSuppliers;
  final bool salesInvoicesHasMore, customersHasMore, purchaseInvoicesHasMore, suppliersHasMore;
  final bool loadingMoreSalesInvoices, loadingMoreCustomers, loadingMorePurchaseInvoices, loadingMoreSuppliers;
  final VoidCallback onLoadSales, onLoadPurchases;
  final void Function({String? doctype}) onOpenSalesWorkflow;
  final Future<void> Function({String? section, String? initialInvoiceName}) onOpenPurchaseWorkflow;
  final Future<void> Function({String? initialItemCode, String? section}) onOpenStockWorkflow;
  final VoidCallback onOpenSalesDashboard, onOpenBankReconciliation, onOpenPayroll, onOpenPaymentReconciliation;
  final void Function({String? doctype}) onOpenHrWorkflows;
  final VoidCallback onOpenSalesPricing, onOpenChartOfAccounts, onOpenJournalEntries, onOpenMasterData, onOpenSalesCommissions, onOpenSalesInvoiceComposer;
  final ValueChanged<String> onSearchSalesInvoices, onSearchCustomers, onSearchPurchaseInvoices, onSearchSuppliers;
  final VoidCallback onLoadMoreSalesInvoices, onLoadMoreCustomers, onLoadMorePurchaseInvoices, onLoadMoreSuppliers;
  final void Function(String doctype, String name) onShowInvoiceDetails;
  final ValueChanged<ErpCustomer> onEditCustomer, onShowCustomerLedger;
  final ValueChanged<ErpSupplier> onShowSupplierLedger;

  @override
  Widget build(BuildContext context) {
    final invoiceQuery=salesInvoiceSearch.toLowerCase(), customerQuery=customerSearch.toLowerCase();
    final purchaseQuery=purchaseInvoiceSearch.toLowerCase(), supplierQuery=supplierSearch.toLowerCase();
    final visibleSalesInvoices=salesInvoices.where((r)=>invoiceQuery.isEmpty||r.id.toLowerCase().contains(invoiceQuery)||r.customerName.toLowerCase().contains(invoiceQuery)).toList(growable:false);
    final visibleCustomers=customers.where((r)=>customerQuery.isEmpty||r.id.toLowerCase().contains(customerQuery)||r.name.toLowerCase().contains(customerQuery)).toList(growable:false);
    final visiblePurchaseInvoices=purchaseInvoices.where((r)=>purchaseQuery.isEmpty||r.id.toLowerCase().contains(purchaseQuery)||r.supplierName.toLowerCase().contains(purchaseQuery)).toList(growable:false);
    final visibleSuppliers=suppliers.where((r)=>supplierQuery.isEmpty||r.id.toLowerCase().contains(supplierQuery)||r.name.toLowerCase().contains(supplierQuery)).toList(growable:false);
    return ListView(padding:const EdgeInsets.all(18),children:[
      if(guestBanner!=null) guestBanner!,
      Row(children:[
        Expanded(child:Row(children:[const CircleAvatar(child:Icon(Icons.receipt_long_outlined)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('المعاملات',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),Text(guest?'عرض عينات المبيعات والمشتريات والعملاء والموردين محلياً':'فواتير المبيعات وإنشاء الفواتير، مع عرض بيانات المشتريات والعملاء والموردين',style:Theme.of(context).textTheme.bodySmall)]))])),
        IconButton(tooltip:'تحديث المبيعات',onPressed:guest||salesLoading?null:onLoadSales,icon:const Icon(Icons.refresh)),
        IconButton(tooltip:'تحديث المشتريات',onPressed:guest||purchaseLoading?null:onLoadPurchases,icon:const Icon(Icons.shopping_cart_outlined)),
      ]),
      Wrap(spacing:8,runSpacing:8,children:[
        for(final item in const [('Quotation','عروض الأسعار'),('Sales Order','أوامر البيع'),('Delivery Note','أذون التسليم')])
          OutlinedButton.icon(onPressed:guest||salesLoading||inventoryLoading?null:()=>onOpenSalesWorkflow(doctype:item.$1),icon:const Icon(Icons.open_in_new),label:Text(item.$2)),
        for(final item in const [('Purchase Order','أوامر الشراء'),('Purchase Invoice','فواتير المشتريات'),('Payment Entry','دفعات الموردين'),('Supplier Ledger','سجل دفعات الموردين')])
          OutlinedButton.icon(onPressed:guest||purchaseLoading?null:()=>onOpenPurchaseWorkflow(section:item.$1),icon:const Icon(Icons.open_in_new),label:Text(item.$2)),
        for(final item in const [('Stock Entry','حركات المخزون'),('Purchase Receipt','إيصالات الشراء'),('Stock Reconciliation','الجرد والتسوية'),('Pick List','قوائم الالتقاط'),('Batch','تتبع الدفعات'),('Serial No','تتبع الأرقام التسلسلية'),('Item Reorder','تنبيهات إعادة الطلب')])
          OutlinedButton.icon(onPressed:guest||inventoryLoading?null:()=>onOpenStockWorkflow(section:item.$1),icon:const Icon(Icons.open_in_new),label:Text(item.$2)),
        OutlinedButton.icon(onPressed:guest||salesLoading?null:onOpenSalesDashboard,icon:const Icon(Icons.insights_outlined),label:const Text('مؤشرات المبيعات')),
        OutlinedButton.icon(onPressed:guest||salesLoading||purchaseLoading?null:onOpenBankReconciliation,icon:const Icon(Icons.account_balance_outlined),label:const Text('التسوية البنكية')),
        OutlinedButton.icon(onPressed:guest||salesLoading?null:onOpenPayroll,icon:const Icon(Icons.payments_outlined),label:const Text('دورة الرواتب')),
        for(final item in const [('Employee','الموظفون'),('Attendance','الحضور'),('Leave Application','طلبات الإجازة'),('Expense Claim','مطالبات المصروفات'),('Salary Slip','قسائم الرواتب')])
          OutlinedButton.icon(onPressed:guest||!companiesAvailable?null:()=>onOpenHrWorkflows(doctype:item.$1),icon:const Icon(Icons.open_in_new),label:Text(item.$2)),
        OutlinedButton.icon(onPressed:guest||salesLoading||purchaseLoading?null:onOpenPaymentReconciliation,icon:const Icon(Icons.compare_arrows_outlined),label:const Text('تسوية المدفوعات')),
        OutlinedButton.icon(onPressed:guest||salesLoading?null:onOpenSalesPricing,icon:const Icon(Icons.price_change_outlined),label:const Text('أسعار البيع')),
        OutlinedButton.icon(onPressed:!guest&&companiesAvailable?onOpenChartOfAccounts:null,icon:const Icon(Icons.account_tree_outlined),label:const Text('دليل الحسابات')),
        OutlinedButton.icon(onPressed:!guest&&companiesAvailable?onOpenJournalEntries:null,icon:const Icon(Icons.post_add_outlined),label:const Text('القيود اليومية')),
        OutlinedButton.icon(onPressed:guest||inventoryLoading||purchaseLoading?null:onOpenMasterData,icon:const Icon(Icons.settings_suggest_outlined),label:const Text('إدارة البيانات الأساسية')),
        OutlinedButton.icon(onPressed:guest||salesLoading?null:onOpenSalesCommissions,icon:const Icon(Icons.percent_outlined),label:const Text('العمولات')),
      ]),
      const SizedBox(height:8),
      Align(alignment:AlignmentDirectional.centerStart,child:FilledButton.icon(onPressed:guest||salesLoading||inventoryLoading?null:onOpenSalesInvoiceComposer,icon:const Icon(Icons.add_shopping_cart),label:const Text('إنشاء فاتورة مبيعات'))),
      if(salesLoading) const LinearProgressIndicator(),
      if(salesError!=null) _errorCard(context,salesError!),
      const SizedBox(height:12),
      ServerSearchField(controller:salesInvoiceSearchController,label:'بحث في فواتير المبيعات',onSearch:onSearchSalesInvoices,loading:searchingSalesInvoices,buttonLabel:guest?'بحث محلي':'بحث في الخادم'),
      Text('فواتير المبيعات (${visibleSalesInvoices.length})',style:Theme.of(context).textTheme.titleMedium),
      if(visibleSalesInvoices.isEmpty&&!salesLoading) const Card(child:ListTile(title:Text('لا توجد فواتير ظاهرة أو تعذر تحميلها'))),
      ...visibleSalesInvoices.map((invoice)=>Card(child:ListTile(
        leading:CircleAvatar(child:Icon(invoice.isReturn?Icons.assignment_return_outlined:Icons.receipt_long_outlined)),
        title:Text(invoice.isReturn?'مرتجع • ${invoice.id}':invoice.id),
        subtitle:Text('${invoice.customerName} • ${invoice.postingDate??'—'}${invoice.returnAgainst==null?'':'\nمرتبط بالفاتورة: ${invoice.returnAgainst}'}\n${invoice.status??'حالة غير محددة'} • متبقٍ: ${invoice.outstandingAmount.toStringAsFixed(2)} ${invoice.currency??''}'),
        isThreeLine:true,trailing:Text(invoice.grandTotal.toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.bold)),
        onTap:guest?null:()=>onShowInvoiceDetails('Sales Invoice',invoice.id),
      ))),
      if(!guest&&(salesInvoicesHasMore||loadingMoreSalesInvoices)) LoadMoreButton(loadingMoreSalesInvoices,'تحميل المزيد من فواتير المبيعات',onLoadMoreSalesInvoices),
      const SizedBox(height:18),
      ServerSearchField(controller:customerSearchController,label:'بحث في العملاء',onSearch:onSearchCustomers,loading:searchingCustomers,buttonLabel:guest?'بحث محلي':'بحث في الخادم'),
      Text('العملاء (${visibleCustomers.length})',style:Theme.of(context).textTheme.titleMedium),
      if(visibleCustomers.isEmpty&&!salesLoading) const Card(child:ListTile(title:Text('لا توجد بيانات عملاء ظاهرة'))),
      ...visibleCustomers.map((customer)=>Card(child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.person_outline)),title:Text(customer.name),
        subtitle:Text([customer.id,if(customer.group!=null)customer.group!,if(customer.territory!=null)customer.territory!].join(' • ')),
        trailing:IconButton(tooltip:'تعديل ملف العميل',icon:const Icon(Icons.edit_outlined),onPressed:guest?null:()=>onEditCustomer(customer)),
        onTap:guest?null:()=>onShowCustomerLedger(customer),
      ))),
      if(!guest&&(customersHasMore||loadingMoreCustomers)) LoadMoreButton(loadingMoreCustomers,'تحميل المزيد من العملاء',onLoadMoreCustomers),
      const Divider(height:28),
      if(purchaseLoading) const LinearProgressIndicator(),
      if(purchaseError!=null) _errorCard(context,purchaseError!),
      ServerSearchField(controller:purchaseInvoiceSearchController,label:'بحث في فواتير المشتريات',onSearch:onSearchPurchaseInvoices,loading:searchingPurchaseInvoices,buttonLabel:guest?'بحث محلي':'بحث في الخادم'),
      Text('فواتير المشتريات (${visiblePurchaseInvoices.length})',style:Theme.of(context).textTheme.titleMedium),
      if(visiblePurchaseInvoices.isEmpty&&!purchaseLoading) const Card(child:ListTile(title:Text('لا توجد فواتير مشتريات ظاهرة'))),
      ...visiblePurchaseInvoices.map((invoice)=>Card(child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.shopping_cart_outlined)),title:Text(invoice.id),
        subtitle:Text('${invoice.supplierName} • ${invoice.postingDate??'—'}\n${invoice.status??'حالة غير محددة'} • متبقٍ: ${invoice.outstandingAmount.toStringAsFixed(2)} ${invoice.currency??''}'),
        isThreeLine:true,trailing:Text(invoice.grandTotal.toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.bold)),
        onTap:guest?null:()=>onOpenPurchaseWorkflow(initialInvoiceName:invoice.id),
      ))),
      if(!guest&&(purchaseInvoicesHasMore||loadingMorePurchaseInvoices)) LoadMoreButton(loadingMorePurchaseInvoices,'تحميل المزيد من فواتير المشتريات',onLoadMorePurchaseInvoices),
      const SizedBox(height:18),
      ServerSearchField(controller:supplierSearchController,label:'بحث في الموردين',onSearch:onSearchSuppliers,loading:searchingSuppliers,buttonLabel:guest?'بحث محلي':'بحث في الخادم'),
      Text('الموردون (${visibleSuppliers.length})',style:Theme.of(context).textTheme.titleMedium),
      if(visibleSuppliers.isEmpty&&!purchaseLoading) const Card(child:ListTile(title:Text('لا توجد بيانات موردين ظاهرة'))),
      ...visibleSuppliers.map((supplier)=>Card(child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.local_shipping_outlined)),title:Text(supplier.name),
        subtitle:Text([supplier.id,if(supplier.group!=null)supplier.group!,if(supplier.type!=null)supplier.type!].join(' • ')),
        trailing:const Icon(Icons.receipt_long_outlined),onTap:guest?null:()=>onShowSupplierLedger(supplier),
      ))),
      if(!guest&&(suppliersHasMore||loadingMoreSuppliers)) LoadMoreButton(loadingMoreSuppliers,'تحميل المزيد من الموردين',onLoadMoreSuppliers),
      const SizedBox(height:10),
      Text('تتم إدارة دورة المبيعات من شاشة المبيعات، ودورة المشتريات والدفعات والمرتجعات من شاشة إدارة المشتريات، مع تحديث أرصدة المخزون بعد العمليات المرحلة.',textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

Widget _errorCard(BuildContext context,String message)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(message,style:TextStyle(color:Theme.of(context).colorScheme.error))));
