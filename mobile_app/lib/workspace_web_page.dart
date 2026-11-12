import 'dart:convert';
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'doctype_workspace_editor_page.dart';
import 'doctype_workspace_model.dart';
import 'models/erp_models.dart';
import 'workspace_report_page.dart';

/// Native Flutter destination for ERPNext Desk links.
/// ERPNext Web is consulted for metadata and server-side business rules only.
class WorkspaceWebPage extends StatefulWidget {
  const WorkspaceWebPage({super.key, required this.api, required this.title, required this.linkType, required this.target, this.routeOptions = const {}});
  final FrappeApi api;
  final String title;
  final String linkType;
  final String target;
  final Map<String, dynamic> routeOptions;

  @override
  State<WorkspaceWebPage> createState() => _WorkspaceWebPageState();
}

class _WorkspaceWebPageState extends State<WorkspaceWebPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _workspace;
  Map<String, dynamic>? _record;
  Map<String, dynamic>? _meta;
  List<Map<String, dynamic>> _numberCards = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _parseRouteOptions(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try { final decoded = jsonDecode(raw); if (decoded is Map) return Map<String, dynamic>.from(decoded); } catch (_) {}
    }
    return const {};
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.linkType == 'Workspace') {
        final rows = await widget.api.fetchWorkspaceDirectory();
        final matches = rows.where((row) => row['name']?.toString() == widget.target);
        if (matches.isEmpty) throw Exception('مساحة العمل غير متاحة أو لا تملك صلاحية عرضها.');
        final workspace = Map<String, dynamic>.from(matches.first);
        final raw = workspace['number_cards'];
        final cards = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
        if (!mounted) return;
        setState(() { _workspace = workspace; _numberCards = cards; _loading = false; });
        return;
      }
      if (widget.linkType == 'DocTypeDocument') {
        final split = widget.target.indexOf('|');
        if (split <= 0 || split == widget.target.length - 1) throw const FormatException('مرجع المستند غير صالح.');
        final doctype = widget.target.substring(0, split);
        final name = widget.target.substring(split + 1);
        final doc = await widget.api.fetchDocTypeDocument(doctype: doctype, name: name);
        final meta = await widget.api.fetchDocTypeMeta(doctype);
        if (!mounted) return;
        setState(() { _record = doc; _meta = meta; _loading = false; });
        return;
      }
      if (widget.linkType == 'Page' || widget.linkType == 'Dashboard') {
        final doc = await widget.api.fetchDocTypeDocument(doctype: widget.linkType, name: widget.target);
        final meta = await widget.api.fetchDocTypeMeta(widget.linkType);
        if (!mounted) return;
        setState(() { _record = doc; _meta = meta; _loading = false; });
        return;
      }
      if (widget.linkType == 'URL') {
        throw Exception('هذه وجهة خارجية وليست شاشة ERPNext. لا يفتح التطبيق صفحات ويب. إذا كانت لها مسؤولية وظيفية داخل النظام فيجب تنفيذها كشاشة Flutter أصلية.');
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  void _openLink(Map<String, dynamic> link) {
    final type = (link['link_type'] ?? link['type'] ?? '').toString();
    final target = (link['link_to'] ?? (type == 'URL' ? link['url'] : null) ?? '').toString().trim();
    if (target.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceWebPage(
      api: widget.api,
      title: (link['label'] ?? target).toString(),
      linkType: type,
      target: target,
      routeOptions: _parseRouteOptions(link['route_options']),
    )));
  }

  Widget _workspaceContent() {
    final workspace = _workspace!;
    final rawLinks = workspace['links'] is List ? workspace['links'] as List
        : workspace['sidebar_items'] is List ? workspace['sidebar_items'] as List : const [];
    final groups = <String, List<Map<String, dynamic>>>{};
    var section = 'عام';
    for (final raw in rawLinks) {
      if (raw is! Map) continue;
      final link = Map<String, dynamic>.from(raw);
      final type = link['type']?.toString() ?? '';
      if (type == 'Card Break' || type == 'Section Break' || type == 'Header') {
        section = link['label']?.toString().trim().isNotEmpty == true ? link['label'].toString() : 'عام';
      } else if (link['hidden'] != 1 && link['hidden'] != true) {
        groups.putIfAbsent(section, () => []).add(link);
      }
    }
    final charts = workspace['charts'] is List ? workspace['charts'] as List : const [];
    final quickLists = workspace['quick_lists'] is List ? workspace['quick_lists'] as List : const [];
    final shortcuts = workspace['shortcuts'] is List ? workspace['shortcuts'] as List : const [];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: ListTile(
        leading: const Icon(Icons.dashboard_outlined),
        title: Text((workspace['title'] ?? widget.title).toString()),
        subtitle: Text('مساحة عمل ERPNext • ${widget.target}', textDirection: TextDirection.ltr),
      )),
      if (_numberCards.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: _numberCards.map((card) => _NativeNumberCard(
          api: widget.api,
          name: (card['number_card_name'] ?? '').toString(),
          label: (card['label'] ?? card['number_card_name'] ?? 'مؤشر').toString(),
        )).toList()),
      for (final group in groups.entries)
        Card(child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(group.key),
          subtitle: Text('${group.value.length} وجهة'),
          children: group.value.map((link) => ListTile(
            leading: const Icon(Icons.arrow_forward_ios, size: 16),
            title: Text((link['label'] ?? link['link_to'] ?? '').toString()),
            subtitle: Text((link['link_type'] ?? '').toString()),
            onTap: () => _openLink(link),
          )).toList(),
        )),
      if (shortcuts.isNotEmpty)
        Card(child: ExpansionTile(
          title: const Text('الاختصارات'),
          leading: const Icon(Icons.shortcut),
          subtitle: Text('${shortcuts.length} اختصار'),
          children: shortcuts.whereType<Map>().map((raw) {
            final shortcut = Map<String, dynamic>.from(raw);
            final type = shortcut['type']?.toString() ?? '';
            final target = (shortcut['link_to'] ?? shortcut['url'] ?? '').toString();
            return ListTile(
              leading: const Icon(Icons.arrow_forward_ios, size: 16),
              title: Text((shortcut['label'] ?? target).toString()),
              subtitle: Text(type),
              onTap: () => _openLink({'type': type, 'link_to': shortcut['link_to'], 'url': shortcut['url'], 'route_options': shortcut['route_options'], 'label': shortcut['label']}),
            );
          }).toList(),
        )),
      if (charts.isNotEmpty)
        Card(child: ExpansionTile(
          initiallyExpanded: true,
          title: const Text('الرسوم البيانية'),
          leading: const Icon(Icons.insert_chart_outlined),
          subtitle: Text('${charts.length} مخطط'),
          children: charts.whereType<Map>().map((raw) {
            final chart = Map<String, dynamic>.from(raw);
            return _NativeDashboardChart(
              api: widget.api,
              chartName: (chart['chart_name'] ?? '').toString(),
              label: (chart['label'] ?? chart['chart_name'] ?? 'مخطط').toString(),
            );
          }).toList(),
        )),
      if (quickLists.isNotEmpty)
        Card(child: ExpansionTile(
          initiallyExpanded: true,
          title: const Text('القوائم السريعة'),
          leading: const Icon(Icons.view_list_outlined),
          subtitle: Text('${quickLists.length} قائمة'),
          children: quickLists.whereType<Map>().map((raw) => _NativeQuickList(
            api: widget.api,
            definition: Map<String, dynamic>.from(raw),
          )).toList(),
        )),
    ]);
  }

  Widget _recordContent() {
    final record = _record!;
    final fields = (_meta?['fields'] as List? ?? const []).whereType<Map>().where((field) {
      final type = field['fieldtype']?.toString() ?? '';
      return field['fieldname'] is String && !{'Section Break','Column Break','Tab Break','HTML','Table','Table MultiSelect','Button'}.contains(type) && field['hidden'] != 1;
    }).toList();
    final dashboardCharts = widget.linkType == 'Dashboard' && record['charts'] is List ? record['charts'] as List : const [];
    final dashboardCards = widget.linkType == 'Dashboard' && record['cards'] is List ? record['cards'] as List : const [];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: ListTile(
        leading: Icon(widget.linkType == 'Dashboard' ? Icons.dashboard : Icons.description_outlined),
        title: Text(widget.title),
        subtitle: Text('${record['doctype'] ?? widget.linkType} • ${record['name'] ?? widget.target}', textDirection: TextDirection.ltr),
      )),
      if (dashboardCards.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: dashboardCards.whereType<Map>().map((raw) {
          final card = Map<String, dynamic>.from(raw);
          return _NativeNumberCard(
            api: widget.api,
            name: (card['card'] ?? '').toString(),
            label: (card['label'] ?? card['card'] ?? 'مؤشر').toString(),
          );
        }).toList()),
      if (dashboardCharts.isNotEmpty)
        for (final raw in dashboardCharts.whereType<Map>())
          _NativeDashboardChart(
            api: widget.api,
            chartName: (raw['chart'] ?? '').toString(),
            label: (raw['label'] ?? raw['chart'] ?? 'مخطط').toString(),
          ),
      for (final field in fields)
        if (record[field['fieldname']] != null && record[field['fieldname']].toString().isNotEmpty)
          Card(margin: const EdgeInsets.symmetric(vertical: 3), child: ListTile(
            title: Text((field['label'] ?? field['fieldname']).toString()),
            subtitle: SelectableText(record[field['fieldname']].toString()),
          )),
      if (widget.linkType == 'Page')
        const Card(child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('محتوى الصفحة البرمجي غير منفذ'),
          subtitle: Text('لا ينفذ التطبيق HTML أو JavaScript القادم من الخادم. يجب تحويل مسؤولية الصفحة إلى واجهة Flutter أصلية وربطها بواجهات API المعتمدة.'),
        )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.linkType == 'DocTypeList' || widget.linkType == 'DocType') {
      return ErpDocTypeWorkspacePage(api: widget.api, definition: ErpDocTypeDefinition('ERPNext', widget.title, widget.target, Icons.list_alt_outlined, 'عام', 'DocType', widget.routeOptions));
    }
    if (widget.linkType == 'Report') {
      return WorkspaceReportPage(api: widget.api, companies: const <ErpCompany>[], reportName: widget.target, initialFilters: widget.routeOptions);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.info_outline, size: 36),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back), label: const Text('رجوع')),
              ]),
            ))
          : _workspace != null ? _workspaceContent()
          : _record != null ? _recordContent()
          : const Center(child: Text('لا توجد شاشة جوال أصلية لهذا النوع من الوجهات بعد.')),
    );
  }
}

