import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class PaymentReconciliationPage extends StatefulWidget {
  const PaymentReconciliationPage({
    super.key,
    required this.api,
    required this.companies,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;

  @override
  State<PaymentReconciliationPage> createState() => _PaymentReconciliationPageState();
}

class _PaymentReconciliationPageState extends State<PaymentReconciliationPage> {
  final _partyController = TextEditingController();
  final _invoiceFromController = TextEditingController();
  final _invoiceToController = TextEditingController();
  final _paymentFromController = TextEditingController();
  final _paymentToController = TextEditingController();

  String? _company;
  String _partyType = 'Customer';
  String? _account;
  List<Map<String, dynamic>> _accounts = const [];
  Map<String, dynamic>? _document;
  bool _loadingAccounts = false;
  bool _loadingEntries = false;
  bool _allocating = false;
  bool _reconciling = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    if (_company != null) _loadAccounts();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _partyController.dispose();
    _invoiceFromController.dispose();
    _invoiceToController.dispose();
    _paymentFromController.dispose();
    _paymentToController.dispose();
    super.dispose();
  }

  bool get _busy => _loadingAccounts || _loadingEntries || _allocating || _reconciling;

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _loadAccounts() async {
    final company = _company;
    if (company == null) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loadingAccounts = true;
      _error = null;
      _account = null;
      _accounts = const [];
      _document = null;
    });
    try {
      final rows = await widget.api.fetchReconciliationAccounts(
        company: company,
        partyType: _partyType,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _accounts = rows;
        _account = rows.isEmpty ? null : rows.first['name']?.toString();
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingAccounts = false);
      }
    }
  }

  Future<void> _loadEntries() async {
    final company = _company;
    final party = _partyController.text.trim();
    final account = _account;
    if (company == null || party.isEmpty || account == null || account.isEmpty) {
      setState(() => _error = 'حدد الشركة والحساب وأدخل رمز العميل أو المورد.');
      return;
    }
    setState(() {
      _loadingEntries = true;
      _error = null;
      _document = null;
    });
    try {
      final document = await widget.api.fetchUnreconciledPaymentEntries(
        company: company,
        partyType: _partyType,
        party: party,
        receivablePayableAccount: account,
        fromInvoiceDate: _invoiceFromController.text.trim(),
        toInvoiceDate: _invoiceToController.text.trim(),
        fromPaymentDate: _paymentFromController.text.trim(),
        toPaymentDate: _paymentToController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _document = document);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  Future<void> _previewAllocation() async {
    final document = _document;
    if (document == null || _busy) return;
    setState(() {
      _allocating = true;
      _error = null;
    });
    try {
      final result = await widget.api.allocatePaymentReconciliation(document);
      if (!mounted) return;
      setState(() => _document = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _allocating = false);
    }
  }

  Future<void> _confirmReconciliation() async {
    final document = _document;
    final allocations = document?['allocation'];
    if (document == null || allocations is! List || allocations.isEmpty || _busy) return;
    final total = allocations.fold<double>(
      0,
      (sum, row) => sum + (row is Map ? _number(row['allocated_amount']) : 0),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تسوية المدفوعات'),
        content: Text(
          'سيتم ربط ${allocations.length} تخصيصات بمبلغ إجمالي ${total.toStringAsFixed(2)} '
          'على ${document['party_type']} ${document['party']} في ERPNext. '
          'لن يتم إنشاء حركة بنكية جديدة. راجع التخصيصات قبل المتابعة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('مراجعة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد التسوية'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _reconciling = true;
      _error = null;
    });
    try {
      final result = await widget.api.reconcilePaymentAllocations(document);
      if (!mounted) return;
      setState(() => _document = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكد ERPNext تنفيذ التسوية. أعد جلب السجلات لمراجعة المتبقي.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 18, bottom: 8),
    child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
  );

  Widget _entryCard({
    required String title,
    required String subtitle,
    required String amount,
    IconData icon = Icons.receipt_long_outlined,
  }) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final invoices = document?['invoices'] is List
        ? (document!['invoices'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final payments = document?['payments'] is List
        ? (document!['payments'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final allocations = document?['allocation'] is List
        ? (document!['allocation'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(title: const Text('تسوية المدفوعات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.companies.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد شركات متاحة.')))
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((company) => DropdownMenuItem(
                value: company.name,
                child: Text(company.name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _busy ? null : (value) {
                setState(() => _company = value);
                _loadAccounts();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _partyType,
              decoration: const InputDecoration(labelText: 'نوع الطرف'),
              items: const [
                DropdownMenuItem(value: 'Customer', child: Text('عميل')),
                DropdownMenuItem(value: 'Supplier', child: Text('مورد')),
              ],
              onChanged: _busy ? null : (value) {
                if (value == null) return;
                setState(() {
                  _partyType = value;
                  _document = null;
                });
                _loadAccounts();
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _partyController,
              enabled: !_busy,
              onChanged: (_) {
                if (_document != null) setState(() => _document = null);
              },
              decoration: InputDecoration(
                labelText: _partyType == 'Customer' ? 'رمز العميل' : 'رمز المورد',
                hintText: _partyType == 'Customer' ? 'مثال: CUST-0001' : 'مثال: SUPP-0001',
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingAccounts) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              initialValue: _account,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'حساب الذمم'),
              items: _accounts.map((row) => DropdownMenuItem(
                value: row['name']?.toString(),
                child: Text(
                  '${row['name']} • ${row['account_currency'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              )).toList(),
              onChanged: _busy || _accounts.isEmpty ? null : (value) {
                setState(() {
                  _account = value;
                  _document = null;
                });
              },
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('فلاتر التاريخ'),
              children: [
                TextField(
                  controller: _invoiceFromController,
                  enabled: !_busy,
                  onChanged: (_) {
                    if (_document != null) setState(() => _document = null);
                  },
                  decoration: const InputDecoration(labelText: 'من تاريخ الفاتورة (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: _invoiceToController,
                  enabled: !_busy,
                  onChanged: (_) {
                    if (_document != null) setState(() => _document = null);
                  },
                  decoration: const InputDecoration(labelText: 'إلى تاريخ الفاتورة (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: _paymentFromController,
                  enabled: !_busy,
                  onChanged: (_) {
                    if (_document != null) setState(() => _document = null);
                  },
                  decoration: const InputDecoration(labelText: 'من تاريخ الدفعة (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: _paymentToController,
                  enabled: !_busy,
                  onChanged: (_) {
                    if (_document != null) setState(() => _document = null);
                  },
                  decoration: const InputDecoration(labelText: 'إلى تاريخ الدفعة (YYYY-MM-DD)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _accounts.isEmpty ? null : _loadEntries,
              icon: const Icon(Icons.search),
              label: Text(_loadingEntries ? 'جارٍ جلب السجلات...' : 'جلب الفواتير والمدفوعات غير المسواة'),
            ),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            if (_loadingEntries || _allocating || _reconciling)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(),
              ),
            if (document != null) ...[
              _sectionTitle('الفواتير غير المسواة (${invoices.length})'),
              if (invoices.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد فواتير مستحقة ضمن الفلاتر.')))
              else
                ...invoices.map((row) => _entryCard(
                  title: '${row['invoice_type'] ?? ''} • ${row['invoice_number'] ?? ''}',
                  subtitle: '${row['invoice_date'] ?? ''} • ${row['currency'] ?? ''}',
                  amount: _number(row['outstanding_amount']).toStringAsFixed(2),
                )),
              _sectionTitle('المدفوعات غير المخصصة (${payments.length})'),
              if (payments.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد مدفوعات غير مخصصة ضمن الفلاتر.')))
              else
                ...payments.map((row) => _entryCard(
                  title: '${row['reference_type'] ?? ''} • ${row['reference_name'] ?? ''}',
                  subtitle: '${row['posting_date'] ?? ''} • ${row['currency'] ?? ''}',
                  amount: _number(row['amount']).toStringAsFixed(2),
                  icon: Icons.payments_outlined,
                )),
              if (allocations.isEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy || invoices.isEmpty || payments.isEmpty ? null : _previewAllocation,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('معاينة التوزيع التلقائي حسب الأقدمية'),
                ),
              ] else ...[
                _sectionTitle('معاينة التخصيصات (${allocations.length})'),
                ...allocations.map((row) => _entryCard(
                  title: '${row['reference_type'] ?? ''} • ${row['reference_name'] ?? ''}',
                  subtitle: 'إلى ${row['invoice_type'] ?? ''} • ${row['invoice_number'] ?? ''}',
                  amount: _number(row['allocated_amount']).toStringAsFixed(2),
                  icon: Icons.compare_arrows_outlined,
                )),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _confirmReconciliation,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('تأكيد التخصيص وترحيل التسوية'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _loadEntries,
                  child: const Text('إلغاء المعاينة وإعادة جلب السجلات'),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
