import 'package:flutter/material.dart';
import 'models/erp_models.dart';
import 'widgets/load_more_button.dart';
import 'widgets/server_search_field.dart';

class SalesInvoicesPage extends StatelessWidget {
  const SalesInvoicesPage({super.key, required this.loading, required this.error, required this.invoices,
    required this.search, required this.searchController, required this.searching, required this.hasMore,
    required this.loadingMore, required this.onRefresh, required this.onSearch, required this.onLoadMore,
    required this.onOpenInvoice, required this.onCreateInvoice});
  final bool loading, searching, hasMore, loadingMore;
  final String? error;
  final List<ErpSalesInvoice> invoices;
  final String search;
  final TextEditingController searchController;
  final VoidCallback onRefresh, onLoadMore, onCreateInvoice;
  final ValueChanged<String> onSearch, onOpenInvoice;

  @override
  Widget build(BuildContext context) {
    final query = search.toLowerCase();
    final visible = invoices.where((invoice) => query.isEmpty ||
      invoice.id.toLowerCase().contains(query) || invoice.customerName.toLowerCase().contains(query)).toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('فواتير المبيعات'), actions: [
        IconButton(tooltip: 'تحديث', onPressed: loading ? null : onRefresh, icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: loading ? null : onCreateInvoice,
        icon: const Icon(Icons.add), label: const Text('فاتورة جديدة')),
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 92), children: [
          ServerSearchField(controller: searchController, label: 'بحث برقم الفاتورة أو العميل', onSearch: onSearch, loading: searching),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline),
            title: const Text('تعذر تحميل فواتير المبيعات'), subtitle: Text(error!))),
          Text('الفواتير (${visible.length})', style: Theme.of(context).textTheme.titleMedium),
          if (visible.isEmpty && !loading) const Card(child: ListTile(title: Text('لا توجد فواتير ظاهرة'))),
          for (final invoice in visible)
            Card(child: ListTile(
              leading: CircleAvatar(child: Icon(invoice.isReturn ? Icons.assignment_return_outlined : Icons.receipt_long_outlined)),
              title: Text(invoice.isReturn ? 'مرتجع • ${invoice.id}' : invoice.id),
              subtitle: Text('${invoice.customerName} • ${invoice.postingDate ?? '—'}\n${invoice.returnAgainst == null ? '' : 'مرتبط بالفاتورة: ${invoice.returnAgainst}\n'}${invoice.status ?? 'حالة غير محددة'} • متبقٍ: ${invoice.outstandingAmount.toStringAsFixed(2)} ${invoice.currency ?? ''}'),
              isThreeLine: true,
              trailing: Text(invoice.grandTotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => onOpenInvoice(invoice.id),
            )),
          if (hasMore || loadingMore) LoadMoreButton(loadingMore, 'تحميل المزيد من الفواتير', onLoadMore),
        ]),
      ),
    );
  }
}
