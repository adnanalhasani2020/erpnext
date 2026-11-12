import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';
import 'workspace_web_page.dart';

class BankReconciliationPage extends StatefulWidget {
  const BankReconciliationPage({
    super.key,
    required this.api,
    required this.companies,
    this.initialDoctype,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;
  final String? initialDoctype;

  @override
  State<BankReconciliationPage> createState() => _BankReconciliationPageState();
}

class _BankReconciliationPageState extends State<BankReconciliationPage> {
  String? _company;
  String? _bankAccount;
  List<core.Map<String, dynamic>> _accounts = [];
  List<core.Map<String, dynamic>> _transactions = [];
  final _fromDate = TextEditingController();
  final _toDate = TextEditingController();
  final _balanceDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  final _statementBalance = TextEditingController();
  bool _loadingAccounts = false;
  bool _loadingTransactions = false;
  bool _loadingMoreTransactions = false;
  bool _hasMoreTransactions = false;
  int _transactionOffset = 0;
  bool _matching = false;
  bool _loadingBalances = false;
  bool _importingStatement = false;
  bool _savingStatementBalance = false;
  String? _statementImportName;
  List<core.Map<String, dynamic>> _statementImports = [];
  final Map<String, List<core.Map<String, dynamic>>> _statementImportLogs = {};
  final Set<String> _loadingImportLogs = <String>{};
  bool _loadingStatementImports = false;
  bool _loadingMoreStatementImports = false;
  bool _hasMoreStatementImports = false;
  int _statementImportOffset = 0;
  int _statementImportGeneration = 0;
  core.Map<String, dynamic>? _savedStatementBalance;
  core.Map<String, dynamic>? _balances;
  String? _error;
  int _generation = 0;
  int _accountGeneration = 0;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    _loadAccounts();
  }

  @override
  void dispose() {
    _fromDate.dispose();
    _toDate.dispose();
    _balanceDate.dispose();
    _statementBalance.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final company = _company;
    if (company == null || company.isEmpty) return;
    final generation = ++_accountGeneration;
    // Invalidate any transaction request from the previously selected account.
    ++_generation;
    setState(() {
      _loadingAccounts = true;
      _loadingTransactions = false;
      _accounts = [];
      _transactions = [];
      _bankAccount = null;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchBankAccounts(company: company);
      if (!mounted || generation != _accountGeneration) return;
      setState(() {
        _accounts = rows;
        _bankAccount = rows.isEmpty ? null : rows.first['name']?.toString();
      });
      if (rows.isNotEmpty) {
        await _loadTransactions();
        await _loadBalances();
        await _loadStatementImports();
      }
    } catch (error) {
      if (mounted && generation == _accountGeneration) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && generation == _accountGeneration) {
        setState(() => _loadingAccounts = false);
      }
    }
  }

  Future<void> _loadTransactions({bool more = false}) async {
    final company = _company;
    final account = _bankAccount;
    if (company == null || account == null || account.isEmpty ||
        _loadingTransactions || _loadingMoreTransactions ||
        (more && !_hasMoreTransactions)) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      if (more) {
        _loadingMoreTransactions = true;
      } else {
        _loadingTransactions = true;
        _transactions = [];
        _transactionOffset = 0;
        _hasMoreTransactions = false;
      }
      _error = null;
    });
    try {
      final rows = await widget.api.fetchBankTransactions(
        bankAccount: account,
        company: company,
        fromDate: _fromDate.text,
        toDate: _toDate.text,
        start: more ? _transactionOffset : 0,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (more) {
          _transactions.addAll(rows);
        } else {
          _transactions = rows;
        }
        _transactionOffset += rows.length;
        _hasMoreTransactions = rows.length == 100;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loadingTransactions = false;
          _loadingMoreTransactions = false;
        });
      }
    }
  }

  Future<void> _loadBalances() async {
    final company = _company;
    final account = _bankAccount;
    if (company == null || account == null || account.isEmpty) return;
    setState(() => _loadingBalances = true);
    try {
      final result = await widget.api.fetchBankReconciliationBalances(
        bankAccount: account,
        company: company,
        date: _balanceDate.text,
      );
      if (!mounted || account != _bankAccount || company != _company) return;
      final saved = await widget.api.fetchLatestBankStatementClosingBalance(
        bankAccount: account, company: company,
      );
      if (!mounted || account != _bankAccount || company != _company) return;
      setState(() {
        _balances = result;
        _savedStatementBalance = saved;
        if (saved != null) _statementBalance.text = saved['closing_balance']?.toString() ?? '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingBalances = false);
    }
  }


  Future<void> _importBankStatement() async {
    if (_importingStatement || _company == null || _bankAccount == null) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: const ['csv', 'xlsx', 'xls', 'txt', 'mt940', '940', 'sta'],
        withData: true, allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw const FormatException('تعذر قراءة محتوى الملف المختار.');
      setState(() { _importingStatement = true; _error = null; });
      final result = await widget.api.createBankStatementImportPreview(
        bankAccount: _bankAccount!, company: _company!,
        fileName: file.name, fileBytes: bytes,
      );
      if (!mounted) return;
      final preview = result['preview'] as core.Map<String, dynamic>;
      final rowCount = int.tryParse(preview['total_number_of_rows']?.toString() ?? '') ?? 0;
      final warnings = result['warnings'] as List;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('معاينة كشف البنك'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
            children: [
              Text('المستند: ${result['name']}'),
              Text('الصفوف التي قرأها ERPNext: $rowCount'),
              Text('الأعمدة: ${(result['columns'] as List).join('، ')}'),
              if (warnings.isNotEmpty) ...[
                Text('تحذيرات المعاينة (${warnings.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                ...warnings.take(12).map((warning) => Text('• ${warning is core.Map ? (warning['message'] ?? warning) : warning}')),
                if (warnings.length > 12)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: dialogContext,
                        builder: (warningsContext) => AlertDialog(
                          title: Text('كل تحذيرات المعاينة (${warnings.length})'),
                          content: SizedBox(
                            width: 520,
                            height: 420,
                            child: ListView.separated(
                              itemCount: warnings.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final warning = warnings[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Text('• ${warning is core.Map ? (warning['message'] ?? warning) : warning}'),
                                );
                              },
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(warningsContext),
                              child: const Text('إغلاق'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.list_alt),
                      label: Text('عرض جميع التحذيرات (${warnings.length})'),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              const Text('سيُنشئ ERPNext حركات Bank Transaction بعد التأكيد. يلزم إعداد مطابقة أعمدة البنك في سجل Bank.'),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: rowCount == 0 ? null : () => Navigator.pop(dialogContext, true), child: const Text('ابدأ الاستيراد')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final started = await widget.api.startBankStatementImport(result['name'].toString());
      if (!mounted) return;
      setState(() => _statementImportName = result['name'].toString());
      await _loadStatementImports();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت جدولة الاستيراد في ERPNext: ${started['job_id']}')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _importingStatement = false);
    }
  }

  Future<void> _loadStatementImports({bool more = false}) async {
    final company = _company;
    final account = _bankAccount;
    if (company == null || account == null || account.isEmpty ||
        _loadingMoreStatementImports || (more && (!_hasMoreStatementImports || _loadingStatementImports))) return;
    final generation = ++_statementImportGeneration;
    setState(() {
      if (more) {
        _loadingMoreStatementImports = true;
      } else {
        _loadingStatementImports = true;
        _statementImportOffset = 0;
        _hasMoreStatementImports = false;
        _statementImports = [];
        _statementImportLogs.clear();
      }
    });
    try {
      final rows = await widget.api.fetchBankStatementImports(
        bankAccount: account,
        company: company,
        start: more ? _statementImportOffset : 0,
      );
      if (!mounted || generation != _statementImportGeneration ||
          account != _bankAccount || company != _company) return;
      setState(() {
        if (more) {
          _statementImports.addAll(rows);
        } else {
          _statementImports = rows;
        }
        _statementImportOffset += rows.length;
        _hasMoreStatementImports = rows.length == 25;
      });
    } catch (error) {
      if (mounted && generation == _statementImportGeneration &&
          account == _bankAccount && company == _company) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && generation == _statementImportGeneration) {
        setState(() {
          _loadingStatementImports = false;
          _loadingMoreStatementImports = false;
        });
      }
    }
  }

  Future<void> _checkStatementImport(String id) async {
    if (id.trim().isEmpty) return;
    try {
      final status = await widget.api.fetchBankStatementImportStatus(id);
      if (!mounted) return;
      final message = 'حالة الاستيراد: ${status['status'] ?? 'غير معروفة'}'
          ' • ناجح: ${status['success'] ?? 0}'
          ' • فاشل: ${status['failed'] ?? 0}'
          ' • الإجمالي: ${status['total_records'] ?? 0}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _loadStatementImports();
      if (status['status'] == 'Success' || status['status'] == 'Partial Success') {
        await _loadTransactions();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadStatementImportLogs(String id) async {
    if (!_loadingImportLogs.add(id)) return;
    setState(() => _error = null);
    try {
      final rows = await widget.api.fetchBankStatementImportLogs(id);
      if (!mounted) return;
      setState(() => _statementImportLogs[id] = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingImportLogs.remove(id));
    }
  }

  Future<void> _saveClosingBalance() async {
    if (_savingStatementBalance || _company == null || _bankAccount == null) return;
    final value = double.tryParse(_statementBalance.text.trim());
    if (value == null || !value.isFinite) {
      setState(() => _error = 'أدخل رصيد كشف ختامياً رقمياً صحيحاً قبل الحفظ.');
      return;
    }
    setState(() { _savingStatementBalance = true; _error = null; });
    try {
      await widget.api.saveBankStatementClosingBalance(
        bankAccount: _bankAccount!, company: _company!,
        statementDate: _balanceDate.text, closingBalance: value,
        importName: _statementImportName,
      );
      final saved = await widget.api.fetchLatestBankStatementClosingBalance(
        bankAccount: _bankAccount!, company: _company!,
      );
      if (!mounted) return;
      setState(() => _savedStatementBalance = saved);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ رصيد كشف البنك في سجل الحساب على ERPNext.')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingStatementBalance = false);
    }
  }

  double get _balanceDifference => _statementBalance.text.trim().isEmpty || _balances == null
      ? 0
      : _number(_statementBalance.text) - _number(_balances!['system_balance']);

  double _number(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;

  String _money(dynamic value, dynamic currency) =>
      '${_number(value).toStringAsFixed(2)} ${currency ?? ''}'.trim();

  Future<void> _matchTransaction(core.Map<String, dynamic> transaction) async {
    if (_matching) return;
    final company = _company;
    final account = _bankAccount;
    final name = transaction['name']?.toString() ?? '';
    if (company == null || account == null || name.isEmpty) return;
    setState(() {
      _matching = true;
      _error = null;
    });
    try {
      final candidates = await widget.api.fetchLinkedBankVouchers(
        transactionName: name,
        bankAccount: account,
        company: company,
        fromDate: _fromDate.text,
        toDate: _toDate.text,
      );
      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يجد ERPNext مستندات مرشحة للمطابقة.')),
        );
        return;
      }
      final selected = <String>{};
      final selectedAmounts = <String, double>{};
      final amountControllers = <String, TextEditingController>{};
      final unallocated = _number(transaction['unallocated_amount']);
      final result = await showDialog<List<core.Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, refresh) {
            final total = selectedAmounts.entries
                .where((entry) => selected.contains(entry.key))
                .fold<double>(0, (sum, entry) => sum + entry.value);
            final validAmounts = candidates.where((row) =>
              selected.contains('${row['doctype']}|${row['name']}')
            ).every((row) {
              final key = '${row['doctype']}|${row['name']}';
              final amount = selectedAmounts[key] ?? 0;
              return amount > 0 && amount <= _number(row['paid_amount']) + 0.000001;
            });
            final canProceed = selected.isNotEmpty && validAmounts && total <= unallocated + 0.000001;
            return AlertDialog(
              title: Text('مطابقة حركة $name'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('المبلغ غير المخصص: ${_money(unallocated, transaction['currency'])}'),
                      Text('المحدد: ${_money(total, transaction['currency'])}'),
                      const Divider(),
                      ...candidates.map((row) {
                        final doctype = row['doctype']?.toString() ?? '';
                        final id = row['name']?.toString() ?? '';
                        final key = '$doctype|$id';
                        final amount = _number(row['paid_amount']);
                        final isSelected = selected.contains(key);
                        final controller = amountControllers.putIfAbsent(
                          key, () => TextEditingController(text: amount.toStringAsFixed(2)),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CheckboxListTile(
                              dense: true,
                              value: isSelected,
                              title: Text('$doctype • $id'),
                              subtitle: Text(
                                '${row['party'] ?? ''} • ${row['posting_date'] ?? ''} • المتاح: ${_money(amount, row['currency'] ?? transaction['currency'])} • تطابق: ${row['rank'] ?? 0}',
                              ),
                              onChanged: !isSelected && (amount <= 0 || total >= unallocated - 0.000001)
                                  ? null
                                  : (checked) => refresh(() {
                                      if (checked == true) {
                                        final remaining = (unallocated - total).clamp(0.0, unallocated).toDouble();
                                        final initial = amount < remaining ? amount : remaining;
                                        selected.add(key);
                                        selectedAmounts[key] = initial;
                                        controller.text = initial.toStringAsFixed(2);
                                      } else {
                                        selected.remove(key);
                                        selectedAmounts.remove(key);
                                      }
                                    }),
                            ),
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(start: 48, end: 12, bottom: 10),
                                child: TextField(
                                  controller: controller,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'المبلغ المراد تخصيصه (المتاح ${amount.toStringAsFixed(2)})',
                                    isDense: true,
                                  ),
                                  onChanged: (value) => refresh(() {
                                    selectedAmounts[key] = double.tryParse(value.trim()) ?? 0;
                                  }),
                                ),
                              ),
                          ],
                        );
                      }),
                      const SizedBox(height: 8),
                      if (!validAmounts || total > unallocated + 0.000001)
                        const Text('راجع مبالغ التخصيص؛ يجب أن تكون موجبة وألا تتجاوز رصيد المستند أو المبلغ غير المخصص في حركة البنك.', style: TextStyle(color: Colors.red)),
                      const Text('يمكن تخصيص جزء من رصيد المستند. المطابقة تربط المستندات بحركة البنك الموجودة فقط ولا تنشئ قيداً أو دفعة جديدة.'),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: !canProceed ? null : () {
                    final rows = candidates.where((row) =>
                      selected.contains('${row['doctype']}|${row['name']}')
                    ).map((row) {
                      final key = '${row['doctype']}|${row['name']}';
                      return <String, dynamic>{
                        'payment_doctype': row['doctype'],
                        'payment_name': row['name'],
                        'amount': selectedAmounts[key],
                      };
                    }).toList();
                    Navigator.pop(dialogContext, rows);
                  },
                  child: const Text('متابعة للمراجعة'),
                ),
              ],
            );
          },
        ),
      );
      for (final controller in amountControllers.values) {
        controller.dispose();
      }
      if (result == null || result.isEmpty || !mounted) return;
      final total = result.fold<double>(0, (sum, row) => sum + _number(row['amount']));
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد مطابقة البنك'),
          content: Text(
            'سيتم ربط ${result.length} مستنداً بمبلغ ${_money(total, transaction['currency'])} '
            'بحركة البنك $name. هذه العملية تحدث تخصيصات Bank Transaction في ERPNext.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد المطابقة'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.api.reconcileBankTransaction(
        transactionName: name,
        bankAccount: account,
        company: company,
        vouchers: result,
        fromDate: _fromDate.text,
        toDate: _toDate.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكد ERPNext تحديث حركة البنك بالمطابقة المحددة.')),
      );
      await _loadTransactions();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _matching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialDoctype == 'Bank Statement Import' ? 'استيراد كشوف البنك' : widget.initialDoctype == 'Bank Transaction' ? 'الحركات البنكية' : 'التسوية البنكية'),
        actions: [
          if (widget.initialDoctype != null)
            IconButton(
              tooltip: 'فتح شاشة ERPNext الأصلية',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => WorkspaceWebPage(
                  api: widget.api,
                  title: widget.initialDoctype!,
                  linkType: 'DocTypeList',
                  target: widget.initialDoctype!,
                ),
              )),
              icon: const Icon(Icons.arrow_forward),
            ),
          IconButton(
            tooltip: widget.initialDoctype == 'Bank Statement Import' ? 'تحديث سجل الاستيراد' : 'تحديث الحركات',
            onPressed: _loadingAccounts || _loadingTransactions || _loadingStatementImports || _matching
                ? null
                : widget.initialDoctype == 'Bank Statement Import'
                    ? () => _loadStatementImports()
                    : _loadTransactions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.companies.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد شركات متاحة.')))
          else
            DropdownButtonFormField<String>(
              initialValue: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((company) => DropdownMenuItem(
                value: company.name,
                child: Text(company.name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _loadingAccounts || _matching ? null : (value) {
                setState(() => _company = value);
                _loadAccounts();
              },
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _bankAccount,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الحساب البنكي'),
            items: _accounts.map((row) => DropdownMenuItem(
              value: row['name']?.toString(),
              child: Text(
                '${row['name']} • ${row['account'] ?? ''}',
                overflow: TextOverflow.ellipsis,
              ),
            )).toList(),
            onChanged: _loadingAccounts || _matching ? null : (value) {
              setState(() {
                _statementImportGeneration++;
                _loadingStatementImports = false;
                _loadingMoreStatementImports = false;
                _bankAccount = value;
                _balances = null;
                _savedStatementBalance = null;
                _statementBalance.clear();
                _statementImportName = null;
                _statementImports = [];
                _statementImportLogs.clear();
              });
              _loadTransactions();
              _loadBalances();
              _loadStatementImports();
            },
          ),
          const SizedBox(height: 10),
          if (widget.initialDoctype != 'Bank Transaction')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('استيراد كشف البنك', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _importingStatement || _loadingAccounts ? null : _importBankStatement,
                  icon: _importingStatement
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file),
                  label: Text(_importingStatement ? 'جارٍ رفع ومعاينة الملف…' : 'اختيار ملف كشف (CSV / Excel / MT940)'),
                ),
                if (_statementImportName != null)
                  Text('آخر مستند أُنشئ: $_statementImportName'),
                const Divider(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text('سجل كشوف البنك المستوردة', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      tooltip: 'تحديث سجل الاستيراد',
                      onPressed: _loadingStatementImports ? null : () => _loadStatementImports(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_loadingStatementImports) const LinearProgressIndicator(),
                if (!_loadingStatementImports && _statementImports.isEmpty)
                  const Text('لا توجد ملفات استيراد محفوظة لهذا الحساب.'),
                ..._statementImports.map((row) {
                  final id = row['name']?.toString() ?? '';
                  final logs = _statementImportLogs[id] ?? const <core.Map<String, dynamic>>[];
                  final loadingLogs = _loadingImportLogs.contains(id);
                  return ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(id, textDirection: TextDirection.ltr),
                    subtitle: Text(
                      '${row['status'] ?? 'غير محدد'} • ${row['reference_doctype'] ?? ''} • ${row['import_type'] ?? ''}',
                    ),
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('الملف: ${row['import_file'] ?? 'غير متاح'}'),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: id.isEmpty ? null : () => _checkStatementImport(id),
                            icon: const Icon(Icons.sync),
                            label: const Text('تحديث الحالة'),
                          ),
                          TextButton.icon(
                            onPressed: id.isEmpty || loadingLogs ? null : () => _loadStatementImportLogs(id),
                            icon: loadingLogs
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.receipt_long_outlined),
                            label: const Text('عرض سجل الصفوف'),
                          ),
                        ],
                      ),
                      if (logs.isNotEmpty)
                        ...logs.map((log) {
                          final success = log['success'] == 1 || log['success'] == true;
                          return ListTile(
                            dense: true,
                            leading: Icon(success ? Icons.check_circle_outline : Icons.error_outline,
                              color: success ? Colors.green : Colors.red),
                            title: Text(log['docname']?.toString().isNotEmpty == true
                                ? log['docname'].toString()
                                : success ? 'تم استيراد الصف' : 'صف لم يُستورد'),
                            subtitle: Text(
                              (log['exception'] ?? log['messages'] ?? '').toString(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      if (logs.isEmpty && !loadingLogs)
                        const Padding(
                          padding: EdgeInsetsDirectional.only(start: 12, bottom: 8),
                          child: Text('لم تُحمّل تفاصيل الصفوف بعد.'),
                        ),
                    ],
                  );
                }),
                if (_hasMoreStatementImports || _loadingMoreStatementImports)
                  TextButton(
                    onPressed: _loadingMoreStatementImports ? null : () => _loadStatementImports(more: true),
                    child: Text(_loadingMoreStatementImports ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من كشوف البنك'),
                  ),
              ]),
            ),
          ),
          if (widget.initialDoctype != 'Bank Statement Import') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('مطابقة رصيد كشف البنك', style: TextStyle(fontWeight: FontWeight.bold))),
                      IconButton(
                        tooltip: 'تحديث الأرصدة',
                        onPressed: _loadingBalances ? null : _loadBalances,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _balanceDate,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(labelText: 'تاريخ المطابقة YYYY-MM-DD'),
                    onSubmitted: (_) => _loadBalances(),
                  ),
                  if (_loadingBalances) const LinearProgressIndicator(),
                  if (_balances != null) ...[
                    const SizedBox(height: 8),
                    Text('رصيد النظام حسب ERPNext: ${_number(_balances!['system_balance']).toStringAsFixed(2)}'),
                    if (_statementBalance.text.trim().isNotEmpty)
                      Text('فرق رصيد الكشف المدخل عن النظام: ${_balanceDifference.toStringAsFixed(2)}'),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _statementBalance,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'رصيد كشف الحساب الختامي (للمقارنة اليدوية)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  FilledButton.icon(
                    onPressed: _savingStatementBalance || _loadingBalances ? null : _saveClosingBalance,
                    icon: _savingStatementBalance
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('حفظ رصيد الكشف الختامي في ERPNext'),
                  ),
                  if (_savedStatementBalance != null)
                    Text('آخر رصيد محفوظ: ${_savedStatementBalance!['statement_date']} • ${_savedStatementBalance!['closing_balance']}'),
                  const Text('يحفظ الرصيد كسجل تدقيقي في سجل الحساب البنكي، ولا ينشئ قيداً محاسبياً.', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          ExpansionTile(
            title: const Text('تصفية الحركات بالتاريخ'),
            children: [
              TextField(
                controller: _fromDate,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'من تاريخ YYYY-MM-DD'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _toDate,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'إلى تاريخ YYYY-MM-DD'),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: _loadingTransactions || _matching ? null : _loadTransactions,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('تطبيق الفلاتر'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingAccounts || _loadingTransactions || _matching)
            const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          if (!_loadingTransactions && _transactions.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_balance_outlined),
                title: Text('لا توجد حركات بنكية غير مخصصة ضمن الفترة المحددة.'),
              ),
            ),
          ..._transactions.map((row) {
            final deposit = _number(row['deposit']);
            final withdrawal = _number(row['withdrawal']);
            final amount = deposit > 0 ? deposit : withdrawal;
            final label = deposit > 0 ? 'إيداع' : 'سحب';
            return Card(
              child: ListTile(
                leading: Icon(
                  deposit > 0 ? Icons.south_west : Icons.north_east,
                  color: deposit > 0 ? Colors.green : Colors.orange,
                ),
                title: Text('${row['name'] ?? ''} • $label'),
                subtitle: Text(
                  '${row['date'] ?? ''} • ${row['description'] ?? ''}\n'
                  'غير مخصص: ${_money(row['unallocated_amount'], row['currency'])}',
                ),
                isThreeLine: true,
                trailing: Text(_money(amount, row['currency'])),
                onTap: _matching ? null : () => _matchTransaction(row),
              ),
            );
          }),
          if (_hasMoreTransactions || _loadingMoreTransactions)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: _loadingMoreTransactions || _loadingTransactions
                    ? null : () => _loadTransactions(more: true),
                icon: const Icon(Icons.expand_more),
                label: Text(_loadingMoreTransactions ? 'جارٍ تحميل المزيد...' : 'تحميل حركات إضافية'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
