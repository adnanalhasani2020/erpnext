import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class SalesWorkflowPage extends StatefulWidget {
  const SalesWorkflowPage({
    super.key,
    required this.api,
    required this.companies,
    required this.customers,
    required this.items,
    required this.warehouses,
    required this.onChanged,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;
  final List<ErpCustomer> customers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final VoidCallback onChanged;

  @override
  State<SalesWorkflowPage> createState() => _SalesWorkflowPageState();
}

class _SalesWorkflowPageState extends State<SalesWorkflowPage> {
  static const _types = ['Quotation', 'Sales Order', 'Delivery Note'];
  static const _labels = ['عروض الأسعار', 'أوامر البيع', 'أذون التسليم'];
  int _tab = 0;
  int _offset = 0;
  bool _loading = false, _hasMore = false;
  String _search = '';
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  String? _error;

  String get _doctype => _types[_tab];
  String get _label => _labels[_tab];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    final start = reset ? 0 : _offset;
    setState(() { _loading = true; _error = null; });
    try {
      final page = await widget.api.fetchSalesWorkflowDocuments(
        _doctype, start: start, search: _search,
      );
      if (!mounted) return;
      setState(() {
        _rows = reset ? page : [..._rows, ...page];
        _offset = start + page.length;
        _hasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() { _tab = index; _offset = 0; _rows = []; _search = ''; _searchController.clear(); });
    _load(reset: true);
  }

  Future<void> _createOrEdit({Map<String, dynamic>? draft}) async {
    if (widget.companies.isEmpty || widget.customers.isEmpty || widget.items.isEmpty) {
      _notice('يلزم تحميل الشركات والعملاء والأصناف أولاً مع توفر صلاحيات القراءة.');
      return;
    }
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _SalesDraftEditor(
        api: widget.api, doctype: _doctype,
        companies: widget.companies, customers: widget.customers,
        items: widget.items, warehouses: widget.warehouses,
        initialDraft: draft,
      ),
    ));
    if (saved == true && mounted) {
      _load(reset: true);
      widget.onChanged();
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openDetails(Map<String, dynamic> row) async {
    final name = row['name']?.toString() ?? '';
    if (name.isEmpty) return;
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      builder: (sheetContext) => FutureBuilder<Map<String, dynamic>>(
        future: widget.api.fetchSalesWorkflowDocument(_doctype, name),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) return Padding(
            padding: const EdgeInsets.all(20),
            child: Text('تعذر تحميل المستند: ${snapshot.error}'),
          );
          final doc = snapshot.data!;
          final status = (doc['docstatus'] as num?)?.toInt() ?? 0;
          final items = doc['items'] is List ? (doc['items'] as List).whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
          final total = double.tryParse(doc['grand_total']?.toString() ?? '') ?? 0;
          final currency = doc['currency']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .82),
              child: ListView(shrinkWrap: true, children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                Text('${doc['customer_name'] ?? doc['customer'] ?? ''} • ${doc['status'] ?? '—'}'),
                Text('الشركة: ${doc['company'] ?? '—'}'),
                Text('الإجمالي: ${total.toStringAsFixed(2)} $currency'),
                const Divider(),
                Text('البنود (${items.length})', style: Theme.of(context).textTheme.titleMedium),
                ...items.map((item) => ListTile(
                  dense: true, title: Text(item['item_name']?.toString() ?? item['item_code']?.toString() ?? 'صنف'),
                  subtitle: Text('الكمية: ${item['qty'] ?? 0} • السعر: ${item['rate'] ?? 0}'),
                  trailing: Text((double.tryParse(item['amount']?.toString() ?? '') ?? 0).toStringAsFixed(2)),
                )),
                if (status == 0) ...[
                  OutlinedButton.icon(
                    onPressed: () { Navigator.pop(sheetContext); _createOrEdit(draft: doc); },
                    icon: const Icon(Icons.edit_outlined), label: const Text('تعديل المسودة'),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await _confirm('ترحيل المستند', 'سيتم ترحيل المستند في ERPNext وتطبيق تحققاته. هل تريد المتابعة؟');
                      if (ok != true || !mounted) return;
                      try {
                        await widget.api.submitSalesWorkflowDocument(_doctype, name);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        _load(reset: true); widget.onChanged();
                        _notice('تم ترحيل $name بنجاح.');
                      } catch (error) { _notice(error.toString().replaceFirst('Exception: ', '')); }
                    },
                    icon: const Icon(Icons.check_circle_outline), label: const Text('ترحيل المستند'),
                  ),
                ],
                if (status == 1) ...[
                  if (_doctype == 'Quotation') _convertButton(sheetContext, name, 'Sales Order', 'إنشاء أمر بيع'),
                  if (_doctype == 'Sales Order') ...[
                    _convertButton(sheetContext, name, 'Delivery Note', 'إنشاء إذن تسليم'),
                    _convertButton(sheetContext, name, 'Sales Invoice', 'إنشاء فاتورة مبيعات'),
                  ],
                  if (_doctype == 'Delivery Note') _convertButton(sheetContext, name, 'Sales Invoice', 'إنشاء فاتورة مبيعات'),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await _confirm('إلغاء المستند', 'سيطلب التطبيق من ERPNext إلغاء المستند. قد يمنع النظام الإلغاء عند وجود مستندات مرتبطة. هل تريد المتابعة؟');
                      if (ok != true || !mounted) return;
                      try {
                        await widget.api.cancelSalesWorkflowDocument(_doctype, name);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        _load(reset: true); widget.onChanged();
                        _notice('تم إلغاء $name.');
                      } catch (error) { _notice(error.toString().replaceFirst('Exception: ', '')); }
                    },
                    icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء المستند'),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _convertButton(BuildContext sheetContext, String name, String target, String label) {
    return OutlinedButton.icon(
      onPressed: () async {
        final ok = await _confirm('إنشاء $target', 'سيُنشئ ERPNext مسودة مرتبطة بالمستند الأصلي. راجعها قبل الترحيل. هل تريد المتابعة؟');
        if (ok != true || !mounted) return;
        try {
          final created = await widget.api.makeSalesWorkflowDocument(
            sourceDoctype: _doctype, sourceName: name, targetDoctype: target,
          );
          if (sheetContext.mounted) Navigator.pop(sheetContext);
          _notice('تم إنشاء المسودة ${created['name']}.');
          if (target == 'Sales Invoice') widget.onChanged();
        } catch (error) { _notice(error.toString().replaceFirst('Exception: ', '')); }
      },
      icon: const Icon(Icons.transform_outlined), label: Text(label),
    );
  }

  Future<bool?> _confirm(String title, String message) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title), content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دورة المبيعات')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(10),
          child: Row(children: List.generate(_types.length, (i) => Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(label: Text(_labels[i]), selected: _tab == i, onSelected: (_) => _selectTab(i)),
          ))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(labelText: 'بحث في $_label', suffixIcon: IconButton(
                icon: const Icon(Icons.search), onPressed: () { _search = _searchController.text.trim(); _load(reset: true); },
              )),
              onSubmitted: (value) { _search = value.trim(); _load(reset: true); },
            )),
            const SizedBox(width: 8),
            IconButton(onPressed: _loading ? null : () => _load(reset: true), icon: const Icon(Icons.refresh)),
          ]),
        ),
        if (_tab != 2) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(alignment: AlignmentDirectional.centerStart, child: FilledButton.icon(
            onPressed: () => _createOrEdit(),
            icon: const Icon(Icons.add), label: Text('إنشاء ${_tab == 0 ? 'عرض سعر' : 'أمر بيع'}'),
          )),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(child: _rows.isEmpty && !_loading
          ? Center(child: Text('لا توجد مستندات في قسم $_label.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _rows.length) return Center(child: TextButton.icon(
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(Icons.expand_more), label: const Text('تحميل المزيد'),
                ));
                final row = _rows[index];
                final total = double.tryParse(row['grand_total']?.toString() ?? '') ?? 0;
                final status = (row['docstatus'] as num?)?.toInt() ?? 0;
                return Card(child: ListTile(
                  leading: CircleAvatar(child: Icon(status == 1 ? Icons.check_circle_outline : status == 2 ? Icons.cancel_outlined : Icons.edit_note)),
                  title: Text(row['name']?.toString() ?? 'مستند'),
                  subtitle: Text('${row['customer_name'] ?? row['customer'] ?? ''} • ${row['status'] ?? 'مسودة'}\n${row['company'] ?? ''}'),
                  isThreeLine: true,
                  trailing: Text(total.toStringAsFixed(2)),
                  onTap: () => _openDetails(row),
                ));
              },
            )),
      ]),
    );
  }
}

