import 'dart:core';
import 'dart:core' as core;
import 'package:material_ui/material_ui.dart';
import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key, required this.api, required this.companies, this.initialType});
  final FrappeApi api;
  final List<ErpCompany> companies;
  final String? initialType;
  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage> {
  static const types = {'Item': 'الأصناف', 'Customer': 'العملاء', 'Supplier': 'الموردون', 'Warehouse': 'المستودعات', 'Item Group': 'مجموعات الأصناف', 'Customer Group': 'مجموعات العملاء', 'Territory': 'المناطق', 'Sales Person': 'مندوبو المبيعات', 'UOM': 'وحدات القياس', 'Supplier Group': 'مجموعات الموردين', 'Price List': 'قوائم الأسعار'};
  String type = 'Item';
  final search = TextEditingController();
  List<core.Map<String, dynamic>> rows = [];
  bool loading = false, moreLoading = false, hasMore = false;
  int offset = 0;
  String? error;

  @override
  void initState() { super.initState(); if (widget.initialType == 'Warehouse') type = 'Warehouse'; load(); }
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

  String titleOf(core.Map<String, dynamic> row) {
    final key = switch (type) { 'Item' => 'item_name', 'Customer' => 'customer_name', 'Supplier' => 'supplier_name', 'Warehouse' => 'warehouse_name', 'Item Group' => 'item_group_name', 'Customer Group' => 'customer_group_name', 'Territory' => 'territory_name', 'Sales Person' => 'sales_person_name', 'UOM' => 'uom_name', 'Supplier Group' => 'supplier_group_name', _ => 'price_list_name' };
    return row[key]?.toString() ?? row['name']?.toString() ?? '';
  }

  String subtitleOf(core.Map<String, dynamic> row) {
    if (type == 'Item') return [row['name'], row['item_group'], row['stock_uom'], (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Customer') return [row['name'], row['customer_group'], row['territory'], row['customer_type'], (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Customer Group') return [row['name'], row['parent_customer_group'], (row['is_group'] == 1 || row['is_group'] == true) ? 'مجموعة رئيسية' : 'مجموعة فرعية', (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Territory') return [row['name'], row['parent_territory'], (row['is_group'] == 1 || row['is_group'] == true) ? 'منطقة رئيسية' : 'منطقة فرعية', (row['disabled'] == 1 || row['disabled'] == true) ? 'معطل' : 'نشط'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    if (type == 'Sales Person') return [row['name'], row['parent_sales_person'], row['employee'], 'العمولة الأساسية: ${row['commission_rate'] ?? 0}%', (row['is_group'] == 1 || row['is_group'] == true) ? 'مجموعة' : '', (row['enabled'] == 1 || row['enabled'] == true) ? 'نشط' : 'معطل'].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
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
      IconButton(onPressed: loading || moreLoading ? null : () => load(), icon: const Icon(Icons.refresh)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: loading || moreLoading ? null : () => edit(), icon: const Icon(Icons.add), label: const Text('إضافة')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
        initialValue: type,
        decoration: const InputDecoration(labelText: 'نوع البيانات'),
        items: types.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: loading || moreLoading ? null : (v) { if (v != null) { setState(() { type = v; rows = []; offset = 0; hasMore = false; error = null; }); load(); } },
      )),
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: TextField(
        controller: search, enabled: !loading && !moreLoading, textInputAction: TextInputAction.search, onSubmitted: (_) => load(),
        decoration: InputDecoration(labelText: 'بحث في ${types[type]!}', prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: loading || moreLoading ? null : () => load(), icon: const Icon(Icons.arrow_forward))),
      )),
      if (loading) const LinearProgressIndicator(),
      if (error != null) ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر التحميل'), subtitle: Text(error!),
        trailing: IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.refresh))),
      Expanded(child: rows.isEmpty && !loading
        ? const Center(child: Text('لا توجد سجلات ظاهرة أو لا تتوفر صلاحية القراءة.'))
        : ListView.builder(padding: const EdgeInsets.only(bottom: 96), itemCount: rows.length,
          itemBuilder: (context, i) => Card(child: ListTile(
            leading: Icon(
              type == 'Item' ? Icons.inventory_2_outlined
                  : type == 'Customer' ? Icons.person_outline
                  : type == 'Supplier' ? Icons.local_shipping_outlined
                  : type == 'Sales Person' ? Icons.badge_outlined
                  : const {'Item Group', 'Customer Group', 'Supplier Group', 'Territory'}.contains(type) ? Icons.account_tree_outlined
                  : type == 'UOM' ? Icons.straighten_outlined
                  : type == 'Price List' ? Icons.price_change_outlined
                  : Icons.warehouse_outlined,
            ),
            title: Text(titleOf(rows[i])), subtitle: Text(subtitleOf(rows[i])),
            trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: loading || moreLoading ? null : () => edit(rows[i]['name']?.toString())),
            onTap: loading || moreLoading ? null : () => edit(rows[i]['name']?.toString()),
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
  String customerType = 'Company';
  String? company, error;
  final List<_ItemUomLine> itemUoms = [];
  bool get editing => widget.name != null;

  @override
  void initState() {
    super.initState();
    final keys = widget.type == 'Item'
      ? ['item_code', 'item_name', 'item_group', 'stock_uom']
      : widget.type == 'Customer'
        ? ['customer_name', 'customer_group', 'territory', 'tax_id', 'mobile_no', 'email_id', 'website', 'default_currency', 'default_price_list']
      : widget.type == 'Supplier'
        ? ['supplier_name', 'supplier_group', 'country', 'tax_id', 'mobile_no', 'email_id', 'website']
        : widget.type == 'Warehouse' ? ['warehouse_name', 'parent_warehouse']
        : widget.type == 'Item Group' ? ['item_group_name', 'parent_item_group']
        : widget.type == 'Customer Group' ? ['customer_group_name', 'parent_customer_group']
        : widget.type == 'Territory' ? ['territory_name', 'parent_territory']
        : widget.type == 'Sales Person' ? ['sales_person_name', 'parent_sales_person', 'commission_rate', 'employee']
        : widget.type == 'UOM' ? ['uom_name']
        : widget.type == 'Supplier Group' ? ['supplier_group_name', 'parent_supplier_group']
        : ['price_list_name', 'currency'];
    for (final k in keys) { fields[k] = TextEditingController(); }
    if (widget.type == 'Sales Person') fields['commission_rate']!.text = '0';
    if (widget.companies.isNotEmpty) company = widget.companies.first.name;
    if (editing) load();
    // Reference options are queried on demand, with server-side search and pagination.
  }

  @override
  void dispose() {
    for (final c in fields.values) { c.dispose(); }
    for (final row in itemUoms) { row.dispose(); }
    super.dispose();
  }

  Future<void> _chooseUom(_ItemUomLine row) async {
    final selected = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (sheetContext) {
        final search = TextEditingController();
        var results = <core.Map<String, dynamic>>[];
        var offset = 0;
        var loading = false;
        var started = false;
        var hasMore = false;
        String? error;
        Future<void> load(StateSetter refresh, {bool more = false}) async {
          if (loading || (more && !hasMore)) return;
          refresh(() { loading = true; error = null; });
          try {
            final page = await widget.api.fetchMasterDataRows(doctype: 'UOM', search: search.text, start: more ? offset : 0);
            if (!sheetContext.mounted) return;
            refresh(() {
              final filtered = page.whereType<core.Map<String, dynamic>>().where((item) =>
                item['enabled'] != 0 && item['enabled'] != false &&
                item['name']?.toString() != fields['stock_uom']?.text.trim()
              ).toList();
              if (more) {
                final ids = results.map((item) => item['name']).toSet();
                results.addAll(filtered.where((item) => !ids.contains(item['name'])));
              } else { results = filtered; }
              offset = more ? offset + page.length : page.length;
              hasMore = page.length == FrappeApi.pageSize;
            });
          } catch (e) {
            if (sheetContext.mounted) refresh(() => error = e.toString().replaceFirst('Exception: ', ''));
          } finally {
            if (sheetContext.mounted) refresh(() => loading = false);
          }
        }
        return StatefulBuilder(builder: (context, refresh) {
          if (!started) {
            started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) { if (sheetContext.mounted) load(refresh); });
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: SizedBox(height: MediaQuery.of(context).size.height * .7, child: Column(children: [
              const Text('اختيار وحدة القياس البديلة'),
              TextField(controller: search, textInputAction: TextInputAction.search,
                onSubmitted: (_) { refresh(() { results = []; offset = 0; hasMore = false; }); load(refresh); },
                decoration: const InputDecoration(labelText: 'ابحث عن وحدة قياس', prefixIcon: Icon(Icons.search))),
              if (loading) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              Expanded(child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final item = results[index];
                  final id = item['name']?.toString() ?? '';
                  return ListTile(title: Text(id), onTap: id.isEmpty ? null : () => Navigator.pop(sheetContext, id));
                },
              )),
              if (hasMore) OutlinedButton(onPressed: loading ? null : () => load(refresh, more: true), child: const Text('تحميل وحدات إضافية')),
            ])),
          );
        });
      },
    );
    if (selected != null && mounted) setState(() => row.uom = selected);
  }


  Future<void> _chooseReference(String key, String label, String doctype, {bool groupsOnly = false, bool sameCompany = false}) async {
    final selected = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (sheetContext) {
        final searchController = TextEditingController();
        var rows = <core.Map<String, dynamic>>[];
        var offset = 0;
        var loading = false;
        var started = false;
        var hasMore = false;
        String? loadError;
        Future<void> load(StateSetter refresh, {bool more = false}) async {
          if (loading || (more && !hasMore)) return;
          refresh(() { loading = true; loadError = null; });
          try {
            final page = await widget.api.fetchMasterDataRows(doctype: doctype, search: searchController.text, start: more ? offset : 0);
            if (!sheetContext.mounted) return;
            refresh(() {
              final filtered = page.whereType<core.Map<String, dynamic>>().where((row) {
                if (row['disabled'] == 1 || row['disabled'] == true) return false;
                if ((doctype == 'UOM' || doctype == 'Sales Person' || doctype == 'Price List') && (row['enabled'] == 0 || row['enabled'] == false)) return false;
                if (doctype == 'Price List' && row['selling'] != 1 && row['selling'] != true) return false;
                if (groupsOnly && row['is_group'] != 1 && row['is_group'] != true) return false;
                if (sameCompany && row['company'] != company) return false;
                if (key.startsWith('parent_') && row['name'] == widget.name) return false;
                return true;
              }).toList(growable: false);
              if (more) { final ids = rows.map((row) => row['name']).toSet(); rows.addAll(filtered.where((row) => !ids.contains(row['name']))); } else { rows = filtered; }
              offset = more ? offset + page.length : page.length;
              hasMore = page.length == FrappeApi.pageSize;
            });
          } catch (error) { if (sheetContext.mounted) refresh(() => loadError = error.toString().replaceFirst('Exception: ', '')); }
          finally { if (sheetContext.mounted) refresh(() => loading = false); }
        }
        return StatefulBuilder(builder: (context, refresh) {
          if (!started) { started = true; WidgetsBinding.instance.addPostFrameCallback((_) { if (sheetContext.mounted) load(refresh); }); }
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: SizedBox(height: MediaQuery.of(context).size.height * .72, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('اختيار $label', style: Theme.of(context).textTheme.titleLarge),
              TextField(controller: searchController, textInputAction: TextInputAction.search, onSubmitted: (_) { refresh(() { rows = []; offset = 0; hasMore = false; }); load(refresh); }, decoration: InputDecoration(labelText: 'ابحث في $label', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: loading ? null : () { refresh(() { rows = []; offset = 0; hasMore = false; }); load(refresh); }, icon: const Icon(Icons.search)))),
              if (loading) const LinearProgressIndicator(),
              if (loadError != null) ListTile(title: const Text('تعذر تحميل النتائج'), subtitle: Text(loadError!)),
              Expanded(child: rows.isEmpty && !loading ? const Center(child: Text('لا توجد نتائج مطابقة.')) : ListView.builder(itemCount: rows.length, itemBuilder: (context, index) { final row = rows[index]; final id = row['name']?.toString() ?? ''; final display = (row['warehouse_name'] ?? row['item_name'] ?? row['customer_name'] ?? row['supplier_name'] ?? row['item_group_name'] ?? row['customer_group_name'] ?? row['territory_name'] ?? row['sales_person_name'] ?? row['uom_name'] ?? row['price_list_name'] ?? id).toString(); return ListTile(title: Text(display), subtitle: Text(id), onTap: id.isEmpty ? null : () => Navigator.pop(sheetContext, id)); })),
              if (hasMore || loading) OutlinedButton.icon(onPressed: loading || !hasMore ? null : () => load(refresh, more: true), icon: const Icon(Icons.expand_more), label: const Text('تحميل نتائج إضافية')),
            ])),
          );
        });
      },
    );
    if (selected != null && mounted) setState(() { fields[key]?.text = selected; });
  }

  Widget referenceField(String key, String label, String doctype, {bool required = false, bool groupsOnly = false, bool sameCompany = false}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(
      controller: fields[key], readOnly: true, onTap: saving ? null : () => _chooseReference(key, label, doctype, groupsOnly: groupsOnly, sameCompany: sameCompany),
      decoration: InputDecoration(labelText: label, hintText: 'اضغط للبحث والاختيار من ERPNext', suffixIcon: const Icon(Icons.search)),
      validator: required ? (value) => value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null : null,
    ));
  }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final d = await widget.api.fetchMasterDataDocument(doctype: widget.type, name: widget.name!);
      if (!mounted) return;
      for (final e in fields.entries) { e.value.text = d[e.key]?.toString() ?? ''; }
      if (widget.type == 'Sales Person' && fields['commission_rate']!.text.isEmpty) {
        fields['commission_rate']!.text = '0';
      }
      for (final row in itemUoms) { row.dispose(); }
      itemUoms.clear();
      if (widget.type == 'Item' && d['uoms'] is List) {
        for (final raw in (d['uoms'] as List).whereType<core.Map>()) {
          itemUoms.add(_ItemUomLine(
            uom: raw['uom']?.toString() ?? '',
            factor: raw['conversion_factor']?.toString() ?? '',
          ));
        }
      }
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
        customerType = d['customer_type']?.toString() == 'Individual' ? 'Individual' : 'Company';
        company = d['company']?.toString() ?? company;
      });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Widget field(String key, String label, {bool required = false, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(controller: fields[key], enabled: !(editing && const {'item_code', 'warehouse_name', 'item_group_name', 'uom_name', 'supplier_group_name', 'customer_group_name', 'territory_name', 'sales_person_name', 'price_list_name'}.contains(key)), keyboardType: keyboard, decoration: InputDecoration(labelText: label),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null : null),
  );

  Widget toggle(String label, bool value, ValueChanged<bool> change) => SwitchListTile(
    contentPadding: EdgeInsets.zero, title: Text(label), value: value, onChanged: saving ? null : change);

  Future<void> save() async {
    if (saving || !(form.currentState?.validate() ?? false)) return;
    if (widget.type == 'Item' && serial && batch) { setState(() => error = 'اختر التتبع التسلسلي أو الدفعات، وليس الاثنين.'); return; }
    double? salesPersonCommissionRate;
    if (widget.type == 'Sales Person') {
      final rawRate = fields['commission_rate']!.text.trim();
      salesPersonCommissionRate = rawRate.isEmpty ? 0.0 : double.tryParse(rawRate);
      if (salesPersonCommissionRate == null || !salesPersonCommissionRate.isFinite ||
          salesPersonCommissionRate < 0 || salesPersonCommissionRate > 100) {
        setState(() => error = 'نسبة العمولة يجب أن تكون رقماً بين 0 و100.');
        return;
      }
    }
    setState(() { saving = true; error = null; });
    try {
      final values = <String, dynamic>{for (final e in fields.entries) e.key: e.value.text.trim()};
      if (widget.type == 'Item') {
        values.addAll({
          'is_stock_item': stock, 'has_serial_no': serial, 'has_batch_no': batch,
          'has_expiry_date': expiry, 'disabled': disabled,
          'uoms': itemUoms.where((row) => row.uom.trim().isNotEmpty || row.factor.text.trim().isNotEmpty)
              .map((row) => {'uom': row.uom, 'conversion_factor': double.tryParse(row.factor.text.trim()) ?? 0})
              .toList(),
        });
      }
      if (widget.type == 'Supplier') values.addAll({'supplier_type': supplierType, 'disabled': disabled});
      if (widget.type == 'Customer') values.addAll({'customer_type': customerType, 'disabled': disabled});
      if (widget.type == 'Sales Person') {
        values['commission_rate'] = salesPersonCommissionRate!;
        values.addAll({'is_group': group, 'enabled': enabled});
      }
      if (widget.type == 'Warehouse') values.addAll({'company': company, 'is_group': group, 'disabled': disabled});
      if (widget.type == 'Item Group' || widget.type == 'Supplier Group' || widget.type == 'Customer Group' || widget.type == 'Territory') values.addAll({'is_group': group, 'disabled': disabled});
      if (widget.type == 'UOM') values.addAll({'must_be_whole_number': wholeNumber, 'enabled': enabled});
      if (widget.type == 'Price List') values.addAll({'buying': buying, 'selling': selling, 'enabled': enabled});
      await widget.api.saveMasterDataDocument(doctype: widget.type, name: widget.name, values: values);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.type) { 'Item' => 'الصنف', 'Customer' => 'العميل', 'Supplier' => 'المورد', 'Warehouse' => 'المستودع', 'Item Group' => 'مجموعة الأصناف', 'Customer Group' => 'مجموعة العملاء', 'Territory' => 'المنطقة', 'Sales Person' => 'مندوب المبيعات', 'UOM' => 'وحدة القياس', 'Supplier Group' => 'مجموعة الموردين', _ => 'قائمة الأسعار' };
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
            const Divider(height: 28),
            Row(children: [
              const Expanded(child: Text('تحويلات وحدات القياس', style: TextStyle(fontWeight: FontWeight.bold))),
              IconButton(
                tooltip: 'إضافة وحدة بديلة',
                onPressed: saving ? null : () => setState(() => itemUoms.add(_ItemUomLine())),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            const Text('أدخل معامل التحويل بالنسبة لوحدة المخزون الأساسية؛ مثال: 1 كرتون = 12 قطعة.'),
            ...List.generate(itemUoms.length, (index) {
              final row = itemUoms[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: TextFormField(
                        key: ValueKey('uom-$index-${row.uom}'),
                        initialValue: row.uom,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'الوحدة البديلة', suffixIcon: Icon(Icons.search)),
                        onTap: saving ? null : () => _chooseUom(row),
                        validator: (value) => value == null || value.trim().isEmpty ? 'اختر وحدة القياس' : null,
                      )),
                      IconButton(
                        tooltip: 'حذف التحويل',
                        onPressed: saving ? null : () => setState(() { itemUoms.removeAt(index).dispose(); }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ]),
                    TextField(
                      controller: row.factor,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'معامل التحويل إلى وحدة المخزون'),
                    ),
                  ]),
                ),
              );
            }),
          ] else if (widget.type == 'Customer') ...[
            field('customer_name', 'اسم العميل', required: true),
            DropdownButtonFormField<String>(
              initialValue: customerType,
              decoration: const InputDecoration(labelText: 'نوع العميل'),
              items: const [
                DropdownMenuItem(value: 'Company', child: Text('شركة')),
                DropdownMenuItem(value: 'Individual', child: Text('فرد')),
              ],
              onChanged: saving ? null : (value) { if (value != null) setState(() => customerType = value); },
            ),
            const SizedBox(height: 10),
            referenceField('customer_group', 'مجموعة العملاء', 'Customer Group', required: true),
            referenceField('territory', 'المنطقة', 'Territory', required: true),
            field('tax_id', 'الرقم الضريبي'),
            field('mobile_no', 'الهاتف', keyboard: TextInputType.phone),
            field('email_id', 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
            field('website', 'الموقع الإلكتروني'),
            field('default_currency', 'العملة الافتراضية'),
            referenceField('default_price_list', 'قائمة الأسعار الافتراضية', 'Price List'),
          ] else if (widget.type == 'Sales Person') ...[
            field('sales_person_name', 'اسم مندوب المبيعات', required: true),
            referenceField('parent_sales_person', 'المندوب الرئيسي', 'Sales Person', required: !group, groupsOnly: true),
            field('commission_rate', 'نسبة العمولة الافتراضية %', keyboard: const TextInputType.numberWithOptions(decimal: true)),
            field('employee', 'الموظف المرتبط'),
            toggle('مجموعة مندوبي مبيعات', group, (v) => setState(() => group = v)),
            toggle('المندوب مفعّل', enabled, (v) => setState(() => enabled = v)),
          ] else if (widget.type == 'Supplier') ...[
            field('supplier_name', 'اسم المورد', required: true),
            DropdownButtonFormField<String>(initialValue: supplierType, decoration: const InputDecoration(labelText: 'نوع المورد'),
              items: const [DropdownMenuItem(value: 'Company', child: Text('شركة')), DropdownMenuItem(value: 'Individual', child: Text('فرد'))],
              onChanged: saving ? null : (v) { if (v != null) setState(() => supplierType = v); }),
            const SizedBox(height: 10), referenceField('supplier_group', 'مجموعة الموردين', 'Supplier Group', required: true, groupsOnly: true),
            field('country', 'الدولة'), field('tax_id', 'الرقم الضريبي'),
            field('mobile_no', 'الهاتف', keyboard: TextInputType.phone), field('email_id', 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
            field('website', 'الموقع الإلكتروني'),
          ] else if (widget.type == 'Warehouse') ...[
            field('warehouse_name', 'اسم المستودع', required: true),
            DropdownButtonFormField<String>(initialValue: company, decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
              onChanged: saving || editing ? null : (v) => setState(() => company = v),
              validator: (v) => v == null || v.isEmpty ? 'حدد الشركة' : null),
            const SizedBox(height: 10), referenceField('parent_warehouse', 'المستودع الأب (اختياري)', 'Warehouse', groupsOnly: true, sameCompany: true),
            toggle('مجموعة مستودعات', group, (v) => setState(() => group = v)),
          ] else if (widget.type == 'Item Group') ...[
            field('item_group_name', 'اسم المجموعة', required: true),
            referenceField('parent_item_group', 'المجموعة الأب (اختياري)', 'Item Group', groupsOnly: true),
            toggle('مجموعة رئيسية', group, (v) => setState(() => group = v)),
          ] else if (widget.type == 'Customer Group') ...[
            field('customer_group_name', 'اسم مجموعة العملاء', required: true),
            referenceField('parent_customer_group', 'مجموعة العملاء الأب (اختياري)', 'Customer Group', groupsOnly: true),
            toggle('مجموعة رئيسية', group, (v) => setState(() => group = v)),
          ] else if (widget.type == 'Territory') ...[
            field('territory_name', 'اسم المنطقة', required: true),
            referenceField('parent_territory', 'المنطقة الأب (اختياري)', 'Territory', groupsOnly: true),
            toggle('منطقة رئيسية', group, (v) => setState(() => group = v)),
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
          if (widget.type != 'UOM' && widget.type != 'Price List' && widget.type != 'Sales Person')
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


class _ItemUomLine {
  _ItemUomLine({this.uom = '', String factor = ''})
      : factor = TextEditingController(text: factor);
  String uom;
  final TextEditingController factor;
  void dispose() => factor.dispose();
}
