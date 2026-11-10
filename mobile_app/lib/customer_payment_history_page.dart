import 'package:flutter/material.dart';

import 'api/frappe_api.dart';

class CustomerPaymentHistoryPage extends StatefulWidget {
  const CustomerPaymentHistoryPage({super.key, required this.api});
  final FrappeApi api;

  @override
  State<CustomerPaymentHistoryPage> createState() => _CustomerPaymentHistoryPageState();
}

class _CustomerPaymentHistoryPageState extends State<CustomerPaymentHistoryPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _payments = const [];
  List<Map<String, dynamic>> _drafts = const [];
  bool _loading = false;
  bool _loadingMorePayments = false;
  bool _loadingMoreDrafts = false;
  bool _hasMorePayments = false;
  bool _hasMoreDrafts = false;
  int _paymentOffset = 0;
  int _draftOffset = 0;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final query = _search.text.trim().isEmpty ? null : _search.text.trim();
      final results = await Future.wait([
        widget.api.fetchCustomerPayments(search: query, start: 0),
        widget.api.fetchDraftCustomerPayments(search: query, start: 0),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _payments = results[0];
        _drafts = results[1];
        _paymentOffset = _payments.length;
        _draftOffset = _drafts.length;
        _hasMorePayments = _payments.length == FrappeApi.pageSize;
        _hasMoreDrafts = _drafts.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMorePayments({required bool drafts}) async {
    if (_loading || (drafts ? _loadingMoreDrafts || !_hasMoreDrafts : _loadingMorePayments || !_hasMorePayments)) {
      return;
    }
    setState(() {
      if (drafts) {
        _loadingMoreDrafts = true;
      } else {
        _loadingMorePayments = true;
      }
    });
    try {
      final query = _search.text.trim().isEmpty ? null : _search.text.trim();
      final page = drafts
          ? await widget.api.fetchDraftCustomerPayments(search: query, start: _draftOffset)
          : await widget.api.fetchCustomerPayments(search: query, start: _paymentOffset);
      if (!mounted) return;
      setState(() {
        if (drafts) {
          _drafts = [..._drafts, ...page];
          _draftOffset += page.length;
          _hasMoreDrafts = page.length == FrappeApi.pageSize;
        } else {
          _payments = [..._payments, ...page];
          _paymentOffset += page.length;
          _hasMorePayments = page.length == FrappeApi.pageSize;
        }
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() {
          if (drafts) {
            _loadingMoreDrafts = false;
          } else {
            _loadingMorePayments = false;
          }
        });
      }
    }
  }

  Future<void> _showDraft(String name) async {
    try {
      final draft = await widget.api.fetchCustomerPaymentDraftDocument(name);
      if (!mounted) return;
      final refs = (draft['references'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      final submit = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('مسودة سند قبض • $name'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('العميل: ${draft['party_name'] ?? draft['party'] ?? '—'}'),
            Text('الشركة: ${draft['company'] ?? '—'}'),
            Text('التاريخ: ${draft['posting_date'] ?? '—'}'),
            Text('حساب التحصيل: ${draft['paid_to'] ?? '—'}'),
            Text('المبلغ: ${draft['paid_amount'] ?? '—'} ${draft['paid_to_account_currency'] ?? ''}'),
            const Divider(),
            Text('إحالات الفواتير (${refs.length})'),
            ...refs.map((row) => ListTile(
              dense: true,
              title: Text('${row['reference_doctype'] ?? ''} • ${row['reference_name'] ?? ''}'),
              trailing: Text((row['allocated_amount'] ?? 0).toString()),
            )),
            const Text('سيعيد التطبيق قراءة المسودة من ERPNext قبل طلب الترحيل.'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إغلاق')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('ترحيل المسودة')),
          ],
        ),
      );
      if (submit != true || !mounted) return;
      final result = await widget.api.submitCustomerPaymentDraft(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ترحيل سند القبض ${result['name']}.')));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _showPayment(String name) async {
    try {
      final payment = await widget.api.fetchCustomerPaymentDocument(name);
      if (!mounted) return;
      final refs = (payment['references'] as List).whereType<Map<String, dynamic>>().toList();
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(shrinkWrap: true, children: [
            Text('سند قبض العميل • $name', style: Theme.of(context).textTheme.titleLarge),
            Text('العميل: ${payment['party_name'] ?? payment['party'] ?? '—'}'),
            Text('الشركة: ${payment['company'] ?? '—'}'),
            Text('التاريخ: ${payment['posting_date'] ?? '—'}'),
            Text('حساب التحصيل: ${payment['paid_to'] ?? '—'}'),
            Text('المبلغ: ${payment['paid_amount'] ?? '—'} ${payment['paid_to_account_currency'] ?? ''}'),
            const Divider(),
            Text('توزيع الدفعة على الفواتير (${refs.length})', style: Theme.of(context).textTheme.titleMedium),
            if (refs.isEmpty) const ListTile(title: Text('لا توجد إحالات فواتير في هذا السند.')),
            ...refs.map((row) => ListTile(
              leading: const Icon(Icons.link_outlined),
              title: Text((row['reference_name'] ?? '—').toString()),
              subtitle: Text((row['reference_doctype'] ?? '—').toString()),
              trailing: Text((row['allocated_amount'] ?? 0).toString()),
            )),
          ]),
        )),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل دفعات العملاء'), actions: [
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _search, textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(labelText: 'بحث برقم السند أو العميل', suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.search))),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Card(child: ListTile(
          leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل سجل دفعات العملاء'),
          subtitle: Text(_error!), trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        )),
        const SizedBox(height: 16),
        Text('مسودات سندات القبض (${_drafts.length})', style: Theme.of(context).textTheme.titleMedium),
        if (_drafts.isEmpty && !_loading) const ListTile(title: Text('لا توجد مسودات دفعات عملاء.')),
        ..._drafts.map((row) => Card(child: ListTile(
          leading: const Icon(Icons.pending_actions_outlined), title: Text((row['name'] ?? '—').toString()),
          subtitle: Text('${row['party_name'] ?? row['party'] ?? 'عميل غير محدد'} • ${row['posting_date'] ?? '—'} • مسودة'),
          trailing: Text((row['paid_amount'] ?? 0).toString()), onTap: () => _showDraft(row['name'].toString()),
        ))),
        if (_hasMoreDrafts || _loadingMoreDrafts)
          Center(child: TextButton.icon(
            onPressed: _loadingMoreDrafts ? null : () => _loadMorePayments(drafts: true),
            icon: _loadingMoreDrafts ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
            label: const Text('تحميل مسودات إضافية'),
          )),
        const Divider(height: 32),
        Text('سجل سندات القبض المرحلة (${_payments.length})', style: Theme.of(context).textTheme.titleMedium),
        if (_payments.isEmpty && !_loading) const ListTile(title: Text('لا توجد دفعات عملاء ظاهرة.')),
        ..._payments.map((row) => Card(child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined), title: Text((row['name'] ?? '—').toString()),
          subtitle: Text('${row['party_name'] ?? row['party'] ?? 'عميل غير محدد'} • ${row['posting_date'] ?? '—'}\nحساب التحصيل: ${row['paid_to'] ?? '—'}'),
          isThreeLine: true, trailing: Text((row['paid_amount'] ?? 0).toString()),
          onTap: () => _showPayment(row['name'].toString()),
        ))),
        if (_hasMorePayments || _loadingMorePayments)
          Center(child: TextButton.icon(
            onPressed: _loadingMorePayments ? null : () => _loadMorePayments(drafts: false),
            icon: _loadingMorePayments ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
            label: const Text('تحميل دفعات إضافية'),
          )),
      ]),
    );
  }
}
