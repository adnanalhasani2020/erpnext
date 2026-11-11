import 'dart:convert';
import 'package:flutter/material.dart';
import 'api/frappe_api.dart';

class ErpDocTypeDefinition {
  const ErpDocTypeDefinition(this.group, this.label, this.doctype, this.icon);
  final String group, label, doctype;
  final IconData icon;
}

const erpDocTypeDefinitions = <ErpDocTypeDefinition>[
  ErpDocTypeDefinition('المبيعات', 'عروض الأسعار', 'Quotation', Icons.request_quote_outlined),
  ErpDocTypeDefinition('المبيعات', 'أوامر البيع', 'Sales Order', Icons.shopping_cart_outlined),
  ErpDocTypeDefinition('المبيعات', 'أذون التسليم', 'Delivery Note', Icons.local_shipping_outlined),
  ErpDocTypeDefinition('المبيعات', 'فواتير المبيعات', 'Sales Invoice', Icons.receipt_long_outlined),
  ErpDocTypeDefinition('المبيعات', 'نقاط البيع', 'POS Invoice', Icons.point_of_sale_outlined),
  ErpDocTypeDefinition('المبيعات', 'العملاء', 'Customer', Icons.people_outline),
  ErpDocTypeDefinition('المبيعات', 'جهات الاتصال', 'Contact', Icons.contact_phone_outlined),
  ErpDocTypeDefinition('المبيعات', 'الفرص البيعية', 'Opportunity', Icons.trending_up_outlined),
  ErpDocTypeDefinition('المبيعات', 'العملاء المحتملون', 'Lead', Icons.person_search_outlined),
  ErpDocTypeDefinition('المشتريات', 'طلبات المواد', 'Material Request', Icons.playlist_add_outlined),
  ErpDocTypeDefinition('المشتريات', 'طلبات عروض الأسعار', 'Request for Quotation', Icons.request_page_outlined),
  ErpDocTypeDefinition('المشتريات', 'عروض الموردين', 'Supplier Quotation', Icons.price_check_outlined),
  ErpDocTypeDefinition('المشتريات', 'أوامر الشراء', 'Purchase Order', Icons.shopping_bag_outlined),
  ErpDocTypeDefinition('المشتريات', 'إيصالات الشراء', 'Purchase Receipt', Icons.move_to_inbox_outlined),
  ErpDocTypeDefinition('المشتريات', 'فواتير المشتريات', 'Purchase Invoice', Icons.receipt_outlined),
  ErpDocTypeDefinition('المشتريات', 'الموردون', 'Supplier', Icons.local_shipping_outlined),
  ErpDocTypeDefinition('المخزون', 'الأصناف', 'Item', Icons.inventory_2_outlined),
  ErpDocTypeDefinition('المخزون', 'المستودعات', 'Warehouse', Icons.warehouse_outlined),
  ErpDocTypeDefinition('المخزون', 'حركات المخزون', 'Stock Entry', Icons.swap_horiz_outlined),
  ErpDocTypeDefinition('المخزون', 'تسويات المخزون', 'Stock Reconciliation', Icons.fact_check_outlined),
  ErpDocTypeDefinition('المخزون', 'قوائم الالتقاط', 'Pick List', Icons.playlist_add_check_outlined),
  ErpDocTypeDefinition('المخزون', 'الدفعات', 'Batch', Icons.qr_code_2_outlined),
  ErpDocTypeDefinition('المخزون', 'الأرقام التسلسلية', 'Serial No', Icons.numbers_outlined),
  ErpDocTypeDefinition('المخزون', 'فحوصات الجودة', 'Quality Inspection', Icons.verified_outlined),
  ErpDocTypeDefinition('المحاسبة', 'القيود اليومية', 'Journal Entry', Icons.menu_book_outlined),
  ErpDocTypeDefinition('المحاسبة', 'سندات الدفع', 'Payment Entry', Icons.payments_outlined),
  ErpDocTypeDefinition('المحاسبة', 'الحسابات', 'Account', Icons.account_balance_outlined),
  ErpDocTypeDefinition('المحاسبة', 'مراكز التكلفة', 'Cost Center', Icons.account_tree_outlined),
  ErpDocTypeDefinition('المحاسبة', 'حركات البنك', 'Bank Transaction', Icons.account_balance_wallet_outlined),
  ErpDocTypeDefinition('المحاسبة', 'مطابقة المدفوعات', 'Payment Reconciliation', Icons.rule_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'الموظفون', 'Employee', Icons.badge_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'الحضور', 'Attendance', Icons.fact_check_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'طلبات الإجازة', 'Leave Application', Icons.event_available_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'تخصيص الإجازات', 'Leave Allocation', Icons.calendar_month_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'مطالبات المصروفات', 'Expense Claim', Icons.request_quote_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'مسيرات الرواتب', 'Payroll Entry', Icons.payments_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'قسائم الرواتب', 'Salary Slip', Icons.receipt_long_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'تسجيلات الحضور', 'Employee Checkin', Icons.login_outlined),
  ErpDocTypeDefinition('المشاريع والدعم', 'المشاريع', 'Project', Icons.work_outline),
  ErpDocTypeDefinition('المشاريع والدعم', 'المهام', 'Task', Icons.task_alt_outlined),
  ErpDocTypeDefinition('المشاريع والدعم', 'سجل الوقت', 'Timesheet', Icons.timer_outlined),
  ErpDocTypeDefinition('المشاريع والدعم', 'التذاكر', 'Issue', Icons.support_agent_outlined),
  ErpDocTypeDefinition('التصنيع', 'قوائم المواد', 'BOM', Icons.schema_outlined),
  ErpDocTypeDefinition('التصنيع', 'أوامر التصنيع', 'Work Order', Icons.precision_manufacturing_outlined),
  ErpDocTypeDefinition('التصنيع', 'بطاقات العمل', 'Job Card', Icons.assignment_outlined),
  ErpDocTypeDefinition('الأصول', 'الأصول الثابتة', 'Asset', Icons.apartment_outlined),
  ErpDocTypeDefinition('الأصول', 'حركة الأصول', 'Asset Movement', Icons.swap_horiz_outlined),
];

