import 'package:flutter/material.dart';

import 'models/erp_models.dart';
import 'widgets/server_search_field.dart';

class WarehouseListPage extends StatelessWidget {
  const WarehouseListPage({
    super.key,
    required this.warehouses,
    required this.search,
    required this.searchController,
    required this.searching,
    required this.guest,
    required this.loading,
    required this.error,
    required this.stockBalances,
    required this.hasMore,
    required this.loadingMore,
    required this.onSearch,
    required this.onOpenHierarchy,
    required this.onSelectWarehouse,
    required this.onLoadMore,
  });

  final List<ErpWarehouse> warehouses;
  final String search;
  final TextEditingController searchController;
  final bool searching;
  final bool guest;
  final bool loading;
  final String? error;
  final List<ErpStockBalance> stockBalances;
  final bool hasMore;
  final bool loadingMore;
  final ValueChanged<String> onSearch;
  final VoidCallback onOpenHierarchy;
  final ValueChanged<ErpWarehouse> onSelectWarehouse;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final query = search.trim().toLowerCase();
    final filtered = warehouses.where((warehouse) =>
      warehouse.name.toLowerCase().contains(query) ||
      warehouse.id.toLowerCase().contains(query) ||
      (warehouse.company ?? '').toLowerCase().contains(query)
    ).toList(growable: false);

    return ListView(padding: const EdgeInsets.all(18), children: [
      if (guest) const Card(child: ListTile(
        leading: Icon(Icons.science_outlined),
        title: Text('بيانات تجريبية محلية'),
        subtitle: Text('هذه سجلات وهمية للاستعراض فقط. لا يوجد اتصال بالخادم ولا يمكن حفظ معاملات.'),
      )),
      Row(children: [
        CircleAvatar(child: Icon(Icons.warehouse_outlined)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('المستودعات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text('المستودعات الفعلية المتاحة للمستخدم', style: Theme.of(context).textTheme.bodySmall),
        ])),
        IconButton(tooltip: 'تحديث البيانات', onPressed: guest || loading ? null : onLoadMore, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 16),
      ServerSearchField(
        controller: searchController,
        label: 'بحث في المستودعات أو الشركة',
        onSearch: onSearch,
        loading: searching,
        buttonLabel: guest ? 'بحث محلي' : 'بحث في الخادم',
      ),
      const SizedBox(height: 10),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: guest || loading ? null : onOpenHierarchy,
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('عرض شجرة المستودعات'),
        ),
      ),
      Text('${filtered.length} مستودع من ${warehouses.length} مستودع محمّل'),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      )),
      if (filtered.isEmpty && !loading)
        const Card(child: ListTile(title: Text('لا توجد مستودعات مطابقة'))),
      ...filtered.map((warehouse) {
        final count = stockBalances.where((row) => row.warehouse == warehouse.id).length;
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.warehouse_outlined)),
          title: Text(warehouse.name),
          subtitle: Text('${warehouse.company ?? 'شركة غير محددة'} • $count أرصدة'),
          onTap: () => onSelectWarehouse(warehouse),
        ));
      }),
      if (hasMore || loadingMore)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: FilledButton.tonal(
            onPressed: loadingMore ? null : onLoadMore,
            child: Text(loadingMore ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من المستودعات'),
          ),
        ),
    ]);
  }
}