class _NativeNumberCard extends StatefulWidget {
  const _NativeNumberCard({required this.api, required this.name, required this.label});
  final FrappeApi api;
  final String name;
  final String label;

  @override
  State<_NativeNumberCard> createState() => _NativeNumberCardState();
}

class _NativeNumberCardState extends State<_NativeNumberCard> {
  late Future<double?> _value;
  @override
  void initState() {
    super.initState();
    _value = widget.api.fetchWorkspaceNumberCardValue(widget.name);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 156,
    child: Card(margin: EdgeInsets.zero, child: Padding(
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<double?>(
        future: _value,
        builder: (context, snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator()
            else if (snapshot.hasError || snapshot.data == null) const Text('المؤشر غير مدعوم في العرض الأصلي للجوال')
            else Text(snapshot.data!.toString(), style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    )),
  );
}


class _NativeDashboardChart extends StatefulWidget {
  const _NativeDashboardChart({required this.api, required this.chartName, required this.label});
  final FrappeApi api;
  final String chartName;
  final String label;

  @override
  State<_NativeDashboardChart> createState() => _NativeDashboardChartState();
}

class _NativeDashboardChartState extends State<_NativeDashboardChart> {
  late Future<Map<String, dynamic>?> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchWorkspaceDashboardChart(widget.chartName);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const ListTile(title: Text('تحميل المخطط...'), subtitle: LinearProgressIndicator());
      }
      if (snapshot.hasError) {
        return ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(widget.label),
          subtitle: Text(snapshot.error.toString().replaceFirst('Exception: ', '')),
        );
      }
      final result = snapshot.data;
      if (result == null) {
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(widget.label),
          subtitle: const Text('هذا المخطط يعتمد على تقرير أو مصدر مخصص أو مرشحات ديناميكية غير منفذة في Flutter.'),
        );
      }
      final definition = result['definition'] as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;
      final labels = (data['labels'] as List? ?? const []).map((value) => value.toString()).toList();
      final datasets = data['datasets'] as List? ?? const [];
      final first = datasets.isNotEmpty && datasets.first is Map ? datasets.first as Map : const {};
      final values = (first['values'] as List? ?? const []).map((value) => (value as num?)?.toDouble() ?? 0).toList();
      if (values.isEmpty) {
        return ListTile(leading: const Icon(Icons.bar_chart), title: Text(widget.label), subtitle: const Text('لا توجد بيانات ضمن المرشحات الحالية.'));
      }
      final visualType = definition['type']?.toString() ?? 'Bar';
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 156,
            child: CustomPaint(
              painter: _WorkspaceChartPainter(values: values, visualType: visualType, colors: Theme.of(context).colorScheme),
              child: const SizedBox.expand(),
            ),
          ),
          if (labels.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < labels.length && i < values.length && i < 8; i++)
                  Text('${labels[i]}: ${values[i].toStringAsFixed(0)}', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
        ]),
      );
    },
  );
}

