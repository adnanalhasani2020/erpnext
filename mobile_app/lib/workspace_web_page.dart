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
    final target = (link['link_to'] ?? '').toString().trim();
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
      if (charts.isNotEmpty)
        Card(child: ExpansionTile(
          title: const Text('الرسوم البيانية'),
          leading: const Icon(Icons.insert_chart_outlined),
          subtitle: Text('${charts.length} مخطط'),
          children: charts.map((chart) => ListTile(
            leading: const Icon(Icons.bar_chart),
            title: Text(chart is Map ? (chart['chart_name'] ?? chart['label'] ?? 'مخطط').toString() : chart.toString()),
            subtitle: const Text('تعريف المخطط موجود في ERPNext؛ لم يُنفّذ عرض بياناته في Flutter بعد.'),
          )).toList(),
        )),
      if (quickLists.isNotEmpty)
        Card(child: ExpansionTile(
          title: const Text('القوائم السريعة'),
          leading: const Icon(Icons.view_list_outlined),
          subtitle: Text('${quickLists.length} قائمة'),
          children: quickLists.map((item) => ListTile(
            leading: const Icon(Icons.list_alt),
            title: Text(item is Map ? (item['quick_list_name'] ?? item['label'] ?? 'قائمة').toString() : item.toString()),
            subtitle: const Text('تعريف القائمة موجود في ERPNext؛ لم يُنفّذ جلب صفوفها في Flutter بعد.'),
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
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: ListTile(
        leading: Icon(widget.linkType == 'Dashboard' ? Icons.dashboard : Icons.description_outlined),
        title: Text(widget.title),
        subtitle: Text('${record['doctype'] ?? widget.linkType} • ${record['name'] ?? widget.target}', textDirection: TextDirection.ltr),
      )),
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
