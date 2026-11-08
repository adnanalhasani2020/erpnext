import 'package:flutter/material.dart';
import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class PurchaseWorkflowPage extends StatefulWidget {
  const PurchaseWorkflowPage({super.key, required this.api, required this.companies, required this.suppliers, required this.items, required this.warehouses, this.onChanged});
  final FrappeApi api;
  final List<ErpCompany> companies;
  final List<ErpSupplier> suppliers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final VoidCallback? onChanged;
  @override State<PurchaseWorkflowPage> createState() => _PurchaseWorkflowPageState();
}

class _PurchaseWorkflowPageState extends State<PurchaseWorkflowPage> {
  List<ErpPurchaseInvoice> rows = [];
  bool loading = false;
  String? error;
  final search = TextEditingController();
  @override void initState() { super.initState(); load(); }
  @override void dispose() { search.dispose(); super.dispose(); }
  Future<void> load() async {
    if (loading) return;
    setState(() { loading = true; error = null; });
    try { final result = await widget.api.fetchPurchaseInvoices(search: search.text.trim().isEmpty ? null : search.text.trim()); if (mounted) setState(() => rows = result); }
    catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }
  void notice(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }
  Future<bool> confirm(String title, String message) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(message), actions: [
    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
  ])) == true;

  Future<void> compose({Map<String, dynamic>? draft}) async {
    if (widget.companies.isEmpty || widget.suppliers.isEmpty || widget.items.isEmpty) { notice('تأكد من تحميل الشركات والموردين والأصناف وصلاحيات قراءتها.'); return; }
    final supplier = TextEditingController(text: draft?['supplier']?.toString() ?? widget.suppliers.first.id);
    final company = TextEditingController(text: draft?['company']?.toString() ?? widget.companies.first.name);
    final item = TextEditingController(text: (draft?['items'] is List && (draft!['items'] as List).isNotEmpty) ? (draft['items'][0]['item_code'] ?? '').toString() : widget.items.first.code);
    final qty = TextEditingController(text: (draft?['items'] is List && (draft!['items'] as List).isNotEmpty) ? (draft['items'][0]['qty'] ?? 1).toString() : '1');
    final rate = TextEditingController(text: (draft?['items'] is List && (draft!['items'] as List).isNotEmpty) ? (draft['items'][0]['rate'] ?? 0).toString() : '0');
    final warehouse = TextEditingController(text: (draft?['items'] is List && (draft!['items'] as List).isNotEmpty) ? (draft['items'][0]['warehouse'] ?? '').toString() : '');
    final updateStock = ValueNotifier<bool>(draft?['update_stock'] == 1 || draft?['update_stock'] == true);
    try {
      final values = await showDialog<Map<String, dynamic>>(context: context, builder: (c) => AlertDialog(
        title: Text(draft == null ? 'فاتورة مشتريات جديدة' : 'تعديل مسودة مشتريات'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(company, 'الشركة (الاسم الكامل)'),
          _field(supplier, 'رمز المورد'),
          _field(item, 'رمز الصنف'),
          Row(children: [Expanded(child: _field(qty, 'الكمية', number: true)), const SizedBox(width: 8), Expanded(child: _field(rate, 'سعر الوحدة', number: true))]),
          _field(warehouse, 'رمز مستودع الاستلام'),
          ValueListenableBuilder<bool>(valueListenable: updateStock, builder: (_, v, __) => SwitchListTile(value: v, onChanged: (x) => updateStock.value = x, title: const Text('تحديث المخزون عند الترحيل'))),
          const Text('أدخل رموز ERPNext كما تظهر في النظام. الضرائب والإجماليات يحسبها الخادم.', style: TextStyle(fontSize: 12)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            final q = double.tryParse(qty.text.trim()), r = double.tryParse(rate.text.trim());
            if (company.text.trim().isEmpty || supplier.text.trim().isEmpty || item.text.trim().isEmpty || q == null || q <= 0 || r == null || r < 0) return;
            Navigator.pop(c, {'company': company.text.trim(), 'supplier': supplier.text.trim(), 'item': item.text.trim(), 'qty': q, 'rate': r, 'warehouse': warehouse.text.trim(), 'update_stock': updateStock.value});
          }, child: const Text('متابعة')),
        ],
      ));
      if (values == null || !mounted) return;
      final payload = <String, dynamic>{
        'doctype': 'Purchase Invoice', 'company': values['company'], 'supplier': values['supplier'],
        'posting_date': draft?['posting_date'] ?? DateTime.now().toIso8601String().substring(0, 10),
        'update_stock': values['update_stock'] == true ? 1 : 0,
        'items': [{'item_code': values['item'], 'qty': values['qty'], 'rate': values['rate'], if ((values['warehouse'] as String).isNotEmpty) 'warehouse': values['warehouse']}],
      };
      final saved = draft == null ? await widget.api.createPurchaseInvoice(payload) : await widget.api.updateDraftPurchaseInvoice(invoiceName: draft['name'].toString(), changes: payload);
      if (await confirm('ترحيل الفاتورة؟', 'تم حفظ المسودة ' + (saved['name'] ?? '').toString() + '. هل تريد ترحيلها الآن؟')) {
        await widget.api.submitPurchaseInvoice(saved);
      }
      notice('تم حفظ فاتورة المشتريات ' + (saved['name'] ?? '').toString());
      await load(); widget.onChanged?.call();
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
    finally { supplier.dispose(); company.dispose(); item.dispose(); qty.dispose(); rate.dispose(); warehouse.dispose(); updateStock.dispose(); }
  }

  Future<void> details(String name) async {
    try {
      final doc = await widget.api.fetchInvoiceDocument('Purchase Invoice', name);
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: ListView(shrinkWrap: true, children: [
          Text(name, style: Theme.of(context).textTheme.titleLarge),
          Text('المورد: ' + (doc['supplier_name'] ?? doc['supplier'] ?? '—').toString()),
          Text('الحالة: ' + (doc['docstatus'] == 0 ? 'مسودة' : doc['docstatus'] == 1 ? 'مرحّل' : 'ملغي')),
          Text('الإجمالي: ' + (doc['grand_total'] ?? '—').toString() + ' ' + (doc['currency'] ?? '').toString()),
          Text('المتبقي: ' + (doc['outstanding_amount'] ?? '—').toString()),
          const Divider(),
          ...((doc['items'] as List? ?? []).whereType<Map<String, dynamic>>().map((x) => ListTile(title: Text((x['item_name'] ?? x['item_code']).toString()), subtitle: Text('الكمية: ' + (x['qty'] ?? '').toString() + ' • المستودع: ' + (x['warehouse'] ?? '—').toString()))),
          if (doc['docstatus'] == 0) ...[
            FilledButton(onPressed: () { Navigator.pop(sheet); compose(draft: doc); }, child: const Text('تعديل المسودة')),
            FilledButton.tonal(onPressed: () async { if (!await confirm('ترحيل الفاتورة', 'قد يؤدي الترحيل إلى تحديث المخزون والقيود المحاسبية.')) return; try { await widget.api.submitPurchaseInvoice(doc); if (sheet.mounted) Navigator.pop(sheet); await load(); widget.onChanged?.call(); } catch (e) { notice(e.toString()); } }, child: const Text('ترحيل الفاتورة')),
          ],
          if (doc['docstatus'] == 1 && doc['is_return'] != 1 && doc['is_return'] != true) ...[
            OutlinedButton(onPressed: () async {
              final amount = await _numberDialog('مبلغ دفعة المورد');
              if (amount == null) return;
              try { final result = await widget.api.payPurchaseInvoice(invoiceName: name, amount: amount); if (sheet.mounted) Navigator.pop(sheet); notice('تم ترحيل سند الصرف ' + (result['name'] ?? '').toString()); await load(); }
              catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
            }, child: const Text('تسجيل دفعة المورد')),
            OutlinedButton(onPressed: () async {
              if (!await confirm('إنشاء مرتجع', 'سيتم إنشاء مسودة إشعار خصم مرتبطة بالفاتورة الأصلية.')) return;
              try { final result = await widget.api.createPurchaseReturn(name); if (sheet.mounted) Navigator.pop(sheet); notice('تم إنشاء مسودة المرتجع ' + (result['name'] ?? '').toString()); await load(); }
              catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
            }, child: const Text('إنشاء مرتجع مشتريات')),
          ],
          if (doc['docstatus'] == 1 && (doc['is_return'] == 1 || doc['is_return'] == true))
            FilledButton(onPressed: () async { if (!await confirm('ترحيل المرتجع', 'سيعكس ERPNext أثر المرتجع وفق إعداداته.')) return; try { await widget.api.submitPurchaseInvoice(doc); if (sheet.mounted) Navigator.pop(sheet); await load(); widget.onChanged?.call(); } catch (e) { notice(e.toString()); } }, child: const Text('ترحيل المرتجع')),
        ]))));
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<double?> _numberDialog(String title) async {
    final c = TextEditingController();
    try { return await showDialog<double>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
      FilledButton(onPressed: () { final n = double.tryParse(c.text.trim()); if (n != null && n > 0 && n.isFinite) Navigator.pop(ctx, n); }, child: const Text('تأكيد')),
    ])); } finally { c.dispose(); }
  }
  Widget _field(TextEditingController c, String label, {bool number = false}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(labelText: label)));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة المشتريات'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => compose(), icon: const Icon(Icons.add), label: const Text('فاتورة مشتريات')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('إنشاء الفواتير وتعديل المسودات وترحيلها وسداد الموردين والمرتجعات.'),
      TextField(controller: search, onSubmitted: (_) => load(), decoration: InputDecoration(labelText: 'بحث بالفاتورة أو المورد', suffixIcon: IconButton(onPressed: load, icon: const Icon(Icons.search)))),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      Text('فواتير المشتريات (' + rows.length.toString() + ')', style: Theme.of(context).textTheme.titleMedium),
      if (rows.isEmpty && !loading) const ListTile(title: Text('لا توجد فواتير ظاهرة')),
      ...rows.map((x) => Card(child: ListTile(leading: const Icon(Icons.shopping_cart_outlined), title: Text(x.id), subtitle: Text(x.supplierName + ' • ' + (x.status ?? '—') + ' • المتبقي ' + x.outstandingAmount.toStringAsFixed(2)), trailing: Text(x.grandTotal.toStringAsFixed(2)), onTap: () => details(x.id)))),
      const SizedBox(height: 90),
    ]),
  );
}