class _WorkspaceChartPainter extends CustomPainter {
  const _WorkspaceChartPainter({required this.values, required this.visualType, required this.colors});
  final List<double> values;
  final String visualType;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final palette = [colors.primary, colors.secondary, colors.tertiary, colors.error, colors.primaryContainer];
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue).abs() < 0.000001 ? 1.0 : maxValue - minValue;
    final baseline = size.height - 12;
    final grid = Paint()..color = colors.outlineVariant..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = 8 + (size.height - 20) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (visualType == 'Pie' || visualType == 'Donut' || visualType == 'Percentage') {
      final total = values.fold<double>(0, (sum, value) => sum + value.abs());
      if (total == 0) return;
      final side = size.height - 16;
      final rect = Rect.fromLTWH((size.width - side) / 2, 8, side, side);
      var start = -1.57079632679;
      for (var i = 0; i < values.length; i++) {
        final sweep = values[i].abs() / total * 6.28318530718;
        final paint = Paint()..color = palette[i % palette.length]..style = PaintingStyle.fill;
        canvas.drawArc(rect, start, sweep, true, paint);
        start += sweep;
      }
      if (visualType == 'Donut') {
        final hole = Paint()..color = colors.surface..style = PaintingStyle.fill;
        canvas.drawCircle(rect.center, side * .22, hole);
      }
      return;
    }
    if (visualType == 'Line') {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1 ? size.width / 2 : i * size.width / (values.length - 1);
        final y = baseline - ((values[i] - minValue) / range) * (size.height - 28);
        if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
      }
      canvas.drawPath(path, Paint()..color = colors.primary..style = PaintingStyle.stroke..strokeWidth = 2.5);
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1 ? size.width / 2 : i * size.width / (values.length - 1);
        final y = baseline - ((values[i] - minValue) / range) * (size.height - 28);
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = colors.primary);
      }
      return;
    }
    final slot = size.width / values.length;
    final barWidth = slot * .62;
    for (var i = 0; i < values.length; i++) {
      final height = ((values[i] - minValue) / range) * (size.height - 30) + 4;
      final rect = Rect.fromLTWH(i * slot + (slot - barWidth) / 2, baseline - height, barWidth, height);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = palette[i % palette.length]);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkspaceChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.visualType != visualType || oldDelegate.colors != colors;
}

