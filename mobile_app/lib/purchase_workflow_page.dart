import 'dart:core';
import 'dart:core' as core;
// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';
import 'models/serial_batch_tracking.dart';

class PurchaseWorkflowPage extends StatefulWidget {
  const PurchaseWorkflowPage({super.key, required this.api, required this.companies, required this.suppliers, required this.items, required this.warehouses, this.initialInvoiceName, this.onChanged, this.initialSection});
  final FrappeApi api;
  final String? initialInvoiceName;
  final String? initialSection;
  final List<ErpCompany> companies;
  final List<ErpSupplier> suppliers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final VoidCallback? onChanged;
  @override State<PurchaseWorkflowPage> createState() => _PurchaseWorkflowPageState();
}

class _PurchaseWorkflowPageState extends State<PurchaseWorkflowPage> {
  bool _actionInProgress = false;


  Future<void> _runExclusive(Future<void> Function() action) async {
    if (_actionInProgress || !mounted) return;
    setState(() => _actionInProgress = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  bool _show(String section) => widget.initialSection == null || widget.initialSection == section;

  List<ErpPurchaseInvoice> rows = [];
  List<core.Map<String, dynamic>> purchaseOrders = [];
  int purchaseOrderOffset = 0;
  bool hasMorePurchaseOrders = false;
  bool loadingMorePurchaseOrders = false;
  List<core.Map<String, dynamic>> supplierPayments = [];
  List<core.Map<String, dynamic>> draftSupplierPayments = [];
  int draftPaymentOffset = 0;
  bool hasMoreDraftPayments = false;
  bool loadingMoreDraftPayments = false;
  List<core.Map<String, dynamic>> supplierLedger = [];
  String? selectedLedgerSupplier;
  String? selectedLedgerCompany;
  bool ledgerLoading = false;
  bool ledgerLoadingMore = false;
  bool ledgerHasMore = false;
  int ledgerOffset = 0;
  int ledgerRequestId = 0;
  String? ledgerError;
  bool loading = false;
  bool reloadPending = false;
  int listRequestId = 0;
  bool loadingMore = false;
  bool hasMore = false;
  bool loadingMorePayments = false;
  bool hasMorePayments = false;
  int offset = 0;
  int paymentOffset = 0;
  String? error;
  final search = TextEditingController();
  @override void initState() {
    super.initState();
    load();
    final initialName = widget.initialInvoiceName?.trim();
    if (initialName != null && initialName.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) details(initialName);
      });
    }
  }
  @override void dispose() { search.dispose(); super.dispose(); }
  Future<void> load() async {
    if (loading) {
      reloadPending = true;
      return;
    }
    final requestId = ++listRequestId;
    final query = search.text.trim().isEmpty ? null : search.text.trim();
    setState(() { loading = true; error = null; });
    final errors = <String>[];
    try {
      final result = await widget.api.fetchPurchaseInvoices(start: 0, search: query);
      if (mounted && requestId == listRequestId) {
        setState(() {
          rows = result;
          offset = result.length;
          hasMore = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (requestId == listRequestId) {
        errors.add('الفواتير: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    try {
      final result = await widget.api.fetchPurchaseOrderRecords(start: 0, search: query);
      if (mounted && requestId == listRequestId) {
        setState(() {
          purchaseOrders = result;
          purchaseOrderOffset = result.length;
          hasMorePurchaseOrders = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (requestId == listRequestId) {
        errors.add('أوامر الشراء: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    try {
      final result = await widget.api.fetchSupplierPayments(start: 0, search: query);
      if (mounted && requestId == listRequestId) {
        setState(() {
          supplierPayments = result;
          paymentOffset = result.length;
          hasMorePayments = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (requestId == listRequestId) {
        errors.add('دفعات الموردين: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    try {
      final result = await widget.api.fetchDraftSupplierPayments(start: 0, search: query);
      if (mounted && requestId == listRequestId) {
        setState(() {
          draftSupplierPayments = result;
          draftPaymentOffset = result.length;
          hasMoreDraftPayments = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (requestId == listRequestId) {
        setState(() {
          draftSupplierPayments = [];
          draftPaymentOffset = 0;
          hasMoreDraftPayments = false;
        });
        errors.add('مسودات دفعات الموردين: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (mounted && requestId == listRequestId) {
      setState(() {
        error = errors.isEmpty ? null : errors.join('\n');
        loading = false;
      });
      if (reloadPending) {
        reloadPending = false;
        await load();
      }
    }
  }

  Future<void> loadSupplierLedger({bool append = false}) async {
    final supplier = selectedLedgerSupplier;
    if (supplier == null || supplier.isEmpty) return;
    if (append && (ledgerLoadingMore || ledgerLoading || !ledgerHasMore)) return;

    // A filter change may happen while an earlier request is still in flight.
    // Give every refresh a new generation so stale responses cannot overwrite
    // the newly selected supplier/company statement.
    final requestId = append ? ledgerRequestId : ++ledgerRequestId;
    setState(() {
      if (append) {
        ledgerLoadingMore = true;
      } else {
        ledgerLoading = true;
        ledgerError = null;
      }
    });
    try {
      final result = await widget.api.fetchSupplierLedger(
        supplier: supplier,
        company: selectedLedgerCompany,
        start: append ? ledgerOffset : 0,
      );
      if (!mounted || requestId != ledgerRequestId) return;
      setState(() {
        supplierLedger = append ? [...supplierLedger, ...result] : result;
        ledgerOffset = (append ? ledgerOffset : 0) + result.length;
        ledgerHasMore = result.length == FrappeApi.pageSize;
        ledgerError = null;
      });
    } catch (e) {
      if (mounted && requestId == ledgerRequestId) {
        setState(() => ledgerError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && requestId == ledgerRequestId) {
        setState(() {
          if (append) {
            ledgerLoadingMore = false;
          } else {
            ledgerLoading = false;
            ledgerLoadingMore = false;
          }
        });
      }
    }
  }

  void resetSupplierLedgerForFilterChange() {
    // Invalidate in-flight refreshes even when the supplier is cleared and
    // loadSupplierLedger therefore has no request to start.
    ledgerRequestId++;
    setState(() {
      supplierLedger = [];
      ledgerOffset = 0;
      ledgerHasMore = false;
      ledgerError = null;
      ledgerLoading = false;
      ledgerLoadingMore = false;
    });
  }

  Future<void> loadMoreDraftSupplierPayments() async {
    if (loading || loadingMoreDraftPayments || !hasMoreDraftPayments) return;
    final requestId = listRequestId;
    final query = search.text.trim().isEmpty ? null : search.text.trim();
    final start = draftPaymentOffset;
    setState(() => loadingMoreDraftPayments = true);
    try {
      final result = await widget.api.fetchDraftSupplierPayments(
        start: start,
        search: query,
      );
      if (mounted && requestId == listRequestId) {
        setState(() {
          draftSupplierPayments = [...draftSupplierPayments, ...result];
          draftPaymentOffset = start + result.length;
          hasMoreDraftPayments = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (mounted && requestId == listRequestId) {
        setState(() => error = 'مسودات دفعات الموردين: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => loadingMoreDraftPayments = false);
    }
  }

  Future<void> loadMorePayments() async {
    if (loading || loadingMorePayments || !hasMorePayments) return;
    final requestId = listRequestId;
    final query = search.text.trim().isEmpty ? null : search.text.trim();
    final start = paymentOffset;
    setState(() => loadingMorePayments = true);
    try {
      final result = await widget.api.fetchSupplierPayments(start: start, search: query);
      if (mounted && requestId == listRequestId) {
        setState(() {
          supplierPayments = [...supplierPayments, ...result];
          paymentOffset = start + result.length;
          hasMorePayments = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (mounted && requestId == listRequestId) {
        setState(() => error = 'دفعات الموردين: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => loadingMorePayments = false);
    }
  }

  Future<void> loadMorePurchaseOrders() async {
    if (loading || loadingMorePurchaseOrders || !hasMorePurchaseOrders) return;
    final requestId = listRequestId;
    final query = search.text.trim().isEmpty ? null : search.text.trim();
    final start = purchaseOrderOffset;
    setState(() => loadingMorePurchaseOrders = true);
    try {
      final result = await widget.api.fetchPurchaseOrderRecords(start: start, search: query);
      if (mounted && requestId == listRequestId) {
        setState(() {
          purchaseOrders = [...purchaseOrders, ...result];
          purchaseOrderOffset = start + result.length;
          hasMorePurchaseOrders = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (mounted && requestId == listRequestId) {
        setState(() => error = 'أوامر الشراء: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => loadingMorePurchaseOrders = false);
    }
  }

  Future<void> showSupplierPaymentDraftDetails(String name) async {
    try {
      final draft = await widget.api.fetchSupplierPaymentDraftDocument(name);
      if (!mounted) return;
      final references = (draft['references'] as List)
          .whereType<core.Map<String, dynamic>>()
          .toList(growable: false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('مسودة سند صرف المورد • ${draft['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المورد: ${draft['party_name'] ?? draft['party'] ?? '—'}'),
                Text('التاريخ: ${draft['posting_date'] ?? '—'}'),
                Text('الحساب: ${draft['paid_from'] ?? '—'}'),
                Text('المبلغ: ${draft['paid_amount'] ?? '—'} ${draft['paid_from_account_currency'] ?? ''}'),
                const Divider(),
                Text('توزيع الفاتورة (${references.length})'),
                ...references.map((row) => ListTile(
                  dense: true,
                  title: Text('${row['reference_doctype'] ?? ''} • ${row['reference_name'] ?? ''}'),
                  trailing: Text((row['allocated_amount'] ?? '0').toString()),
                )),
                const Text('لن يُرحّل السند إلا بعد تأكيدك.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('مراجعة وترحيل'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _runExclusive(() async {
        final submitted = await widget.api.submitSupplierPaymentDraft(draft);
        notice('تم ترحيل سند الصرف ${submitted['name']} بنجاح.');
        await load();
        widget.onChanged?.call();
      });
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> showSupplierPaymentDetails(String name) async {
    try {
      final payment = await widget.api.fetchSupplierPaymentDocument(name);
      if (!mounted) return;
      final references = (payment['references'] as List)
          .whereType<core.Map<String, dynamic>>()
          .toList(growable: false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(shrinkWrap: true, children: [
              Text('سند صرف المورد • ${payment['name']}', style: Theme.of(context).textTheme.titleLarge),
              Text('المورد: ${payment['party_name'] ?? payment['party'] ?? '—'}'),
              Text('التاريخ: ${payment['posting_date'] ?? '—'}'),
              Text('الحساب: ${payment['paid_from'] ?? '—'}'),
              Text('المبلغ المدفوع: ${payment['paid_amount'] ?? '—'} ${payment['paid_from_account_currency'] ?? ''}'),
              const Divider(),
              Text('توزيع الدفعة على الفواتير (${references.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              if (references.isEmpty)
                const ListTile(title: Text('لا توجد إحالات فواتير في هذا السند.')),
              ...references.map((reference) => ListTile(
                leading: const Icon(Icons.link_outlined),
                title: Text((reference['reference_name'] ?? 'مرجع غير محدد').toString()),
                subtitle: Text((reference['reference_doctype'] ?? '—').toString()),
                trailing: Text((reference['allocated_amount'] ?? '0').toString()),
              )),
            ]),
          ),
        ),
      );
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }
  Future<void> loadMoreInvoices() async {
    if (loading || loadingMore || !hasMore) return;
    final requestId = listRequestId;
    final query = search.text.trim().isEmpty ? null : search.text.trim();
    final start = offset;
    setState(() => loadingMore = true);
    try {
      final result = await widget.api.fetchPurchaseInvoices(start: start, search: query);
      if (mounted && requestId == listRequestId) {
        setState(() {
          rows = [...rows, ...result];
          offset = start + result.length;
          hasMore = result.length == FrappeApi.pageSize;
        });
      }
    } catch (e) {
      if (mounted && requestId == listRequestId) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  void notice(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }
  Future<bool> confirm(String title, String message, {String actionLabel = 'تأكيد'}) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(message), actions: [
    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
    FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(actionLabel)),
  ])) == true;

  Future<void> compose({core.Map<String, dynamic>? draft}) =>
      _runExclusive(() => _compose(draft: draft));

  Future<void> _compose({core.Map<String, dynamic>? draft}) async {
    if (widget.companies.isEmpty || widget.suppliers.isEmpty || widget.items.isEmpty) {
      notice('تأكد من تحميل الشركات والموردين والأصناف وصلاحيات قراءتها.');
      return;
    }
    var selectedCompany = draft?['company']?.toString() ?? widget.companies.first.name;
    var selectedSupplier = draft?['supplier']?.toString() ?? widget.suppliers.first.id;
    final updateStock = ValueNotifier<bool>(draft?['update_stock'] == 1 || draft?['update_stock'] == true);
    final lineRows = <core.Map<String, dynamic>>[];
    final sourceLines = draft?['items'] is List
        ? (draft!['items'] as List).whereType<core.Map<String, dynamic>>().toList()
        : <core.Map<String, dynamic>>[];
    void addLine([core.Map<String, dynamic>? source]) {
      // Keep the original item code if the catalog page does not contain it.
      // Saving is blocked until the user selects a loaded item; never substitute
      // the first catalog item into an existing purchase invoice draft.
      final sourceCode = source?['item_code']?.toString();
      final validItem = sourceCode != null && sourceCode.isNotEmpty
          ? sourceCode
          : widget.items.first.code;
      final allowed = widget.warehouses.where((w) => w.company == selectedCompany);
      final sourceWarehouse = source?['warehouse']?.toString();
      lineRows.add({
        'item': validItem,
        'source': source == null ? null : core.Map<String, dynamic>.from(source),
        'qty': TextEditingController(text: (source?['qty'] ?? 1).toString()),
        'rate': TextEditingController(text: (source?['rate'] ?? 0).toString()),
        'serial_no': TextEditingController(text: source?['serial_no']?.toString() ?? ''),
        'batch_no': TextEditingController(text: source?['batch_no']?.toString() ?? ''),
        'expiry_date': TextEditingController(text: source?['expiry_date']?.toString() ?? ''),
        'warehouse': allowed.any((w) => w.id == sourceWarehouse) ? sourceWarehouse : null,
      });
    }
    if (sourceLines.isEmpty) { addLine(); } else { for (final row in sourceLines) { addLine(row); } }
    try {
      final values = await showDialog<core.Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) {
          final companies = widget.companies.map((x) => x.name).toSet().toList();
          final companyOptions = [...companies];
          if (!companyOptions.contains(selectedCompany)) companyOptions.insert(0, selectedCompany);
          final suppliers = widget.suppliers.map((x) => x.id).toSet().toList();
          final supplierOptions = [...suppliers];
          if (!supplierOptions.contains(selectedSupplier)) supplierOptions.insert(0, selectedSupplier);
          final warehouses = widget.warehouses.where((w) => w.company == selectedCompany).toList();
          return AlertDialog(
            title: Text(draft == null ? 'فاتورة مشتريات جديدة' : 'تعديل مسودة مشتريات'),
            content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: selectedCompany, isExpanded: true,
                decoration: const InputDecoration(labelText: 'الشركة'),
                items: companyOptions.map((v) => DropdownMenuItem(value: v, child: Text(companies.contains(v) ? v : '$v (غير متاح في القائمة)'))).toList(),
                onChanged: (v) => refreshDialog(() {
                  if (v == null || v == selectedCompany) return;
                  selectedCompany = v;
                  for (final row in lineRows) {
                    if (!widget.warehouses.any((w) => w.id == row['warehouse'] &&
                        (w.company == selectedCompany))) row['warehouse'] = null;
                    final source = row['source'];
                    if (source is core.Map<String, dynamic>) {
                      row['source'] = <String, dynamic>{
                        if (source['name'] != null) 'name': source['name'],
                      };
                    }
                    (row['serial_no'] as TextEditingController).clear();
                    (row['batch_no'] as TextEditingController).clear();
                    (row['expiry_date'] as TextEditingController).clear();
                  }
                }),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedSupplier, isExpanded: true,
                decoration: const InputDecoration(labelText: 'المورد'),
                items: [
                  ...supplierOptions.where((id) => !suppliers.contains(id)).map((id) => DropdownMenuItem(value: id, child: Text('$id (غير متاح في القائمة)'))),
                  ...widget.suppliers.map((s) => DropdownMenuItem(value: s.id,
                    child: Text('${s.name} (${s.id})', overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => refreshDialog(() { if (v != null) selectedSupplier = v; }),
              ),
              const Divider(height: 24),
              Row(children: [
                const Expanded(child: Text('أصناف الفاتورة', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => refreshDialog(addLine),
                  icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
              ]),
              ...List.generate(lineRows.length, (index) {
                final row = lineRows[index];
                final matchingItems = widget.items.where((x) => x.code == row['item']).toList();
                final item = matchingItems.isEmpty ? null : matchingItems.first;
                return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(
                  padding: const EdgeInsets.all(10), child: Column(children: [
                    Row(children: [
                      Expanded(child: Text('الصنف ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (lineRows.length > 1) IconButton(
                        tooltip: 'حذف الصنف',
                        onPressed: () => refreshDialog(() {
                          final removed = lineRows.removeAt(index);
                          (removed['qty'] as TextEditingController).dispose();
                          (removed['rate'] as TextEditingController).dispose();
                          (removed['serial_no'] as TextEditingController).dispose();
                          (removed['batch_no'] as TextEditingController).dispose();
                          (removed['expiry_date'] as TextEditingController).dispose();
                        }),
                        icon: const Icon(Icons.delete_outline)),
                    ]),
                    DropdownButtonFormField<String>(
                initialValue: item?.code, isExpanded: true,
                      decoration: InputDecoration(labelText: 'الصنف', helperText: item?.name ?? 'حمّل قائمة الأصناف لاختيار صنف.'),
                      items: widget.items.map((x) => DropdownMenuItem(value: x.code,
                        child: Text('${x.name} (${x.code})', overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: widget.items.isEmpty ? null : (v) => refreshDialog(() {
                        if (v == null || v == row['item']) return;
                        row['item'] = v;
                        (row['serial_no'] as TextEditingController).clear();
                        (row['batch_no'] as TextEditingController).clear();
                        (row['expiry_date'] as TextEditingController).clear();
                        final source = row['source'];
                        if (source is core.Map<String, dynamic>) {
                          row['source'] = <String, dynamic>{
                            if (source['name'] != null) 'name': source['name'],
                          };
                        }
                      }),
                    ),
                    Row(children: [
                      Expanded(child: _field(row['qty'] as TextEditingController, 'الكمية', number: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _field(row['rate'] as TextEditingController, 'سعر الوحدة', number: true)),
                    ]),
                    if (item?.hasSerialNo == true)
                      TextField(controller: row['serial_no'] as TextEditingController, minLines: 2, maxLines: 4,
                        decoration: const InputDecoration(labelText: 'الأرقام التسلسلية', helperText: 'رقم لكل وحدة، افصل بينها بسطر جديد أو فاصلة.')),
                    if (item?.hasBatchNo == true)
                      TextField(controller: row['batch_no'] as TextEditingController, decoration: const InputDecoration(labelText: 'رقم الدفعة')),
                    if (updateStock.value && item?.hasExpiryDate == true)
                      TextField(controller: row['expiry_date'] as TextEditingController,
                        decoration: const InputDecoration(labelText: 'تاريخ انتهاء الدفعة (YYYY-MM-DD)')),
                    DropdownButtonFormField<String>(
                initialValue: row['warehouse'] as String?, isExpanded: true,
                      decoration: const InputDecoration(labelText: 'مستودع الصنف (اختياري)'),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text('حسب إعدادات الصنف')),
                        ...warehouses.map((w) => DropdownMenuItem(value: w.id,
                          child: Text('${w.name} (${w.id})', overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => refreshDialog(() => row['warehouse'] = v),
                    ),
                  ]),
                ));
              }),
              ValueListenableBuilder<bool>(valueListenable: updateStock, builder: (_, value, __) =>
                SwitchListTile(value: value, onChanged: (v) => updateStock.value = v,
                  title: const Text('تحديث المخزون عند ترحيل الفاتورة'))),
              const Text('الضرائب والإجماليات يحسبها ERPNext. إذا استلمت نفس البضاعة بسند Purchase Receipt، لا تفعّل تحديث المخزون هنا.',
                style: TextStyle(fontSize: 12)),
            ]))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(onPressed: () {
                if (selectedCompany.isEmpty || selectedSupplier.isEmpty || lineRows.isEmpty) return;
                if (!widget.companies.any((x) => x.name == selectedCompany) ||
                    !widget.suppliers.any((x) => x.id == selectedSupplier)) {
                  notice('الشركة أو المورد الموجود في المسودة غير موجود ضمن البيانات المحمّلة. حدّث القوائم قبل الحفظ.');
                  return;
                }
                final items = <core.Map<String, dynamic>>[];
                for (final row in lineRows) {
                  final qty = double.tryParse((row['qty'] as TextEditingController).text.trim());
                  final rate = double.tryParse((row['rate'] as TextEditingController).text.trim());
                  final code = row['item'] as String;
                  final matchingItems = widget.items.where((x) => x.code == code).toList();
                  if (matchingItems.isEmpty) {
                    notice('الصنف $code غير موجود في قائمة الأصناف المحملة. حدّث قائمة الأصناف ثم أعد المحاولة.');
                    return;
                  }
                  final selectedItem = matchingItems.first;
                  if (code.isEmpty || qty == null || !qty.isFinite || qty <= 0 ||
                      rate == null || !rate.isFinite || rate < 0) return;
                  final itemRow = row['source'] is core.Map<String, dynamic>
                      ? core.Map<String, dynamic>.from(row['source'] as core.Map<String, dynamic>)
                      : <String, dynamic>{};
                  if (itemRow['item_code'] != null && itemRow['item_code'] != code) {
                    for (final field in const ['serial_and_batch_bundle', 'rejected_serial_and_batch_bundle', 'serial_no', 'batch_no', 'use_serial_batch_fields']) {
                      itemRow.remove(field);
                    }
                  }
                  itemRow['item_code'] = code;
                  itemRow['qty'] = qty;
                  itemRow['rate'] = rate;
                  try {
                    if (!updateStock.value) {
                      for (final field in const [
                        'serial_and_batch_bundle', 'rejected_serial_and_batch_bundle',
                        'serial_no', 'rejected_serial_no', 'batch_no', 'use_serial_batch_fields',
                      ]) {
                        itemRow.remove(field);
                      }
                    } else if (itemRow['serial_and_batch_bundle'] == null) {
                      itemRow.addAll(buildSerialBatchFields(
                        item: selectedItem, quantity: qty,
                        serialNumbers: (row['serial_no'] as TextEditingController).text,
                        batchNumber: (row['batch_no'] as TextEditingController).text,
                      ));
                      if (selectedItem.hasBatchNo) {
                        final expiry = (row['expiry_date'] as TextEditingController).text.trim();
                        if (expiry.isNotEmpty) itemRow['expiry_date'] = expiry;
                      }
                    }
                  } catch (error) { notice(error.toString().replaceFirst('FormatException: ', '')); return; }
                  if (row['warehouse'] != null) {
                    itemRow['warehouse'] = row['warehouse'];
                  } else {
                    itemRow.remove('warehouse');
                  }
                  items.add(itemRow);
                }
                Navigator.pop(dialogContext, {
                  'company': selectedCompany, 'supplier': selectedSupplier,
                  'items': items, 'update_stock': updateStock.value,
                });
              }, child: const Text('حفظ ومتابعة')),
            ],
          );
        }),
      );
      if (values == null || !mounted) return;
      final payload = <String, dynamic>{
        'doctype': 'Purchase Invoice', 'company': values['company'], 'supplier': values['supplier'],
        'posting_date': draft?['posting_date'] ?? DateTime.now().toIso8601String().substring(0, 10),
        'update_stock': values['update_stock'] == true ? 1 : 0, 'items': values['items'],
      };
      final saved = draft == null
          ? await widget.api.createPurchaseInvoice(payload)
          : await widget.api.updateDraftPurchaseInvoice(invoiceName: draft['name'].toString(), changes: payload);
      if (await confirm('ترحيل الفاتورة؟',
          'تم حفظ المسودة ${saved['name'] ?? ''} بعدد ${values['items'].length} صنف. هل تريد ترحيلها الآن؟')) {
        try {
          final submitted = await widget.api.submitPurchaseInvoice(saved);
          notice('تم ترحيل فاتورة المشتريات ${submitted['name'] ?? saved['name']}');
        } catch (e) {
          notice('حُفظت المسودة ${saved['name'] ?? ''} لكن تعذر تأكيد ترحيلها. راجعها قبل إعادة المحاولة. ${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('تم حفظ مسودة فاتورة المشتريات ${saved['name'] ?? ''}');
      }
      await load();
      widget.onChanged?.call();
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      for (final row in lineRows) {
        (row['qty'] as TextEditingController).dispose();
        (row['rate'] as TextEditingController).dispose();
        (row['serial_no'] as TextEditingController).dispose();
        (row['batch_no'] as TextEditingController).dispose();
        (row['expiry_date'] as TextEditingController).dispose();
      }
      updateStock.dispose();
    }
  }

  Future<void> composePurchaseOrder({core.Map<String, dynamic>? draft}) =>
      _runExclusive(() => _composePurchaseOrder(draft: draft));

  Future<void> _composePurchaseOrder({core.Map<String, dynamic>? draft}) async {
    if (widget.companies.isEmpty || widget.suppliers.isEmpty || widget.items.isEmpty) {
      notice('حمّل الشركات والموردين والأصناف أولاً لإنشاء أمر الشراء.');
      return;
    }
    var company = draft?['company']?.toString() ?? widget.companies.first.name;
    var supplier = draft?['supplier']?.toString() ?? widget.suppliers.first.id;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final scheduleDate = TextEditingController(text: draft?['schedule_date']?.toString() ?? today);
    final sourceRows = draft?['items'] is List
        ? (draft!['items'] as List).whereType<core.Map<String, dynamic>>().toList()
        : <core.Map<String, dynamic>>[];
    final lines = <core.Map<String, dynamic>>[];
    void addLine([core.Map<String, dynamic>? source]) {
      final code = source?['item_code']?.toString();
      // Preserve an existing draft's item code even when the current
      // dashboard catalog is incomplete; never silently replace it with item 1.
      final validCode = code != null && code.isNotEmpty
          ? code
          : widget.items.first.code;
      final sourceWarehouse = source?['warehouse']?.toString();
      lines.add({
        'item': validCode,
        'source': source == null ? null : core.Map<String, dynamic>.from(source),
        'qty': TextEditingController(text: (source?['qty'] ?? 1).toString()),
        'rate': TextEditingController(text: (source?['rate'] ?? 0).toString()),
        'warehouse': widget.warehouses.any((w) => w.id == sourceWarehouse &&
            (w.company == null || w.company == company)) ? sourceWarehouse : null,
      });
    }
    if (sourceRows.isEmpty) { addLine(); } else { for (final row in sourceRows) { addLine(row); } }
    try {
      final values = await showDialog<core.Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) {
          final companies = widget.companies.map((x) => x.name).toSet().toList();
          final companyOptions = [...companies];
          if (!companyOptions.contains(company)) companyOptions.insert(0, company);
          final suppliers = widget.suppliers.map((x) => x.id).toSet().toList();
          final supplierOptions = [...suppliers];
          if (!supplierOptions.contains(supplier)) supplierOptions.insert(0, supplier);
          final warehouses = widget.warehouses.where((w) => w.company == null || w.company == company).toList();
          return AlertDialog(
            title: Text(draft == null ? 'أمر شراء جديد' : 'تعديل مسودة أمر الشراء'),
            content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: company, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الشركة'),
                  items: companyOptions.map((v) => DropdownMenuItem(value: v, child: Text(companies.contains(v) ? v : '$v (غير متاح في القائمة)'))).toList(),
                  onChanged: (v) => refresh(() {
                    if (v == null) return;
                    company = v;
                    for (final line in lines) {
                      if (!widget.warehouses.any((w) => w.id == line['warehouse'] &&
                          (w.company == null || w.company == company))) line['warehouse'] = null;
                    }
                  }),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: supplier, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المورد'),
                  items: [
                    ...supplierOptions.where((id) => !suppliers.contains(id)).map((id) => DropdownMenuItem(value: id, child: Text('$id (غير متاح في القائمة)'))),
                    ...widget.suppliers.map((s) => DropdownMenuItem(
                      value: s.id, child: Text('${s.name} (${s.id})', overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (v) => refresh(() { if (v != null) supplier = v; }),
                ),
                _field(scheduleDate, 'تاريخ التوريد المطلوب (YYYY-MM-DD)'),
                const Divider(height: 24),
                Row(children: [
                  const Expanded(child: Text('بنود أمر الشراء', style: TextStyle(fontWeight: FontWeight.w600))),
                  TextButton.icon(onPressed: () => refresh(addLine),
                    icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
                ]),
                ...List.generate(lines.length, (index) {
                  final line = lines[index];
                  final matches = widget.items.where((item) => item.code == line['item']).toList();
                  final item = matches.isEmpty ? null : matches.first;
                  return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(
                    padding: const EdgeInsets.all(10), child: Column(children: [
                      Row(children: [
                        Expanded(child: Text('الصنف ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (lines.length > 1) IconButton(
                          tooltip: 'حذف البند',
                          onPressed: () => refresh(() {
                            final removed = lines.removeAt(index);
                            (removed['qty'] as TextEditingController).dispose();
                            (removed['rate'] as TextEditingController).dispose();
                           (removed['serial_no'] as TextEditingController).dispose();
                           (removed['batch_no'] as TextEditingController).dispose();
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ]),
                      DropdownButtonFormField<String>(
                        initialValue: item?.code, isExpanded: true,
                        decoration: InputDecoration(labelText: 'الصنف', helperText: item?.name ?? 'اختر صنفاً محمّلاً'),
                        items: widget.items.map((x) => DropdownMenuItem(
                          value: x.code, child: Text('${x.name} (${x.code})', overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => refresh(() {
                          if (v == null) return;
                          line['item'] = v;
                          final source = line['source'];
                          if (source is core.Map<String, dynamic>) {
                            line['source'] = <String, dynamic>{};
                          }
                        }),
                      ),
                      Row(children: [
                        Expanded(child: _field(line['qty'] as TextEditingController, 'الكمية المطلوبة', number: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _field(line['rate'] as TextEditingController, 'سعر الوحدة', number: true)),
                      ]),
                      DropdownButtonFormField<String>(
                        initialValue: line['warehouse'] as String?, isExpanded: true,
                        decoration: InputDecoration(labelText: item?.isStockItem == true ? 'مستودع الاستلام المقترح (اختياري)' : 'المستودع (اختياري)'),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('حسب إعدادات الصنف')),
                          ...warehouses.map((w) => DropdownMenuItem(value: w.id,
                            child: Text('${w.name} (${w.id})', overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) => refresh(() => line['warehouse'] = v),
                      ),
                    ]),
                  ));
                }),
              ],
            ))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(onPressed: () {
                final parsedDate = DateTime.tryParse(scheduleDate.text.trim());
                if (company.trim().isEmpty || supplier.trim().isEmpty || parsedDate == null || lines.isEmpty) {
                  notice('حدد الشركة والمورد وتاريخ توريد صحيحاً وأضف بنداً واحداً على الأقل.');
                  return;
                }
                if (!widget.companies.any((x) => x.name == company) ||
                    !widget.suppliers.any((x) => x.id == supplier)) {
                  notice('الشركة أو المورد الموجود في المسودة غير موجود ضمن البيانات المحمّلة. حدّث القوائم قبل الحفظ.');
                  return;
                }
                final payloadLines = <core.Map<String, dynamic>>[];
                for (final line in lines) {
                  final code = line['item'] as String;
                  final matching = widget.items.where((x) => x.code == code).toList();
                  final item = matching.isEmpty ? null : matching.first;
                  final qty = double.tryParse((line['qty'] as TextEditingController).text.trim());
                  final rate = double.tryParse((line['rate'] as TextEditingController).text.trim());
                  if (item == null || qty == null || !qty.isFinite || qty <= 0 ||
                      rate == null || !rate.isFinite || rate < 0 ||
                      !(qty * rate).isFinite ||
                      (line['warehouse'] != null && line['warehouse'] is! String)) {
                    notice('تحقق من الصنف والكمية والسعر، وتأكد من صحة المستودع إذا اخترته.');
                    return;
                  }
                  final source = line['source'] is core.Map<String, dynamic>
                      ? core.Map<String, dynamic>.from(line['source'] as core.Map<String, dynamic>)
                      : <String, dynamic>{};
                  source['item_code'] = code;
                  source['qty'] = qty;
                  source['rate'] = rate;
                  source['schedule_date'] = scheduleDate.text.trim();
                  if (line['warehouse'] != null) source['warehouse'] = line['warehouse'];
                  else source.remove('warehouse');
                  payloadLines.add(source);
                }
                Navigator.pop(dialogContext, {
                  'company': company, 'supplier': supplier,
                  'schedule_date': scheduleDate.text.trim(), 'items': payloadLines,
                });
              }, child: const Text('حفظ ومتابعة')),
            ],
          );
        }),
      );
      if (values == null || !mounted) return;
      final payload = <String, dynamic>{
        'doctype': 'Purchase Order',
        'company': values['company'],
        'supplier': values['supplier'],
        'transaction_date': draft?['transaction_date'] ?? today,
        'schedule_date': values['schedule_date'],
        'items': values['items'],
      };
      final saved = draft == null
          ? await widget.api.createPurchaseOrder(payload)
          : await widget.api.updateDraftPurchaseOrder(name: draft['name'].toString(), changes: payload);
      if (await confirm('ترحيل أمر الشراء؟',
          'تم حفظ المسودة ${saved['name'] ?? ''}. هل تريد ترحيل أمر الشراء الآن؟')) {
        try {
          final submitted = await widget.api.submitPurchaseOrder(saved);
          notice('تم ترحيل أمر الشراء ${submitted['name'] ?? saved['name']}');
        } catch (e) {
          notice('حُفظت المسودة ${saved['name'] ?? ''} لكن تعذر تأكيد ترحيلها. راجعها قبل إعادة المحاولة. ${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('تم حفظ مسودة أمر الشراء ${saved['name'] ?? ''}');
      }
      await load();
      widget.onChanged?.call();
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      for (final line in lines) {
        (line['qty'] as TextEditingController).dispose();
        (line['rate'] as TextEditingController).dispose();
      }
      scheduleDate.dispose();
    }
  }

  Future<void> purchaseOrderDetails(String name) async {
    try {
      final doc = await widget.api.fetchPurchaseOrderRecordDocument(name);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(shrinkWrap: true, children: [
            Text('أمر شراء • $name', style: Theme.of(context).textTheme.titleLarge),
            Text('المورد: ${doc['supplier_name'] ?? doc['supplier'] ?? '—'}'),
            Text('الشركة: ${doc['company'] ?? '—'}'),
            Text('الحالة: ${doc['docstatus'] == 0 ? 'مسودة' : doc['docstatus'] == 1 ? 'مرحّل' : 'ملغي'} • ${doc['status'] ?? '—'}'),
            Text('الإجمالي: ${doc['grand_total'] ?? '—'} ${doc['currency'] ?? ''}'),
            const Divider(),
            ...((doc['items'] as List? ?? []).whereType<core.Map<String, dynamic>>().map((row) => ListTile(
              title: Text((row['item_name'] ?? row['item_code'] ?? 'صنف').toString()),
              subtitle: Text('الكمية: ${row['qty'] ?? '—'} • المستلم: ${row['received_qty'] ?? 0} • المستودع: ${row['warehouse'] ?? '—'}'),
            ))),
            if (doc['docstatus'] == 0) ...[
              FilledButton(onPressed: () { Navigator.pop(sheet); composePurchaseOrder(draft: doc); },
                child: const Text('تعديل المسودة')),
              FilledButton.tonal(onPressed: () async {
                if (!await confirm('ترحيل أمر الشراء', 'سيصبح أمر الشراء متاحاً للاستلام. هل تريد المتابعة؟')) return;
                try {
                  await widget.api.submitPurchaseOrder(doc);
                  if (sheet.mounted) Navigator.pop(sheet);
                  notice('تم ترحيل أمر الشراء $name');
                  await load();
                } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
              }, child: const Text('ترحيل أمر الشراء')),
              OutlinedButton.icon(onPressed: () async {
                if (!await confirm('حذف مسودة أمر الشراء', 'سيُحذف المستند غير المرحّل نهائياً. هل تريد المتابعة؟', actionLabel: 'حذف')) return;
                try {
                  await widget.api.deleteDraftDocument(doctype: 'Purchase Order', name: name);
                  if (sheet.mounted) Navigator.pop(sheet);
                  notice('تم حذف مسودة أمر الشراء $name');
                  await load();
                } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
              }, icon: const Icon(Icons.delete_outline), label: const Text('حذف المسودة')),
            ],
            if (doc['docstatus'] == 1)
              OutlinedButton.icon(onPressed: () async {
                if (!await confirm('إلغاء أمر الشراء', 'قد يرفض ERPNext الإلغاء إذا كانت هناك مستندات استلام أو فواتير مرتبطة. هل تريد المتابعة؟')) return;
                try {
                  await widget.api.cancelPurchaseOrder(name);
                  if (sheet.mounted) Navigator.pop(sheet);
                  notice('تم إلغاء أمر الشراء $name');
                  await load();
                } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
              }, icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء أمر الشراء')),
          ]),
        )),
      );
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> details(String name) async {
    try {
      final doc = await widget.api.fetchInvoiceDocument('Purchase Invoice', name);
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: ListView(shrinkWrap: true, children: [
          Text((doc['is_return'] == 1 || doc['is_return'] == true ? 'مرتجع مشتريات • ' : 'فاتورة مشتريات • ') + name, style: Theme.of(context).textTheme.titleLarge),
          if (doc['return_against'] != null) Text('مرتبط بالفاتورة الأصلية: ' + doc['return_against'].toString()),
          Text('المورد: ' + (doc['supplier_name'] ?? doc['supplier'] ?? '—').toString()),
          Text('الحالة: ' + (doc['docstatus'] == 0 ? 'مسودة' : doc['docstatus'] == 1 ? 'مرحّل' : 'ملغي')),
          Text('الإجمالي: ' + (doc['grand_total'] ?? '—').toString() + ' ' + (doc['currency'] ?? '').toString()),
          Text('المتبقي: ' + (doc['outstanding_amount'] ?? '—').toString()),
          const Divider(),
          ...((doc['items'] as List? ?? []).whereType<core.Map<String, dynamic>>().map((x) => ListTile(title: Text((x['item_name'] ?? x['item_code']).toString()), subtitle: Text('الكمية: ' + (x['qty'] ?? '').toString() + ' • المستودع: ' + (x['warehouse'] ?? '—').toString())))),
          if (doc['docstatus'] == 0) ...[
            if (doc['is_return'] != 1 && doc['is_return'] != true)
              FilledButton(onPressed: () { Navigator.pop(sheet); compose(draft: doc); }, child: const Text('تعديل المسودة')),
            FilledButton.tonal(onPressed: () async { if (!await confirm(doc['is_return'] == 1 || doc['is_return'] == true ? 'ترحيل المرتجع' : 'ترحيل الفاتورة', 'قد يؤدي الترحيل إلى تحديث المخزون والقيود المحاسبية.')) return; try { await widget.api.submitPurchaseInvoice(doc); if (sheet.mounted) Navigator.pop(sheet); await load(); widget.onChanged?.call(); } catch (e) { notice(e.toString()); } }, child: Text(doc['is_return'] == 1 || doc['is_return'] == true ? 'ترحيل المرتجع' : 'ترحيل الفاتورة')),
            OutlinedButton.icon(
              onPressed: () async {
                if (!await confirm('حذف مسودة المشتريات', 'سيُحذف المستند غير المرحّل نهائياً. لا يمكن حذف فاتورة أو مرتجع مرحّل. هل تريد المتابعة؟')) return;
                try {
                  await widget.api.deleteDraftDocument(doctype: 'Purchase Invoice', name: name);
                  if (sheet.mounted) Navigator.pop(sheet);
                  notice('تم حذف المسودة ' + name);
                  await load();
                  widget.onChanged?.call();
                } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف المسودة'),
            ),
          ],
          if (doc['docstatus'] == 1 && doc['is_return'] != 1 && doc['is_return'] != true) ...[
            OutlinedButton(onPressed: () async {
              final payment = await _supplierPaymentDialog((doc['company'] ?? '').toString());
              if (payment == null) return;
              try {
                final result = await widget.api.payPurchaseInvoice(
                  invoiceName: name,
                  amount: payment['amount'] as double,
                  bankAccount: payment['account'] as String,
                );
                if (sheet.mounted) Navigator.pop(sheet);
                notice('تم ترحيل سند الصرف ' + (result['name'] ?? '').toString());
                await load();
              }
              catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
            }, child: const Text('تسجيل دفعة المورد')),
            OutlinedButton(onPressed: () async {
              try {
                final returnable = await widget.api.fetchPurchaseReturnableQuantities(name);
                if (returnable.isEmpty) {
                  notice('لا توجد كميات متبقية قابلة للإرجاع لهذه الفاتورة.');
                  return;
                }
                final quantities = await _purchaseReturnQuantitiesDialog(doc, returnable);
                if (quantities == null || quantities.isEmpty) return;
              try {
                final result = await widget.api.createPurchaseReturn(name, quantitiesBySourceItem: quantities);
                if (sheet.mounted) Navigator.pop(sheet);
                notice('تم إنشاء مسودة المرتجع ' + (result['name'] ?? '').toString());
                await load();
              } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
              } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
            }, child: const Text('إنشاء مرتجع / إرجاع جزئي')),
          ],
          if (doc['docstatus'] == 1 && (doc['is_return'] == 1 || doc['is_return'] == true))
            const ListTile(leading: Icon(Icons.check_circle_outline), title: Text('المرتجع مرحّل بالفعل')),
          if (doc['docstatus'] == 1 && doc['is_return'] != 1 && doc['is_return'] != true)
            OutlinedButton.icon(
              onPressed: () async {
                if (!await confirm('إلغاء فاتورة المشتريات', 'سيطلب التطبيق من ERPNext إلغاء الفاتورة وعكس أثرها المحاسبي والمخزني وفق قواعد النظام. قد يرفض ERPNext الإلغاء إذا وُجدت دفعات أو مرتجعات أو مستندات مرتبطة.')) return;
                try {
                  final canceled = await widget.api.cancelPurchaseInvoice(name);
                  if (sheet.mounted) Navigator.pop(sheet);
                  notice('أكد ERPNext إلغاء الفاتورة ' + (canceled['name'] ?? name).toString());
                  await load();
                  widget.onChanged?.call();
                } catch (e) {
                  notice(e.toString().replaceFirst('Exception: ', ''));
                }
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء الفاتورة المرحلة'),
            ),
        ]))));
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<core.Map<String, double?>?> _purchaseReturnQuantitiesDialog(
      core.Map<String, dynamic> invoice, core.Map<String, double> returnable) async {
    final sourceItems = (invoice['items'] as List? ?? [])
        .whereType<core.Map<String, dynamic>>()
        .where((row) => row['name'] is String && (row['name'] as String).isNotEmpty)
        .toList();
    if (sourceItems.isEmpty) {
      notice('لا توجد بنود مصدر صالحة لتجهيز المرتجع.');
      return null;
    }
    final controllers = <String, TextEditingController>{};
    for (final row in sourceItems) {
      final name = row['name'].toString();
      controllers[name] = TextEditingController(text: (returnable[name] ?? 0).toString());
    }
    try {
      return await showDialog<core.Map<String, double?>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('كميات مرتجع المشتريات'),
          content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اكتب الكمية التي تريد إرجاعها لكل بند. اكتب صفر لتجاوز البند. سيتحقق ERPNext من الكمية المتبقية بعد المرتجعات السابقة.'),
              const SizedBox(height: 12),
              ...sourceItems.map((row) {
                final name = row['name'].toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((row['item_name'] ?? row['item_code'] ?? name).toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('الكمية الأصلية: ${row['qty'] ?? '—'} • المتبقي القابل للإرجاع: ${(returnable[name] ?? 0).toStringAsFixed(3)}'),
                    _field(controllers[name]!, 'كمية الإرجاع (صفر للتجاوز)', number: true),
                  ]),
                );
              }),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              final result = <String, double?>{};
              for (final entry in controllers.entries) {
                final value = double.tryParse(entry.value.text.trim());
                if (value == null || !value.isFinite || value < 0) return;
                result[entry.key] = value;
              }
              if (result.values.any((value) => value != null && value > 0)) {
                Navigator.pop(dialogContext, result);
              }
            }, child: const Text('إنشاء مسودة المرتجع')),
          ],
        ),
      );
    } finally {
      for (final controller in controllers.values) { controller.dispose(); }
    }
  }

  Future<core.Map<String, dynamic>?> _supplierPaymentDialog(String company) async {
    try {
      final accounts = await widget.api.fetchPaymentAccounts(company);
      if (!mounted) return null;
      if (accounts.isEmpty) {
        notice('لا توجد حسابات صندوق أو بنك مفعّلة لهذه الشركة في ERPNext.');
        return null;
      }
      final amount = TextEditingController();
      var account = accounts.first.name;
      try {
        return await showDialog<core.Map<String, dynamic>>(
          context: context,
          builder: (c) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
            title: const Text('تسجيل دفعة المورد'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'مبلغ الدفعة'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: account,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'حساب الصندوق / البنك'),
                items: accounts.map((x) => DropdownMenuItem(
                  value: x.name,
                  child: Text('${x.accountName} • ${x.accountType}', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => refresh(() { if (v != null) account = v; }),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
              FilledButton(onPressed: () {
                final value = double.tryParse(amount.text.trim());
                if (value != null && value > 0 && value.isFinite) {
                  Navigator.pop(c, {'amount': value, 'account': account});
                }
              }, child: const Text('تأكيد الدفعة')),
            ],
          )),
        );
      } finally {
        amount.dispose();
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
      return null;
    }
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(labelText: label)));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initialSection == 'Purchase Order' ? 'أوامر الشراء' : widget.initialSection == 'Purchase Invoice' ? 'فواتير المشتريات' : widget.initialSection == 'Payment Entry' ? 'دفعات الموردين' : widget.initialSection == 'Supplier Ledger' ? 'سجل دفعات الموردين' : 'إدارة المشتريات'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: _show('Purchase Invoice') ? FloatingActionButton.extended(onPressed: () => compose(), icon: const Icon(Icons.add), label: const Text('فاتورة مشتريات')) : null,
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.initialSection == null) const Text('إدارة أوامر الشراء وفواتير الموردين والاستلام والدفعات والمرتجعات.'),
      Row(children: [
        Expanded(child: TextField(controller: search, onSubmitted: (_) => load(),
          decoration: InputDecoration(labelText: 'بحث بالمستند أو المورد', suffixIcon: IconButton(onPressed: load, icon: const Icon(Icons.search))))),
        const SizedBox(width: 8),
        if (_show('Purchase Order')) FilledButton.tonalIcon(onPressed: () => composePurchaseOrder(),
          icon: const Icon(Icons.playlist_add), label: const Text('أمر شراء')),
      ]),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      if (_show('Purchase Order')) ...[
      Text('أوامر الشراء (${purchaseOrders.length})', style: Theme.of(context).textTheme.titleMedium),
      if (purchaseOrders.isEmpty && !loading) const ListTile(title: Text('لا توجد أوامر شراء ظاهرة')),
      ...purchaseOrders.map((order) {
        final status = (order['docstatus'] as num?)?.toInt() ?? 0;
        final total = double.tryParse(order['grand_total']?.toString() ?? '') ?? 0;
        return Card(child: ListTile(
          leading: Icon(status == 1 ? Icons.shopping_bag_outlined : status == 2 ? Icons.cancel_outlined : Icons.edit_note),
          title: Text((order['name'] ?? '—').toString()),
          subtitle: Text('${order['supplier_name'] ?? order['supplier'] ?? '—'} • ${order['status'] ?? (status == 0 ? 'مسودة' : status == 2 ? 'ملغي' : 'مرحّل')} • مستلم ${order['per_received'] ?? 0}%'),
          trailing: Text(total.toStringAsFixed(2)),
          onTap: () => purchaseOrderDetails(order['name'].toString()),
        ));
      }),
      if (hasMorePurchaseOrders || loadingMorePurchaseOrders)
        Center(child: TextButton.icon(
          onPressed: loadingMorePurchaseOrders ? null : loadMorePurchaseOrders,
          icon: loadingMorePurchaseOrders ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
          label: const Text('تحميل أوامر شراء إضافية'),
        )),
      ],
      const Divider(height: 24),
      if (_show('Purchase Invoice')) ...[

      Text('فواتير المشتريات (' + rows.length.toString() + ')', style: Theme.of(context).textTheme.titleMedium),
      if (rows.isEmpty && !loading) const ListTile(title: Text('لا توجد فواتير ظاهرة')),
      ...rows.map((x) => Card(child: ListTile(leading: Icon(x.isReturn ? Icons.assignment_return_outlined : Icons.shopping_cart_outlined), title: Text((x.isReturn ? 'مرتجع • ' : '') + x.id), subtitle: Text(x.supplierName + (x.returnAgainst == null ? '' : ' • أصل: ' + x.returnAgainst!) + ' • ' + (x.status ?? '—') + ' • المتبقي ' + x.outstandingAmount.toStringAsFixed(2)), trailing: Text(x.grandTotal.toStringAsFixed(2)), onTap: () => details(x.id)))),
      if (hasMore || loadingMore)
        Center(child: TextButton.icon(
          onPressed: loadingMore ? null : loadMoreInvoices,
          icon: loadingMore ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
          label: const Text('تحميل فواتير إضافية'),
        )),
      ],
      const Divider(height: 32),
      if (_show('Payment Entry')) ...[

      Text('مسودات دفعات الموردين (${draftSupplierPayments.length})', style: Theme.of(context).textTheme.titleMedium),
      const Text('يمكن مراجعة المسودة والتحقق من إحالات الفواتير ثم ترحيلها دون إنشاء سند مكرر.'),
      if (draftSupplierPayments.isEmpty && !loading)
        const ListTile(leading: Icon(Icons.edit_note), title: Text('لا توجد مسودات دفعات موردين.')),
      ...draftSupplierPayments.map((payment) => Card(
        child: ListTile(
          leading: const Icon(Icons.pending_actions_outlined),
          title: Text((payment['name'] ?? '—').toString()),
          subtitle: Text('${payment['party_name'] ?? payment['party'] ?? 'مورد غير محدد'} • ${payment['posting_date'] ?? '—'} • مسودة'),
          trailing: Text((double.tryParse(payment['paid_amount']?.toString() ?? '') ?? 0).toStringAsFixed(2)),
          onTap: () => showSupplierPaymentDraftDetails(payment['name'].toString()),
        ),
      )),
      if (hasMoreDraftPayments || loadingMoreDraftPayments)
        Center(child: TextButton.icon(
          onPressed: loadingMoreDraftPayments ? null : loadMoreDraftSupplierPayments,
          icon: loadingMoreDraftPayments
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.expand_more),
          label: const Text('تحميل مسودات دفعات إضافية'),
        )),
      ],
      const Divider(height: 32),
      if (_show('Supplier Ledger')) ...[

      Text('سجل دفعات الموردين (${supplierPayments.length})', style: Theme.of(context).textTheme.titleMedium),
      const Text('يعرض سندات الصرف المرحلة فقط؛ المسودات والقيود الملغاة لا تدخل في السجل.'),
      if (supplierPayments.isEmpty && !loading)
        const ListTile(leading: Icon(Icons.payments_outlined), title: Text('لا توجد دفعات موردين ظاهرة')),
      ...supplierPayments.map((payment) => Card(child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text((payment['name'] ?? '—').toString()),
        subtitle: Text('${payment['party_name'] ?? payment['party'] ?? 'مورد غير محدد'} • ${payment['posting_date'] ?? '—'}\nالحساب: ${payment['paid_from'] ?? '—'}'),
        isThreeLine: true,
        trailing: Text((double.tryParse(payment['paid_amount']?.toString() ?? '') ?? 0).toStringAsFixed(2)),
        onTap: () => showSupplierPaymentDetails(payment['name'].toString()),
      ))),
      if (hasMorePayments || loadingMorePayments)
        Center(child: TextButton.icon(
          onPressed: loadingMorePayments ? null : loadMorePayments,
          icon: loadingMorePayments ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
          label: const Text('تحميل دفعات إضافية'),
        )),
      const Divider(height: 32),
      Text('كشف حساب المورد', style: Theme.of(context).textTheme.titleMedium),
      const Text('يعرض القيود المحاسبية المرحلة للمورد من دفتر الأستاذ العام في ERPNext.'),
      DropdownButtonFormField<String>(
        initialValue: selectedLedgerSupplier,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'اختر المورد'),
        items: widget.suppliers.map((supplier) => DropdownMenuItem(
          value: supplier.id,
          child: Text('${supplier.name} (${supplier.id})', overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (value) {
          setState(() => selectedLedgerSupplier = value);
          resetSupplierLedgerForFilterChange();
          loadSupplierLedger();
        },
      ),
      DropdownButtonFormField<String>(
        initialValue: selectedLedgerCompany,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'تصفية حسب الشركة'),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('كل الشركات')),
          ...widget.companies.map((company) => DropdownMenuItem(
            value: company.name,
            child: Text(company.name, overflow: TextOverflow.ellipsis),
          )),
        ],
        onChanged: (value) {
          setState(() => selectedLedgerCompany = value);
          resetSupplierLedgerForFilterChange();
          loadSupplierLedger();
        },
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: selectedLedgerSupplier == null || ledgerLoading ? null : () => loadSupplierLedger(),
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث كشف الحساب'),
        ),
      ),
      if (ledgerLoading) const LinearProgressIndicator(),
      if (ledgerError != null) Text(ledgerError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (selectedLedgerSupplier != null && supplierLedger.isEmpty && !ledgerLoading && ledgerError == null)
        const ListTile(leading: Icon(Icons.account_balance_outlined), title: Text('لا توجد قيود ظاهرة لهذا المورد.')),
      ...supplierLedger.map((entry) {
        final debit = double.tryParse(entry['debit']?.toString() ?? '') ?? 0;
        final credit = double.tryParse(entry['credit']?.toString() ?? '') ?? 0;
        return Card(child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text('${entry['voucher_type'] ?? 'قيد'} • ${entry['voucher_no'] ?? '—'}'),
          subtitle: Text('${entry['posting_date'] ?? '—'} • ${entry['account'] ?? ''} • ${entry['company'] ?? 'شركة غير محددة'}\n${entry['remarks'] ?? entry['against'] ?? ''}'),
          isThreeLine: true,
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('مدين ${debit.toStringAsFixed(2)}'),
            Text('دائن ${credit.toStringAsFixed(2)}'),
          ]),
        ));
      }),
      if (ledgerHasMore || ledgerLoadingMore)
        Center(child: TextButton.icon(
          onPressed: ledgerLoadingMore ? null : () => loadSupplierLedger(append: true),
          icon: ledgerLoadingMore ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
          label: const Text('تحميل قيود إضافية'),
        )),
      ],
      const SizedBox(height: 90),
    ]),
  );
}
