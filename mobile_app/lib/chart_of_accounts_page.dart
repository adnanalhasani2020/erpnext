import 'dart:core';
import 'dart:core' as core;
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
  List<core.Map<String, dynamic>> rows = [];
  bool loading = false, loadingMore = false, hasMore = false;
  bool includeDisabled = false;
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
        includeDisabled: includeDisabled,
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

  Future<void> showAccountEditor({core.Map<String, dynamic>? row}) async {
    final isEdit = row != null;
    final name = TextEditingController(text: row?['account_name']?.toString() ?? '');
    final parent = TextEditingController(text: row?['parent_account']?.toString() ?? '');
    final currency = TextEditingController(text: row?['account_currency']?.toString() ?? '');
    final accountType = TextEditingController(text: row?['account_type']?.toString() ?? '');
    final rootType = row?['root_type']?.toString() ?? '';
    var isGroup = row?['is_group'] == 1 || row?['is_group'] == true;
    var saving = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text(isEdit ? 'تعديل الحساب' : 'إضافة حساب جديد'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الحساب *')),
              TextField(controller: parent, enabled: !isEdit, decoration: const InputDecoration(labelText: 'الحساب الأب التجميعي *')),
              if (isEdit)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('التصنيف الرئيسي'),
                  subtitle: Text(rootType.isEmpty ? 'يحدده ERPNext' : rootType),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('سيُورث التصنيف الرئيسي ونوع التقرير تلقائياً من الحساب الأب في ERPNext.'),
                ),
              TextField(controller: currency, enabled: !isEdit, decoration: const InputDecoration(labelText: 'عملة الحساب *')),
              TextField(controller: accountType, decoration: const InputDecoration(labelText: 'نوع الحساب (اختياري)')),
              if (!isEdit) CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: isGroup,
                title: const Text('حساب تجميعي'),
                onChanged: (v) => refresh(() => isGroup = v ?? false),
              ),
              if (isEdit) const Align(
                alignment: Alignment.centerRight,
                child: Text('يمكن تعديل الاسم ونوع الحساب فقط؛ تبقى هوية الحساب وتصنيفه ثابتين.',
                  style: TextStyle(fontSize: 12)),
              ),
            ],
          )),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
            FilledButton(
              onPressed: saving ? null : () async {
                refresh(() => saving = true);
                try {
                  await widget.api.saveAccountingAccount(
                    name: row?['name']?.toString(),
                    accountName: name.text,
                    company: company!,
                    parentAccount: parent.text,
                    accountCurrency: currency.text,
                    isGroup: isGroup,
                    accountType: accountType.text,
                    disabled: row?['disabled'] == 1 || row?['disabled'] == true,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                    refresh(() => saving = false);
                  }
                }
              },
              child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    parent.dispose();
    currency.dispose();
    accountType.dispose();
    if (result == true && mounted) {
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'تم تحديث الحساب.' : 'تم إنشاء الحساب.')),
        );
      }
    }
  }

  void showDetails(core.Map<String, dynamic> row) {
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, useSafeArea: true,
      builder: (sheetContext) => Padding(
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
          if (!(row['is_group'] == 1 || row['is_group'] == true))
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                showAccountEditor(row: row);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل الحساب'),
            ),
          if (!(row['is_group'] == 1 || row['is_group'] == true))
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(sheetContext);
                final currentlyDisabled = row['disabled'] == 1 || row['disabled'] == true;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(currentlyDisabled ? 'تفعيل الحساب' : 'تعطيل الحساب'),
                    content: Text(currentlyDisabled
                        ? 'سيُطلب من ERPNext إعادة تفعيل الحساب ${row['name']}.'
                        : 'سيُطلب من ERPNext تعطيل الحساب ${row['name']}. قد يرفض ERPNext ذلك إذا كانت هناك قيود أو ارتباطات تمنع التعطيل.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('رجوع')),
                      FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('تأكيد')),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                try {
                  await widget.api.saveAccountingAccount(
                    name: row['name']?.toString(),
                    company: company!,
                    accountName: row['account_name']?.toString() ?? row['name']?.toString() ?? '',
                    parentAccount: row['parent_account']?.toString() ?? '',
                    isGroup: false,
                    accountType: row['account_type']?.toString() ?? '',
                    accountCurrency: row['account_currency']?.toString() ?? '',
                    disabled: !currentlyDisabled,
                  );
                  await load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(currentlyDisabled ? 'تم تفعيل الحساب.' : 'تم تعطيل الحساب.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                }
              },
              icon: Icon((row['disabled'] == 1 || row['disabled'] == true)
                  ? Icons.check_circle_outline : Icons.block_outlined),
              label: Text((row['disabled'] == 1 || row['disabled'] == true)
                  ? 'تفعيل الحساب' : 'تعطيل الحساب'),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('دليل الحسابات'), actions: [
      IconButton(onPressed: loading ? null : () => load(), icon: const Icon(Icons.refresh)),
      IconButton(onPressed: company == null || loading || loadingMore ? null : () => showAccountEditor(),
        tooltip: 'إضافة حساب', icon: const Icon(Icons.add)),
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
        controller: search, enabled: !loading && !loadingMore, textInputAction: TextInputAction.search,
        onSubmitted: (_) => load(),
        decoration: InputDecoration(
          labelText: 'بحث باسم الحساب أو رمزه أو نوعه',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: loading || loadingMore ? null : () => load(), icon: const Icon(Icons.arrow_forward)),
        ),
      )),
      SwitchListTile(
        dense: true,
        title: const Text('عرض الحسابات المعطلة'),
        value: includeDisabled,
        onChanged: loading || loadingMore ? null : (value) {
          setState(() { includeDisabled = value; rows = []; offset = 0; hasMore = false; });
          load();
        },
      ),
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
              trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(row['account_currency']?.toString() ?? ''),
                if (row['disabled'] == 1 || row['disabled'] == true)
                  const Text('معطل', style: TextStyle(fontSize: 11, color: Colors.red)),
              ]),
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
