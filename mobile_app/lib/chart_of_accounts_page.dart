import 'package:flutter/material.dart';
import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class ChartOfAccountsPage extends StatefulWidget {
  const ChartOfAccountsPage({super.key, required this.api, required this.companies});
  final FrappeApi api;
  final List<ErpCompany> companies;
  @override
  State<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends State<ChartOfAccountsPage> {
  String? company;
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  bool loading = false, loadingMore = false, hasMore = false;
  int offset = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.companies.isNotEmpty) {
      company = widget.companies.first.name;
      load();
    }
  }

  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> load({bool more = false}) async {
    if (company == null || loading || loadingMore || (more && !hasMore)) return;
    setState(() { if (more) { loadingMore = true; } else { loading = true; error = null; } });
    try {
      final page = await widget.api.fetchAccountingAccounts(
        company: company!, search: search.text, start: more ? offset : 0,
      );
      if (!mounted) return;
      setState(() {
        if (more) { rows.addAll(page); } else { rows = page; }
        offset = rows.length;
        hasMore = page.length == 200;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() { loading = false; loadingMore = false; });
    }
  }

  void showDetails(Map<String, dynamic> row) {
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(shrinkWrap: true, children: [
          Text(row['account_name']?.toString() ?? row['name']?.toString() ?? 'الحساب',
            style: Theme.of(context).textTheme.titleLarge),
          ListTile(title: const Text('رمز الحساب'), subtitle: Text(row['name']?.toString() ?? '—')),
          ListTile(title: const Text('نوع الحساب'), subtitle: Text(row['account_type']?.toString() ?? '—')),
          ListTile(title: const Text('التصنيف الرئيسي'), subtitle: Text(row['root_type']?.toString() ?? '—')),
          ListTile(title: const Text('الحساب الأب'), subtitle: Text(row['parent_account']?.toString() ?? '—')),
          ListTile(title: const Text('العملة'), subtitle: Text(row['account_currency']?.toString() ?? '—')),
          ListTile(title: const Text('الشركة'), subtitle: Text(row['company']?.toString() ?? '—')),
          ListTile(title: const Text('النوع'), subtitle: Text((row['is_group'] == 1 || row['is_group'] == true) ? 'حساب تجميعي' : 'حساب حركة')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('دليل الحسابات'), actions: [
      IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.refresh)),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
        initialValue: company,
        decoration: const InputDecoration(labelText: 'الشركة'),
        items: widget.companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
        onChanged: loading || loadingMore ? null : (v) {
          setState(() { company = v; rows = []; offset = 0; hasMore = false; error = null; });
          load();
        },
      )),
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: TextField(
        controller: search, textInputAction: TextInputAction.search,
        onSubmitted: (_) => load(),
        decoration: InputDecoration(
          labelText: 'بحث باسم الحساب أو رمزه أو نوعه',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.arrow_forward)),
        ),
      )),
      if (loading) const LinearProgressIndicator(),
      if (error != null) ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('تعذر تحميل دليل الحسابات'),
        subtitle: Text(error!),
        trailing: IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.refresh)),
      ),
      Expanded(child: rows.isEmpty && !loading
        ? Center(child: Text(company == null ? 'لا توجد شركة متاحة للمستخدم.' : 'لا توجد حسابات ظاهرة أو لا تتوفر صلاحية القراءة.'))
        : ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            final isGroup = row['is_group'] == 1 || row['is_group'] == true;
            return ListTile(
              leading: Icon(isGroup ? Icons.account_tree_outlined : Icons.account_balance_wallet_outlined),
              title: Text(row['account_name']?.toString() ?? row['name']?.toString() ?? ''),
              subtitle: Text([
                row['name']?.toString() ?? '',
                row['account_type']?.toString() ?? row['root_type']?.toString() ?? '',
                row['parent_account']?.toString() ?? '',
              ].where((v) => v.isNotEmpty).join(' • ')),
              trailing: Text(row['account_currency']?.toString() ?? ''),
              onTap: () => showDetails(row),
            );
          },
        ),
      ),
      if (hasMore || loadingMore) Padding(padding: const EdgeInsets.all(12), child: OutlinedButton(
        onPressed: loadingMore ? null : () => load(more: true),
        child: Text(loadingMore ? 'جارٍ التحميل...' : 'تحميل المزيد'),
      )),
    ]),
  );
}