class _SalesLineDraft {
  ErpItem? item;
  Map<String, dynamic>? sourceRow;
  ErpWarehouse? warehouse;
  final qty = TextEditingController(text: '1');
  final rate = TextEditingController(text: '0');
  void dispose() { qty.dispose(); rate.dispose(); }
}

class _SalesDraftEditor extends StatefulWidget {
  const _SalesDraftEditor({
    required this.api, required this.doctype, required this.companies,
    required this.customers, required this.items, required this.warehouses,
    this.initialDraft,
  });
  final FrappeApi api;
  final String doctype;
  final List<ErpCompany> companies;
  final List<ErpCustomer> customers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final Map<String, dynamic>? initialDraft;

  @override
  State<_SalesDraftEditor> createState() => _SalesDraftEditorState();
}

class _SalesDraftEditorState extends State<_SalesDraftEditor> {
  final _key = GlobalKey<FormState>();
  final _lines = <_SalesLineDraft>[];
  late final List<ErpCompany> _availableCompanies;
  late final List<ErpCustomer> _availableCustomers;
  late final List<ErpItem> _availableItems;
  late final List<ErpWarehouse> _availableWarehouses;
  ErpCompany? _company;
  ErpCustomer? _customer;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _availableCompanies = List<ErpCompany>.of(widget.companies);
    _availableCustomers = List<ErpCustomer>.of(widget.customers);
    _availableItems = List<ErpItem>.of(widget.items);
    _availableWarehouses = List<ErpWarehouse>.of(widget.warehouses);
    final draft = widget.initialDraft;
    final companyName = draft?['company']?.toString();
    final customerId = draft?['customer']?.toString();
    _company = _firstOrNull(_availableCompanies.where((x) => x.name == companyName));
    if (_company == null && companyName != null) {
      _company = ErpCompany(name: companyName);
      _availableCompanies.add(_company!);
    }
    _customer = _firstOrNull(_availableCustomers.where((x) => x.id == customerId));
    if (_customer == null && customerId != null) {
      _customer = ErpCustomer(id: customerId, name: draft?['customer_name']?.toString() ?? customerId);
      _availableCustomers.add(_customer!);
    }
    final rawItems = draft?['items'];
    if (rawItems is List) {
      for (final raw in rawItems.whereType<Map<String, dynamic>>()) {
        final line = _SalesLineDraft()..sourceRow = Map<String, dynamic>.from(raw);
        final code = raw['item_code']?.toString();
        line.item = _firstOrNull(_availableItems.where((x) => x.code == code));
        if (line.item == null && code != null) {
          line.item = ErpItem(code: code, name: raw['item_name']?.toString() ?? code);
          _availableItems.add(line.item!);
        }
        line.qty.text = raw['qty']?.toString() ?? '1';
        line.rate.text = raw['rate']?.toString() ?? '0';
        final warehouseId = raw['warehouse']?.toString();
        if (warehouseId != null) {
          line.warehouse = _firstOrNull(_availableWarehouses.where((x) => x.id == warehouseId));
          if (line.warehouse == null) {
            line.warehouse = ErpWarehouse(id: warehouseId, name: warehouseId, company: companyName);
            _availableWarehouses.add(line.warehouse!);
          }
        }
        _lines.add(line);
      }
    }
    if (_lines.isEmpty) _lines.add(_SalesLineDraft());
  }

  @override
  void dispose() { for (final line in _lines) { line.dispose(); } super.dispose(); }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    if (_company == null || _customer == null || _lines.any((x) => x.item == null)) {
      setState(() => _error = 'اختر الشركة والعميل والصنف لكل بند.');
      return;
    }
    if (widget.doctype == 'Sales Order' && _lines.any((x) => x.item!.isStockItem && (x.warehouse == null || x.warehouse!.company != _company!.name))) {
      setState(() => _error = 'حدد مستودعاً تابعاً للشركة لكل صنف مخزني في أمر البيع.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final doc = <String, dynamic>{
        'doctype': widget.doctype,
        'company': _company!.name,
        'customer': _customer!.id,
        'transaction_date': today,
        if (widget.doctype == 'Quotation') 'quotation_to': 'Customer',
        if (widget.doctype == 'Sales Order') ...{'order_type': 'Sales', 'delivery_date': today},
        'items': _lines.map((line) {
          final row = Map<String, dynamic>.from(line.sourceRow ?? const <String, dynamic>{})
            ..['item_code'] = line.item!.code
            ..['qty'] = double.parse(line.qty.text.trim())
            ..['rate'] = double.parse(line.rate.text.trim());
          if (widget.doctype == 'Sales Order' && line.item!.isStockItem) {
            row['warehouse'] = line.warehouse!.id;
          }
          if (widget.doctype == 'Sales Order') row['delivery_date'] = today;
          return row;
        }).toList(),
      };
      if (widget.initialDraft == null) {
        await widget.api.createSalesWorkflowDraft(widget.doctype, doc);
      } else {
        await widget.api.updateSalesWorkflowDraft(widget.doctype, widget.initialDraft!['name'].toString(), doc);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _positive(String? value, String label, {bool allowZero = false}) {
    final n = double.tryParse((value ?? '').trim());
    if (n == null || !n.isFinite || (allowZero ? n < 0 : n <= 0)) return 'أدخل $label صحيحاً.';
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initialDraft == null ? 'إنشاء ${widget.doctype == 'Quotation' ? 'عرض سعر' : 'أمر بيع'}' : 'تعديل مسودة')),
    body: Form(
      key: _key,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<ErpCompany>(
          value: _company, isExpanded: true,
          decoration: const InputDecoration(labelText: 'الشركة'),
          items: _availableCompanies.map((x) => DropdownMenuItem(value: x, child: Text(x.name))).toList(),
          onChanged: _saving ? null : (v) => setState(() { _company = v; for (final line in _lines) { line.warehouse = null; } }),
          validator: (v) => v == null ? 'اختر الشركة.' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ErpCustomer>(
          value: _customer, isExpanded: true,
          decoration: const InputDecoration(labelText: 'العميل'),
          items: _availableCustomers.map((x) => DropdownMenuItem(value: x, child: Text('${x.name} • ${x.id}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _saving ? null : (v) => setState(() => _customer = v),
          validator: (v) => v == null ? 'اختر العميل.' : null,
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('بنود المستند', style: TextStyle(fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: _saving ? null : () => setState(() => _lines.add(_SalesLineDraft())), icon: const Icon(Icons.add), label: const Text('إضافة بند')),
        ]),
        ...List.generate(_lines.length, (i) {
          final line = _lines[i];
          return Card(key: ObjectKey(line), child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text('البند ${i + 1}')),
                IconButton(onPressed: _saving || _lines.length == 1 ? null : () => setState(() { _lines.removeAt(i).dispose(); }), icon: const Icon(Icons.delete_outline)),
              ]),
              DropdownButtonFormField<ErpItem>(
                value: line.item, isExpanded: true,
                decoration: const InputDecoration(labelText: 'الصنف'),
                items: _availableItems.map((x) => DropdownMenuItem(value: x, child: Text('${x.name} • ${x.code}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _saving ? null : (v) => setState(() { line.item = v; line.warehouse = null; }),
                validator: (v) => v == null ? 'اختر الصنف.' : null,
              ),
              if (widget.doctype == 'Sales Order' && line.item?.isStockItem == true) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<ErpWarehouse>(
                  value: line.warehouse, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'مستودع التسليم'),
                  items: _availableWarehouses.where((w) => w.company == _company?.name).map((w) => DropdownMenuItem(value: w, child: Text(w.name, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: _saving ? null : (v) => setState(() => line.warehouse = v),
                  validator: (v) => widget.doctype == 'Sales Order' && line.item?.isStockItem == true && v == null ? 'اختر مستودعاً تابعاً للشركة.' : null,
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextFormField(controller: line.qty, enabled: !_saving, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية'), validator: (v) => _positive(v, 'الكمية'))),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: line.rate, enabled: !_saving, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الوحدة'), validator: (v) => _positive(v, 'السعر', allowZero: true))),
              ]),
            ]),
          ));
        }),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: const Text('حفظ كمسودة')),
      ]),
    ),
  );
}

T? _firstOrNull<T>(Iterable<T> values) {
  for (final value in values) { return value; }
  return null;
}
