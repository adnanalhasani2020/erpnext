import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class WorkspaceReportPage extends StatefulWidget {
  const WorkspaceReportPage({
    super.key,
    required this.api,
    required this.reportName,
    required this.companies,
    this.initialFilters = const {},
  });

  final FrappeApi api;
  final String reportName;
  final List<ErpCompany> companies;
  final Map<String, dynamic> initialFilters;

  @override
  State<WorkspaceReportPage> createState() => _WorkspaceReportPageState();
}

class _WorkspaceReportPageState extends State<WorkspaceReportPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _values = {};
  List<Map<String, dynamic>> _filters = const [];
  List<dynamic> _columns = const [];
  List<Map<String, dynamic>> _rows = const [];
  bool _loadingDefinition = true;
  bool _running = false;
  bool _linkSearchLoading = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadDefinition();
  }

  @override
  void dispose() {
    _generation++;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDefinition() async {
    final generation = ++_generation;
    setState(() {
      _loadingDefinition = true;
      _error = null;
    });
    try {
      final definition = await widget.api.fetchWorkspaceReportDefinition(
        reportName: widget.reportName,
      );
      if (!mounted || generation != _generation) return;
      final filters = (definition['filters'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      for (final filter in filters) {
        final fieldname = filter['fieldname']?.toString().trim() ?? '';
        if (fieldname.isEmpty) continue;
        final type = filter['fieldtype']?.toString() ?? 'Data';
        var initial = widget.initialFilters[fieldname] ?? filter['default'];
        if (initial is String &&
            (initial.startsWith('frappe.') || initial.startsWith('eval:') ||
             initial.contains('function('))) {
          initial = null;
        }
        if ((initial == null || initial.toString().isEmpty) &&
            fieldname == 'company' && widget.companies.isNotEmpty) {
          initial = widget.companies.first.name;
        }
        if (type == 'Check') {
          _values[fieldname] = initial == 1 || initial == true ||
              initial?.toString() == '1';
        } else {
          final text = initial?.toString() ?? '';
          _values[fieldname] = text;
          _controllers[fieldname] = TextEditingController(text: text);
        }
      }
      setState(() {
        _filters = filters;
        _loadingDefinition = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loadingDefinition = false;
      });
    }
  }

  bool _evaluateFilterDependency(String? expression) {
    var rule = expression?.trim() ?? '';
    if (rule.isEmpty) return true;
    if (rule.startsWith('eval:')) rule = rule.substring(5).trim();
    final orParts = rule.split('||');
    if (orParts.length > 1) {
      return orParts.any(_evaluateFilterDependency);
    }
    final andParts = rule.split('&&');
    if (andParts.length > 1) {
      return andParts.every(_evaluateFilterDependency);
    }
    String? comparisonOperator;
    var operatorIndex = -1;
    for (final candidate in const ['===', '!==', '==', '!=']) {
      final index = rule.indexOf(candidate);
      if (index >= 0) {
        comparisonOperator = candidate;
        operatorIndex = index;
        break;
      }
    }
    if (comparisonOperator != null) {
      var field = rule.substring(0, operatorIndex).trim();
      if (field.startsWith('doc.')) field = field.substring(4);
      var expected = rule.substring(operatorIndex + comparisonOperator.length).trim();
      if (expected.length >= 2 &&
          ((expected.startsWith("'") && expected.endsWith("'")) ||
           (expected.startsWith('"') && expected.endsWith('"')))) {
        expected = expected.substring(1, expected.length - 1);
      }
      final equal = _values[field]?.toString() == expected;
      return comparisonOperator.startsWith('!') ? !equal : equal;
    }
    var negate = false;
    if (rule.startsWith('!')) {
      negate = true;
      rule = rule.substring(1).trim();
    }
    if (rule.startsWith('doc.')) rule = rule.substring(4);
    if (rule.contains(' ')) return true;
    final value = _values[rule];
    final truthy = value != null && value != false && value != 0 &&
        value.toString().isNotEmpty && value.toString() != '0';
    return negate ? !truthy : truthy;
  }

  bool _isFilterVisible(Map<String, dynamic> filter) =>
      _evaluateFilterDependency(filter['depends_on']?.toString());

  List<String> _options(Map<String, dynamic> filter) {
    final raw = filter['options'];
    if (raw is List) {
      return raw.map((value) => value.toString()).where((value) => value.isNotEmpty).toList();
    }
    if (raw is String) {
      return raw.split('\n').map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
    }
    return const [];
  }

  String _fieldname(Map<String, dynamic> filter) =>
      filter['fieldname']?.toString() ?? '';

  String _label(Map<String, dynamic> filter) =>
      filter['label']?.toString() ?? _fieldname(filter);

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(String fieldname, {bool dateTime = false}) async {
    final current = DateTime.tryParse(_controllers[fieldname]?.text ?? '') ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date == null || !mounted) return;
    var value = _dateText(date);
    if (dateTime) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
      );
      if (time == null || !mounted) return;
      value += ' ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
    }
    _controllers[fieldname]?.text = value;
    setState(() => _values[fieldname] = value);
  }

  Future<String?> _pickLinkValue(String target) async {
    if (target.trim().isEmpty) return null;
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
        final fields = (meta['fields'] as List? ?? const [])
            .whereType<Map<String, dynamic>>();
        displayFields = fields.where((field) =>
          field['fieldname'] is String &&
          (field['in_list_view'] == 1 || field['reqd'] == 1))
          .map((field) => field['fieldname'].toString())
          .where((field) => field != 'name').take(4).toList();
        rows = await widget.api.fetchDocTypeRows(
          doctype: target,
          fields: displayFields,
          search: query.text.trim(),
          searchFields: displayFields,
        );
      } catch (exception) {
        error = exception.toString().replaceFirst('Exception: ', '');
      }
      if (dialogOpen && mounted) refresh(() => loading = false);
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text('اختيار سجل من $target'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(refresh),
                  decoration: InputDecoration(
                    labelText: 'ابحث في $target',
                    suffixIcon: IconButton(
                      onPressed: loading ? null : () => search(refresh),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                if (loading) const LinearProgressIndicator(),
                if (error != null) Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(error!),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final name = row['name']?.toString() ?? '';
                      final subtitle = displayFields
                          .where((field) => row[field] != null)
                          .map((field) => row[field].toString())
                          .join(' • ');
                      return ListTile(
                        title: Text(name),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        onTap: name.isEmpty ? null : () {
                          dialogOpen = false;
                          Navigator.pop(dialogContext, name);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                dialogOpen = false;
                Navigator.pop(dialogContext);
              },
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
    dialogOpen = false;
    query.dispose();
    return selected;
  }

  Widget _buildFilter(Map<String, dynamic> filter) {
    final fieldname = _fieldname(filter);
    if (fieldname.isEmpty) return const SizedBox.shrink();
    final label = _label(filter);
    final type = filter['fieldtype']?.toString() ?? 'Data';
    final requiredField = filter['reqd'] == 1 || filter['reqd'] == true;

    if (type == 'Check') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: _values[fieldname] == true,
        onChanged: (value) => setState(() => _values[fieldname] = value ?? false),
      );
    }

    if (type == 'Select' && _options(filter).isNotEmpty) {
      final options = _options(filter);
      final current = _values[fieldname]?.toString();
      return DropdownButtonFormField<String>(
        value: options.contains(current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: options.map((option) => DropdownMenuItem(
          value: option,
          child: Text(option),
        )).toList(),
        validator: requiredField
            ? (value) => value == null || value.isEmpty ? 'هذا الحقل مطلوب' : null
            : null,
        onChanged: (value) => setState(() => _values[fieldname] = value ?? ''),
      );
    }

    if (type == 'Date' || type == 'Datetime') {
      return TextFormField(
        controller: _controllers[fieldname],
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        validator: requiredField
            ? (value) => value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null
            : null,
        onTap: () => _pickDate(fieldname, dateTime: type == 'Datetime'),
      );
    }

    final isLink = type == 'Link' || type == 'Dynamic Link';
    final linkTarget = type == 'Dynamic Link'
        ? (_values[filter['options']?.toString()]?.toString() ?? '')
        : (filter['options']?.toString() ?? '');
    return TextFormField(
      controller: _controllers[fieldname],
      keyboardType: const {
        'Int', 'Float', 'Currency', 'Percent', 'Rating'
      }.contains(type) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: isLink && linkTarget.isEmpty
            ? 'حدد نوع المرجع أولاً'
            : isLink ? linkTarget : null,
        suffixIcon: isLink ? IconButton(
          tooltip: 'اختيار سجل',
          onPressed: _linkSearchLoading || linkTarget.isEmpty ? null : () async {
            setState(() => _linkSearchLoading = true);
            try {
              final selected = await _pickLinkValue(linkTarget);
              if (selected != null && mounted) {
                _controllers[fieldname]?.text = selected;
                setState(() => _values[fieldname] = selected);
              }
            } finally {
              if (mounted) setState(() => _linkSearchLoading = false);
            }
          },
          icon: _linkSearchLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search),
        ) : null,
      ),
      validator: requiredField
          ? (value) => value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null
          : null,
      onChanged: (value) => setState(() => _values[fieldname] = value),
    );
  }

  dynamic _normalizedFilterValue(Map<String, dynamic> filter) {
    final fieldname = _fieldname(filter);
    final type = filter['fieldtype']?.toString() ?? '';
    final value = _values[fieldname];
    if (type == 'Check') return value == true ? 1 : 0;
    if (value == null || value.toString().trim().isEmpty) return null;
    if (type == 'Int') return int.tryParse(value.toString());
    if (const {'Float', 'Currency', 'Percent', 'Rating'}.contains(type)) {
      return num.tryParse(value.toString());
    }
    return value.toString().trim();
  }

  Future<void> _runReport() async {
    if (_filters.isNotEmpty && !(_formKey.currentState?.validate() ?? false)) return;
    for (final filter in _filters.where(_isFilterVisible)) {
      final fieldname = _fieldname(filter);
      final requiredField = filter['reqd'] == 1 || filter['reqd'] == true;
      if (requiredField && filter['fieldtype']?.toString() == 'Check' &&
          _values[fieldname] != true) {
        setState(() => _error = 'الحقل ${_label(filter)} مطلوب.');
        return;
      }
    }
    final generation = ++_generation;
    final filters = <String, dynamic>{};
    for (final filter in _filters.where(_isFilterVisible)) {
      final fieldname = _fieldname(filter);
      if (fieldname.isEmpty) continue;
      final value = _normalizedFilterValue(filter);
      if (value != null) filters[fieldname] = value;
    }
    setState(() {
      _running = true;
      _error = null;
      _rows = const [];
      _columns = const [];
    });
    try {
      final result = await widget.api.runStandardReport(
        reportName: widget.reportName,
        filters: filters,
      );
      if (!mounted || generation != _generation) return;
      final columns = result['columns'] as List? ?? const [];
      final rawRows = result['result'] as List? ?? const [];
      final rows = <Map<String, dynamic>>[];
      for (final raw in rawRows) {
        if (raw is Map) {
          rows.add(Map<String, dynamic>.from(raw));
        } else if (raw is List) {
          final row = <String, dynamic>{};
          for (var index = 0; index < columns.length && index < raw.length; index++) {
            final column = columns[index];
            final key = column is Map
                ? (column['fieldname'] ?? column['label'] ?? 'column_$index').toString()
                : column.toString();
            row[key] = raw[index];
          }
          rows.add(row);
        }
      }
      setState(() {
        _columns = columns;
        _rows = rows;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && generation == _generation) setState(() => _running = false);
    }
  }

  String _columnKey(dynamic column, int index) {
    if (column is Map) {
      return (column['fieldname'] ?? column['label'] ?? 'column_$index').toString();
    }
    return column.toString();
  }

  String _columnLabel(dynamic column, int index) {
    if (column is Map) {
      return (column['label'] ?? column['fieldname'] ?? 'عمود ${index + 1}').toString();
    }
    return column.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reportName),
        actions: [
          IconButton(
            tooltip: 'تحديث تعريف التقرير',
            onPressed: _loadingDefinition || _running ? null : _loadDefinition,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingDefinition
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: const Text('تعذر تحميل التقرير'),
                      subtitle: Text(_error!),
                    ),
                  ),
                if (_filters.isNotEmpty)
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        for (final filter in _filters.where(_isFilterVisible)) _buildFilter(filter),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _running ? null : _runReport,
                          icon: _running
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow),
                          label: const Text('تشغيل التقرير'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('لا توجد فلاتر معرفة لهذا التقرير'),
                      subtitle: Text('يمكن تشغيل التقرير مباشرة وفق إعدادات ERPNext وصلاحيات المستخدم.'),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _running ? null : _runReport,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('تشغيل التقرير'),
                  ),
                ],
                if (_running) const LinearProgressIndicator(),
                if (_rows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('النتائج: ${_rows.length}', style: Theme.of(context).textTheme.titleMedium),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        for (var index = 0; index < _columns.length; index++)
                          DataColumn(label: Text(_columnLabel(_columns[index], index))),
                      ],
                      rows: [
                        for (final row in _rows)
                          DataRow(cells: [
                            for (var index = 0; index < _columns.length; index++)
                              DataCell(ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Text(
                                  row[_columnKey(_columns[index], index)]?.toString() ?? '',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )),
                          ]),
                    ),
                  ),
                ] else if (!_running && _columns.isNotEmpty)
                  const Card(child: ListTile(title: Text('لا توجد نتائج مطابقة للفلاتر.'))),
              ],
            ),
    );
  }
}
