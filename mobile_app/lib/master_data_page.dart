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
  static const types = {'Item': 'الأصناف', 'Supplier': 'الموردون', 'Warehouse': 'المستودعات', 'Item Group': 'مجموعات الأصناف', 'UOM': 'وحدات القياس', 'Supplier Group': 'مجموعات الموردين', 'Price List': 'قوائم الأسعار'};
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
    final key = switch (type) { 'Item' => 'item_name', 'Supplier' => 'supplier_name', 'Warehouse' => 'warehouse_name', 'Item Group' => 'item_group_name', 'UOM' => 'uom_name', 'Supplier Group' => 'supplier_group_name', _ => 'price_list_name' };
    return row[key]?.toString() ?? row['name']?.toString() ?? '';
  }

  String subtitleOf(Map<String, dynamic> row) {
    if (type == 'Item') return [row['name'], row['item_group'], row['stock_uom'], (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Supplier') return [row['name'], row['supplier_group'], row['supplier_type'], (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Warehouse') return [row['name'], row['company'], (row['is_group'] == 1 || row['is_group'] == true) ? 'مجموعة' : 'مستودع فعلي', (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Item Group') return [row['name'], row['parent_item_group'], (row['is_group'] == 1 || row['is_group'] == true) ? 'مجموعة' : 'تصنيف', (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Supplier Group') return [row['name'], row['parent_supplier_group'], (row['is_group'] == 1 || row['is_group'] == true) ? 'مجموعة' : 'تصنيف', (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'UOM') return [row['name'], (row['must_be_whole_number'] == 1 || row['must_be_whole_number'] == true) ? 'أعداد صحيحة فقط' : 'يسمح بالكسور', (row['enabled'] == 1 || row['enabled'] == true) ? 'نشط' : 'معطل'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    return [row['name'], row['currency'], (row['selling'] == 1 || row['selling'] == true) ? 'مبيعات' : '', (row['buying'] == 1 || row['buying'] == true) ? 'مشتريات' : '', (row['enabled'] == 1 || row['enabled'] == true) ? 'نشط' : 'معطل'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
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
      Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
        value: type,
        decoration: const InputDecoration(labelText: 'نوع البيانات'),
        items: types.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if (v != null) { setState(() { type = v; rows = []; offset = 0; hasMore = false; error = null; }); load(); } },
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
  bool loading = false, saving = false, stock = true, serial = false, batch = false, expiry = false, disabled = false, group = false, enabled = true, wholeNumber = false, buying = false, selling = true;
  String supplierType = 'Company';
  String? company, error;
  final Map<String, List<Map<String, dynamic>>> references = {};
  bool referencesLoading = false;
  bool get editing => widget.name != null;

  @override
  void initState() {
    super.initState();
    final keys = widget.type == 'Item'
      ? ['item_code', 'item_name', 'item_group', 'stock_uom']
      : widget.type == 'Supplier'
        ? ['supplier_name', 'supplier_group', 'country', 'tax_id', 'mobile_no', 'email_id', 'website']
        : widget.type == 'Warehouse' ? ['warehouse_name', 'parent_warehouse']
        : widget.type == 'Item Group' ? ['item_group_name', 'parent_item_group']
        : widget.type == 'UOM' ? ['uom_name']
        : widget.type == 'Supplier Group' ? ['supplier_group_name', 'parent_supplier_group']
        : ['price_list_name', 'currency'];
    for (final k in keys) { fields[k] = TextEditingController(); }
    if (widget.companies.isNotEmpty) company = widget.companies.first.name;
    if (editing) load();
    _loadReferences();
  }

  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }

  Future<void> _loadReferences() async {
    final requiredTypes = switch (widget.type) {
      'Item' => const ['Item Group', 'UOM'],
      'Supplier' => const ['Supplier Group'],
      'Warehouse' => const ['Warehouse'],
      'Item Group' => const ['Item Group'],
      'Supplier Group' => const ['Supplier Group'],
      _ => const <String>[],
    };
    if (requiredTypes.isEmpty) return;
    setState(() => referencesLoading = true);
    try {
      final results = await Future.wait(requiredTypes.map(widget.api.fetchMasterDataOptions));
      if (!mounted) return;
      for (var i = 0; i < requiredTypes.length; i++) {
        references[requiredTypes[i]] = results[i];
      }
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر تحميل القوائم المرجعية: ' + e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => referencesLoading = false);
    }
  }

  Widget referenceField(String key, String label, String doctype, {bool required = false, bool groupsOnly = false, bool sameCompany = false}) {
    final current = fields[key]?.text.trim() ?? '';
    var options = references[doctype] ?? const <Map<String, dynamic>>[];
    options = options.where((row) {
      if (widget.type == 'UOM' && (row['enabled'] == 0 || row['enabled'] == false)) return false;
      if (groupsOnly && row['is_group'] != 1 && row['is_group'] != true) return false;
      if (sameCompany && row['company'] != company) return false;
      if (editing && key != 'parent_warehouse' && key != 'item_group' && key != 'supplier_group' &&
          row['name'] == widget.name) return false;
      if (key.startsWith('parent_') && row['name'] == widget.name) return false;
      return true;
    }).toList(growable: false);
    final names = options.map((row) => row['name']?.toString() ?? '').where((v) => v.isNotEmpty).toSet().toList();
    if (current.isNotEmpty && !names.contains(current)) names.insert(0, current);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, suffixIcon: referencesLoading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null),
        items: [
          if (!required) const DropdownMenuItem<String>(value: '', child: Text('بدون تحديد')),
          ...names.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: saving || referencesLoading ? null : (value) {
          fields[key]?.text = value ?? '';
          setState(() {});
        },
        validator: required ? (value) => value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null : null,
      ),
    );
  }

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
        enabled = d['enabled'] == 1 || d['enabled'] == true;
        wholeNumber = d['must_be_whole_number'] == 1 || d['must_be_whole_number'] == true;
        buying = d['buying'] == 1 || d['buying'] == true;
        selling = d['selling'] == 1 || d['selling'] == true;
        supplierType = d['supplier_type']?.toString() == 'Individual' ? 'Individual' : 'Company';
        company = d['company']?.toString() ?? company;
      });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Widget field(String key, String label, {bool required = false, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(controller: fields[key], enabled: !(editing && const {'item_code', 'warehouse_name', 'item_group_name', 'uom_name', 'supplier_group_name', 'price_list_name'}.contains(key)), keyboardType: keyboard, decoration: InputDecoration(labelText: label),
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
      if (widget.type == 'Item Group' || widget.type == 'Supplier Group') values.addAll({'is_group': group, 'disabled': disabled});
      if (widget.type == 'UOM') values.addAll({'must_be_whole_number': wholeNumber, 'enabled': enabled});
      if (widget.type == 'Price List') values.addAll({'buying': buying, 'selling': selling, 'enabled': enabled});
      await widget.api.saveMasterDataDocument(doctype: widget.type, name: widget.name, values: values);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.type) { 'Item' => 'الصنف', 'Supplier' => 'المورد', 'Warehouse' => 'المستودع', 'Item Group' => 'مجموعة الأصناف', 'UOM' => 'وحدة القياس', 'Supplier Group' => 'مجموعة الموردين', _ => 'قائمة الأسعار' };
    return SizedBox(height: MediaQuery.of(context).size.height * .88,
      child: loading ? const Center(child: CircularProgressIndicator()) : Form(key: form, child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24),
        children: [
          Text((editing ? 'تعديل ' : 'إضافة ') + label, style: Theme.of(context).textTheme.titleLarge),
          if (editing) Text(widget.name!),
          if (error != null) Card(child: Padding(padding: const EdgeInsets.all(10), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
          if (widget.type == 'Item') ...[
            field('item_code', 'رمز الصنف', required: true), field('item_name', 'اسم الصنف', required: true),
            referenceField('item_group', 'مجموعة الأصناف', 'Item Group', required: true, groupsOnly: true), referenceField('stock_uom', 'وحدة القياس', 'UOM', required: true),
            toggle('صنف مخزني', stock, (v) => setState(() => stock = v)),
            toggle('تتبع بالأرقام التسلسلية', serial, (v) => setState(() { serial = v; if (v) batch = false; })),
            toggle('تتبع بالدفعات', batch, (v) => setState(() { batch = v; if (v) serial = false; })),
            toggle('يتطلب تاريخ انتهاء', expiry, (v) => setState(() => expiry = v)),
          ] else if (widget.type == 'Supplier') ...[
            field('supplier_name', 'اسم المورد', required: true),
            DropdownButtonFormField<String>(value: supplierType, decoration: const InputDecoration(labelText: 'نوع المورد'),
              items: const [DropdownMenuItem(value: 'Company', child: Text('شركة')), DropdownMenuItem(value: 'Individual', child: Text('فرد'))],
              onChanged: saving ? null : (v) { if (v != null) setState(() => supplierType = v); }),
            const SizedBox(height: 10), referenceField('supplier_group', 'مجموعة الموردين', 'Supplier Group', required: true, groupsOnly: true),
            field('country', 'الدولة'), field('tax_id', 'الرقم الضريبي'),
            field('mobile_no', 'الهاتف', keyboard: TextInputType.phone), field('email_id', 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
            field('website', 'الموقع الإلكتروني'),
          ] else if (widget.type == 'Warehouse') ...[
            field('warehouse_name', 'اسم المستودع', required: true),
            DropdownButtonFormField<String>(value: company, decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
              onChanged: saving || editing ? null : (v) => setState(() => company = v),
              validator: (v) => v == null || v.isEmpty ? 'حدد الشركة' : null),
            const SizedBox(height: 10), referenceField('parent_warehouse', 'المستودع الأب (اختياري)', 'Warehouse', groupsOnly: true, sameCompany: true),
            toggle('مجموعة مستودعات', group, (v) => setState(() => group = v)),
          ] else if (widget.type == 'Item Group') ...[
            field('item_group_name', 'اسم المجموعة', required: true),
            referenceField('parent_item_group', 'المجموعة الأب (اختياري)', 'Item Group', groupsOnly: true),
            toggle('مجموعة رئيسية', group, (v) => setState(() => group = v)),
          ] else if (widget.type == 'Supplier Group') ...[
            field('supplier_group_name', 'اسم مجموعة الموردين', required: true),
            referenceField('parent_supplier_group', 'المجموعة الأب (اختياري)', 'Supplier Group', groupsOnly: true),
            toggle('مجموعة رئيسية', group, (v) => setState(() => group = v)),
          ] else if (widget.type == 'UOM') ...[
            field('uom_name', 'اسم وحدة القياس', required: true),
            toggle('يجب أن تكون الكمية أعداداً صحيحة', wholeNumber, (v) => setState(() => wholeNumber = v)),
            toggle('الوحدة مفعّلة', enabled, (v) => setState(() => enabled = v)),
          ] else ...[
            field('price_list_name', 'اسم قائمة الأسعار', required: true),
            field('currency', 'العملة', required: true),
            toggle('قائمة أسعار المبيعات', selling, (v) => setState(() => selling = v)),
            toggle('قائمة أسعار المشتريات', buying, (v) => setState(() => buying = v)),
            toggle('القائمة مفعّلة', enabled, (v) => setState(() => enabled = v)),
          ],
          if (widget.type != 'UOM' && widget.type != 'Price List')
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
