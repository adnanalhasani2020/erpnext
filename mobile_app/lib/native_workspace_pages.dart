import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';
import 'widgets/server_link_field.dart';

class StockSummaryNativePage extends StatefulWidget {
  const StockSummaryNativePage({
    super.key,
    required this.api,
    this.routeOptions = const <String, dynamic>{},
  });
  final FrappeApi api;
  final Map<String, dynamic> routeOptions;

  @override
  State<StockSummaryNativePage> createState() => _StockSummaryNativePageState();
}

class _StockSummaryNativePageState extends State<StockSummaryNativePage> {
  late final TextEditingController _item;
  late final TextEditingController _warehouse;
  late final TextEditingController _itemGroup;
  final _sorts = const <String, String>{
    'projected_qty': 'الكمية المتوقعة',
    'reserved_qty': 'الكمية المحجوزة',
    'reserved_qty_for_production': 'محجوز للإنتاج',
    'reserved_qty_for_sub_contract': 'محجوز للتصنيع لدى الغير',
    'reserved_qty_for_production_plan': 'محجوز لخطة الإنتاج',
    'reserved_stock': 'المخزون المحجوز',
    'ordered_qty': 'الكمية المطلوبة',
    'indented_qty': 'الكمية المطلوبة داخلياً',
    'planned_qty': 'الكمية المخططة',
    'actual_qty': 'الرصيد الفعلي',
  };
  String _sortBy = 'projected_qty';
  String _sortOrder = 'asc';
  List<Map<String, dynamic>> _rows = const [];
  int _start = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The ERPNext Stock Summary Page reads these exact route_options.
    // Preserve them when a Workspace link opens the native Flutter page.
    _item = TextEditingController(text: widget.routeOptions['item_code']?.toString() ?? '');
    _warehouse = TextEditingController(text: widget.routeOptions['warehouse']?.toString() ?? '');
    _itemGroup = TextEditingController(text: widget.routeOptions['item_group']?.toString() ?? '');
    _load(reset: true);
  }

  @override
  void dispose() {
    _item.dispose();
    _warehouse.dispose();
    _itemGroup.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || _loadingMore) return;
    final start = reset ? 0 : _start;
    setState(() {
      if (reset) { _rows = const []; _start = 0; _hasMore = false; }
      if (reset) { _loading = true; } else { _loadingMore = true; }
      _error = null;
    });
    try {
      final page = await widget.api.fetchStockSummary(
        itemCode: _item.text,
        warehouse: _warehouse.text,
        itemGroup: _itemGroup.text,
        start: start,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
      );
      if (!mounted) return;
      final visible = page.take(20).toList(growable: false);
      setState(() {
        _rows = reset ? visible : [..._rows, ...visible];
        _start = start + visible.length;
        _hasMore = page.length > 20;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  String _qty(dynamic value) => value == null ? '—' : value is num ? value.toStringAsFixed(2) : value.toString();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ملخص المخزون'),
      actions: [IconButton(tooltip: 'تحديث', onPressed: _loading ? null : () => _load(reset: true), icon: const Icon(Icons.refresh))],
    ),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ServerLinkField(api: widget.api, doctype: 'Item', label: 'الصنف', controller: _item, searchFields: const ['item_name', 'item_group'], icon: Icons.inventory_2_outlined, onSelected: (_) => _load(reset: true)),
          const SizedBox(height: 8),
          ServerLinkField(api: widget.api, doctype: 'Warehouse', label: 'المستودع', controller: _warehouse, searchFields: const ['warehouse_name', 'company'], icon: Icons.warehouse_outlined, onSelected: (_) => _load(reset: true)),
          const SizedBox(height: 8),
          ServerLinkField(api: widget.api, doctype: 'Item Group', label: 'مجموعة الأصناف', controller: _itemGroup, searchFields: const ['item_group_name'], icon: Icons.category_outlined, onSelected: (_) => _load(reset: true)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _sortBy,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ترتيب حسب'),
              items: _sorts.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (value) { if (value != null) setState(() => _sortBy = value); _load(reset: true); },
            )),
            const SizedBox(width: 8),
            SizedBox(width: 112, child: DropdownButtonFormField<String>(
              initialValue: _sortOrder,
              decoration: const InputDecoration(labelText: 'الاتجاه'),
              items: const [DropdownMenuItem(value: 'asc', child: Text('تصاعدي')), DropdownMenuItem(value: 'desc', child: Text('تنازلي'))],
              onChanged: (value) { if (value != null) setState(() => _sortOrder = value); _load(reset: true); },
            )),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.search),
            label: const Text('تطبيق المرشحات'),
          )),
        ]),
      )),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل ملخص المخزون'), subtitle: Text(_error!))),
      Row(children: [
        Expanded(child: Text('النتائج: ${_rows.length}', style: Theme.of(context).textTheme.titleSmall)),
        Text(_sorts[_sortBy] ?? _sortBy, style: Theme.of(context).textTheme.bodySmall),
      ]),
      if (_rows.isEmpty && !_loading) const Card(child: ListTile(title: Text('لا توجد أرصدة مطابقة للمرشحات.'))),
      for (final row in _rows)
        Card(child: ExpansionTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text((row['item_name'] ?? row['item_code'] ?? 'صنف').toString()),
          subtitle: Text('${row['item_code'] ?? ''} • ${row['warehouse'] ?? ''}'),
          trailing: Text(_qty(row['actual_qty']), style: Theme.of(context).textTheme.titleSmall),
          children: [
            _value('الرصيد الفعلي', row['actual_qty'], row['stock_uom']),
            _value('الكمية المتوقعة', row['projected_qty'], row['stock_uom']),
            _value('المحجوز', row['reserved_qty'], row['stock_uom']),
            _value('محجوز للإنتاج', row['reserved_qty_for_production'], row['stock_uom']),
            _value('محجوز للتصنيع لدى الغير', row['reserved_qty_for_sub_contract'], row['stock_uom']),
            _value('المخزون المحجوز', row['reserved_stock'], row['stock_uom']),
            _value('معدل التقييم', row['valuation_rate'], row['stock_uom']),
          ],
        )),
      if (_hasMore || _loadingMore)
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: FilledButton.tonal(
          onPressed: _loadingMore ? null : () => _load(),
          child: Text(_loadingMore ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد'),
        )),
    ]),
  );

  Widget _value(String label, dynamic value, String? unit) => ListTile(
    dense: true,
    title: Text(label),
    trailing: Text('${_qty(value)} ${unit ?? ''}'),
  );
}

