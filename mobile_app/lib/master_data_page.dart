import 'package:flutter/material.dart';
import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key, required this.api, required this.companies});
  final FrappeApi api;
  final List<ErpCompany> companies;
  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage> {
  static const types = {'Item': 'الأصناف', 'Supplier': 'الموردون', 'Warehouse': 'المستودعات'};
  String type = 'Item';
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  bool loading = false, moreLoading = false, hasMore = false;
  int offset = 0;
  String? error;

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> load({bool more = false}) async {
    if (loading || moreLoading || (more && !hasMore)) return;
    setState(() { if (more) { moreLoading = true; } else { loading = true; error = null; } });
    try {
      final page = await widget.api.fetchMasterDataRows(doctype: type, search: search.text, start: more ? offset : 0);
      if (!mounted) return;
      setState(() {
        if (more) { rows.addAll(page); } else { rows = page; }
        offset = rows.length;
        hasMore = page.length == FrappeApi.pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() { loading = false; moreLoading = false; });
    }
  }

  String titleOf(Map<String, dynamic> row) {
    final key = type == 'Item' ? 'item_name' : type == 'Supplier' ? 'supplier_name' : 'warehouse_name';
    return row[key]?.toString() ?? row['name']?.toString() ?? '';
  }

  String subtitleOf(Map<String, dynamic> row) {
    if (type == 'Item') return [row['name'], row['item_group'], row['stock_uom'], (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Supplier') return [row['name'], row['supplier_group'], row['supplier_type'], (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    return [row['name'], row['company'], (row['is_group'] == 1 || row['is_group'] == true) ? 'مجموعة' : 'مستودع فعلي', (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
  }

  Future<void> edit([String? name]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (_) => _MasterDataEditor(api: widget.api, type: type, companies: widget.companies, name: name),
    );
    if (saved == true && mounted) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة البيانات الأساسية'), actions: [
      IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.refresh)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: loading ? null : () => edit(), icon: const Icon(Icons.add), label: const Text('إضافة')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<String>(
        segments: types.entries.map((e) => ButtonSegment(value: e.key, label: Text(e.value))).toList(),
        selected: {type},
        onSelectionChanged: (v) { setState(() { type = v.first; rows = []; offset = 0; hasMore = false; error = null; }); load(); },
      )),
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: TextField(
        controller: search, textInputAction: TextInputAction.search, onSubmitted: (_) => load(),
        decoration: InputDecoration(labelText: 'بحث في ' + types[type]!, prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.arrow_forward))),
      )),
      if (loading) const LinearProgressIndicator(),
      if (error != null) ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر التحميل'), subtitle: Text(error!),
        trailing: IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.refresh))),
      Expanded(child: rows.isEmpty && !loading
        ? const Center(child: Text('لا توجد سجلات ظاهرة أو لا تتوفر صلاحية القراءة.'))
        : ListView.builder(padding: const EdgeInsets.only(bottom: 96), itemCount: rows.length,
          itemBuilder: (context, i) => Card(child: ListTile(
            leading: Icon(type == 'Item' ? Icons.inventory_2_outlined : type == 'Supplier' ? Icons.local_shipping_outlined : Icons.warehouse_outlined),
            title: Text(titleOf(rows[i])), subtitle: Text(subtitleOf(rows[i])),
            trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => edit(rows[i]['name']?.toString())),
            onTap: () => edit(rows[i]['name']?.toString()),
          )),
        ),
      ),
      if (hasMore || moreLoading) Padding(padding: const EdgeInsets.all(12), child: OutlinedButton(
        onPressed: moreLoading ? null : () => load(more: true),
        child: Text(moreLoading ? 'جارٍ التحميل...' : 'تحميل المزيد'),
      )),
    ]),
  );
}

class _MasterDataEditor extends StatefulWidget {
  const _MasterDataEditor({required this.api, required this.type, required this.companies, this.name});
  final FrappeApi api;
  final String type;
  final List<ErpCompany> companies;
  final String? name;
  @override
  State<_MasterDataEditor> createState() => _MasterDataEditorState();
}