class ErpDocTypeDirectoryPage extends StatelessWidget {
  const ErpDocTypeDirectoryPage({super.key, required this.api});
  final FrappeApi api;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ErpDocTypeDefinition>>{};
    for (final item in erpDocTypeDefinitions) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('شاشات ERPNext المستقلة')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('كل نوع مستند في شاشة مستقلة'),
            subtitle: Text('تُحمّل تعريفات الحقول من ERPNext، وتبقى الصلاحيات والتحققات النهائية للخادم.'),
          )),
          for (final group in groups.entries)
            Card(child: ExpansionTile(
              initiallyExpanded: group.key == 'المبيعات' || group.key == 'المشتريات',
              leading: const Icon(Icons.folder_outlined),
              title: Text(group.key),
              subtitle: Text(group.value.length.toString() + ' شاشة'),
              children: [
                for (final item in group.value)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    subtitle: Text(item.doctype, textDirection: TextDirection.ltr),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                      builder: (_) => ErpDocTypeWorkspacePage(api: api, definition: item),
                    )),
                  ),
              ],
            )),
        ],
      ),
    );
  }
}

class ErpDocTypeWorkspacePage extends StatefulWidget {
  const ErpDocTypeWorkspacePage({super.key, required this.api, required this.definition});
  final FrappeApi api;
  final ErpDocTypeDefinition definition;
  @override
  State<ErpDocTypeWorkspacePage> createState() => _ErpDocTypeWorkspacePageState();
}

class _ErpDocTypeWorkspacePageState extends State<ErpDocTypeWorkspacePage> {
  final _search = TextEditingController();
  Map<String, dynamic>? _meta;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filterFields = [];
  final Map<String, String> _filters = {};
  bool _loading = true, _more = false, _hasMore = false;
  int _offset = 0, _generation = 0;
  String? _error;