class WarehouseCapacitySummaryNativePage extends StatefulWidget {
  const WarehouseCapacitySummaryNativePage({super.key, required this.api});
  final FrappeApi api;

  @override
  State<WarehouseCapacitySummaryNativePage> createState() => _WarehouseCapacitySummaryNativePageState();
}

class _WarehouseCapacitySummaryNativePageState extends State<WarehouseCapacitySummaryNativePage> {
  final _warehouse = TextEditingController();
  final _item = TextEditingController();
  final _parentWarehouse = TextEditingController();
  List<ErpCompany> _companies = const [];
  String? _company;
  String _sortBy = 'stock_capacity';
  String _sortOrder = 'desc';
  List<Map<String, dynamic>> _rows = const [];
  int _start = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _warehouse.dispose();
    _item.dispose();
    _parentWarehouse.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    setState(() { _loading = true; _error = null; });
    try {
      final companies = await widget.api.fetchCompanies();
      if (!mounted) return;
      setState(() {
        _companies = companies;
        if (_company == null && companies.length == 1) _company = companies.first.name;
        _loading = false;
      });
      if (_company != null) await _load(reset: true);
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || _loadingMore) return;
    if (_company == null || _company!.trim().isEmpty) {
      setState(() => _error = 'اختر الشركة أولاً؛ هذا التقرير يتطلب شركة محددة.');
      return;
    }
    final start = reset ? 0 : _start;
    setState(() {
      if (reset) { _rows = const []; _start = 0; _hasMore = false; _loading = true; }
      else { _loadingMore = true; }
      _error = null;
    });
    try {
      final page = await widget.api.fetchWarehouseCapacitySummary(
        company: _company!,
        warehouse: _warehouse.text,
        itemCode: _item.text,
        parentWarehouse: _parentWarehouse.text,
        start: start,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
      );
      if (!mounted) return;
      final visible = page.take(10).toList(growable: false);
      setState(() {
        _rows = reset ? visible : [..._rows, ...visible];
        _start = start + visible.length;
        _hasMore = page.length > 10;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ملخص سعة المستودعات'),
      actions: [IconButton(tooltip: 'تحديث', onPressed: _loading ? null : () => _loadCompanies(), icon: const Icon(Icons.refresh))],
    ),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          DropdownButtonFormField<String>(
            initialValue: _company,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الشركة *'),
            items: _companies.map((company) => DropdownMenuItem(value: company.name, child: Text(company.name))).toList(),
            onChanged: (value) { setState(() => _company = value); _load(reset: true); },
          ),
          const SizedBox(height: 8),
          ServerLinkField(api: widget.api, doctype: 'Warehouse', label: 'المستودع', controller: _warehouse, searchFields: const ['warehouse_name', 'company'], onSelected: (_) => _load(reset: true)),
          const SizedBox(height: 8),
          ServerLinkField(api: widget.api, doctype: 'Warehouse', label: 'المستودع الأب (مجموعة)', controller: _parentWarehouse, searchFields: const ['warehouse_name', 'company'], filters: const [['is_group', '=', 1]], icon: Icons.account_tree_outlined, onSelected: (_) => _load(reset: true)),
          const SizedBox(height: 8),
          ServerLinkField(api: widget.api, doctype: 'Item', label: 'الصنف', controller: _item, searchFields: const ['item_name', 'item_group'], onSelected: (_) => _load(reset: true)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _sortBy,
            decoration: const InputDecoration(labelText: 'ترتيب حسب'),
            items: const [
              DropdownMenuItem(value: 'stock_capacity', child: Text('السعة')),
              DropdownMenuItem(value: 'percent_occupied', child: Text('نسبة الإشغال')),
              DropdownMenuItem(value: 'actual_qty', child: Text('الرصيد الفعلي')),
            ],
            onChanged: (value) { if (value != null) setState(() => _sortBy = value); _load(reset: true); },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _sortOrder,
            decoration: const InputDecoration(labelText: 'اتجاه الترتيب'),
            items: const [DropdownMenuItem(value: 'asc', child: Text('تصاعدي')), DropdownMenuItem(value: 'desc', child: Text('تنازلي'))],
            onChanged: (value) { if (value != null) setState(() => _sortOrder = value); _load(reset: true); },
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _loading ? null : () => _load(reset: true), icon: const Icon(Icons.search), label: const Text('تطبيق المرشحات'))),
        ]),
      )),
      if (_loading) const LinearProgressIndicator(),
      if (_companies.isEmpty && !_loading) const Card(child: ListTile(leading: Icon(Icons.business_outlined), title: Text('لا توجد شركات متاحة'), subtitle: Text('تحقق من صلاحية قراءة Company.'))),
      if (_error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل السعة'), subtitle: Text(_error!))),
      for (final row in _rows)
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text((row['warehouse'] ?? '').toString(), style: Theme.of(context).textTheme.titleMedium),
            Text((row['item_code'] ?? '').toString(), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('السعة: ${row['stock_capacity'] ?? 0}')),
              Text('الرصيد: ${row['actual_qty'] ?? 0}'),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: ((row['percent_occupied'] as num?)?.toDouble() ?? 0).clamp(0, 100) / 100),
            const SizedBox(height: 4),
            Text('الإشغال: ${row['percent_occupied'] ?? 0}% • ${row['company'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        )),
      if (_rows.isEmpty && !_loading) const Card(child: ListTile(title: Text('لا توجد قواعد سعة مطابقة.'))),
      if (_hasMore || _loadingMore)
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: FilledButton.tonal(onPressed: _loadingMore ? null : () => _load(), child: Text(_loadingMore ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد'))),
    ]),
  );
}


