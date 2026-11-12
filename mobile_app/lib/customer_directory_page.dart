import 'package:flutter/material.dart';
import 'models/erp_models.dart';
import 'widgets/load_more_button.dart';
import 'widgets/server_search_field.dart';

class CustomerDirectoryPage extends StatelessWidget {
  const CustomerDirectoryPage({super.key, required this.loading, required this.error, required this.customers,
    required this.search, required this.searchController, required this.searching, required this.hasMore,
    required this.loadingMore, required this.onRefresh, required this.onSearch, required this.onLoadMore,
    required this.onEdit, required this.onOpenLedger});
  final bool loading, searching, hasMore, loadingMore;
  final String? error;
  final List<ErpCustomer> customers;
  final String search;
  final TextEditingController searchController;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onSearch;
  final ValueChanged<ErpCustomer> onEdit, onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final query = search.toLowerCase();
    final visible = customers.where((customer) => query.isEmpty ||
      customer.id.toLowerCase().contains(query) || customer.name.toLowerCase().contains(query)).toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء'), actions: [
        IconButton(tooltip: 'تحديث', onPressed: loading ? null : () => onRefresh(), icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ServerSearchField(controller: searchController, label: 'بحث باسم العميل أو رقمه', onSearch: onSearch, loading: searching),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline),
            title: const Text('تعذر تحميل العملاء'), subtitle: Text(error!))),
          Text('العملاء (${visible.length})', style: Theme.of(context).textTheme.titleMedium),
          if (visible.isEmpty && !loading) const Card(child: ListTile(title: Text('لا توجد بيانات عملاء ظاهرة'))),
          for (final customer in visible)
            Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(customer.name),
              subtitle: Text([customer.id, if (customer.group != null) customer.group!, if (customer.territory != null) customer.territory!].join(' • ')),
              trailing: IconButton(tooltip: 'تعديل ملف العميل', icon: const Icon(Icons.edit_outlined), onPressed: () => onEdit(customer)),
              onTap: () => onOpenLedger(customer),
            )),
          if (hasMore || loadingMore) LoadMoreButton(loadingMore, 'تحميل المزيد من العملاء', onLoadMore),
        ]),
      ),
    );
  }
}
