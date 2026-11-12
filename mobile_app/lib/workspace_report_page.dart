import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class WorkspaceReportPage extends StatefulWidget {
  const WorkspaceReportPage({
    super.key,
    required this.api,
    required this.reportName,
    required this.companies,
  });

  final FrappeApi api;
  final String reportName;
  final List<ErpCompany> companies;

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
        var initial = filter['default'];
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

    return TextFormField(
      controller: _controllers[fieldname],
      keyboardType: const {
        'Int', 'Float', 'Currency', 'Percent', 'Rating'
      }.contains(type) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: filter['options']?.toString().isNotEmpty == true &&
                (type == 'Link' || type == 'Dynamic Link')
            ? filter['options'].toString()
            : null,
      ),
      validator: requiredField
          ? (value) => value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null
          : null,
      onChanged: (value) => _values[fieldname] = value,
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final generation = ++_generation;
    final filters = <String, dynamic>{};
    for (final filter in _filters) {
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
                        for (final filter in _filters) _buildFilter(filter),
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
