import 'dart:convert';
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'doctype_workspace_editor_page.dart';
import 'doctype_workspace_model.dart';
import 'models/erp_models.dart';
import 'native_workspace_pages.dart';
import 'workspace_report_page.dart';

/// Native Flutter destination for ERPNext Desk links.
/// ERPNext Web is consulted for metadata and server-side business rules only.
class WorkspaceNativeDestinationPage extends StatefulWidget {
  const WorkspaceNativeDestinationPage({super.key, required this.api, required this.title, required this.linkType, required this.target, this.routeOptions = const {}, this.onOpenDefinition});
  final FrappeApi api;
  final String title;
  final String linkType;
  final String target;
  final Map<String, dynamic> routeOptions;
  final ValueChanged<ErpDocTypeDefinition>? onOpenDefinition;

  @override
  State<WorkspaceNativeDestinationPage> createState() => _WorkspaceNativeDestinationPageState();
}

class _WorkspaceNativeDestinationPageState extends State<WorkspaceNativeDestinationPage> {
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
    if (widget.linkType == 'Page' && const {'stock-balance', 'warehouse-capacity-summary', 'visual-plant-floor'}.contains(widget.target)) {
      if (mounted) setState(() { _loading = false; _error = null; });
      return;
    }
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
      if (widget.linkType == 'Page') {
        if (!mounted) return;
        setState(() {
          _error = 'هذه صفحة ERPNext مخصصة ولا توجد لها شاشة Flutter مطابقة حتى الآن. لم يتم فتح WebView أو عرض نموذج مستند بديل.';
          _loading = false;
        });
        return;
      }
      if (widget.linkType == 'Dashboard') {
        final doc = await widget.api.fetchDocTypeDocument(doctype: 'Dashboard', name: widget.target);
        final meta = await widget.api.fetchDocTypeMeta('Dashboard');
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

  Future<void> _openLink(Map<String, dynamic> link) async {
    final type = (link['link_type'] ?? link['type'] ?? '').toString();
    final target = (link['link_to'] ?? (type == 'URL' ? link['url'] : null) ?? '').toString().trim();
    if (target.isEmpty) return;
    if (type == 'Report') {
      try {
        final companies = await widget.api.fetchCompanies();
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceReportPage(
          api: widget.api,
          companies: companies,
          reportName: target,
          initialFilters: _parseRouteOptions(link['route_options']),
        )));
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (type == 'DocType' && widget.onOpenDefinition != null) {
      widget.onOpenDefinition!(ErpDocTypeDefinition(
        (_workspace?['title'] ?? 'ERPNext').toString(),
        (link['label'] ?? target).toString(),
        target,
        Icons.list_alt_outlined,
        'عام',
        type,
        _parseRouteOptions(link['route_options']),
        _workspace?['name']?.toString() ?? '',
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceNativeDestinationPage(
      api: widget.api,
      title: (link['label'] ?? target).toString(),
      linkType: type,
      target: target,
      routeOptions: _parseRouteOptions(link['route_options']),
      onOpenDefinition: widget.onOpenDefinition,
    )));
  }

  Widget _workspaceContent() {
    final workspace = _workspace!;
    final rawLinks = workspace['links'] is List ? workspace['links'] as List
        : workspace['sidebar_items'] is List ? workspace['sidebar_items'] as List : const [];
    final groups = <String, List<Map<String, dynamic>>>{};
    var section = 'عام';
    var hiddenCard = false;
    for (final raw in rawLinks) {
      if (raw is! Map) continue;
      final link = Map<String, dynamic>.from(raw);
      final type = link['type']?.toString() ?? '';
      if (type == 'Card Break' || type == 'Section Break' || type == 'Header') {
        hiddenCard = link['hidden'] == 1 || link['hidden'] == true;
        final heading = link['label']?.toString().trim() ?? '';
        if (!hiddenCard && heading.isNotEmpty) section = heading;
      } else if (!hiddenCard && link['hidden'] != 1 && link['hidden'] != true) {
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
            onTap: () { _openLink(link); },
          )).toList(),
        )),
      if (shortcuts.isNotEmpty)
        Card(child: ExpansionTile(
          title: const Text('الاختصارات'),
          leading: const Icon(Icons.shortcut),
          subtitle: Text('${shortcuts.length} اختصار'),
          children: shortcuts.whereType<Map>()
              .where((raw) => raw['hidden'] != 1 && raw['hidden'] != true)
              .map((raw) {
            final shortcut = Map<String, dynamic>.from(raw);
            final type = shortcut['type']?.toString() ?? '';
            final target = (shortcut['link_to'] ?? shortcut['url'] ?? '').toString();
            return ListTile(
              leading: const Icon(Icons.arrow_forward_ios, size: 16),
              title: Text((shortcut['label'] ?? target).toString()),
              subtitle: Text(type),
              onTap: () { _openLink({'type': type, 'link_to': shortcut['link_to'], 'url': shortcut['url'], 'route_options': shortcut['route_options'], 'label': shortcut['label']}); },
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
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.linkType == 'Page' && widget.target == 'stock-balance') {
      return StockSummaryNativePage(api: widget.api, routeOptions: widget.routeOptions);
    }
    if (widget.linkType == 'Page' && widget.target == 'warehouse-capacity-summary') {
      return WarehouseCapacitySummaryNativePage(api: widget.api, routeOptions: widget.routeOptions);
    }
    if (widget.linkType == 'Page' && widget.target == 'visual-plant-floor') {
      return VisualPlantFloorNativePage(api: widget.api);
    }
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
      final datasets = (data['datasets'] as List? ?? const [])
          .whereType<Map>()
          .map((dataset) => <String, dynamic>{
            'name': dataset['name']?.toString() ?? '',
            'values': (dataset['values'] as List? ?? const [])
                .map((value) => (value as num?)?.toDouble() ?? 0).toList(),
          })
          .where((dataset) => (dataset['values'] as List<double>).isNotEmpty)
          .toList(growable: false);
      if (datasets.isEmpty) {
        return ListTile(leading: const Icon(Icons.bar_chart), title: Text(widget.label), subtitle: const Text('لا توجد بيانات ضمن المرشحات الحالية.'));
      }
      final visualType = definition['type']?.toString() ?? 'Bar';
      final seriesValues = datasets.map((dataset) => dataset['values'] as List<double>).toList(growable: false);
      final seriesNames = datasets.map((dataset) => dataset['name'] as String).toList(growable: false);
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 156,
            child: CustomPaint(
              painter: _WorkspaceChartPainter(seriesValues: seriesValues, visualType: visualType, colors: Theme.of(context).colorScheme),
              child: const SizedBox.expand(),
            ),
          ),
          if (labels.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var seriesIndex = 0; seriesIndex < seriesValues.length; seriesIndex++)
                  for (var pointIndex = 0;
                      pointIndex < labels.length && pointIndex < seriesValues[seriesIndex].length;
                      pointIndex++)
                    Text(
                      '${seriesNames.length > 1 ? '${seriesNames[seriesIndex]} • ' : ''}${labels[pointIndex]}: ${seriesValues[seriesIndex][pointIndex].toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
              ],
            ),
          if (seriesNames.length > 1)
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (var i = 0; i < seriesNames.length; i++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, size: 8, color: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.tertiary, Theme.of(context).colorScheme.error][i % 4]),
                    const SizedBox(width: 4),
                    Text(seriesNames[i], style: Theme.of(context).textTheme.labelSmall),
                  ]),
              ],
            ),
        ]),
      );
    },
  );
}

