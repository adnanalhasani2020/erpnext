import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'api/frappe_api.dart';
import 'doctype_workspace_model.dart';
import 'workspace_web_page.dart';

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
  final Map<String, String> _filterOperators = {};
  final Map<String, TextEditingController> _filterControllers = {};
  String _sortField = 'modified';
  bool _sortDescending = true;
  bool _loading = true, _more = false, _hasMore = false;
  int _offset = 0, _generation = 0;
  String? _error;

  String get _doctype => widget.definition.doctype;
  List<Map<String, dynamic>> get _fields => (_meta?['fields'] as List? ?? const [])
      .whereType<Map<String, dynamic>>().toList();
  List<String> get _listFields {
    final result = _fields.where((f) => f['fieldname'] is String &&
      f['fieldtype'] != 'Table' && f['fieldtype'] != 'Table MultiSelect' &&
      f['in_list_view'] == 1)
      .map((f) => f['fieldname'].toString()).toList();
    if (!result.contains('name')) result.insert(0, 'name');
    if (!result.contains('modified')) result.add('modified');
    return result;
  }

  String _fieldLabel(String fieldname) {
    if (fieldname == 'name') return 'المعرّف';
    if (fieldname == 'modified') return 'آخر تعديل';
    final matches = _fields.where((field) => field['fieldname'] == fieldname).toList();
    return matches.isEmpty ? fieldname : (matches.first['label']?.toString() ?? fieldname);
  }

  @override
  void initState() { super.initState(); _initialize(); }
  @override
  void dispose() {
    _search.dispose();
    for (final controller in _filterControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

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
          .toList();
        for (final field in _filterFields) {
          final key = field['fieldname'].toString();
          _filterControllers.putIfAbsent(key, () => TextEditingController());
        }
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
      for (final entry in widget.definition.routeOptions.entries) {
        activeFilters.add([entry.key, '=', entry.value]);
      }
      for (final field in _filterFields) {
        final key = field['fieldname'].toString();
        final value = _filters[key]?.trim() ?? '';
        if (value.isEmpty) continue;
        final type = field['fieldtype']?.toString() ?? '';
        final operator = _filterOperators[key] ?? (type == 'Data' || type == 'Small Text' ? 'like' : '=');
        final filterValue = operator == 'like' ? '%$value%' : value;
        activeFilters.add([key, operator, filterValue]);
      }
      final rows = await widget.api.fetchDocTypeRows(
        doctype: _doctype, fields: fields, search: _search.text,
        start: start, filters: activeFilters,
        orderBy: '$_sortField ${_sortDescending ? 'desc' : 'asc'}',
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


  List<String> _filterOperatorsFor(Map<String, dynamic> field) {
    final type = field['fieldtype']?.toString() ?? '';
    if (const {'Int','Float','Currency','Percent','Date','Datetime','Time','Duration'}.contains(type)) {
      return const ['=', '!=', '>', '>=', '<', '<='];
    }
    if (type == 'Data' || type == 'Link' || type == 'Dynamic Link' || type == 'Small Text') {
      return const ['like', '=', '!='];
    }
    return const ['=', '!='];
  }

  Future<String?> _pickLinkValue(String target) async {
    final query = TextEditingController();
    List<Map<String, dynamic>> rows = [];
    List<String> displayFields = const [];
    bool loading = false;
    bool dialogOpen = true;
    String? error;
    Future<void> search(StateSetter refresh) async {
      refresh(() { loading = true; error = null; });
      try {
        final meta = await widget.api.fetchDocTypeMeta(target);
        final fields = (meta['fields'] as List? ?? const []).whereType<Map<String, dynamic>>();
        displayFields = fields.where((f) => f['fieldname'] is String &&
          (f['in_list_view'] == 1 || f['reqd'] == 1))
          .map((f) => f['fieldname'].toString()).where((f) => f != 'name').take(4).toList();
        rows = await widget.api.fetchDocTypeRows(
          doctype: target, fields: displayFields, search: query.text.trim(),
          searchFields: displayFields,
        );
      } catch (e) {
        error = e.toString().replaceFirst('Exception: ', '');
      }
      if (dialogOpen && mounted) refresh(() => loading = false);
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text('اختيار سجل من $target'),
        content: SizedBox(width: 520, height: 420, child: Column(children: [
          TextField(
            controller: query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => search(refresh),
            decoration: InputDecoration(
              labelText: 'ابحث في $target',
              suffixIcon: IconButton(onPressed: loading ? null : () => search(refresh), icon: const Icon(Icons.search)),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
          Expanded(child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, index) {
              final row = rows[index];
              final name = row['name']?.toString() ?? '';
              final subtitle = displayFields.where((f) => row[f] != null)
                .map((f) => row[f].toString()).join(' • ');
              return ListTile(
                title: Text(name),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
                onTap: name.isEmpty ? null : () { dialogOpen = false; Navigator.pop(dialogContext, name); },
              );
            },
          )),
        ])),
        actions: [TextButton(onPressed: () { dialogOpen = false; Navigator.pop(dialogContext); }, child: const Text('إغلاق'))],
      )),
    );
    dialogOpen = false;
    query.dispose();
    return picked;
  }

  Future<bool> _confirmAction(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('رجوع')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد')),
          ],
        ),
      ) ?? false;

  Future<List<Map<String, dynamic>>?> _editChildTable(
    Map<String, dynamic> field,
    List<Map<String, dynamic>> currentRows,
  ) async {
    final childDoctype = field['options']?.toString().trim() ?? '';
    if (childDoctype.isEmpty) {
      _notice('تعريف نوع الجدول الفرعي غير متاح من ERPNext.');
      return null;
    }
    late final Map<String, dynamic> meta;
    try {
      meta = await widget.api.fetchDocTypeMeta(childDoctype);
    } catch (e) {
      _notice('تعذر تحميل تعريف الجدول الفرعي: ${e.toString().replaceFirst('Exception: ', '')}');
      return null;
    }
    final rows = currentRows.map((row) => Map<String, dynamic>.from(row)).toList();
    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text(field['label']?.toString() ?? childDoctype),
        content: SizedBox(
          width: 560,
          height: 440,
          child: Column(children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: () async {
                  final row = await _editChildRow(meta, null);
                  if (row != null) refresh(() => rows.add(row));
                },
                icon: const Icon(Icons.add),
                label: const Text('إضافة صف'),
              ),
            ),
            Expanded(child: rows.isEmpty
              ? const Center(child: Text('لا توجد صفوف. أضف صفاً للبدء.'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = rows[index];
                    final labelField = (meta['fields'] as List? ?? const [])
                        .whereType<Map<String, dynamic>>()
                        .firstWhere((f) => f['in_list_view'] == 1 && row[f['fieldname']] != null,
                          orElse: () => <String, dynamic>{});
                    final labelKey = labelField['fieldname']?.toString();
                    final title = labelKey == null ? 'السطر ${index + 1}' : row[labelKey].toString();
                    return ListTile(
                      title: Text(title),
                      subtitle: Text('السطر ${index + 1}'),
                      onTap: () async {
                        final edited = await _editChildRow(meta, row);
                        if (edited != null) refresh(() => rows[index] = edited);
                      },
                      trailing: IconButton(
                        tooltip: 'حذف الصف',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => refresh(() => rows.removeAt(index)),
                      ),
                    );
                  },
                )),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, rows), child: const Text('اعتماد الصفوف')),
        ],
      )),
    );
  }

  Future<Map<String, dynamic>?> _editChildRow(
    Map<String, dynamic> meta,
    Map<String, dynamic>? source,
  ) async {
    final fields = (meta['fields'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((field) {
          final key = field['fieldname']?.toString() ?? '';
          final type = field['fieldtype']?.toString() ?? '';
          return key.isNotEmpty && !const {
            'name','owner','creation','modified','modified_by','docstatus','idx',
            'parent','parenttype','parentfield'
          }.contains(key) && field['hidden'] != 1 && field['read_only'] != 1 &&
            !const {'Section Break','Column Break','Tab Break','HTML','Button','Fold','Heading'}.contains(type);
        }).toList();
    final controllers = <String, TextEditingController>{};
    final checks = <String, bool>{};
    final selections = <String, String?>{};
    final tableValues = <String, List<Map<String, dynamic>>>{};
    for (final field in fields) {
      final key = field['fieldname'].toString();
      final type = field['fieldtype']?.toString() ?? '';
      final initial = source?[key] ?? widget.definition.routeOptions[key] ?? field['default'];
      if (type == 'Table' || type == 'Table MultiSelect') {
        tableValues[key] = initial is List
            ? initial.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
            : <Map<String, dynamic>>[];
      } else if (type == 'Check') {
        checks[key] = initial == 1 || initial == true || initial?.toString() == '1';
      } else if (type == 'Select') {
        selections[key] = initial?.toString();
      } else {
        controllers[key] = TextEditingController(text: initial?.toString() ?? '');
      }
    }
    void clearDependentDynamicLinks(String targetField) {
      for (final dynamicField in fields.where((field) =>
          field['fieldtype'] == 'Dynamic Link' && field['options']?.toString() == targetField)) {
        final dynamicKey = dynamicField['fieldname']?.toString();
        if (dynamicKey != null) controllers[dynamicKey]?.clear();
      }
    }
    String error = '';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text(source == null ? 'إضافة صف' : 'تعديل الصف'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error.isNotEmpty) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            for (final field in fields)
              Builder(builder: (context) {
                final key = field['fieldname'].toString();
                final type = field['fieldtype']?.toString() ?? '';
                final label = field['label']?.toString() ?? key;
                if (type == 'Table' || type == 'Table MultiSelect') {
                  final count = tableValues[key]?.length ?? 0;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.table_rows_outlined),
                      title: Text(label),
                      subtitle: Text('$count صف'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final updated = await _editChildTable(
                          field,
                          tableValues[key] ?? <Map<String, dynamic>>[],
                        );
                        if (updated != null) refresh(() => tableValues[key] = updated);
                      },
                    ),
                  );
                }
                if (type == 'Check') {
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    value: checks[key] ?? false,
                    onChanged: (value) => refresh(() => checks[key] = value ?? false),
                  );
                }
                if (type == 'Select') {
                  final options = (field['options']?.toString() ?? '').split('\n')
                      .map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
                  final current = selections[key];
                  final items = <String>{...options, if (current != null && current.isNotEmpty) current}.toList();
                  return DropdownButtonFormField<String>(
                    initialValue: current != null && current.isNotEmpty ? current : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: label),
                    items: items.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (value) {
                        clearDependentDynamicLinks(key);
                        refresh(() => selections[key] = value);
                      },
                  );
                }
                final controller = controllers[key]!;
                final isLink = type == 'Link' && (field['options']?.toString().trim().isNotEmpty ?? false);
                final dynamicLinkField = field['options']?.toString() ?? '';
                final dynamicLinkTarget = selections[dynamicLinkField] ??
                    controllers[dynamicLinkField]?.text ??
                    source?[dynamicLinkField]?.toString() ?? '';
                final isDynamicLink = type == 'Dynamic Link';
                final canPickLink = isLink || (isDynamicLink && dynamicLinkTarget.trim().isNotEmpty);
                final isDate = type == 'Date';
                final isDateTime = type == 'Datetime';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controller,
                    onChanged: (_) {
                      final hasDynamicDependents = fields.any((field) =>
                        field['fieldtype'] == 'Dynamic Link' && field['options']?.toString() == key);
                      if (hasDynamicDependents) {
                        clearDependentDynamicLinks(key);
                        refresh(() {});
                      }
                    },
                    keyboardType: const {'Int','Float','Currency','Percent'}.contains(type)
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : type == 'Email' ? TextInputType.emailAddress
                      : type == 'Phone' ? TextInputType.phone : TextInputType.text,
                    readOnly: isDate || isDateTime,
                    decoration: InputDecoration(
                      labelText: label,
                      helperText: canPickLink ? 'اختر سجلاً موجوداً في ERPNext' : isDynamicLink ? 'حدد نوع المرجع أولاً' : field['reqd'] == 1 ? 'حقل إلزامي' : null,
                      suffixIcon: isDate
                        ? const Icon(Icons.calendar_today_outlined)
                        : canPickLink ? IconButton(
                            tooltip: 'اختيار سجل',
                            onPressed: () async {
                              final target = isLink ? field['options'].toString() : dynamicLinkTarget.trim();
                              final selected = await _pickLinkValue(target);
                              if (selected != null) controller.text = selected;
                            },
                            icon: const Icon(Icons.search),
                          ) : null,
                    ),
                    onTap: isDate || isDateTime ? () async {
                      final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: context, initialDate: initial,
                        firstDate: DateTime(1900), lastDate: DateTime(2200),
                      );
                      if (picked == null) return;
                      var chosen = DateTime(picked.year, picked.month, picked.day, initial.hour, initial.minute);
                      if (isDateTime) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
                        );
                        if (time == null) return;
                        chosen = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                      }
                      final date = '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
                      controller.text = isDateTime
                        ? '${date} ${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')}:00'
                        : date;
                    } : null,
                  ),
                );
              }),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('رجوع')),
          FilledButton(
            onPressed: () {
              try {
                final values = <String, dynamic>{...?source};
                values['doctype'] ??= meta['name']?.toString();
                for (final field in fields) {
                  final key = field['fieldname'].toString();
                  final type = field['fieldtype']?.toString() ?? '';
                  if (type == 'Table' || type == 'Table MultiSelect') {
                    values[key] = tableValues[key] ?? <Map<String, dynamic>>[];
                    continue;
                  }
                  if (type == 'Check') {
                    values[key] = checks[key] == true ? 1 : 0;
                    continue;
                  }
                  if (type == 'Select') {
                    final selected = selections[key]?.trim() ?? '';
                    if (field['reqd'] == 1 && selected.isEmpty) {
                      throw FormatException('الحقل ${field['label'] ?? key} مطلوب.');
                    }
                    if (selected.isNotEmpty) values[key] = selected;
                    else if (source != null && source.containsKey(key)) values[key] = null;
                    continue;
                  }
                  final raw = controllers[key]!.text.trim();
                  if (field['reqd'] == 1 && raw.isEmpty) {
                    throw FormatException('الحقل ${field['label'] ?? key} مطلوب.');
                  }
                  if (raw.isEmpty) {
                    if (source != null && source.containsKey(key)) values[key] = null;
                    continue;
                  }
                  if (type == 'Int') {
                    values[key] = int.tryParse(raw) ??
                      (throw FormatException('قيمة ${field['label'] ?? key} يجب أن تكون عدداً صحيحاً.'));
                  } else if (const {'Float','Currency','Percent'}.contains(type)) {
                    final number = double.tryParse(raw);
                    if (number == null || !number.isFinite) {
                      throw FormatException('قيمة ${field['label'] ?? key} غير رقمية.');
                    }
                    values[key] = number;
                  } else {
                    values[key] = raw;
                  }
                }
                Navigator.pop(dialogContext, values);
              } catch (e) {
                refresh(() => error = e.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('حفظ الصف'),
          ),
        ],
      )),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }


  bool _evaluateSimpleDocDependency(String? expression, Map<String, dynamic> values) {
    var rule = expression?.trim() ?? '';
    if (rule.isEmpty) return true;
    if (rule.startsWith('eval:')) rule = rule.substring(5).trim();

    final orParts = rule.split('||');
    if (orParts.length > 1) {
      return orParts.any((part) => _evaluateSimpleDocDependency(part, values));
    }
    final andParts = rule.split('&&');
    if (andParts.length > 1) {
      return andParts.every((part) => _evaluateSimpleDocDependency(part, values));
    }

    String? comparisonOperator;
    var comparisonOperatorIndex = -1;
    for (final candidate in const ['===', '!==', '==', '!=']) {
      final index = rule.indexOf(candidate);
      if (index >= 0) {
        comparisonOperator = candidate;
        comparisonOperatorIndex = index;
        break;
      }
    }
    if (comparisonOperator != null) {
      var field = rule.substring(0, comparisonOperatorIndex).trim();
      if (field.startsWith('doc.')) field = field.substring(4);
      var expected = rule.substring(comparisonOperatorIndex + comparisonOperator.length).trim();
      if (expected.length >= 2 &&
          ((expected.startsWith("'") && expected.endsWith("'")) ||
           (expected.startsWith('"') && expected.endsWith('"')))) {
        expected = expected.substring(1, expected.length - 1);
      }
      final equal = values[field]?.toString() == expected;
      return comparisonOperator.startsWith('!') ? !equal : equal;
    }

    var negate = false;
    if (rule.startsWith('!')) {
      negate = true;
      rule = rule.substring(1).trim();
    }
    if (rule.startsWith('doc.')) rule = rule.substring(4);
    if (rule.contains(' ')) return true;
    final value = values[rule];
    final truthy = value != null && value != false && value != 0 &&
        value.toString().isNotEmpty && value.toString() != '0';
    return negate ? !truthy : truthy;
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
    final checks = <String, bool>{};
    final selections = <String, String?>{};
    final tableValues = <String, List<Map<String, dynamic>>>{};
    for (final f in editable) {
      final key = f['fieldname'].toString();
      final type = f['fieldtype']?.toString() ?? '';
      final initial = source?[key] ?? f['default'];
      if (type == 'Table' || type == 'Table MultiSelect') {
        tableValues[key] = initial is List
          ? initial.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
          : <Map<String, dynamic>>[];
      } else if (type == 'Check') {
        checks[key] = initial == 1 || initial == true || initial?.toString() == '1';
      } else if (type == 'Select') {
        selections[key] = initial?.toString();
      } else {
        controllers[key] = TextEditingController(text: initial?.toString() ?? '');
      }
    }
    void clearDependentDynamicLinks(String targetField) {
      for (final dynamicField in editable.where((field) =>
          field['fieldtype'] == 'Dynamic Link' && field['options']?.toString() == targetField)) {
        final dynamicKey = dynamicField['fieldname']?.toString();
        if (dynamicKey != null) controllers[dynamicKey]?.clear();
      }
    }


    Map<String, dynamic> dependencyValues() {
      final values = <String, dynamic>{...?source};
      for (final field in editable) {
        final key = field['fieldname'].toString();
        final type = field['fieldtype']?.toString() ?? '';
        if (type == 'Check') values[key] = checks[key] == true ? 1 : 0;
        else if (type == 'Select') values[key] = selections[key];
        else if (type == 'Table' || type == 'Table MultiSelect') values[key] = tableValues[key];
        else values[key] = controllers[key]?.text ?? source?[key];
      }
      return values;
    }
    bool visibleField(Map<String, dynamic> field) {
      final rule = field['depends_on']?.toString() ?? '';
      return rule.trim().isEmpty || _evaluateSimpleDocDependency(rule, dependencyValues());
    }
    bool requiredField(Map<String, dynamic> field) {
      final rule = field['mandatory_depends_on']?.toString() ?? '';
      return field['reqd'] == 1 || (rule.trim().isNotEmpty && _evaluateSimpleDocDependency(rule, dependencyValues()));
    }
    bool readOnlyField(Map<String, dynamic> field) {
      final rule = field['read_only_depends_on']?.toString() ?? '';
      return field['read_only'] == 1 || (rule.trim().isNotEmpty && _evaluateSimpleDocDependency(rule, dependencyValues()));
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
              if (visibleField(f))
              Builder(builder: (context) {
                final key = f['fieldname'].toString();
                final type = f['fieldtype']?.toString() ?? '';
                final label = f['label']?.toString() ?? key;
                final requiredNow = requiredField(f);
                final readOnlyNow = readOnlyField(f);
                final options = (f['options']?.toString() ?? '').split('\n').where((v) => v.trim().isNotEmpty).toList();
                if (type == 'Table' || type == 'Table MultiSelect') {
                  final count = tableValues[key]?.length ?? 0;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.table_rows_outlined),
                      title: Text(label),
                      subtitle: Text('${count} صف'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: saving || readOnlyNow ? null : () async {
                        final updated = await _editChildTable(f, tableValues[key] ?? <Map<String, dynamic>>[]);
                        if (updated != null) refresh(() => tableValues[key] = updated);
                      },
                    ),
                  );
                }
                if (type == 'Check') {
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    value: checks[key] ?? false,
                    onChanged: saving || readOnlyNow ? null : (value) => refresh(() => checks[key] = value ?? false),
                  );
                }
                if (type == 'Select' && options.isNotEmpty) {
                  final current = selections[key];
                  final items = <String>{...options, if (current != null && current.isNotEmpty) current}.toList();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: current != null && current.isNotEmpty ? current : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: label),
                      items: items.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: saving || readOnlyNow ? null : (value) {
                      clearDependentDynamicLinks(key);
                      refresh(() => selections[key] = value);
                    },
                    ),
                  );
                }
                final controller = controllers[key]!;
                final isDate = type == 'Date';
                final isDateTime = type == 'Datetime';
                final isLink = type == 'Link' && (f['options']?.toString().trim().isNotEmpty ?? false);
                final dynamicLinkField = f['options']?.toString() ?? '';
                final dynamicLinkTarget = selections[dynamicLinkField] ??
                    controllers[dynamicLinkField]?.text ??
                    source?[dynamicLinkField]?.toString() ?? '';
                final isDynamicLink = type == 'Dynamic Link';
                final canPickLink = isLink || (isDynamicLink && dynamicLinkTarget.trim().isNotEmpty);
                final keyboard = const {'Int','Float','Currency','Percent'}.contains(type)
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : type == 'Email' ? TextInputType.emailAddress
                    : type == 'Phone' ? TextInputType.phone : TextInputType.text;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controller,
                    onChanged: (_) {
                      final hasDynamicDependents = editable.any((field) =>
                        field['fieldtype'] == 'Dynamic Link' && field['options']?.toString() == key);
                      if (hasDynamicDependents) clearDependentDynamicLinks(key);
                      refresh(() {});
                    },
                    keyboardType: keyboard,
                    readOnly: isDate || isDateTime || readOnlyNow,
                    minLines: (type == 'Text' || type == 'Long Text') ? 3 : 1,
                    maxLines: (type == 'Text' || type == 'Long Text') ? 5 : 1,
                    onTap: (isDate || isDateTime) && !readOnlyNow ? () async {
                      final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
                      final date = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (date == null) return;
                      var chosen = DateTime(date.year, date.month, date.day, initial.hour, initial.minute);
                      if (isDateTime) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
                        );
                        if (time == null) return;
                        chosen = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      }
                      final formattedDate = '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
                      controller.text = isDateTime
                        ? '${formattedDate} ${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')}:00'
                        : formattedDate;
                      refresh(() {});
                    } : null,
                    decoration: InputDecoration(
                      labelText: label,
                      helperText: canPickLink ? 'اختر سجلاً موجوداً في ERPNext' : isDynamicLink ? 'حدد نوع المرجع أولاً' : requiredNow ? 'حقل إلزامي' : null,
                      suffixIcon: isDate
                        ? const Icon(Icons.calendar_today_outlined)
                        : canPickLink ? IconButton(
                            tooltip: 'اختيار سجل',
                            onPressed: readOnlyNow ? null : () async {
                              final target = isLink ? f['options'].toString() : dynamicLinkTarget.trim();
                              final selected = await _pickLinkValue(target);
                              if (selected != null) { controller.text = selected; refresh(() {}); }
                            },
                            icon: const Icon(Icons.search),
                          ) : null,
                    ),
                  ),
                );
              }),
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
                  if (!visibleField(f) || readOnlyField(f)) continue;
                  final requiredNow = requiredField(f);
                  if (type == 'Table' || type == 'Table MultiSelect') {
                    if (requiredNow && (tableValues[key]?.isEmpty ?? true)) {
                      throw FormatException('الحقل ' + (f['label']?.toString() ?? key) + ' مطلوب.');
                    }
                    values[key] = tableValues[key] ?? <Map<String, dynamic>>[];
                    continue;
                  }
                  if (type == 'Check') {
                    final checked = checks[key] == true;
                    if (requiredNow && !checked) {
                      throw FormatException('الحقل ' + (f['label']?.toString() ?? key) + ' مطلوب.');
                    }
                    values[key] = checked ? 1 : 0;
                    continue;
                  }
                  if (type == 'Select') {
                    final selected = selections[key]?.trim() ?? '';
                    if (requiredNow && selected.isEmpty) {
                      throw FormatException('الحقل ' + (f['label']?.toString() ?? key) + ' مطلوب.');
                    }
                    if (selected.isNotEmpty) values[key] = selected;
                    else if (source != null && source.containsKey(key)) values[key] = null;
                    continue;
                  }
                  final raw = controllers[key]!.text.trim();
                  if (requiredNow && raw.isEmpty) throw FormatException('الحقل ' + (f['label']?.toString() ?? key) + ' مطلوب.');
                  if (raw.isEmpty) {
                    if (source != null && source.containsKey(key)) values[key] = null;
                    continue;
                  }
                  if (type == 'Int') {
                    values[key] = int.tryParse(raw) ?? (throw FormatException('قيمة ' + key + ' يجب أن تكون عدداً صحيحاً.'));
                  } else if (const {'Float','Currency','Percent'}.contains(type)) {
                    final number = double.tryParse(raw);
                    if (number == null || !number.isFinite) throw FormatException('قيمة ' + key + ' غير رقمية.');
                    values[key] = number;
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


  Future<void> _showActivity(String name) async {
    final commentController = TextEditingController();
    Map<String, List<Map<String, dynamic>>> activity = {
      'attachments': <Map<String, dynamic>>[],
      'comments': <Map<String, dynamic>>[],
      'versions': <Map<String, dynamic>>[],
    };
    var loading = true;
    var busy = false;
    var started = false;
    BuildContext? activityContext;
    String? error;

    Future<void> load(StateSetter refresh) async {
      refresh(() { loading = true; error = null; });
      try {
        final result = await widget.api.fetchDocTypeActivity(doctype: _doctype, name: name);
        if (!mounted || activityContext?.mounted != true) return;
        refresh(() { activity = result; loading = false; });
      } catch (e) {
        if (!mounted || activityContext?.mounted != true) return;
        refresh(() { error = e.toString().replaceFirst('Exception: ', ''); loading = false; });
      }
    }

    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (sheet) => StatefulBuilder(builder: (context, refresh) {
        activityContext = sheet;
        if (!started) {
          started = true;
          WidgetsBinding.instance.addPostFrameCallback((_) { if (sheet.mounted) load(refresh); });
        }
        Future<void> addComment() async {
          final value = commentController.text.trim();
          if (value.isEmpty || busy) return;
          refresh(() { busy = true; error = null; });
          try {
            await widget.api.addDocTypeComment(doctype: _doctype, name: name, content: value);
            commentController.clear();
            await load(refresh);
          } catch (e) {
            refresh(() => error = e.toString().replaceFirst('Exception: ', ''));
          } finally {
            if (sheet.mounted) refresh(() => busy = false);
          }
        }
        Future<void> uploadAttachment() async {
          if (busy) return;
          try {
            final picked = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false, withData: true);
            if (picked == null || picked.files.isEmpty) return;
            final file = picked.files.single;
            final bytes = file.bytes;
            if (bytes == null || bytes.isEmpty) throw const FormatException('تعذر قراءة محتوى الملف المحدد.');
            refresh(() { busy = true; error = null; });
            await widget.api.uploadDocTypeAttachment(
              doctype: _doctype, name: name, fileName: file.name, bytes: bytes,
            );
            await load(refresh);
          } catch (e) {
            if (sheet.mounted) refresh(() => error = e.toString().replaceFirst('Exception: ', ''));
          } finally {
            if (sheet.mounted) refresh(() => busy = false);
          }
        }

        final attachments = activity['attachments'] ?? const <Map<String, dynamic>>[];
        final comments = activity['comments'] ?? const <Map<String, dynamic>>[];
        final versions = activity['versions'] ?? const <Map<String, dynamic>>[];
        return SizedBox(
          height: MediaQuery.of(sheet).size.height * .86,
          child: Column(children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('المرفقات وسجل النشاط', style: Theme.of(context).textTheme.titleLarge),
                  Text('$_doctype • $name', style: Theme.of(context).textTheme.labelSmall),
                ])),
                IconButton(tooltip: 'تحديث النشاط', onPressed: loading || busy ? null : () => load(refresh), icon: const Icon(Icons.refresh)),
              ]),
            ),
            if (error != null) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MaterialBanner(content: Text(error!), actions: [
                TextButton(onPressed: () => load(refresh), child: const Text('إعادة المحاولة')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: commentController, minLines: 1, maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'إضافة تعليق إلى سجل المستند',
                  suffixIcon: IconButton(tooltip: 'إرسال التعليق', onPressed: busy ? null : addComment, icon: const Icon(Icons.send)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : uploadAttachment,
                  icon: const Icon(Icons.attach_file), label: const Text('إرفاق ملف'),
                ),
              ),
            ),
            if (loading || busy) const LinearProgressIndicator(),
            Expanded(child: ListView(children: [
              ExpansionTile(
                initiallyExpanded: true,
                leading: const Icon(Icons.attach_file),
                title: Text('المرفقات (${attachments.length})'),
                children: attachments.isEmpty
                  ? const [ListTile(title: Text('لا توجد مرفقات لهذا المستند.'))]
                  : attachments.map((file) => ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(file['file_name']?.toString() ?? file['name']?.toString() ?? 'ملف'),
                      subtitle: Text([
                        if (file['creation'] != null) file['creation'].toString(),
                        if (file['file_size'] != null) '${file['file_size']} بايت',
                        file['is_private'] == 1 || file['is_private'] == true ? 'خاص' : 'عام',
                      ].join(' • ')),
                    )).toList(),
              ),
              ExpansionTile(
                initiallyExpanded: true,
                leading: const Icon(Icons.forum_outlined),
                title: Text('التعليقات (${comments.length})'),
                children: comments.isEmpty
                  ? const [ListTile(title: Text('لا توجد تعليقات.'))]
                  : comments.map((comment) => ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(comment['comment_by']?.toString() ?? comment['comment_email']?.toString() ?? 'مستخدم'),
                      subtitle: Text(comment['content']?.toString() ?? ''),
                      trailing: comment['creation'] == null ? null : Text(comment['creation'].toString(), style: Theme.of(context).textTheme.labelSmall),
                    )).toList(),
              ),
              ExpansionTile(
                leading: const Icon(Icons.history),
                title: Text('سجل الإصدارات (${versions.length})'),
                children: versions.isEmpty
                  ? const [ListTile(title: Text('لا توجد إصدارات محفوظة لهذا المستند.'))]
                  : versions.map((version) => ListTile(
                      leading: const Icon(Icons.history_toggle_off),
                      title: Text(version['owner']?.toString() ?? 'تعديل'),
                      subtitle: Text(version['creation']?.toString() ?? ''),
                      isThreeLine: true,
                      trailing: const Icon(Icons.info_outline),
                      onTap: () {
                        final data = version['data']?.toString() ?? '';
                        showDialog<void>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                            title: const Text('تفاصيل الإصدار'),
                            content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(data))),
                            actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إغلاق'))],
                          ),
                        );
                      },
                    )).toList(),
              ),
            ])),
          ]),
        );
      }),
    );
    commentController.dispose();
  }

  Future<void> _details(String name) async {
    try {
      final doc = await widget.api.fetchDocTypeDocument(doctype: _doctype, name: name);
      if (!mounted) return;
      final fields = _fields.where((f) => f['fieldname'] is String && doc.containsKey(f['fieldname'])).toList();
      final childMeta = <String, Map<String, dynamic>>{};
      for (final field in fields.where((f) => f['fieldtype'] == 'Table' || f['fieldtype'] == 'Table MultiSelect')) {
        final childDoctype = field['options']?.toString().trim() ?? '';
        if (childDoctype.isEmpty || childMeta.containsKey(childDoctype)) continue;
        try {
          childMeta[childDoctype] = await widget.api.fetchDocTypeMeta(childDoctype);
        } catch (_) {
          // Keep raw child-row fields visible if child metadata is not readable.
        }
      }
      final transitions = await widget.api.fetchDocTypeWorkflowTransitions(doctype: _doctype, name: name).catchError((_) => <Map<String, dynamic>>[]);
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
              IconButton(
                tooltip: 'فتح المستند في ERPNext Web',
                onPressed: () {
                  Navigator.pop(sheet);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => WorkspaceWebPage(
                      api: widget.api,
                      title: '${widget.definition.label} • $name',
                      linkType: 'DocTypeDocument',
                      target: '$_doctype|$name',
                    ),
                  ));
                },
                icon: const Icon(Icons.open_in_browser),
              ),
              IconButton(
                tooltip: 'المرفقات وسجل النشاط',
                onPressed: () { Navigator.pop(sheet); _showActivity(name); },
                icon: const Icon(Icons.history),
              ),
            ])),
            Expanded(child: ListView.separated(
              itemCount: fields.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final f = fields[i], key = f['fieldname'].toString(), value = doc[key];
                final label = f['label']?.toString() ?? key;
                if (value is List) {
                  final childDoctype = f['options']?.toString() ?? '';
                  final childFields = (childMeta[childDoctype]?['fields'] as List? ?? const [])
                      .whereType<Map<String, dynamic>>()
                      .where((childField) => childField['fieldname'] is String &&
                        childField['fieldtype'] != 'Section Break' &&
                        childField['fieldtype'] != 'Column Break' &&
                        childField['fieldtype'] != 'Tab Break' &&
                        childField['hidden'] != 1)
                      .toList();
                  return ExpansionTile(
                    title: Text(label),
                    subtitle: Text('${value.length} صف'),
                    leading: const Icon(Icons.table_rows_outlined),
                    children: [
                      for (var rowIndex = 0; rowIndex < value.length; rowIndex++)
                        Card(
                          margin: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
                          child: ExpansionTile(
                            title: Text('السطر ${rowIndex + 1}'),
                            children: [
                              for (final childField in childFields)
                                if (value[rowIndex] is Map &&
                                    (value[rowIndex] as Map).containsKey(childField['fieldname']))
                                  ListTile(
                                    dense: true,
                                    title: Text(childField['label']?.toString() ?? childField['fieldname'].toString()),
                                    subtitle: SelectableText(
                                      (value[rowIndex] as Map)[childField['fieldname']]?.toString() ?? '—',
                                    ),
                                  ),
                              if (childFields.isEmpty && value[rowIndex] is Map)
                                ListTile(
                                  title: SelectableText((value[rowIndex] as Map).toString()),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                }
                if (value is Map) {
                  return ExpansionTile(
                    title: Text(label),
                    subtitle: const Text('تفاصيل مرتبطة'),
                    children: value.entries.map((entry) => ListTile(
                      dense: true,
                      title: Text(entry.key),
                      subtitle: SelectableText(entry.value?.toString() ?? '—'),
                    )).toList(),
                  );
                }
                return ListTile(
                  title: Text(label),
                  subtitle: SelectableText(value?.toString() ?? '—'),
                );
              },
            )),
            Padding(padding: const EdgeInsets.all(12), child: Wrap(
              spacing: 8,
              children: [
                if (status == 0) OutlinedButton.icon(
                  onPressed: () { Navigator.pop(sheet); _edit(source: doc); },
                  icon: const Icon(Icons.edit_outlined), label: const Text('تعديل المسودة'),
                ),
                if (status == 0 && _meta?['is_submittable'] == 1) FilledButton.tonal(
                  onPressed: () async {
                    if (!await _confirmAction('ترحيل المستند', 'سيُرسل المستند إلى ERPNext للتحقق والترحيل وفق الصلاحيات والقواعد. هل تريد المتابعة؟')) return;
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
                      if (!await _confirmAction('تنفيذ إجراء سير العمل', 'هل تريد تنفيذ الإجراء: ' + action + '؟')) return;
                      try {
                        await widget.api.applyDocTypeWorkflowAction(doctype: _doctype, name: name, action: action);
                        if (sheet.mounted) Navigator.pop(sheet);
                        _generation++; await _load();
                      } catch (e) { _notice(e.toString()); }
                    },
                    child: Text(transition['action']?.toString() ?? 'إجراء'),
                  ),
                if (status == 1 && _meta?['is_submittable'] == 1) OutlinedButton(
                  onPressed: () async {
                    if (!await _confirmAction('إلغاء المستند', 'سيطلب التطبيق من ERPNext إلغاء المستند. قد يرفض الخادم الإلغاء إذا كانت هناك مستندات مرتبطة. هل تريد المتابعة؟')) return;
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

  Widget _standardFilterInput(Map<String, dynamic> field) {
    final key = field['fieldname'].toString();
    final label = field['label']?.toString() ?? key;
    final type = field['fieldtype']?.toString() ?? '';
    final controller = _filterControllers[key]!;
    if (type == 'Select') {
      final options = (field['options']?.toString() ?? '').split('\\n')
          .map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
      if (options.isNotEmpty) {
        final current = _filters[key];
        return DropdownButtonFormField<String>(
          key: ValueKey('filter-$key-${current ?? ''}'),
          initialValue: current,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: options.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
          onChanged: (value) {
            if (value == null) {
              _filters.remove(key);
            } else {
              _filters[key] = value;
            }
          },
        );
      }
    }
    if (type == 'Check') {
      final current = _filters[key];
      return DropdownButtonFormField<String>(
        key: ValueKey('filter-$key-${current ?? ''}'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: const [
          DropdownMenuItem(value: '1', child: Text('نعم')),
          DropdownMenuItem(value: '0', child: Text('لا')),
        ],
        onChanged: (value) {
          if (value == null) {
            _filters.remove(key);
          } else {
            _filters[key] = value;
          }
        },
      );
    }
    final isDate = type == 'Date';
    final isDateTime = type == 'Datetime';
    final isLink = type == 'Link' && (field['options']?.toString().trim().isNotEmpty ?? false);
    return TextField(
      controller: controller,
      keyboardType: const {'Int','Float','Currency','Percent'}.contains(type)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      readOnly: isDate || isDateTime,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: isDate || isDateTime
          ? const Icon(Icons.calendar_today_outlined)
          : isLink ? IconButton(
              tooltip: 'اختيار سجل',
              onPressed: () async {
                final selected = await _pickLinkValue(field['options'].toString());
                if (selected != null) {
                  controller.text = selected;
                  _filters[key] = selected;
                }
              },
              icon: const Icon(Icons.search),
            ) : null,
      ),
      onChanged: (value) => _filters[key] = value,
      onTap: isDate || isDateTime ? () async {
        final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1900),
          lastDate: DateTime(2200),
        );
        if (picked != null) {
          var chosen = DateTime(picked.year, picked.month, picked.day, initial.hour, initial.minute);
          if (isDateTime) {
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
            );
            if (time == null) return;
            chosen = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
          }
          final date = '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
          controller.text = isDateTime
            ? '${date} ${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')}:00'
            : date;
          _filters[key] = controller.text;
        }
      } : null,
    );
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
          IconButton(
            tooltip: 'فتح قائمة ERPNext الأصلية',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => WorkspaceWebPage(
                api: widget.api,
                title: widget.definition.label,
                linkType: 'DocTypeList',
                target: _doctype,
              ),
            )),
            icon: const Icon(Icons.open_in_browser),
          ),
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
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
          child: Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _sortField,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ترتيب حسب', isDense: true),
              items: <String>{'modified', 'name', ..._fields
                .where((field) => field['fieldname'] is String &&
                  !const {'Table','Table MultiSelect','Section Break','Column Break','Tab Break','HTML','Button'}.contains(field['fieldtype']))
                .map((field) => field['fieldname'].toString())}.map((key) {
                  final matches = _fields.where((f) => f['fieldname'] == key).toList();
                  final label = matches.isEmpty
                    ? (key == 'modified' ? 'آخر تعديل' : key)
                    : (matches.first['label']?.toString() ?? key);
                  return DropdownMenuItem(value: key, child: Text(label, overflow: TextOverflow.ellipsis));
                }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() { _sortField = value; _generation++; });
                _load();
              },
            )),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: _sortDescending ? 'ترتيب تنازلي' : 'ترتيب تصاعدي',
              onPressed: _loading ? null : () {
                setState(() { _sortDescending = !_sortDescending; _generation++; });
                _load();
              },
              icon: Icon(_sortDescending ? Icons.south : Icons.north),
            ),
          ]),
        ),
        if (_filterFields.isNotEmpty)
          ExpansionTile(
            title: const Text('فلاتر الشاشة الأصلية'),
            leading: const Icon(Icons.filter_alt_outlined),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  for (final field in _filterFields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        SizedBox(
                          width: 112,
                          child: DropdownButtonFormField<String>(
                            initialValue: _filterOperators[field['fieldname'].toString()] ??
                              ((field['fieldtype'] == 'Data' || field['fieldtype'] == 'Small Text') ? 'like' : '='),
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'المعامل', isDense: true),
                            items: _filterOperatorsFor(field).map((value) => DropdownMenuItem(
                              value: value, child: Text(value, overflow: TextOverflow.ellipsis),
                            )).toList(),
                            onChanged: (value) {
                              if (value != null) _filterOperators[field['fieldname'].toString()] = value;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _standardFilterInput(field)),
                      ]),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(spacing: 8, children: [
                      TextButton.icon(
                        onPressed: _loading ? null : () {
                          _filters.clear();
                          _filterOperators.clear();
                          for (final controller in _filterControllers.values) {
                            controller.clear();
                          }
                          _generation++;
                          _load();
                        },
                        icon: const Icon(Icons.clear_all), label: const Text('مسح الفلاتر'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _loading ? null : () { _generation++; _load(); },
                        icon: const Icon(Icons.filter_alt), label: const Text('تطبيق الفلاتر'),
                      ),
                    ]),
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
                  .take(3).map((f) => _fieldLabel(f) + ': ' + row[f].toString()).join(' • ');
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