class VisualPlantFloorNativePage extends StatefulWidget {
  const VisualPlantFloorNativePage({super.key, required this.api});
  final FrappeApi api;

  @override
  State<VisualPlantFloorNativePage> createState() => _VisualPlantFloorNativePageState();
}

class _VisualPlantFloorNativePageState extends State<VisualPlantFloorNativePage> {
  List<Map<String, dynamic>> _floors = const [];
  List<Map<String, dynamic>> _types = const [];
  List<Map<String, dynamic>> _workstations = const [];
  String? _floor;
  String? _type;
  String? _status;
  bool _loading = true;
  String? _error;

  static const _statuses = ['Production', 'Off', 'Idle', 'Problem', 'Maintenance', 'Setup'];

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.api.fetchDocTypeRows(doctype: 'Plant Floor', fields: const ['floor_name', 'company', 'warehouse'], orderBy: 'floor_name asc'),
        widget.api.fetchDocTypeRows(doctype: 'Workstation Type', fields: const [], orderBy: 'name asc'),
      ]);
      if (!mounted) return;
      final floors = results[0];
      final types = results[1];
      setState(() {
        _floors = floors;
        _types = types;
        _floor ??= floors.isNotEmpty ? floors.first['name']?.toString() : null;
        _loading = false;
      });
      if (_floor != null) await _loadWorkstations();
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadWorkstations() async {
    if (_floor == null || _floor!.isEmpty) {
      setState(() => _workstations = const []);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.api.fetchPlantFloorWorkstations(
        plantFloor: _floor!,
        workstationType: _type,
        workstationStatus: _status,
      );
      if (!mounted) return;
      setState(() { _workstations = rows; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'Production': return Colors.green;
      case 'Problem': return scheme.error;
      case 'Maintenance': return Colors.orange;
      case 'Setup': return scheme.tertiary;
      default: return scheme.outline;
    }
  }

  String _statusLabel(String status) => switch (status) {
    'Production' => 'إنتاج',
    'Off' => 'متوقف',
    'Idle' => 'خامل',
    'Problem' => 'عطل',
    'Maintenance' => 'صيانة',
    'Setup' => 'تجهيز',
    _ => status,
  };

  Widget _statusImage(Map<String, dynamic> row, String status) {
    final path = row['status_image']?.toString().trim() ?? '';
    final base = Uri.tryParse(widget.api.baseUrl);
    if (path.isEmpty || base == null) {
      return CircleAvatar(
        backgroundColor: _statusColor(context, status).withOpacity(.14),
        child: Icon(Icons.precision_manufacturing_outlined, color: _statusColor(context, status)),
      );
    }
    final uri = base.resolve(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        uri.toString(),
        width: 68,
        height: 68,
        fit: BoxFit.cover,
        headers: widget.api.imageRequestHeadersFor(uri.toString()),
        errorBuilder: (_, __, ___) => CircleAvatar(
          backgroundColor: _statusColor(context, status).withOpacity(.14),
          child: Icon(Icons.precision_manufacturing_outlined, color: _statusColor(context, status)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('أرضية المصنع المرئية'),
        actions: [IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _loadWorkstations, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            DropdownButtonFormField<String>(
              initialValue: _floor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'أرضية المصنع *'),
              items: _floors.map((row) => DropdownMenuItem(value: row['name']?.toString(), child: Text((row['floor_name'] ?? row['name']).toString()))).toList(),
              onChanged: (value) { setState(() => _floor = value); _loadWorkstations(); },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'نوع المحطة'),
              items: [const DropdownMenuItem<String>(value: null, child: Text('كل الأنواع')),..._types.map((row) => DropdownMenuItem(value: row['name']?.toString(), child: Text((row['name'] ?? '').toString())))],
              onChanged: (value) { setState(() => _type = value); _loadWorkstations(); },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الحالة'),
              items: [const DropdownMenuItem<String>(value: null, child: Text('كل الحالات')),..._statuses.map((status) => DropdownMenuItem(value: status, child: Text(_statusLabel(status))))],
              onChanged: (value) { setState(() => _status = value); _loadWorkstations(); },
            ),
          ]),
        )),
        const Card(child: ListTile(
          leading: Icon(Icons.sync),
          title: Text('تحديث يدوي للحالات'),
          subtitle: Text('يعرض حالة Workstation التي يرسلها ERPNext. التحديث اللحظي WebSocket غير مفعّل في نسخة الجوال حالياً.'),
        )),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل أرضية المصنع'), subtitle: Text(_error!))),
        if (_floor == null && !_loading) const Card(child: ListTile(title: Text('لا توجد أرضيات مصنع متاحة أو لا تملك صلاحية قراءتها.'))),
        if (_workstations.isEmpty && !_loading && _error == null && _floor != null)
          const Card(child: ListTile(title: Text('لا توجد محطات عمل مطابقة للمرشحات.'))),
        for (final row in _workstations)
          Card(child: ListTile(
            leading: _statusImage(row, (row['status'] ?? '').toString()),
            title: Text((row['name'] ?? '').toString()),
            subtitle: Text((row['description'] ?? '').toString().isEmpty ? 'لا يوجد وصف' : row['description'].toString()),
            trailing: Chip(
              backgroundColor: _statusColor(context, (row['status'] ?? '').toString()).withOpacity(.14),
              label: Text(_statusLabel((row['status'] ?? '').toString())),
            ),
          )),
      ]),
    );
  }
}