class _NativeQuickList extends StatefulWidget {
  const _NativeQuickList({required this.api, required this.definition});
  final FrappeApi api;
  final Map<String, dynamic> definition;

  @override
  State<_NativeQuickList> createState() => _NativeQuickListState();
}

class _NativeQuickListState extends State<_NativeQuickList> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchWorkspaceQuickListRows(widget.definition);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      final doctype = widget.definition['document_type']?.toString() ?? '';
      final label = widget.definition['label']?.toString() ?? doctype;
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const ListTile(title: Text('تحميل القائمة السريعة...'), subtitle: LinearProgressIndicator());
      }
      if (snapshot.hasError) {
        return ListTile(leading: const Icon(Icons.error_outline), title: Text(label), subtitle: Text(snapshot.error.toString()));
      }
      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
      if (rows.isEmpty) return ListTile(leading: const Icon(Icons.list_alt), title: Text(label), subtitle: const Text('لا توجد سجلات مطابقة.'));
      return Column(children: [
        for (final row in rows)
          ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text((row['title'] ?? row['name'] ?? 'مستند').toString()),
            subtitle: Text([
              if (row['status'] != null) row['status'].toString(),
              if (row['modified'] != null) row['modified'].toString(),
            ].join(' • ')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceWebPage(
              api: widget.api,
              title: label,
              linkType: 'DocTypeDocument',
              target: '${doctype}|${row['name']}',
            ))),
          ),
      ]);
    },
  );
}
