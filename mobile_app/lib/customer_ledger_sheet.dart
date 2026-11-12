import 'dart:core';
import 'dart:core' as core;

import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class CustomerLedgerSheet extends StatefulWidget {
  const CustomerLedgerSheet({required this.api, required this.customer, required this.companies});

  final FrappeApi api;
  final ErpCustomer customer;
  final List<ErpCompany> companies;

  @override
  State<CustomerLedgerSheet> createState() => _CustomerLedgerSheetState();
}

class _CustomerLedgerSheetState extends State<CustomerLedgerSheet> {
  final List<core.Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _company;
  String? _error;
  final _fromDate = TextEditingController();
  final _toDate = TextEditingController();
  final _accountFilter = TextEditingController();
  final _voucherTypeFilter = TextEditingController();
  core.Map<String, dynamic> _opening = {'balance': 0.0};
  core.Map<String, dynamic> _periodTotals = {'debit': 0.0, 'credit': 0.0, 'balance': 0.0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loadingMore || (more && !_hasMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await widget.api.fetchCustomerLedger(
        customer: widget.customer.id,
        company: _company,
        fromDate: _fromDate.text,
        toDate: _toDate.text,
        account: _accountFilter.text,
        voucherType: _voucherTypeFilter.text,
        start: more ? _rows.length : 0,
      );
      if (!more) {
        if (_company == null) {
          if (mounted) {
            setState(() {
              _periodTotals = {'debit': 0.0, 'credit': 0.0, 'balance': 0.0};
              _opening = {'balance': 0.0};
            });
          }
        } else {
          final totals = await widget.api.fetchPartyLedgerTotals(
            partyType: 'Customer', party: widget.customer.id,
            company: _company, fromDate: _fromDate.text, toDate: _toDate.text,
            account: _accountFilter.text, voucherType: _voucherTypeFilter.text,
          );
          final opening = _fromDate.text.trim().isEmpty
              ? <String, dynamic>{'balance': 0.0}
              : await widget.api.fetchPartyLedgerOpeningBalance(
                  partyType: 'Customer', party: widget.customer.id,
                  company: _company, beforeDate: _fromDate.text,
                  account: _accountFilter.text, voucherType: _voucherTypeFilter.text,
                );
          if (mounted) setState(() { _periodTotals = totals; _opening = opening; });
        }
      }
      if (!mounted) return;
      setState(() {
        if (more) {
          _rows.addAll(page);
        } else {
          _rows
            ..clear()
            ..addAll(page);
        }
        _hasMore = page.length == FrappeApi.pageSize;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _fromDate.dispose();
    _toDate.dispose();
    _accountFilter.dispose();
    _voucherTypeFilter.dispose();
    super.dispose();
  }

  double _amount(core.Map<String, dynamic> row, String field) =>
      double.tryParse(row[field]?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كشف حساب العميل', style: Theme.of(context).textTheme.titleLarge),
                Text('${widget.customer.name} • ${widget.customer.id}'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _company ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الشركة'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('جميع الشركات')),
                    ...widget.companies.map((company) => DropdownMenuItem(
                      value: company.name,
                      child: Text(company.name),
                    )),
                  ],
                  onChanged: (_loading || _loadingMore) ? null : (value) {
                    setState(() => _company = value == null || value.isEmpty ? null : value);
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: _fromDate, keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(labelText: 'من تاريخ YYYY-MM-DD'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _toDate, keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(labelText: 'إلى تاريخ YYYY-MM-DD'))),
                ]),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('فلاتر متقدمة'),
                  children: [
                    TextField(
                      controller: _accountFilter,
                      decoration: const InputDecoration(
                        labelText: 'الحساب المحاسبي (اختياري)',
                        hintText: 'مثال: Accounts Receivable - CO',
                      ),
                    ),
                    TextField(
                      controller: _voucherTypeFilter,
                      decoration: const InputDecoration(
                        labelText: 'نوع المستند (اختياري)',
                        hintText: 'مثال: Sales Invoice أو Payment Entry',
                      ),
                    ),
                  ],
                ),
                Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(
                  onPressed: _loading || _loadingMore ? null : () => _load(),
                  icon: const Icon(Icons.filter_alt_outlined), label: const Text('تطبيق فترة الكشف'),
                )),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (_company == null)
                      const Text('اختر شركة لاحتساب الأرصدة؛ لا يتم جمع عملات شركات مختلفة.')
                    else ...[
                      Text('مدين الفترة: ${(_periodTotals['debit'] ?? 0)}'),
                      Text('دائن الفترة: ${(_periodTotals['credit'] ?? 0)}'),
                      Text('الرصيد الافتتاحي: ${(_opening['balance'] ?? 0)}'),
                      Text('الرصيد الختامي: ${((_opening['balance'] as num? ?? 0) + (_periodTotals['balance'] as num? ?? 0)).toStringAsFixed(2)}'),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton.icon(onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
              ]),
            ),
          Expanded(
            child: _rows.isEmpty
                ? Center(child: Text(_loading ? 'جارٍ تحميل كشف الحساب...' : 'لا توجد حركات حساب ظاهرة.'))
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final debitValue = _amount(row, 'debit');
                      final creditValue = _amount(row, 'credit');
                      return ListTile(
                        dense: true,
                        title: Text(row['voucher_no']?.toString() ?? row['name']?.toString() ?? 'قيد محاسبي'),
                        subtitle: Text([
                          row['posting_date']?.toString() ?? '',
                          row['voucher_type']?.toString() ?? '',
                          row['account']?.toString() ?? '',
                          row['company']?.toString() ?? '',
                          row['remarks']?.toString() ?? '',
                        ].where((value) => value.isNotEmpty).join(' • ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (debitValue != 0) Text('مدين ${debitValue.toStringAsFixed(2)}'),
                            if (creditValue != 0) Text('دائن ${creditValue.toStringAsFixed(2)}'),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_hasMore || _loadingMore)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton(
                onPressed: _loadingMore ? null : () => _load(more: true),
                child: Text(_loadingMore ? 'جارٍ التحميل...' : 'تحميل المزيد'),
              ),
            ),
        ],
      ),
    );
  }
}