class _MasterDataEditorState extends State<_MasterDataEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  bool loading = false, saving = false, stock = true, serial = false, batch = false, expiry = false, disabled = false, group = false;
  String supplierType = 'Company';
  String? company, error;
  bool get editing => widget.name != null;

  @override
  void initState() {
    super.initState();
    final keys = widget.type == 'Item'
      ? ['item_code', 'item_name', 'item_group', 'stock_uom']
      : widget.type == 'Supplier'
        ? ['supplier_name', 'supplier_group', 'country', 'tax_id', 'mobile_no', 'email_id', 'website']
        : ['warehouse_name', 'parent_warehouse'];
    for (final k in keys) { fields[k] = TextEditingController(); }
    if (widget.companies.isNotEmpty) company = widget.companies.first.name;
    if (editing) load();
  }

  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final d = await widget.api.fetchMasterDataDocument(doctype: widget.type, name: widget.name!);
      if (!mounted) return;
      for (final e in fields.entries) { e.value.text = d[e.key]?.toString() ?? ''; }
      setState(() {
        stock = d['is_stock_item'] == 1 || d['is_stock_item'] == true;
        serial = d['has_serial_no'] == 1 || d['has_serial_no'] == true;
        batch = d['has_batch_no'] == 1 || d['has_batch_no'] == true;
        expiry = d['has_expiry_date'] == 1 || d['has_expiry_date'] == true;
        disabled = d['disabled'] == 1 || d['disabled'] == true;
        group = d['is_group'] == 1 || d['is_group'] == true;
        supplierType = d['supplier_type']?.toString() == 'Individual' ? 'Individual' : 'Company';
        company = d['company']?.toString() ?? company;
      });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Widget field(String key, String label, {bool required = false, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(controller: fields[key], enabled: !(key == 'item_code' && editing), keyboardType: keyboard, decoration: InputDecoration(labelText: label),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null : null),
  );

  Widget toggle(String label, bool value, ValueChanged<bool> change) => SwitchListTile(
    contentPadding: EdgeInsets.zero, title: Text(label), value: value, onChanged: saving ? null : change);

  Future<void> save() async {
    if (saving || !(form.currentState?.validate() ?? false)) return;
    if (widget.type == 'Item' && serial && batch) { setState(() => error = 'اختر التتبع التسلسلي أو الدفعات، وليس الاثنين.'); return; }
    setState(() { saving = true; error = null; });
    try {
      final values = <String, dynamic>{for (final e in fields.entries) e.key: e.value.text.trim()};
      if (widget.type == 'Item') values.addAll({'is_stock_item': stock, 'has_serial_no': serial, 'has_batch_no': batch, 'has_expiry_date': expiry, 'disabled': disabled});
      if (widget.type == 'Supplier') values.addAll({'supplier_type': supplierType, 'disabled': disabled});
      if (widget.type == 'Warehouse') values.addAll({'company': company, 'is_group': group, 'disabled': disabled});
      await widget.api.saveMasterDataDocument(doctype: widget.type, name: widget.name, values: values);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.type == 'Item' ? 'الصنف' : widget.type == 'Supplier' ? 'المورد' : 'المستودع';
    return SizedBox(height: MediaQuery.of(context).size.height * .88,
      child: loading ? const Center(child: CircularProgressIndicator()) : Form(key: form, child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24),
        children: [
          Text((editing ? 'تعديل ' : 'إضافة ') + label, style: Theme.of(context).textTheme.titleLarge),
          if (editing) Text(widget.name!),
          if (error != null) Card(child: Padding(padding: const EdgeInsets.all(10), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
          if (widget.type == 'Item') ...[
            field('item_code', 'رمز الصنف', required: true), field('item_name', 'اسم الصنف', required: true),
            field('item_group', 'مجموعة الأصناف', required: true), field('stock_uom', 'وحدة القياس', required: true),
            toggle('صنف مخزني', stock, (v) => setState(() => stock = v)),
            toggle('تتبع بالأرقام التسلسلية', serial, (v) => setState(() { serial = v; if (v) batch = false; })),
            toggle('تتبع بالدفعات', batch, (v) => setState(() { batch = v; if (v) serial = false; })),
            toggle('يتطلب تاريخ انتهاء', expiry, (v) => setState(() => expiry = v)),
          ] else if (widget.type == 'Supplier') ...[
            field('supplier_name', 'اسم المورد', required: true),
            DropdownButtonFormField<String>(value: supplierType, decoration: const InputDecoration(labelText: 'نوع المورد'),
              items: const [DropdownMenuItem(value: 'Company', child: Text('شركة')), DropdownMenuItem(value: 'Individual', child: Text('فرد'))],
              onChanged: saving ? null : (v) { if (v != null) setState(() => supplierType = v); }),
            const SizedBox(height: 10), field('supplier_group', 'مجموعة الموردين', required: true),
            field('country', 'الدولة'), field('tax_id', 'الرقم الضريبي'),
            field('mobile_no', 'الهاتف', keyboard: TextInputType.phone), field('email_id', 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
            field('website', 'الموقع الإلكتروني'),
          ] else ...[
            field('warehouse_name', 'اسم المستودع', required: true),
            DropdownButtonFormField<String>(value: company, decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
              onChanged: saving || editing ? null : (v) => setState(() => company = v),
              validator: (v) => v == null || v.isEmpty ? 'حدد الشركة' : null),
            const SizedBox(height: 10), field('parent_warehouse', 'المستودع الأب (اختياري)'),
            toggle('مجموعة مستودعات', group, (v) => setState(() => group = v)),
          ],
          toggle('تعطيل السجل', disabled, (v) => setState(() => disabled = v)),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: saving ? null : save,
            icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
            label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ في ERPNext')),
          const Text('تُطبق صلاحيات ERPNext وقواعد التحقق والتسمية على الخادم. لا تعدل هذه الشاشة أرصدة المخزون أو حركاته.', textAlign: TextAlign.center),
        ],
      )),
    );
  }
}
