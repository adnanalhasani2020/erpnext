import 'package:flutter/material.dart';
import 'models/erp_models.dart';
import 'widgets/load_more_button.dart';
import 'widgets/server_search_field.dart';

class SupplierDirectoryPage extends StatelessWidget {
  const SupplierDirectoryPage({super.key, required this.loading, required this.error, required this.suppliers,
    required this.search, required this.searchController, required this.searching, required this.hasMore,
    required this.loadingMore, required this.onRefresh, required this.onSearch, required this.onLoadMore,
    required this.onOpenLedger});
  final bool loading, searching, hasMore, loadingMore;
  final String? error;
  final List<ErpSupplier> suppliers;
  final String search;
  final TextEditingController searchController;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onSearch;
  final ValueChanged<ErpSupplier> onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final query = search.toLowerCase();
    final visible = suppliers.where((supplier) => query.isEmpty ||
      supplier.id.toLowerCase().contains(query) || supplier.name.toLowerCase().contains(query)).toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('الموردون'), actions: [
        IconButton(tooltip: 'تحديث', onPressed: loading ? null : () => onRefresh(), icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ServerSearchField(controller: searchController, label: 'بحث باسم المورد أو رقمه', onSearch: onSearch, loading: searching),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline),
            title: const Text('تعذر تحميل الموردين'), subtitle: Text(error!))),
          Text('الموردون (${visible.length})', style: Theme.of(context).textTheme.titleMedium),
          if (visible.isEmpty && !loading) const Card(child: ListTile(title: Text('لا توجد بيانات موردين ظاهرة'))),
          for (final supplier in visible)
            Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
              title: Text(supplier.name),
              subtitle: Text([supplier.id, if (supplier.group != null) supplier.group!, if (supplier.type != null) supplier.type!].join(' • ')),
              trailing: const Icon(Icons.receipt_long_outlined),
              onTap: () => onOpenLedger(supplier),
            )),
          if (hasMore || loadingMore) LoadMoreButton(loadingMore, 'تحميل المزيد من الموردين', onLoadMore),
        ]),
      ),
    );
  }
}
