// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures
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
    if (widget.companies.isEmpty || widget.suppliers.isEmpty || widget.items.isEmpty) {
      notice('تأكد من تحميل الشركات والموردين والأصناف وصلاحيات قراءتها.');
      return;
    }
    var selectedCompany = draft?['company']?.toString() ?? widget.companies.first.name;
    var selectedSupplier = draft?['supplier']?.toString() ?? widget.suppliers.first.id;
    final updateStock = ValueNotifier<bool>(draft?['update_stock'] == 1 || draft?['update_stock'] == true);
    final lineRows = <Map<String, dynamic>>[];
    final sourceLines = draft?['items'] is List
        ? (draft!['items'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    void addLine([Map<String, dynamic>? source]) {
      final validItem = widget.items.any((x) => x.code == source?['item_code'])
          ? source!['item_code'].toString() : widget.items.first.code;
      final allowed = widget.warehouses.where((w) => w.company == null || w.company == selectedCompany);
      final sourceWarehouse = source?['warehouse']?.toString();
      lineRows.add({
        'item': validItem,
        'qty': TextEditingController(text: (source?['qty'] ?? 1).toString()),
        'rate': TextEditingController(text: (source?['rate'] ?? 0).toString()),
        'warehouse': allowed.any((w) => w.id == sourceWarehouse) ? sourceWarehouse : null,
      });
    }
    if (sourceLines.isEmpty) { addLine(); } else { for (final row in sourceLines) { addLine(row); } }
    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) {
          final companies = widget.companies.map((x) => x.name).toSet().toList();
          if (!companies.contains(selectedCompany)) selectedCompany = companies.first;
          final suppliers = widget.suppliers.map((x) => x.id).toSet().toList();
          if (!suppliers.contains(selectedSupplier)) selectedSupplier = suppliers.first;
          final warehouses = widget.warehouses.where((w) => w.company == null || w.company == selectedCompany).toList();
          return AlertDialog(
            title: Text(draft == null ? 'فاتورة مشتريات جديدة' : 'تعديل مسودة مشتريات'),
            content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selectedCompany, isExpanded: true,
                decoration: const InputDecoration(labelText: 'الشركة'),
                items: companies.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => refreshDialog(() {
                  if (v == null) return;
                  selectedCompany = v;
                  for (final row in lineRows) {
                    if (!widget.warehouses.any((w) => w.id == row['warehouse'] &&
                        (w.company == null || w.company == selectedCompany))) row['warehouse'] = null;
                  }
                }),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedSupplier, isExpanded: true,
                decoration: const InputDecoration(labelText: 'المورد'),
                items: widget.suppliers.map((s) => DropdownMenuItem(value: s.id,
                  child: Text('\${s.name} (\${s.id})', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => refreshDialog(() { if (v != null) selectedSupplier = v; }),
              ),
              const Divider(height: 24),
              Row(children: [
                const Expanded(child: Text('أصناف الفاتورة', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => refreshDialog(addLine),
                  icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
              ]),
              ...List.generate(lineRows.length, (index) {
                final row = lineRows[index];
                final item = widget.items.firstWhere((x) => x.code == row['item'], orElse: () => widget.items.first);
                return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(
                  padding: const EdgeInsets.all(10), child: Column(children: [
                    Row(children: [
                      Expanded(child: Text('الصنف \${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (lineRows.length > 1) IconButton(
                        tooltip: 'حذف الصنف',
                        onPressed: () => refreshDialog(() {
                          final removed = lineRows.removeAt(index);
                          (removed['qty'] as TextEditingController).dispose();
                          (removed['rate'] as TextEditingController).dispose();
                        }),
                        icon: const Icon(Icons.delete_outline)),
                    ]),
                    DropdownButtonFormField<String>(
                      value: item.code, isExpanded: true,
                      decoration: InputDecoration(labelText: 'الصنف', helperText: item.name),
                      items: widget.items.map((x) => DropdownMenuItem(value: x.code,
                        child: Text('\${x.name} (\${x.code})', overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => refreshDialog(() { if (v != null) row['item'] = v; }),
                    ),
                    Row(children: [
                      Expanded(child: _field(row['qty'] as TextEditingController, 'الكمية', number: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _field(row['rate'] as TextEditingController, 'سعر الوحدة', number: true)),
                    ]),
                    DropdownButtonFormField<String>(
                      value: row['warehouse'] as String?, isExpanded: true,
                      decoration: const InputDecoration(labelText: 'مستودع الصنف (اختياري)'),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text('حسب إعدادات الصنف')),
                        ...warehouses.map((w) => DropdownMenuItem(value: w.id,
                          child: Text('\${w.name} (\${w.id})', overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => refreshDialog(() => row['warehouse'] = v),
                    ),
                  ]),
                ));
              }),
              ValueListenableBuilder<bool>(valueListenable: updateStock, builder: (_, value, __) =>
                SwitchListTile(value: value, onChanged: (v) => updateStock.value = v,
                  title: const Text('تحديث المخزون عند ترحيل الفاتورة'))),
              const Text('الضرائب والإجماليات يحسبها ERPNext. إذا استلمت نفس البضاعة بسند Purchase Receipt، لا تفعّل تحديث المخزون هنا.',
                style: TextStyle(fontSize: 12)),
            ]))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(onPressed: () {
                if (selectedCompany.isEmpty || selectedSupplier.isEmpty || lineRows.isEmpty) return;
                final items = <Map<String, dynamic>>[];
                for (final row in lineRows) {
                  final qty = double.tryParse((row['qty'] as TextEditingController).text.trim());
                  final rate = double.tryParse((row['rate'] as TextEditingController).text.trim());
                  final code = row['item'] as String;
                  if (code.isEmpty || qty == null || !qty.isFinite || qty <= 0 ||
                      rate == null || !rate.isFinite || rate < 0) return;
                  items.add({'item_code': code, 'qty': qty, 'rate': rate,
                    if (row['warehouse'] != null) 'warehouse': row['warehouse']});
                }
                Navigator.pop(dialogContext, {
                  'company': selectedCompany, 'supplier': selectedSupplier,
                  'items': items, 'update_stock': updateStock.value,
                });
              }, child: const Text('حفظ ومتابعة')),
            ],
          );
        }),
      );
      if (values == null || !mounted) return;
      final payload = <String, dynamic>{
        'doctype': 'Purchase Invoice', 'company': values['company'], 'supplier': values['supplier'],
        'posting_date': draft?['posting_date'] ?? DateTime.now().toIso8601String().substring(0, 10),
        'update_stock': values['update_stock'] == true ? 1 : 0, 'items': values['items'],
      };
      final saved = draft == null
          ? await widget.api.createPurchaseInvoice(payload)
          : await widget.api.updateDraftPurchaseInvoice(invoiceName: draft['name'].toString(), changes: payload);
      if (await confirm('ترحيل الفاتورة؟',
          'تم حفظ المسودة \${saved['name'] ?? ''} بعدد \${values['items'].length} صنف. هل تريد ترحيلها الآن؟')) {
        try {
          final submitted = await widget.api.submitPurchaseInvoice(saved);
          notice('تم ترحيل فاتورة المشتريات \${submitted['name'] ?? saved['name']}');
        } catch (e) {
          notice('حُفظت المسودة \${saved['name'] ?? ''} لكن تعذر تأكيد ترحيلها. راجعها قبل إعادة المحاولة. \${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('تم حفظ مسودة فاتورة المشتريات \${saved['name'] ?? ''}');
      }
      await load();
      widget.onChanged?.call();
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      for (final row in lineRows) {
        (row['qty'] as TextEditingController).dispose();
        (row['rate'] as TextEditingController).dispose();
      }
      updateStock.dispose();
    }
  }

  Future<void> details(String name) async {
    try {
      final doc = await widget.api.fetchInvoiceDocument('Purchase Invoice', name);
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: ListView(shrinkWrap: true, children: [
          Text((doc['is_return'] == 1 || doc['is_return'] == true ? 'مرتجع مشتريات • ' : 'فاتورة مشتريات • ') + name, style: Theme.of(context).textTheme.titleLarge),
          if (doc['return_against'] != null) Text('مرتبط بالفاتورة الأصلية: ' + doc['return_against'].toString()),
          Text('المورد: ' + (doc['supplier_name'] ?? doc['supplier'] ?? '—').toString()),
          Text('الحالة: ' + (doc['docstatus'] == 0 ? 'مسودة' : doc['docstatus'] == 1 ? 'مرحّل' : 'ملغي')),
          Text('الإجمالي: ' + (doc['grand_total'] ?? '—').toString() + ' ' + (doc['currency'] ?? '').toString()),
          Text('المتبقي: ' + (doc['outstanding_amount'] ?? '—').toString()),
          const Divider(),
          ...((doc['items'] as List? ?? []).whereType<Map<String, dynamic>>().map((x) => ListTile(title: Text((x['item_name'] ?? x['item_code']).toString()), subtitle: Text('الكمية: ' + (x['qty'] ?? '').toString() + ' • المستودع: ' + (x['warehouse'] ?? '—').toString())))),
          if (doc['docstatus'] == 0) ...[
            if (doc['is_return'] != 1 && doc['is_return'] != true)
              FilledButton(onPressed: () { Navigator.pop(sheet); compose(draft: doc); }, child: const Text('تعديل المسودة')),
            FilledButton.tonal(onPressed: () async { if (!await confirm(doc['is_return'] == 1 || doc['is_return'] == true ? 'ترحيل المرتجع' : 'ترحيل الفاتورة', 'قد يؤدي الترحيل إلى تحديث المخزون والقيود المحاسبية.')) return; try { await widget.api.submitPurchaseInvoice(doc); if (sheet.mounted) Navigator.pop(sheet); await load(); widget.onChanged?.call(); } catch (e) { notice(e.toString()); } }, child: Text(doc['is_return'] == 1 || doc['is_return'] == true ? 'ترحيل المرتجع' : 'ترحيل الفاتورة')),
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
            const ListTile(leading: Icon(Icons.check_circle_outline), title: Text('المرتجع مرحّل بالفعل')),
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
      ...rows.map((x) => Card(child: ListTile(leading: Icon(x.isReturn ? Icons.assignment_return_outlined : Icons.shopping_cart_outlined), title: Text((x.isReturn ? 'مرتجع • ' : '') + x.id), subtitle: Text(x.supplierName + (x.returnAgainst == null ? '' : ' • أصل: ' + x.returnAgainst!) + ' • ' + (x.status ?? '—') + ' • المتبقي ' + x.outstandingAmount.toStringAsFixed(2)), trailing: Text(x.grandTotal.toStringAsFixed(2)), onTap: () => details(x.id)))),
      const SizedBox(height: 90),
    ]),
  );
}

class StockWorkflowPage extends StatefulWidget {
  const StockWorkflowPage({super.key, required this.api, required this.companies, required this.suppliers, required this.items, required this.warehouses, this.onChanged});
  final FrappeApi api;
  final List<ErpCompany> companies;
  final List<ErpSupplier> suppliers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final VoidCallback? onChanged;
  @override State<StockWorkflowPage> createState() => _StockWorkflowPageState();
}

class _StockWorkflowPageState extends State<StockWorkflowPage> {
  List<Map<String, dynamic>> movements = [];
  List<Map<String, dynamic>> drafts = [];
  String? draftError;
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = false;
  int offset = 0;
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
    try {
      final data = await widget.api.fetchStockMovements(itemCode: itemFilter.text.trim().isEmpty ? null : itemFilter.text.trim(), warehouse: warehouseFilter.text.trim().isEmpty ? null : warehouseFilter.text.trim());
      if (mounted) setState(() { movements = data; offset = data.length; hasMore = data.length == FrappeApi.pageSize; });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    final loadedDrafts = <Map<String, dynamic>>[];
    final draftErrors = <String>[];
    for (final type in const ['Purchase Receipt', 'Stock Entry', 'Stock Reconciliation']) {
      try { loadedDrafts.addAll(await widget.api.fetchDraftStockDocuments(type)); }
      catch (e) { draftErrors.add(type + ': ' + e.toString().replaceFirst('Exception: ', '')); }
    }
    if (mounted) setState(() { drafts = loadedDrafts; draftError = draftErrors.isEmpty ? null : draftErrors.join('\n'); });
    if (mounted) setState(() => loading = false);
  }
  Future<void> reviewDraft(Map<String, dynamic> summary) async {
    try {
      final type = summary['doctype'].toString();
      final name = summary['name'].toString();
      final doc = await widget.api.fetchStockDocument(type, name);
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: ListView(shrinkWrap: true, children: [
          Text(type + ' • ' + name, style: Theme.of(context).textTheme.titleLarge),
          Text('الشركة: ' + (doc['company'] ?? '—').toString()),
          Text('التاريخ: ' + (doc['posting_date'] ?? '—').toString()),
          Text('الغرض: ' + (doc['purpose'] ?? doc['stock_entry_type'] ?? '—').toString()),
          const Divider(),
          ...((doc['items'] as List? ?? []).whereType<Map<String, dynamic>>().map((row) => ListTile(
            title: Text((row['item_name'] ?? row['item_code'] ?? 'صنف').toString()),
            subtitle: Text('الكمية: ' + (row['qty'] ?? '—').toString() + ' • من: ' + (row['s_warehouse'] ?? '—').toString() + ' • إلى: ' + (row['t_warehouse'] ?? row['warehouse'] ?? '—').toString()),
          ))),
          FilledButton.icon(onPressed: () { Navigator.pop(sheet); submitDraft(summary); },
            icon: const Icon(Icons.check_circle_outline), label: const Text('متابعة لترحيل المسودة')),
        ]))));
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<void> submitDraft(Map<String, dynamic> summary) async {
    final type = summary['doctype'].toString();
    final name = summary['name'].toString();
    if (!await confirm('ترحيل مسودة ' + name, 'سيتم ترحيل المستند وتحديث المخزون أو القيود حسب نوعه. راجع تفاصيله في ERPNext إذا لزم الأمر.')) return;
    try {
      final doc = await widget.api.fetchStockDocument(type, name);
      if (doc['docstatus'] != 0) throw const FormatException('المستند لم يعد مسودة.');
      if (type == 'Purchase Receipt') {
        await widget.api.submitPurchaseReceipt(doc);
      } else if (type == 'Stock Entry') {
        await widget.api.submitStockEntry(doc);
      } else if (type == 'Stock Reconciliation') {
        await widget.api.submitStockReconciliation(doc);
      } else {
        throw ArgumentError('نوع المستند غير مدعوم.');
      }
      notice('تم ترحيل ' + name + ' بنجاح.');
      await load(); widget.onChanged?.call();
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<void> loadMoreMovements() async {
    if (loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    try {
      final data = await widget.api.fetchStockMovements(start: offset,
        itemCode: itemFilter.text.trim().isEmpty ? null : itemFilter.text.trim(),
        warehouse: warehouseFilter.text.trim().isEmpty ? null : warehouseFilter.text.trim());
      if (mounted) setState(() { movements = [...movements, ...data]; offset += data.length; hasMore = data.length == FrappeApi.pageSize; });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loadingMore = false); }
  }
  Future<List<Map<String, dynamic>>?> _stockItemLinesDialog({
    required String title, bool includeRate = false, bool allowZeroQuantity = false,
  }) async {
    if (widget.items.isEmpty) return null;
    final lines = <Map<String, dynamic>>[];
    void addLine() => lines.add({
      'item': widget.items.first.code,
      'qty': TextEditingController(text: allowZeroQuantity ? '0' : '1'),
      'rate': TextEditingController(text: '0'),
    });
    addLine();
    try {
      return await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Expanded(child: Text('الأصناف والكميات', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => refresh(addLine),
                  icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
              ]),
              ...List.generate(lines.length, (index) {
                final row = lines[index];
                final item = widget.items.firstWhere((x) => x.code == row['item'], orElse: () => widget.items.first);
                return Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
                  Row(children: [
                    Expanded(child: Text('الصنف \${index + 1}')),
                    if (lines.length > 1) IconButton(onPressed: () => refresh(() {
                      final removed = lines.removeAt(index);
                      (removed['qty'] as TextEditingController).dispose();
                      (removed['rate'] as TextEditingController).dispose();
                    }), icon: const Icon(Icons.delete_outline)),
                  ]),
                  DropdownButtonFormField<String>(
                    value: item.code, isExpanded: true,
                    decoration: InputDecoration(labelText: 'الصنف', helperText: item.name),
                    items: widget.items.map((x) => DropdownMenuItem(value: x.code,
                      child: Text('\${x.name} (\${x.code})', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => refresh(() { if (v != null) row['item'] = v; }),
                  ),
                  _field(row['qty'] as TextEditingController, allowZeroQuantity ? 'الكمية الفعلية' : 'الكمية', number: true),
                  if (includeRate) _field(row['rate'] as TextEditingController, 'سعر التقييم', number: true),
                ])));
              }),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              final result = <Map<String, dynamic>>[];
              for (final row in lines) {
                final qty = double.tryParse((row['qty'] as TextEditingController).text.trim());
                final rate = double.tryParse((row['rate'] as TextEditingController).text.trim());
                if (qty == null || !qty.isFinite ||
                    (allowZeroQuantity ? qty < 0 : qty <= 0) ||
                    (includeRate && (rate == null || !rate.isFinite || rate < 0))) return;
                result.add({'item_code': row['item'], 'qty': qty, if (includeRate) 'valuation_rate': rate});
              }
              if (result.isNotEmpty) Navigator.pop(dialogContext, result);
            }, child: const Text('متابعة')),
          ],
        )),
      );
    } finally {
      for (final row in lines) {
        (row['qty'] as TextEditingController).dispose();
        (row['rate'] as TextEditingController).dispose();
      }
    }
  }

  Future<void> movement(String purpose) async {
    if (widget.companies.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) {
      notice('حمّل الشركات والأصناف والمستودعات أولاً.');
      return;
    }
    final company = TextEditingController(text: widget.companies.first.name);
    final from = TextEditingController();
    final to = TextEditingController();
    try {
      final warehouses = widget.warehouses;
      final values = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(purpose == 'Material Receipt' ? 'استلام مخزون' :
              purpose == 'Material Issue' ? 'صرف / تسليم مخزون' : 'تحويل بين المستودعات'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: widget.companies.first.name, isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(),
              onChanged: (v) { if (v != null) company.text = v; },
            ),
            if (purpose != 'Material Receipt')
              DropdownButtonFormField<String>(
                value: null, isExpanded: true,
                decoration: const InputDecoration(labelText: 'مستودع المصدر'),
                items: warehouses.where((w) => w.company == null || w.company == company.text)
                    .map((w) => DropdownMenuItem(value: w.id, child: Text('\${w.name} (\${w.id})'))).toList(),
                onChanged: (v) => from.text = v ?? '',
              ),
            if (purpose != 'Material Issue')
              DropdownButtonFormField<String>(
                value: null, isExpanded: true,
                decoration: const InputDecoration(labelText: 'مستودع الوجهة / الاستلام'),
                items: warehouses.where((w) => w.company == null || w.company == company.text)
                    .map((w) => DropdownMenuItem(value: w.id, child: Text('\${w.name} (\${w.id})'))).toList(),
                onChanged: (v) => to.text = v ?? '',
              ),
            const SizedBox(height: 8),
            const Text('ستحدد الأصناف والكميات في الخطوة التالية.'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if ((purpose != 'Material Receipt' && from.text.trim().isEmpty) ||
                  (purpose != 'Material Issue' && to.text.trim().isEmpty) ||
                  (purpose == 'Material Transfer' && from.text.trim() == to.text.trim())) return;
              Navigator.pop(c, true);
            }, child: const Text('التالي')),
          ],
        ),
      ));
      if (values != true || !mounted) return;
      final items = await _stockItemLinesDialog(
        title: 'أصناف حركة المخزون', includeRate: purpose == 'Material Receipt',
      );
      if (items == null || !mounted) return;
      final doc = await widget.api.createStockEntry(
        company: company.text.trim(), purpose: purpose,
        fromWarehouse: from.text.trim().isEmpty ? null : from.text.trim(),
        toWarehouse: to.text.trim().isEmpty ? null : to.text.trim(),
        items: items,
      );
      if (await confirm('ترحيل حركة المخزون',
          'تم إنشاء المسودة \${doc['name'] ?? ''} بعدد \${items.length} صنف. الترحيل سيغير أرصدة المخزون.')) {
        try {
          final result = await widget.api.submitStockEntry(doc);
          notice('تم ترحيل الحركة \${result['name'] ?? doc['name']}');
          await load();
          widget.onChanged?.call();
        } catch (e) {
          notice('حُفظت مسودة الحركة \${doc['name'] ?? ''} ولم يؤكد ترحيلها. راجعها قبل إنشاء حركة بديلة. \${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('حُفظت المسودة \${doc['name'] ?? ''}');
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      company.dispose();
      from.dispose();
      to.dispose();
    }
  }

  Future<void> purchaseReceipt() async {
    if (widget.companies.isEmpty || widget.suppliers.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) {
      notice('حمّل الشركات والموردين والأصناف والمستودعات أولاً.');
      return;
    }
    var company = widget.companies.first.name;
    var supplier = widget.suppliers.first.id;
    String? warehouse;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
      builder: (context, refresh) {
        final available = widget.warehouses.where((w) => w.company == null || w.company == company).toList();
        if (!available.any((w) => w.id == warehouse)) warehouse = null;
        return AlertDialog(
          title: const Text('استلام بضاعة من مورد'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: company, isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(),
              onChanged: (v) => refresh(() { if (v != null) { company = v; warehouse = null; } }),
            ),
            DropdownButtonFormField<String>(
              value: supplier, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المورد'),
              items: widget.suppliers.map((x) => DropdownMenuItem(value: x.id,
                child: Text('\${x.name} (\${x.id})', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => refresh(() { if (v != null) supplier = v; }),
            ),
            DropdownButtonFormField<String>(
              value: warehouse, isExpanded: true,
              decoration: const InputDecoration(labelText: 'مستودع الاستلام'),
              items: available.map((w) => DropdownMenuItem(value: w.id,
                child: Text('\${w.name} (\${w.id})', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => refresh(() => warehouse = v),
            ),
            const Text('يمكن إضافة عدة أصناف في سند الاستلام نفسه.'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if (company.isNotEmpty && supplier.isNotEmpty && warehouse != null) Navigator.pop(c, true);
            }, child: const Text('التالي')),
          ],
        );
      },
    ));
    if (ok != true || warehouse == null || !mounted) return;
    final lines = await _stockItemLinesDialog(title: 'أصناف سند الاستلام', includeRate: true);
    if (lines == null || !mounted) return;
    try {
      final doc = await widget.api.createPurchaseReceipt({
        'doctype': 'Purchase Receipt', 'company': company, 'supplier': supplier,
        'posting_date': DateTime.now().toIso8601String().substring(0, 10),
        'items': lines.map((row) => {
          'item_code': row['item_code'], 'qty': row['qty'],
          'rate': row['valuation_rate'], 'warehouse': warehouse,
        }).toList(),
      });
      if (await confirm('ترحيل سند الاستلام',
          'تم إنشاء سند الاستلام \${doc['name'] ?? ''} بعدد \${lines.length} صنف. الترحيل سيضيف الكميات للمخزون.')) {
        try {
          final result = await widget.api.submitPurchaseReceipt(doc);
          notice('تم ترحيل سند الاستلام \${result['name'] ?? doc['name']}');
          await load();
          widget.onChanged?.call();
        } catch (e) {
          notice('حُفظ سند الاستلام \${doc['name'] ?? ''} كمسودة. راجعه قبل إنشاء سند آخر. \${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('حُفظت مسودة سند الاستلام \${doc['name'] ?? ''}');
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> reconcile() async {
    if (widget.companies.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) {
      notice('حمّل الشركات والأصناف والمستودعات أولاً.');
      return;
    }
    var company = widget.companies.first.name;
    String? warehouse;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
      builder: (context, refresh) {
        final available = widget.warehouses.where((w) => w.company == null || w.company == company).toList();
        if (!available.any((w) => w.id == warehouse)) warehouse = null;
        return AlertDialog(
          title: const Text('جرد وتسوية المخزون'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: company, isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(),
              onChanged: (v) => refresh(() { if (v != null) { company = v; warehouse = null; } }),
            ),
            DropdownButtonFormField<String>(
              value: warehouse, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المستودع'),
              items: available.map((w) => DropdownMenuItem(value: w.id,
                child: Text('\${w.name} (\${w.id})', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => refresh(() => warehouse = v),
            ),
            const Text('أدخل الكمية الفعلية لكل صنف. الكمية صفر مسموحة.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if (company.isNotEmpty && warehouse != null) Navigator.pop(c, true);
            }, child: const Text('التالي')),
          ],
        );
      },
    ));
    if (ok != true || warehouse == null || !mounted) return;
    final lines = await _stockItemLinesDialog(
      title: 'أصناف الجرد والكميات الفعلية',
      includeRate: true,
      allowZeroQuantity: true,
    );
    if (lines == null || !mounted) return;
    try {
      final doc = await widget.api.createStockReconciliation(
        company: company,
        warehouse: warehouse!,
        items: lines,
      );
      if (await confirm('تأكيد تسوية المخزون',
          'تم إنشاء مسودة \${doc['name'] ?? ''} بعدد \${lines.length} صنف. ستضبط الأرصدة إلى الكميات الفعلية المدخلة. هل تريد الترحيل؟')) {
        try {
          final result = await widget.api.submitStockReconciliation(doc);
          notice('تم ترحيل التسوية \${result['name'] ?? doc['name']}');
          await load();
          widget.onChanged?.call();
        } catch (e) {
          notice('حُفظت مسودة التسوية \${doc['name'] ?? ''} ولم يؤكد ترحيلها. راجعها قبل إنشاء تسوية أخرى. \${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('حُفظت مسودة التسوية \${doc['name'] ?? ''}');
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(labelText: label)));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('عمليات المخزون'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('الاستلام والصرف والتحويل والجرد تُنفّذ بمستندات ERPNext الرسمية. لا يتم تعديل Bin مباشرة.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonal(onPressed: () => movement('Material Receipt'), child: const Text('استلام مخزون')),
        FilledButton.tonal(onPressed: purchaseReceipt, child: const Text('استلام مشتريات')),
        FilledButton.tonal(onPressed: () => movement('Material Issue'), child: const Text('صرف / تسليم')),
        FilledButton.tonal(onPressed: () => movement('Material Transfer'), child: const Text('تحويل')),
        FilledButton.icon(onPressed: reconcile, icon: const Icon(Icons.fact_check_outlined), label: const Text('جرد وتسوية')),
      ]),
      const Divider(height: 28),
      Text('المسودات غير المرحلة (' + drafts.length.toString() + ')', style: Theme.of(context).textTheme.titleMedium),
      if (draftError != null) Text(draftError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
      if (drafts.isEmpty && !loading) const ListTile(title: Text('لا توجد مسودات مخزون ظاهرة.')),
      ...drafts.map((draft) => Card(child: ListTile(
        leading: const Icon(Icons.pending_actions_outlined),
        title: Text((draft['doctype'] ?? '').toString() + ' • ' + (draft['name'] ?? '').toString()),
        subtitle: Text((draft['company'] ?? '').toString() + ' • ' + (draft['posting_date'] ?? '').toString()),
        trailing: IconButton(tooltip: 'مراجعة المسودة', onPressed: () => reviewDraft(draft), icon: const Icon(Icons.visibility_outlined)),
        onTap: () => reviewDraft(draft),
      ))),
      const Divider(height: 28), Text('سجل الحركات', style: Theme.of(context).textTheme.titleMedium),
      _field(itemFilter, 'رمز الصنف للبحث'), _field(warehouseFilter, 'رمز المستودع للبحث'),
      Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: load, icon: const Icon(Icons.search), label: const Text('بحث'))),
      if (loading) const LinearProgressIndicator(), if (error != null) Text(error!),
      if (movements.isEmpty && !loading) const ListTile(title: Text('لا توجد حركات ظاهرة أو لا تتوفر صلاحية قراءة سجل المخزون.')),
      ...movements.map((x) => Card(child: ListTile(leading: const Icon(Icons.swap_horiz),
        title: Text((x['item_code'] ?? '—').toString() + ' • ' + (x['warehouse'] ?? '—').toString()),
        subtitle: Text((x['posting_date'] ?? '').toString() + ' • ' + (x['voucher_type'] ?? '').toString() + ' • ' + (x['voucher_no'] ?? '').toString()),
        trailing: Text((x['actual_qty'] ?? 0).toString())))),
      if (hasMore || loadingMore) Center(child: TextButton.icon(onPressed: loadingMore ? null : loadMoreMovements, icon: loadingMore ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more), label: const Text('تحميل حركات إضافية'))),
    ]),
  );
}