class StockWorkflowPage extends StatefulWidget {
  const StockWorkflowPage({super.key, required this.api, required this.companies, required this.items, required this.warehouses, this.onChanged});
  final FrappeApi api;
  final List<ErpCompany> companies;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final VoidCallback? onChanged;
  @override State<StockWorkflowPage> createState() => _StockWorkflowPageState();
}

class _StockWorkflowPageState extends State<StockWorkflowPage> {
  List<Map<String, dynamic>> movements = [];
  bool loading = false;
  String? error;
  final itemFilter = TextEditingController(), warehouseFilter = TextEditingController();
  @override void initState() { super.initState(); load(); }
  @override void dispose() { itemFilter.dispose(); warehouseFilter.dispose(); super.dispose(); }
  void notice(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Future<bool> confirm(String title, String message) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(message), actions: [
    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لاحقاً')),
    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ترحيل')),
  ])) == true;
  Future<void> load() async {
    if (loading) return; setState(() { loading = true; error = null; });
    try { final data = await widget.api.fetchStockMovements(itemCode: itemFilter.text.trim().isEmpty ? null : itemFilter.text.trim(), warehouse: warehouseFilter.text.trim().isEmpty ? null : warehouseFilter.text.trim()); if (mounted) setState(() => movements = data); }
    catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> movement(String purpose) async {
    if (widget.companies.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) { notice('حمّل الشركات والأصناف والمستودعات أولاً.'); return; }
    final company = TextEditingController(text: widget.companies.first.name);
    final item = TextEditingController(text: widget.items.first.code);
    final from = TextEditingController(), to = TextEditingController(), qty = TextEditingController(text: '1'), rate = TextEditingController(text: '0');
    try {
      final values = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(purpose == 'Material Receipt' ? 'استلام مخزون' : purpose == 'Material Issue' ? 'صرف / تسليم مخزون' : 'تحويل بين المستودعات'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(company, 'الشركة'), _field(item, 'رمز الصنف'), if (purpose != 'Material Receipt') _field(from, 'مستودع المصدر'),
          if (purpose != 'Material Issue') _field(to, 'مستودع الوجهة / الاستلام'),
          _field(qty, 'الكمية', number: true), if (purpose == 'Material Receipt') _field(rate, 'سعر التقييم', number: true),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            final q = double.tryParse(qty.text.trim()), r = double.tryParse(rate.text.trim());
            if (company.text.trim().isEmpty || item.text.trim().isEmpty || q == null || q <= 0 ||
              (purpose != 'Material Receipt' && from.text.trim().isEmpty) ||
              (purpose != 'Material Issue' && to.text.trim().isEmpty) ||
              (purpose == 'Material Transfer' && from.text.trim() == to.text.trim()) ||
              (purpose == 'Material Receipt' && (r == null || r < 0)) ) return;
            Navigator.pop(c, true);
          }, child: const Text('إنشاء المسودة')),
        ]));
      if (values != true || !mounted) return;
      final q = double.parse(qty.text.trim()), r = double.parse(rate.text.trim());
      final doc = await widget.api.createStockEntry(company: company.text.trim(), purpose: purpose,
        fromWarehouse: from.text.trim().isEmpty ? null : from.text.trim(),
        toWarehouse: to.text.trim().isEmpty ? null : to.text.trim(),
        items: [{'item_code': item.text.trim(), 'qty': q, if (purpose == 'Material Receipt') 'valuation_rate': r}]);
      if (await confirm('ترحيل حركة المخزون', 'تم إنشاء المسودة ' + (doc['name'] ?? '').toString() + '. الترحيل سيغير أرصدة المخزون.')) {
        final result = await widget.api.submitStockEntry(doc);
        notice('تم ترحيل الحركة ' + (result['name'] ?? doc['name']).toString());
        await load(); widget.onChanged?.call();
      } else { notice('حُفظت المسودة ' + (doc['name'] ?? '').toString()); }
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
    finally { company.dispose(); item.dispose(); from.dispose(); to.dispose(); qty.dispose(); rate.dispose(); }
  }

  Future<void> reconcile() async {
    if (widget.companies.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) { notice('حمّل الشركات والأصناف والمستودعات أولاً.'); return; }
    final company = TextEditingController(text: widget.companies.first.name), warehouse = TextEditingController(), item = TextEditingController(text: widget.items.firstWhere((x) => x.isStockItem, orElse: () => widget.items.first).code), qty = TextEditingController(text: '0'), rate = TextEditingController(text: '0');
    try {
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('جرد وتسوية المخزون'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(company, 'الشركة'), _field(warehouse, 'رمز المستودع'), _field(item, 'رمز الصنف'),
          _field(qty, 'الكمية الفعلية', number: true), _field(rate, 'سعر التقييم', number: true),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () { final q = double.tryParse(qty.text), r = double.tryParse(rate.text); if (company.text.trim().isNotEmpty && warehouse.text.trim().isNotEmpty && item.text.trim().isNotEmpty && q != null && q >= 0 && r != null && r >= 0) Navigator.pop(c, true); }, child: const Text('إنشاء التسوية'))]));
      if (ok != true || !mounted) return;
      final doc = await widget.api.createStockReconciliation(company: company.text.trim(), warehouse: warehouse.text.trim(), items: [{'item_code': item.text.trim(), 'qty': double.parse(qty.text), 'valuation_rate': double.parse(rate.text)}]);
      if (await confirm('تأكيد تسوية المخزون', 'سيتم ضبط الرصيد إلى الكمية الفعلية المدخلة في ERPNext. هل تريد الترحيل؟')) {
        final result = await widget.api.submitStockReconciliation(doc);
        notice('تم ترحيل التسوية ' + (result['name'] ?? doc['name']).toString()); await load(); widget.onChanged?.call();
      } else { notice('حُفظت مسودة التسوية ' + (doc['name'] ?? '').toString()); }
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
    finally { company.dispose(); warehouse.dispose(); item.dispose(); qty.dispose(); rate.dispose(); }
  }
  Widget _field(TextEditingController c, String label, {bool number = false}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(labelText: label)));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('عمليات المخزون'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('الاستلام والصرف والتحويل والجرد تُنفّذ بمستندات ERPNext الرسمية. لا يتم تعديل Bin مباشرة.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonal(onPressed: () => movement('Material Receipt'), child: const Text('استلام مخزون')),
        FilledButton.tonal(onPressed: () => movement('Material Issue'), child: const Text('صرف / تسليم')),
        FilledButton.tonal(onPressed: () => movement('Material Transfer'), child: const Text('تحويل')),
        FilledButton.icon(onPressed: reconcile, icon: const Icon(Icons.fact_check_outlined), label: const Text('جرد وتسوية')),
      ]),
      const Divider(height: 28), Text('سجل الحركات', style: Theme.of(context).textTheme.titleMedium),
      _field(itemFilter, 'رمز الصنف للبحث'), _field(warehouseFilter, 'رمز المستودع للبحث'),
      Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: load, icon: const Icon(Icons.search), label: const Text('بحث'))),
      if (loading) const LinearProgressIndicator(), if (error != null) Text(error!),
      if (movements.isEmpty && !loading) const ListTile(title: Text('لا توجد حركات ظاهرة أو لا تتوفر صلاحية قراءة سجل المخزون.')),
      ...movements.map((x) => Card(child: ListTile(leading: const Icon(Icons.swap_horiz),
        title: Text((x['item_code'] ?? '—').toString() + ' • ' + (x['warehouse'] ?? '—').toString()),
        subtitle: Text((x['posting_date'] ?? '').toString() + ' • ' + (x['voucher_type'] ?? '').toString() + ' • ' + (x['voucher_no'] ?? '').toString()),
        trailing: Text((x['actual_qty'] ?? 0).toString())))),
    ]),
  );
}