class _WorkspaceChartPainter extends CustomPainter {
  const _WorkspaceChartPainter({required this.seriesValues, required this.visualType, required this.colors});
  final List<List<double>> seriesValues;
  final String visualType;
  final ColorScheme colors;

  List<Color> get _palette => [colors.primary, colors.secondary, colors.tertiary, colors.error, colors.primaryContainer];

  @override
  void paint(Canvas canvas, Size size) {
    if (seriesValues.isEmpty || seriesValues.every((series) => series.isEmpty)) return;
    final palette = _palette;
    final values = visualType == 'Pie' || visualType == 'Donut' || visualType == 'Percentage'
        ? seriesValues.first
        : seriesValues.expand((series) => series).toList(growable: false);
    if (values.isEmpty) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue).abs() < 0.000001 ? 1.0 : maxValue - minValue;
    final baseline = size.height - 12;
    final grid = Paint()..color = colors.outlineVariant..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = 8 + (size.height - 20) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (visualType == 'Heatmap') {
      final pointCount = seriesValues.map((series) => series.length).fold<int>(0, (a, b) => a > b ? a : b);
      if (pointCount == 0) return;
      final cellWidth = size.width / pointCount;
      final cellHeight = size.height / seriesValues.length;
      for (var seriesIndex = 0; seriesIndex < seriesValues.length; seriesIndex++) {
        final series = seriesValues[seriesIndex];
        for (var pointIndex = 0; pointIndex < series.length; pointIndex++) {
          final normalized = range == 0
              ? .5
              : ((series[pointIndex] - minValue) / range).clamp(0.0, 1.0).toDouble();
          final opacity = (.12 + normalized * .82).toDouble();
          final rect = Rect.fromLTWH(
            pointIndex * cellWidth + 1,
            seriesIndex * cellHeight + 1,
            (cellWidth - 2).clamp(0.0, cellWidth).toDouble(),
            (cellHeight - 2).clamp(0.0, cellHeight).toDouble(),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()..color = palette[seriesIndex % palette.length].withOpacity(opacity),
          );
        }
      }
      return;
    }
    if (visualType == 'Pie' || visualType == 'Donut' || visualType == 'Percentage') {
      final pieValues = seriesValues.first;
      final total = pieValues.fold<double>(0, (sum, value) => sum + value.abs());
      if (total == 0) return;
      final side = size.height - 16;
      final rect = Rect.fromLTWH((size.width - side) / 2, 8, side, side);
      var start = -1.57079632679;
      for (var i = 0; i < pieValues.length; i++) {
        final sweep = pieValues[i].abs() / total * 6.28318530718;
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
    final seriesCount = seriesValues.length;
    if (visualType == 'Line') {
      for (var seriesIndex = 0; seriesIndex < seriesCount; seriesIndex++) {
        final current = seriesValues[seriesIndex];
        if (current.isEmpty) continue;
        final path = Path();
        for (var i = 0; i < current.length; i++) {
          final x = current.length == 1 ? size.width / 2 : i * size.width / (current.length - 1);
          final y = baseline - ((current[i] - minValue) / range) * (size.height - 28);
          if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
        }
        final color = palette[seriesIndex % palette.length];
        canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);
        for (var i = 0; i < current.length; i++) {
          final x = current.length == 1 ? size.width / 2 : i * size.width / (current.length - 1);
          final y = baseline - ((current[i] - minValue) / range) * (size.height - 28);
          canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
        }
      }
      return;
    }
    final pointCount = seriesValues.map((series) => series.length).reduce((a, b) => a > b ? a : b);
    if (pointCount == 0) return;
    final slot = size.width / pointCount;
    final groupWidth = slot * .78;
    final barWidth = groupWidth / seriesCount;
    for (var seriesIndex = 0; seriesIndex < seriesCount; seriesIndex++) {
      final current = seriesValues[seriesIndex];
      for (var i = 0; i < current.length; i++) {
        final height = ((current[i] - minValue) / range) * (size.height - 30) + 4;
        final left = i * slot + (slot - groupWidth) / 2 + seriesIndex * barWidth;
        final rect = Rect.fromLTWH(left, baseline - height, barWidth * .88, height);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), Paint()..color = palette[seriesIndex % palette.length]);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WorkspaceChartPainter oldDelegate) =>
      oldDelegate.seriesValues != seriesValues || oldDelegate.visualType != visualType || oldDelegate.colors != colors;
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
            title: Text((row['_mobile_title'] ?? row['name'] ?? 'مستند').toString()),
            subtitle: Text([
              if (row['status'] != null) row['status'].toString(),
              if (row['workflow_state'] != null) row['workflow_state'].toString(),
              if (row['modified'] != null) row['modified'].toString(),
            ].join(' • ')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceNativeDestinationPage(
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


/// Backward-compatible name for old call sites; it still renders native Flutter only.
@Deprecated('Use WorkspaceNativeDestinationPage')
class WorkspaceWebPage extends WorkspaceNativeDestinationPage {
  const WorkspaceWebPage({super.key, required super.api, required super.title, required super.linkType, required super.target, super.routeOptions = const {}});
}