  String get _doctype => widget.definition.doctype;
  List<Map<String, dynamic>> get _fields => (_meta?['fields'] as List? ?? const [])
      .whereType<Map<String, dynamic>>().toList();
  List<String> get _listFields {
    final result = _fields.where((f) => f['fieldname'] is String &&
      f['fieldtype'] != 'Table' && f['fieldtype'] != 'Table MultiSelect' &&
      (f['in_list_view'] == 1 || f['in_standard_filter'] == 1 || f['reqd'] == 1))
      .map((f) => f['fieldname'].toString()).take(10).toList();
    if (!result.contains('name')) result.insert(0, 'name');
    return result;
  }

  @override
  void initState() { super.initState(); _initialize(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _initialize() async {
    setState(() { _loading = true; _error = null; });
    try {
      final meta = await widget.api.fetchDocTypeMeta(_doctype);
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _filterFields = (meta['fields'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((f) => f['fieldname'] is String && f['in_standard_filter'] == 1 &&
            !const {'Table','Table MultiSelect','Section Break','Column Break','Tab Break','HTML'}.contains(f['fieldtype']))
          .take(8).toList();
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _load({bool append = false}) async {
    if (_meta == null || (_loading && append) || (_more && append)) return;
    final generation = _generation;
    final start = append ? _offset : 0;
    setState(() { if (append) { _more = true; } else { _loading = true; _error = null; } });
    try {
      final fields = _listFields;
      final activeFilters = <List<dynamic>>[];
      for (final field in _filterFields) {
        final key = field['fieldname'].toString();
        final value = _filters[key]?.trim() ?? '';
        if (value.isEmpty) continue;
        final type = field['fieldtype']?.toString() ?? '';
        final operator = type == 'Data' || type == 'Link' ? 'like' : '=';
        activeFilters.add([key, operator, operator == 'like' ? '%' + value + '%' : value]);
      }
      final rows = await widget.api.fetchDocTypeRows(
        doctype: _doctype, fields: fields, search: _search.text,
        start: start, filters: activeFilters,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = append ? [..._rows, ...rows] : rows;
        _offset = start + rows.length;
        _hasMore = rows.length == FrappeApi.pageSize;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && generation == _generation) setState(() { _loading = false; _more = false; });
    }
  }


  Future<void> _edit({Map<String, dynamic>? source}) async {
    final editable = _fields.where((f) {
      final key = f['fieldname']?.toString() ?? '';
      final type = f['fieldtype']?.toString() ?? '';
      return key.isNotEmpty && !const {'name','owner','creation','modified','modified_by','docstatus','idx'}.contains(key) &&
        f['hidden'] != 1 && f['read_only'] != 1 &&
        !const {'Section Break','Column Break','Tab Break','HTML','Button','Fold','Heading'}.contains(type);
    }).toList();
    final controllers = <String, TextEditingController>{};
    for (final f in editable) {
      final key = f['fieldname'].toString();
      controllers[key] = TextEditingController(text: source?[key]?.toString() ?? f['default']?.toString() ?? '');
    }
    String error = '';
    bool saving = false;
    final saved = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text(source == null ? 'إنشاء ' + widget.definition.label : 'تعديل ' + widget.definition.label),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error.isNotEmpty) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            for (final f in editable)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controllers[f['fieldname'].toString()],
                  minLines: (f['fieldtype'] == 'Text' || f['fieldtype'] == 'Long Text' || f['fieldtype'] == 'Table') ? 3 : 1,
                  maxLines: (f['fieldtype'] == 'Text' || f['fieldtype'] == 'Long Text' || f['fieldtype'] == 'Table') ? 5 : 1,
                  decoration: InputDecoration(
                    labelText: f['label']?.toString() ?? f['fieldname'].toString(),
                    helperText: f['fieldtype'] == 'Table' || f['fieldtype'] == 'Table MultiSelect' ? 'أدخل صفوف الجدول بصيغة JSON' : f['fieldtype'] == 'Link' ? 'اسم السجل المرتبط في ERPNext' : f['reqd'] == 1 ? 'حقل إلزامي' : null,
                  ),
                ),
              ),
          ],
        ))),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: saving ? null : () async {
              refresh(() { saving = true; error = ''; });
              try {
                final values = <String, dynamic>{};
                for (final f in editable) {
                  final key = f['fieldname'].toString();
                  final type = f['fieldtype']?.toString() ?? '';
                  final raw = controllers[key]!.text.trim();
                  if (f['reqd'] == 1 && raw.isEmpty) throw FormatException('الحقل ' + (f['label']?.toString() ?? key) + ' مطلوب.');
                  if (raw.isEmpty) continue;
                  if (type == 'Check') {
                    values[key] = raw == '1' || raw.toLowerCase() == 'true' ? 1 : 0;
                  } else if (type == 'Table' || type == 'Table MultiSelect') {
                    final parsed = jsonDecode(raw);
                    if (parsed is! List) throw FormatException('قيمة الجدول ' + key + ' يجب أن تكون JSON array.');
                    values[key] = parsed;
                  } else if (type == 'Int') {
                    values[key] = int.tryParse(raw) ?? (throw FormatException('قيمة ' + key + ' يجب أن تكون عدداً صحيحاً.'));
                  } else if (const {'Float','Currency','Percent'}.contains(type)) {
                    values[key] = double.tryParse(raw) ?? (throw FormatException('قيمة ' + key + ' غير رقمية.'));
                  } else {
                    values[key] = raw;
                  }
                }
                await widget.api.saveDocTypeDocument(doctype: _doctype, name: source?['name']?.toString(), values: values);
                if (dialog.mounted) Navigator.pop(dialog, true);
              } catch (e) {
                refresh(() { error = e.toString().replaceFirst('Exception: ', ''); saving = false; });
              }
            },
            child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ عبر ERPNext'),
          ),
        ],
      )),
    );
    for (final c in controllers.values) { c.dispose(); }
    if (saved == true && mounted) { _generation++; await _load(); }
  }

  Future<void> _details(String name) async {
    try {
      final doc = await widget.api.fetchDocTypeDocument(doctype: _doctype, name: name);
      if (!mounted) return;
      final fields = _fields.where((f) => f['fieldname'] is String && doc.containsKey(f['fieldname'])).toList();
      final company = doc['company']?.toString() ?? '';
      final transitions = company.isEmpty ? <Map<String, dynamic>>[] : await widget.api.fetchWorkflowTransitions(doctype: _doctype, name: name, company: company).catchError((_) => <Map<String, dynamic>>[]);
      final status = (doc['docstatus'] as num?)?.toInt() ?? 0;
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
        builder: (sheet) => SizedBox(
          height: MediaQuery.of(sheet).size.height * .88,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(16), child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: Theme.of(sheet).textTheme.titleLarge),
                Text(_doctype + ' • ' + (status == 0 ? 'مسودة' : status == 1 ? 'مرحّل' : 'ملغى')),
              ])),
            ])),
            Expanded(child: ListView.separated(
              itemCount: fields.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final f = fields[i], key = f['fieldname'].toString(), value = doc[key];
                return ListTile(
                  title: Text(f['label']?.toString() ?? key),
                  subtitle: SelectableText(value is List || value is Map ? value.toString() : value?.toString() ?? '—'),
                );
              },
            )),
            Padding(padding: const EdgeInsets.all(12), child: Wrap(
              spacing: 8,
              children: [
                if (status == 0 && _meta?['is_submittable'] == 1) OutlinedButton.icon(
                  onPressed: () { Navigator.pop(sheet); _edit(source: doc); },
                  icon: const Icon(Icons.edit_outlined), label: const Text('تعديل المسودة'),
                ),
                if (status == 0 && _meta?['is_submittable'] == 1) FilledButton.tonal(
                  onPressed: () async {
                    try {
                      await widget.api.transitionDocTypeDocument(doctype: _doctype, name: name, action: 'Submit');
                      if (sheet.mounted) Navigator.pop(sheet);
                      _generation++; await _load();
                    } catch (e) { _notice(e.toString()); }
                  },
                  child: const Text('ترحيل'),
                ),
                for (final transition in transitions)
                  OutlinedButton(
                    onPressed: () async {
                      final action = transition['action']?.toString() ?? '';
                      if (action.isEmpty) return;
                      try {
                        await widget.api.applyWorkflowAction(doctype: _doctype, name: name, company: company, action: action);
                        if (sheet.mounted) Navigator.pop(sheet);
                        _generation++; await _load();
                      } catch (e) { _notice(e.toString()); }
                    },
                    child: Text(transition['action']?.toString() ?? 'إجراء'),
                  ),
                if (status == 1 && _meta?['is_submittable'] == 1) OutlinedButton(
                  onPressed: () async {
                    try {
                      await widget.api.transitionDocTypeDocument(doctype: _doctype, name: name, action: 'Cancel');
                      if (sheet.mounted) Navigator.pop(sheet);
                      _generation++; await _load();
                    } catch (e) { _notice(e.toString()); }
                  },
                  child: const Text('إلغاء'),
                ),
              ],
            )),
          ]),
        ),
      );
      _generation++; await _load();
    } catch (e) { _notice(e.toString()); }
  }

  void _notice(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value.replaceFirst('Exception: ', ''))));
  }

  @override
  Widget build(BuildContext context) {
    final fields = _listFields;
    return Scaffold(
      appBar: AppBar(
        title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.definition.label),
          Text(_doctype, style: Theme.of(context).textTheme.labelSmall),
        ]),
        actions: [
          IconButton(tooltip: 'إضافة سجل', onPressed: _loading ? null : () => _edit(), icon: const Icon(Icons.add)),
          IconButton(tooltip: 'تحديث', onPressed: _loading ? null : () { _generation++; _load(); }, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) { _generation++; _load(); },
          decoration: InputDecoration(
            labelText: 'بحث في ' + widget.definition.label,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(onPressed: () { _generation++; _load(); }, icon: const Icon(Icons.search)),
          ),
        )),
        if (_filterFields.isNotEmpty)
          ExpansionTile(
            title: const Text('فلاتر الشاشة الأصلية'),
            leading: const Icon(Icons.filter_alt_outlined),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  for (final field in _filterFields)
                    TextField(
                      decoration: InputDecoration(labelText: field['label']?.toString() ?? field['fieldname'].toString()),
                      onChanged: (value) => _filters[field['fieldname'].toString()] = value,
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonalIcon(
                      onPressed: _loading ? null : () { _generation++; _load(); },
                      icon: const Icon(Icons.filter_alt), label: const Text('تطبيق الفلاتر'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        if (_loading || _more) const LinearProgressIndicator(),
        if (_error != null) MaterialBanner(
          content: Text(_error!),
          actions: [TextButton(onPressed: _initialize, child: const Text('إعادة المحاولة'))],
        ),
        Expanded(child: _rows.isEmpty
          ? Center(child: Text(_loading ? 'جارٍ تحميل السجلات...' : 'لا توجد سجلات أو لا تملك صلاحية القراءة.'))
          : ListView.separated(
            itemCount: _rows.length + (_hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == _rows.length) return Center(child: TextButton(
                onPressed: _more ? null : () => _load(append: true),
                child: const Text('تحميل المزيد'),
              ));
              final row = _rows[index];
              final title = fields.firstWhere(
                (f) => f != 'name' && row[f] != null,
                orElse: () => 'name',
              );
              final subtitle = fields.where((f) => f != title && row[f] != null)
                  .take(3).map((f) => f + ': ' + row[f].toString()).join(' • ');
              return ListTile(
                leading: Icon(widget.definition.icon),
                title: Text(row[title]?.toString() ?? row['name']?.toString() ?? '—'),
                subtitle: Text(subtitle.isEmpty ? row['name']?.toString() ?? '' : subtitle),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _details(row['name'].toString()),
              );
            },
          ),
        ),
      ]),
    );
  }
}
