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
    appBar: AppBar(title: Text(widget.initialSection == 'Purchase Order' ? 'أوامر الشراء' : widget.initialSection == 'Purchase Invoice' ? 'فواتير المشتريات' : widget.initialSection == 'Payment Entry' ? 'دفعات الموردين' : widget.initialSection == 'Supplier Ledger' ? 'كشف حساب المورد' : 'إدارة المشتريات'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
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

class StockWorkflowPage extends StatefulWidget {
  const StockWorkflowPage({super.key, required this.api, required this.companies, required this.suppliers, required this.items, required this.warehouses, this.initialItemCode, this.onChanged});
  final FrappeApi api;
  final String? initialItemCode;
  final List<ErpCompany> companies;
  final List<ErpSupplier> suppliers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final VoidCallback? onChanged;
  @override State<StockWorkflowPage> createState() => _StockWorkflowPageState();
}

class _StockWorkflowPageState extends State<StockWorkflowPage> {
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

  List<ErpStockReorderAlert> reorderAlerts = [];
  bool loadingReorderAlerts = false;
  String? reorderAlertError;
  List<core.Map<String, dynamic>> movements = [];
  List<core.Map<String, dynamic>> drafts = [];
  final core.Map<String, int> draftOffsets = {};
  final core.Map<String, bool> draftHasMore = {};
  bool loadingMoreDrafts = false;
  String? draftError;
  bool loading = false;
  bool reloadPending = false;
  bool loadingMore = false;
  bool hasMore = false;
  int offset = 0;
  String? error;
  String? selectedMovementItem;
  String? selectedMovementWarehouse;
  String? selectedMovementCompany;
  DateTime? selectedMovementFromDate;
  DateTime? selectedMovementToDate;

  String _movementDateLabel(DateTime? value) {
    if (value == null) return 'بدون تحديد';
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickMovementDate({required bool from}) async {
    final current = from ? selectedMovementFromDate : selectedMovementToDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (from ? selectedMovementToDate : selectedMovementFromDate) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: from ? 'بداية فترة الحركات' : 'نهاية فترة الحركات',
    );
    if (picked == null || !mounted) return;
    final nextFrom = from ? DateTime(picked.year, picked.month, picked.day) : selectedMovementFromDate;
    final nextTo = from ? selectedMovementToDate : DateTime(picked.year, picked.month, picked.day);
    if (nextFrom != null && nextTo != null && nextFrom.isAfter(nextTo)) {
      notice('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
      return;
    }
    setState(() {
      selectedMovementFromDate = nextFrom;
      selectedMovementToDate = nextTo;
    });
    await load();
  }

  @override void initState() {
    super.initState();
    selectedMovementItem = widget.initialItemCode?.trim().isNotEmpty == true
        ? widget.initialItemCode!.trim()
        : null;
    load();
  }
  @override void dispose() { super.dispose(); }
  void notice(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Future<bool> confirm(String title, String message, {String actionLabel = 'ترحيل'}) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(message), actions: [
    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
    FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(actionLabel)),
  ])) == true;
  Future<void> load() async {
    if (loading) { reloadPending = true; return; }
    setState(() { loading = true; error = null; });
    try {
      final data = await widget.api.fetchStockMovements(
        itemCode: selectedMovementItem,
        warehouse: selectedMovementWarehouse,
        company: selectedMovementCompany,
        fromDate: selectedMovementFromDate,
        toDate: selectedMovementToDate,
      );
      if (mounted) setState(() { movements = data; offset = data.length; hasMore = data.length == FrappeApi.pageSize; });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    final loadedDrafts = <core.Map<String, dynamic>>[];
    final draftErrors = <String>[];
    final nextOffsets = <String, int>{};
    final nextHasMore = <String, bool>{};
    for (final type in const ['Purchase Receipt', 'Stock Entry', 'Stock Reconciliation']) {
      try {
        final page = await widget.api.fetchDraftStockDocuments(type, start: 0);
        loadedDrafts.addAll(page);
        nextOffsets[type] = page.length;
        nextHasMore[type] = page.length == FrappeApi.pageSize;
      } catch (e) {
        nextOffsets[type] = 0;
        nextHasMore[type] = false;
        draftErrors.add(type + ': ' + e.toString().replaceFirst('Exception: ', ''));
      }
    }
    if (mounted) setState(() {
      drafts = loadedDrafts;
      draftOffsets
        ..clear()
        ..addAll(nextOffsets);
      draftHasMore
        ..clear()
        ..addAll(nextHasMore);
      draftError = draftErrors.isEmpty ? null : draftErrors.join('\n');
    });
    if (mounted) {
      setState(() => loading = false);
      if (reloadPending) {
        reloadPending = false;
        await load();
      }
    }
  }
  Future<void> loadMoreStockDrafts() async {
    if (loading || loadingMoreDrafts ||
        !draftHasMore.values.any((hasMore) => hasMore)) return;
    setState(() => loadingMoreDrafts = true);
    final additions = <core.Map<String, dynamic>>[];
    final errors = <String>[];
    final nextOffsets = <String, int>{};
    final nextHasMore = <String, bool>{};
    for (final type in const ['Purchase Receipt', 'Stock Entry', 'Stock Reconciliation']) {
      if (draftHasMore[type] != true) continue;
      final start = draftOffsets[type] ?? 0;
      try {
        final page = await widget.api.fetchDraftStockDocuments(type, start: start);
        additions.addAll(page);
        nextOffsets[type] = start + page.length;
        nextHasMore[type] = page.length == FrappeApi.pageSize;
      } catch (e) {
        errors.add('$type: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (mounted) setState(() {
      drafts = [...drafts, ...additions];
      draftOffsets.addAll(nextOffsets);
      draftHasMore.addAll(nextHasMore);
      if (errors.isNotEmpty) {
        draftError = [if (draftError != null && draftError!.isNotEmpty) draftError!, ...errors].join('\n');
      }
      loadingMoreDrafts = false;
    });
  }

  Future<void> loadReorderAlerts() async {
    if (loadingReorderAlerts || !mounted) return;
    setState(() {
      loadingReorderAlerts = true;
      reorderAlertError = null;
    });
    try {
      final rows = await widget.api.fetchStockReorderAlerts();
      if (mounted) setState(() => reorderAlerts = rows);
    } catch (e) {
      if (mounted) setState(() => reorderAlertError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loadingReorderAlerts = false);
    }
  }

  Future<void> reviewDraft(core.Map<String, dynamic> summary) async {
    try {
      final type = summary['doctype'].toString();
      final name = summary['name'].toString();
      final doc = await widget.api.fetchStockDocument(type, name);
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: ListView(shrinkWrap: true, children: [
          Text(type + ' • ' + name, style: Theme.of(context).textTheme.titleLarge),
          Text('الشركة: ' + (doc['company'] ?? '—').toString()),
          Text('التاريخ: ' + (doc['posting_date'] ?? '—').toString()),
          Text('الغرض: ' + (doc['purpose'] ?? doc['stock_entry_type'] ?? '—').toString()),
          const Divider(),
          ...((doc['items'] as List? ?? []).whereType<core.Map<String, dynamic>>().map((row) => ListTile(
            title: Text((row['item_name'] ?? row['item_code'] ?? 'صنف').toString()),
            subtitle: Text('الكمية: ' + (row['qty'] ?? '—').toString() + ' • من: ' + (row['s_warehouse'] ?? '—').toString() + ' • إلى: ' + (row['t_warehouse'] ?? row['warehouse'] ?? '—').toString()),
          ))),
          OutlinedButton.icon(
            onPressed: () async {
              if (!await confirm('حذف مسودة المخزون', 'سيُحذف المستند غير المرحّل نهائياً. لن يُسمح بحذف أي مستند مرحّل. هل تريد المتابعة؟', actionLabel: 'حذف المسودة')) return;
              try {
                await widget.api.deleteDraftDocument(doctype: type, name: name);
                if (sheet.mounted) Navigator.pop(sheet);
                notice('تم حذف المسودة ' + name);
                await load();
              } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف المسودة'),
          ),
          FilledButton.icon(onPressed: () { Navigator.pop(sheet); submitDraft(summary); },
            icon: const Icon(Icons.check_circle_outline), label: const Text('متابعة لترحيل المسودة')),
        ]))));
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<void> submitDraft(core.Map<String, dynamic> summary) =>
      _runExclusive(() => _submitDraft(summary));

  Future<void> _submitDraft(core.Map<String, dynamic> summary) async {
    final type = summary['doctype'].toString();
    final name = summary['name'].toString();
    if (!await confirm('ترحيل مسودة ' + name, 'سيتم ترحيل المستند وتحديث المخزون أو القيود حسب نوعه. راجع تفاصيله في ERPNext إذا لزم الأمر.')) return;
    try {
      final doc = await widget.api.fetchStockDocument(type, name);
      if (doc['docstatus'] != 0) throw const FormatException('المستند لم يعد مسودة.');
      if (type == 'Purchase Receipt') {
        await widget.api.submitPurchaseReceipt(doc);
      } else if (type == 'Stock Entry') {
        await widget.api.submitStockEntry(doc);
      } else if (type == 'Stock Reconciliation') {
        await widget.api.submitStockReconciliation(doc);
      } else {
        throw ArgumentError('نوع المستند غير مدعوم.');
      }
      notice('تم ترحيل ' + name + ' بنجاح.');
      await load(); widget.onChanged?.call();
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<void> showMovementDetails(core.Map<String, dynamic> movement) async {
    if (!mounted) return;
    final voucherType = movement['voucher_type']?.toString() ?? '';
    final voucherName = movement['voucher_no']?.toString() ?? '';
    const traceableVouchers = {
      'Sales Invoice', 'Purchase Invoice', 'Purchase Receipt',
      'Stock Entry', 'Stock Reconciliation',
    };
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(shrinkWrap: true, children: [
            Text('تفاصيل حركة المخزون', style: Theme.of(context).textTheme.titleLarge),
            ListTile(title: const Text('الصنف'), subtitle: Text((movement['item_code'] ?? '—').toString())),
            ListTile(title: const Text('الشركة'), subtitle: Text((movement['company'] ?? '—').toString())),
            ListTile(title: const Text('المستودع'), subtitle: Text((movement['warehouse'] ?? '—').toString())),
            ListTile(title: const Text('التاريخ والوقت'), subtitle: Text('${movement['posting_date'] ?? '—'} • ${movement['posting_time'] ?? '—'}')),
            ListTile(title: const Text('الكمية المتغيرة'), subtitle: Text((movement['actual_qty'] ?? '—').toString())),
            ListTile(title: const Text('الرصيد بعد الحركة'), subtitle: Text((movement['qty_after_transaction'] ?? '—').toString())),
            ListTile(title: const Text('المستند المصدر'), subtitle: Text('${movement['voucher_type'] ?? '—'} • ${movement['voucher_no'] ?? '—'}')),
            ListTile(title: const Text('مرجع سجل المخزون'), subtitle: Text((movement['name'] ?? '—').toString())),
            if (traceableVouchers.contains(voucherType) && voucherName.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  openVoucherDetails(voucherType, voucherName);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('فتح المستند المصدر'),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> openVoucherDetails(String doctype, String name) async {
    try {
      final document = doctype == 'Sales Invoice' || doctype == 'Purchase Invoice'
          ? await widget.api.fetchInvoiceDocument(doctype, name)
          : await widget.api.fetchStockDocument(doctype, name);
      if (!mounted) return;
      final status = document['docstatus'] == 0
          ? 'مسودة'
          : document['docstatus'] == 1
              ? 'مرحّل'
              : document['docstatus'] == 2
                  ? 'ملغي'
                  : 'غير محدد';
      final rows = (document['items'] as List? ?? [])
          .whereType<core.Map<String, dynamic>>()
          .toList(growable: false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('$doctype • $name', style: Theme.of(context).textTheme.titleLarge),
                ListTile(title: const Text('الحالة'), subtitle: Text(status)),
                ListTile(title: const Text('الشركة'), subtitle: Text((document['company'] ?? '—').toString())),
                ListTile(title: const Text('التاريخ'), subtitle: Text((document['posting_date'] ?? '—').toString())),
                if (document['customer'] != null)
                  ListTile(title: const Text('العميل'), subtitle: Text((document['customer_name'] ?? document['customer']).toString())),
                if (document['supplier'] != null)
                  ListTile(title: const Text('المورد'), subtitle: Text((document['supplier_name'] ?? document['supplier']).toString())),
                if (document['purpose'] != null || document['stock_entry_type'] != null)
                  ListTile(title: const Text('نوع الحركة'), subtitle: Text((document['purpose'] ?? document['stock_entry_type']).toString())),
                if (document['grand_total'] != null)
                  ListTile(title: const Text('الإجمالي'), subtitle: Text('${document['grand_total']} ${document['currency'] ?? ''}')),
                const Divider(),
                Text('البنود (${rows.length})', style: Theme.of(context).textTheme.titleMedium),
                ...rows.map((row) => ListTile(
                  title: Text((row['item_name'] ?? row['item_code'] ?? 'صنف').toString()),
                  subtitle: Text('الكمية: ${row['qty'] ?? '—'} • المستودع: ${row['warehouse'] ?? row['s_warehouse'] ?? '—'}'),
                )),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      notice('تعذر فتح المستند المصدر: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> loadMoreMovements() async {
    if (loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    try {
      final data = await widget.api.fetchStockMovements(start: offset,
        itemCode: selectedMovementItem,
        warehouse: selectedMovementWarehouse,
        company: selectedMovementCompany,
        fromDate: selectedMovementFromDate,
        toDate: selectedMovementToDate);
      if (mounted) setState(() { movements = [...movements, ...data]; offset += data.length; hasMore = data.length == FrappeApi.pageSize; });
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loadingMore = false); }
  }
  Future<List<core.Map<String, dynamic>>?> _stockItemLinesDialog({
    required String title, bool includeRate = false, bool allowZeroQuantity = false, bool requirePositiveRate = false,
    String? trackingWarehouse,
    String? reconciliationWarehouse,
  }) async {
    final availableItems = List<ErpItem>.from(widget.items);
    final itemSearch = TextEditingController();
    if (availableItems.isEmpty) {
      try { availableItems.addAll(await widget.api.fetchItems()); } catch (_) {}
    }
    if (!mounted) return null;
    final lines = <core.Map<String, dynamic>>[];
    void addLine() {
      if (lines.length >= 500) { notice('الحد الأقصى 500 بند في المستند الواحد؛ قسّم العملية إلى مستندات أصغر.'); return; }
      if (availableItems.isEmpty) { notice('ابحث عن صنف من الخادم أولاً.'); return; }
      lines.add({
        'item': availableItems.first.code,
        'qty': TextEditingController(text: allowZeroQuantity ? '0' : '1'),
        'rate': TextEditingController(text: '0'),
        'serial_no': TextEditingController(),
        'batch_no': TextEditingController(),
        'expiry_date': TextEditingController(),
        'current_serial_no': TextEditingController(),
        'current_qty': null,
        'current_item_code': null,
        'current_batch_no': null,
      });
    }
    addLine();
    try {
      return await showDialog<List<core.Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Expanded(child: Text('الأصناف والكميات', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => refresh(addLine),
                  icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
              ]),
              Row(children: [
                Expanded(child: TextField(controller: itemSearch, decoration: const InputDecoration(
                  labelText: 'بحث عن صنف في ERPNext', hintText: 'رمز الصنف أو الاسم'),
                  onSubmitted: (_) async {
                    try {
                      final found = await widget.api.fetchItems(search: itemSearch.text.trim());
                      refresh(() {
                        final known = availableItems.map((x) => x.code).toSet();
                        availableItems.addAll(found.where((x) => !known.contains(x.code)));
                        if (lines.isEmpty && availableItems.isNotEmpty) addLine();
                      });
                    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
                  })),
                IconButton(tooltip: 'بحث في الخادم', onPressed: () async {
                  try {
                    final found = await widget.api.fetchItems(search: itemSearch.text.trim());
                    refresh(() {
                      final known = availableItems.map((x) => x.code).toSet();
                      availableItems.addAll(found.where((x) => !known.contains(x.code)));
                      if (lines.isEmpty && availableItems.isNotEmpty) addLine();
                    });
                  } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
                }, icon: const Icon(Icons.search)),
              ]),
              ...List.generate(lines.length, (index) {
                final row = lines[index];
                final matchingItems = availableItems.where((x) => x.code == row['item']).toList();
                final item = matchingItems.isEmpty ? null : matchingItems.first;
                return Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
                  Row(children: [
                    Expanded(child: Text('الصنف ${index + 1}')),
                    if (lines.length > 1) IconButton(onPressed: () => refresh(() {
                      final removed = lines.removeAt(index);
                      (removed['qty'] as TextEditingController).dispose();
                      (removed['rate'] as TextEditingController).dispose();
                      (removed['serial_no'] as TextEditingController).dispose();
                      (removed['batch_no'] as TextEditingController).dispose();
                      (removed['expiry_date'] as TextEditingController).dispose();
                      (removed['current_serial_no'] as TextEditingController).dispose();
                    }), icon: const Icon(Icons.delete_outline)),
                  ]),
                  DropdownButtonFormField<String>(
                initialValue: item?.code, isExpanded: true,
                    decoration: InputDecoration(labelText: 'الصنف', helperText: item?.name ?? 'ابحث عن الصنف في الخادم لإضافته.'),
                    items: availableItems.map((x) => DropdownMenuItem(value: x.code,
                      child: Text('${x.name} (${x.code})', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: availableItems.isEmpty ? null : (v) => refresh(() {
                      if (v != null && v != row['item']) {
                        row['item'] = v;
                        (row['serial_no'] as TextEditingController).clear();
                        (row['batch_no'] as TextEditingController).clear();
                        (row['current_serial_no'] as TextEditingController).clear();
                        row['current_qty'] = null;
                      }
                    }),
                  ),
                  _field(row['qty'] as TextEditingController, allowZeroQuantity ? 'الكمية الفعلية' : 'الكمية', number: true),
                  if (includeRate) _field(row['rate'] as TextEditingController, 'سعر التقييم', number: true),
                  if (item?.hasSerialNo == true)
                    TextField(controller: row['serial_no'] as TextEditingController, minLines: 2, maxLines: 4,
                      decoration: const InputDecoration(labelText: 'الأرقام التسلسلية', helperText: 'رقم لكل وحدة.')),
                  if (item?.hasBatchNo == true)
                    TextField(controller: row['batch_no'] as TextEditingController,
                      onChanged: (value) {
                        if (allowZeroQuantity && row['current_batch_no'] != null &&
                            value.trim() != row['current_batch_no']) {
                          refresh(() {
                            row['current_qty'] = null;
                            row['current_batch_no'] = null;
                            (row['current_serial_no'] as TextEditingController).clear();
                          });
                        }
                      },
                      decoration: const InputDecoration(labelText: 'رقم الدفعة')),
                  if ((includeRate || allowZeroQuantity) && item?.hasBatchNo == true && item?.hasExpiryDate == true)
                    TextField(controller: row['expiry_date'] as TextEditingController,
                      decoration: const InputDecoration(labelText: 'تاريخ انتهاء الدفعة (YYYY-MM-DD)')),
                  if (allowZeroQuantity && item != null && (item.hasSerialNo || item.hasBatchNo)) ...[
                    TextField(controller: row['current_serial_no'] as TextEditingController, readOnly: true,
                      minLines: 1, maxLines: 4,
                      decoration: const InputDecoration(labelText: 'الأرقام الحالية في المستودع', helperText: 'تُحمّل من رصيد ERPNext قبل التسوية.')),
                    Text('الكمية الحالية: ${row['current_qty'] ?? 'لم يتم تحميلها'}'),
                    Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(
                      onPressed: () async {
                        try {
                          final balanceRows = await widget.api.fetchStockBalances(
                            warehouse: reconciliationWarehouse!,
                            search: item.code,
                          );
                          final balances = balanceRows.where((entry) =>
                            entry.itemCode == item.code && entry.warehouse == reconciliationWarehouse).toList();
                          final actualQty = balances.isEmpty ? 0.0 : balances.first.actualQty;
                          String batchNo = (row['batch_no'] as TextEditingController).text.trim();
                          var currentQty = actualQty;
                          if (item.hasBatchNo) {
                            final available = await widget.api.fetchAvailableBatches(
                              itemCode: item.code, warehouse: reconciliationWarehouse,
                              ignoreReservedStock: true,
                              includeExpired: true,
                            );
                            final availableRows = available.whereType<Map<String, dynamic>>().toList(growable: false);
                            if (batchNo.isEmpty && availableRows.length == 1) {
                              batchNo = availableRows.first['batch_no'].toString();
                            } else if (batchNo.isEmpty && availableRows.length > 1) {
                              if (!context.mounted) return;
                              final chosen = await showDialog<String>(
                                context: context,
                                builder: (pickerContext) => SimpleDialog(
                                  title: const Text('اختر الدفعة الحالية'),
                                  children: availableRows.map((entry) => SimpleDialogOption(
                                    onPressed: () => Navigator.pop(pickerContext, entry['batch_no'].toString()),
                                    child: Text(entry['batch_no'].toString() + ' • الكمية الحالية: ' + (entry['qty'] ?? 0).toString()),
                                  )).toList(),
                                ),
                              );
                              if (chosen == null) return;
                              batchNo = chosen;
                            }
                            final batchRows = availableRows.where((entry) => entry['batch_no'] == batchNo).toList();
                            currentQty = batchRows.isEmpty ? 0.0 :
                              (double.tryParse(batchRows.first['qty']?.toString() ?? '') ?? 0);
                            if (batchNo.isEmpty && currentQty > 0) {
                              notice('اختر الدفعة قبل تحميل رصيدها الحالي.');
                              return;
                            }
                            (row['batch_no'] as TextEditingController).text = batchNo;
                          }
                          var currentSerials = <String>[];
                          if (item.hasSerialNo && currentQty > 0) {
                            if ((currentQty - currentQty.round()).abs() > 0.000001 || currentQty > 5000) {
                              notice('عدد الأرقام الحالية يتجاوز حد المعالجة الآمن (5000) أو ليس عدداً صحيحاً؛ قسّم التسوية إلى مستندات أصغر.');
                              return;
                            }
                            currentSerials = await widget.api.fetchAvailableSerialNumbers(
                              itemCode: item.code,
                              warehouse: reconciliationWarehouse,
                              quantity: currentQty.round(),
                              batchNumbers: batchNo.isEmpty ? const [] : [batchNo],
                            );
                            if (currentSerials.length != currentQty.round()) {
                              notice('لم تتطابق الأرقام الحالية مع كمية الصنف؛ لم يتم تحميل لقطة غير مكتملة.');
                              return;
                            }
                          }
                          refresh(() {
                            row['current_qty'] = currentQty;
                            row['current_item_code'] = item.code;
                            row['current_batch_no'] = batchNo;
                            (row['current_serial_no'] as TextEditingController).text = currentSerials.join('\n');
                          });
                        } catch (error) {
                          notice(error.toString().replaceFirst('Exception: ', ''));
                        }
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('تحميل الأرقام والكمية الحالية'),
                    )),
                  ],
                  if (trackingWarehouse != null && item != null &&
                      (item.hasSerialNo || item.hasBatchNo))
                    Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(
                      onPressed: () async {
                        final qty = double.tryParse((row['qty'] as TextEditingController).text.trim()) ?? 0;
                        try {
                          final picked = await showAvailableSerialBatchPicker(
                            context: context, api: widget.api, item: item,
                            quantity: qty, warehouse: trackingWarehouse,
                          );
                          if (picked != null) refresh(() {
                            (row['serial_no'] as TextEditingController).text = picked['serial_no']?.toString() ?? '';
                            (row['batch_no'] as TextEditingController).text = picked['batch_no']?.toString() ?? '';
                          });
                        } catch (error) {
                          notice(error.toString().replaceFirst('Exception: ', ''));
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('اختيار من المتاح في مستودع المصدر'),
                    )),
                ])));
              }),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              final result = <core.Map<String, dynamic>>[];
              final seenItems = <String>{};
              for (final row in lines) {
                final itemCode = row['item'] as String;
                final qty = double.tryParse((row['qty'] as TextEditingController).text.trim());
                final rate = double.tryParse((row['rate'] as TextEditingController).text.trim());
                final matchingItems = availableItems.where((x) => x.code == row['item']).toList();
                if (matchingItems.isEmpty) {
                  notice('الصنف ${row['item']} غير موجود في نتائج البحث الحالية؛ ابحث عنه من الخادم أولاً.');
                  return;
                }
                final selectedItem = matchingItems.first;
                if (qty == null || !qty.isFinite ||
                    (allowZeroQuantity ? qty < 0 : qty <= 0) ||
                    (includeRate && (rate == null || !rate.isFinite || (requirePositiveRate ? rate <= 0 : rate < 0)))) return;
                final serialText = (row['serial_no'] as TextEditingController).text;
                final batchText = (row['batch_no'] as TextEditingController).text;
                final currentQty = row['current_qty'];
                final currentSerialText = (row['current_serial_no'] as TextEditingController).text;
                if (allowZeroQuantity && (selectedItem.hasSerialNo || selectedItem.hasBatchNo) &&
                    (row['current_item_code'] != selectedItem.code ||
                     (selectedItem.hasBatchNo && row['current_batch_no'] != batchText.trim()) ||
                     currentQty is! num || !currentQty.isFinite || currentQty < 0)) {
                  notice('حمّل الأرقام والكمية الحالية للصنف المتتبع قبل التسوية.');
                  return;
                }
                if (allowZeroQuantity && qty == 0 &&
                    (selectedItem.hasSerialNo || selectedItem.hasBatchNo) &&
                    (currentQty as num) == 0) {
                  continue;
                }
                if (allowZeroQuantity && qty == 0 && (selectedItem.hasSerialNo || selectedItem.hasBatchNo) &&
                    ((selectedItem.hasSerialNo && currentSerialText.trim().isEmpty && (currentQty as num) > 0) ||
                     (selectedItem.hasBatchNo && batchText.trim().isEmpty))) {
                  notice('تعذر تحديد الأرقام أو الدفعة الحالية التي ستُزال من المستودع.');
                  return;
                }
                final trackingKey = selectedItem.hasBatchNo
                    ? itemCode + '|' + batchText.trim()
                    : itemCode;
                if (allowZeroQuantity && !seenItems.add(trackingKey)) {
                  notice('لا تكرر الصنف والدفعة نفسيهما في تسوية الجرد.');
                  return;
                }
                try {
                  final trackingFields = allowZeroQuantity && qty == 0 &&
                      (selectedItem.hasSerialNo || selectedItem.hasBatchNo)
                      ? <String, dynamic>{
                          'use_serial_batch_fields': 1,
                          'serial_no': '',
                          if (selectedItem.hasBatchNo) 'batch_no': batchText.trim(),
                        }
                      : buildSerialBatchFields(item: selectedItem, quantity: qty,
                          serialNumbers: serialText, batchNumber: batchText);
                  final expiry = (row['expiry_date'] as TextEditingController).text.trim();
                  result.add({'item_code': row['item'], 'qty': qty,
                    if (includeRate) 'valuation_rate': rate,
                    if (expiry.isNotEmpty) 'expiry_date': expiry,
                    if (allowZeroQuantity && (selectedItem.hasSerialNo || selectedItem.hasBatchNo)) ...{
                      'current_qty': currentQty,
                      'current_serial_no': currentSerialText,
                    },
                    ...trackingFields});
                } catch (error) { notice(error.toString().replaceFirst('FormatException: ', '')); return; }
              }
              if (result.isNotEmpty) Navigator.pop(dialogContext, result);
            }, child: const Text('متابعة')),
          ],
        )),
      );
    } finally {
      itemSearch.dispose();
      for (final row in lines) {
        (row['qty'] as TextEditingController).dispose();
        (row['rate'] as TextEditingController).dispose();
        (row['serial_no'] as TextEditingController).dispose();
        (row['batch_no'] as TextEditingController).dispose();
        (row['expiry_date'] as TextEditingController).dispose();
        (row['current_serial_no'] as TextEditingController).dispose();
      }
    }
  }

  Future<void> movement(String purpose) =>
      _runExclusive(() => _movement(purpose));

  Future<void> _movement(String purpose, {bool damage = false}) async {
    if (widget.companies.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) {
      notice('حمّل الشركات والأصناف والمستودعات أولاً.');
      return;
    }
    var selectedCompany = widget.companies.first.name;
    final from = TextEditingController();
    final to = TextEditingController();
    final damageReason = TextEditingController();
    try {
      final warehouses = widget.warehouses;
      final values = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(damage ? 'تسجيل تلف وهالك' : purpose == 'Material Receipt' ? 'استلام مخزون' :
              purpose == 'Material Issue' ? 'صرف / تسليم مخزون' : 'تحويل بين المستودعات'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
                initialValue: selectedCompany, isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(),
              onChanged: (v) => refresh(() {
                if (v != null) {
                  selectedCompany = v;
                  from.clear();
                  to.clear();
                }
              }),
            ),
            if (purpose != 'Material Receipt')
              DropdownButtonFormField<String>(
                initialValue: null, isExpanded: true,
                decoration: const InputDecoration(labelText: 'مستودع المصدر'),
                items: warehouses.where((w) => w.company == selectedCompany)
                    .map((w) => DropdownMenuItem(value: w.id, child: Text('${w.name} (${w.id})'))).toList(),
                onChanged: (v) => from.text = v ?? '',
              ),
            if (purpose != 'Material Issue')
              DropdownButtonFormField<String>(
                initialValue: null, isExpanded: true,
                decoration: const InputDecoration(labelText: 'مستودع الوجهة / الاستلام'),
                items: warehouses.where((w) => w.company == selectedCompany)
                    .map((w) => DropdownMenuItem(value: w.id, child: Text('${w.name} (${w.id})'))).toList(),
                onChanged: (v) => to.text = v ?? '',
              ),
            if (damage) TextField(controller: damageReason, maxLines: 2, decoration: const InputDecoration(labelText: 'سبب التلف والهالك *', hintText: 'انتهاء صلاحية، كسر، تلف أثناء التخزين')),
            const SizedBox(height: 8),
            const Text('ستحدد الأصناف والكميات في الخطوة التالية.'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if ((purpose != 'Material Receipt' && from.text.trim().isEmpty) ||
                  (purpose != 'Material Issue' && to.text.trim().isEmpty) ||
                  (damage && damageReason.text.trim().isEmpty) ||
                  (purpose == 'Material Transfer' && from.text.trim() == to.text.trim())) return;
              Navigator.pop(c, true);
            }, child: const Text('التالي')),
          ],
        ),
      ));
      if (values != true || !mounted) return;
      final items = await _stockItemLinesDialog(
        title: 'أصناف حركة المخزون', includeRate: purpose == 'Material Receipt',
        requirePositiveRate: purpose == 'Material Receipt',
        trackingWarehouse: purpose == 'Material Issue' || purpose == 'Material Transfer'
            ? from.text.trim() : null,
      );
      if (items == null || !mounted) return;
      final doc = await widget.api.createStockEntry(
        company: selectedCompany, purpose: purpose,
        fromWarehouse: from.text.trim().isEmpty ? null : from.text.trim(),
        toWarehouse: to.text.trim().isEmpty ? null : to.text.trim(),
        items: items,
        remarks: damage ? 'تلف وهالك: ${damageReason.text.trim()}' : null,
      );
      if (await confirm('ترحيل حركة المخزون',
          'تم إنشاء المسودة ${doc['name'] ?? ''} بعدد ${items.length} صنف. الترحيل سيغير أرصدة المخزون.')) {
        try {
          final result = await widget.api.submitStockEntry(doc);
          notice('تم ترحيل الحركة ${result['name'] ?? doc['name']}');
          await load();
          widget.onChanged?.call();
        } catch (e) {
          notice('حُفظت مسودة الحركة ${doc['name'] ?? ''} ولم يؤكد ترحيلها. راجعها قبل إنشاء حركة بديلة. ${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('حُفظت المسودة ${doc['name'] ?? ''}');
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      from.dispose();
      to.dispose();
      damageReason.dispose();
    }
  }

  Future<void> pickPackShip() => _runExclusive(_pickPackShip);

  Future<void> _pickPackShip() async {
    try {
      final orders = <core.Map<String, dynamic>>[];
      var start = 0;
      while (true) {
        final page = await widget.api.fetchSalesWorkflowDocuments('Sales Order', start: start);
        orders.addAll(page);
        if (page.length < FrappeApi.pageSize) break;
        start += page.length;
        if (orders.length >= 10000) throw const FormatException('تجاوزت أوامر البيع حد البحث البالغ 10,000؛ استخدم فلتر أمر بيع أضيق.');
      }
      if (!mounted) return;
      final eligible = orders.where((row) => row['docstatus'] == 1 && !const {'Completed', 'Closed', 'Cancelled'}.contains(row['status']?.toString())).toList(growable: false);
      if (eligible.isEmpty) { notice('لا توجد أوامر بيع مرحلة ضمن النتائج الحالية.'); return; }
      String? selected = eligible.first['name']?.toString();
      final confirmedOrder = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('التقاط وتجهيز طلب تسليم'),
        content: SizedBox(width: 480, child: DropdownButtonFormField<String>(
          initialValue: selected, isExpanded: true, decoration: const InputDecoration(labelText: 'أمر البيع المرحّل'),
          items: eligible.map((row) => DropdownMenuItem(value: row['name']?.toString(), child: Text('${row['name']} • ${row['customer_name'] ?? row['customer'] ?? ''}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) => refresh(() => selected = value),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: selected == null ? null : () => Navigator.pop(dialogContext, true), child: const Text('إنشاء قائمة الالتقاط'))],
      )));
      if (confirmedOrder != true || selected == null || !mounted) return;
      final draft = await widget.api.createPickListFromSalesOrder(selected!);
      if (!mounted) return;
      final locations = (draft['locations'] as List? ?? []).whereType<core.Map<String, dynamic>>().toList();
      final picked = <String, TextEditingController>{};
      for (var i = 0; i < locations.length; i++) picked['$i'] = TextEditingController(text: (locations[i]['picked_qty'] ?? '').toString());
      try {
        final ready = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
          title: Text('مراجعة التجهيز • ${draft['name']}'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('راجع المستودع والدفعة والأرقام التسلسلية، وأدخل الكمية الملتقطة فعلياً. سيعيد ERPNext التحقق من التوفر عند الترحيل.'),
            ...List.generate(locations.length, (i) { final row = locations[i]; return Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${row['item_code'] ?? ''} • ${row['warehouse'] ?? 'سيحدده ERPNext'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('المطلوب: ${row['stock_qty'] ?? row['qty'] ?? 0} • الدفعة: ${row['batch_no'] ?? '—'}'),
              TextField(controller: picked['$i'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية الملتقطة فعلياً')),
            ])));}),
          ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('حفظ كمسودة')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد التجهيز والترحيل'))],
        ));
        for (var i = 0; i < locations.length; i++) {
          final rawQty = picked['$i']!.text.trim();
          final qty = rawQty.isEmpty && ready != true ? 0.0 : double.tryParse(rawQty);
          if (qty == null || !qty.isFinite || qty < 0 ||
              (ready == true && qty <= 0) ||
              qty > (double.tryParse((locations[i]['stock_qty'] ?? locations[i]['qty'] ?? 0).toString()) ?? 0) + 0.000001) {
            throw const FormatException('أدخل كمية ملتقطة موجبة لكل بند قبل الترحيل، ولا تتجاوز الكمية المطلوبة. يمكنك حفظ المسودة بكمية صفر.');
          }
          locations[i]['picked_qty'] = qty;
        }
        if (ready != true) {
          await widget.api.saveStockPickList(draft['name'].toString(), locations);
          notice('حُفظت كميات الالتقاط في المسودة ${draft['name']}.');
          return;
        }
        final saved = await widget.api.saveStockPickList(draft['name'].toString(), locations);
        final submitted = await widget.api.submitPickList(saved);
        final notes = await widget.api.createDeliveryNotesFromPickList(submitted['name'].toString());
        notice('تم ترحيل قائمة الالتقاط ${submitted['name']} وإنشاء ${notes.length} إذن تسليم: ${notes.map((x) => x['name']).join('، ')}. أذونات التسليم مسودات وتحتاج مراجعة وترحيلاً منفصلاً.');
        await load(); widget.onChanged?.call();
      } finally { for (final controller in picked.values) { controller.dispose(); } }
    } catch (e) { notice(e.toString().replaceFirst('Exception: ', '')); }
  }

  Future<void> showBatchTrace() async {
    final search = TextEditingController();
    try {
      final query = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تتبع الدفعات'),
          content: TextField(
            controller: search,
            decoration: const InputDecoration(labelText: 'رقم الدفعة أو الصنف'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, search.text.trim()), child: const Text('بحث')),
          ],
        ),
      );
      if (query == null || !mounted) return;
      if (query.trim().isEmpty) {
        notice('أدخل رقم دفعة أو رمز صنف لتضييق البحث.');
        return;
      }

      final rows = <core.Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final page = await widget.api.fetchBatchTraceRecords(start: offset, search: query);
        rows.addAll(page);
        if (page.length < FrappeApi.pageSize) break;
        offset += page.length;
        if (rows.length >= 10000) {
          throw const FormatException('تجاوز سجل الدفعات 10,000 نتيجة؛ استخدم رقم دفعة أو صنفاً أكثر تحديداً.');
        }
      }
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length + 1,
            itemBuilder: (listContext, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('نتائج الدفعات (${rows.length})', style: Theme.of(listContext).textTheme.titleLarge),
                );
              }
              final row = rows[index - 1];
              return ListTile(
                title: Text('${row['batch_id'] ?? row['name']}'),
                subtitle: Text('الصنف: ${row['item'] ?? '—'} • انتهاء: ${row['expiry_date'] ?? '—'}'),
                onTap: () async {
                  try {
                    final bundleEntries = <core.Map<String, dynamic>>[];
                    var bundleOffset = 0;
                    while (true) {
                      final page = await widget.api.fetchBatchLedgerEntries(
                        row['name'].toString(),
                        start: bundleOffset,
                      );
                      bundleEntries.addAll(page);
                      if (page.length < 500) break;
                      bundleOffset += page.length;
                      if (bundleEntries.length >= 10000) {
                        throw const FormatException('تجاوز سجل الدفعة 10,000 حركة.');
                      }
                    }
                    if (!mounted || !sheetContext.mounted) return;
                    Navigator.pop(sheetContext);

                    if (bundleEntries.isNotEmpty) {
                      await showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => SafeArea(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: bundleEntries.length + 1,
                            itemBuilder: (historyContext, historyIndex) {
                              if (historyIndex == 0) {
                                return Text('السجل التاريخي للدفعة ${row['name']}',
                                  style: Theme.of(historyContext).textTheme.titleLarge);
                              }
                              final entry = bundleEntries[historyIndex - 1];
                              final bundle = entry['bundle'] as core.Map<String, dynamic>? ?? const <String, dynamic>{};
                              return ListTile(
                                title: Text('${bundle['posting_date'] ?? '—'} • ${bundle['voucher_type'] ?? '—'} ${bundle['voucher_no'] ?? ''}'),
                                subtitle: Text('المستودع: ${bundle['warehouse'] ?? '—'} • الكمية: ${entry['qty'] ?? '—'} • الرقم التسلسلي: ${entry['serial_no'] ?? '—'} • الاتجاه: ${bundle['type_of_transaction'] ?? '—'}'),
                              );
                            },
                          ),
                        ),
                      );
                      return;
                    }

                    final moves = <core.Map<String, dynamic>>[];
                    var moveOffset = 0;
                    while (true) {
                      final page = await widget.api.fetchStockMovements(
                        start: moveOffset,
                        batchNo: row['name']?.toString(),
                      );
                      moves.addAll(page);
                      if (page.length < FrappeApi.pageSize) break;
                      moveOffset += page.length;
                      if (moves.length >= 10000) {
                        throw const FormatException('تجاوزت حركات الدفعة 10,000 حركة؛ استخدم فلاتر زمنية أضيق.');
                      }
                    }
                    if (!mounted) return;
                    await showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => SafeArea(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: moves.length + 1,
                          itemBuilder: (historyContext, historyIndex) {
                            if (historyIndex == 0) {
                              return Text('حركة الدفعة ${row['name']}',
                                style: Theme.of(historyContext).textTheme.titleLarge);
                            }
                            final move = moves[historyIndex - 1];
                            return ListTile(
                              title: Text('${move['posting_date']} • ${move['voucher_type']} ${move['voucher_no']}'),
                              subtitle: Text('المستودع: ${move['warehouse']} • الكمية: ${move['actual_qty']} • الرصيد: ${move['qty_after_transaction']}'),
                            );
                          },
                        ),
                      ),
                    );
                  } catch (error) {
                    if (mounted) notice(error.toString().replaceFirst('Exception: ', ''));
                  }
                },
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) notice(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      search.dispose();
    }
  }

  Future<void> showSerialTrace() async {
    final search = TextEditingController();
    try {
      final query = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تتبع الأرقام التسلسلية'),
          content: TextField(
            controller: search,
            decoration: const InputDecoration(labelText: 'الرقم التسلسلي أو رمز الصنف'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, search.text.trim()), child: const Text('بحث')),
          ],
        ),
      );
      if (query == null || !mounted) return;
      if (query.trim().isEmpty) {
        notice('أدخل رقماً تسلسلياً أو رمز صنف لتضييق البحث.');
        return;
      }

      final rows = <core.Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final page = await widget.api.fetchSerialTraceRecords(start: offset, search: query);
        rows.addAll(page);
        if (page.length < FrappeApi.pageSize) break;
        offset += page.length;
        if (rows.length >= 10000) {
          throw const FormatException('تجاوز سجل الأرقام التسلسلية 10,000 نتيجة؛ استخدم رقماً تسلسلياً أو صنفاً أكثر تحديداً.');
        }
      }
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length + 1,
            itemBuilder: (listContext, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('الأرقام التسلسلية (${rows.length})', style: Theme.of(listContext).textTheme.titleLarge),
                );
              }
              final row = rows[index - 1];
              return ListTile(
                title: Text(row['name']?.toString() ?? ''),
                subtitle: Text('الصنف: ${row['item_code'] ?? '—'} • الحالة: ${row['status'] ?? '—'} • المستودع: ${row['warehouse'] ?? '—'}'),
                onTap: () async {
                  try {
                    final entries = <core.Map<String, dynamic>>[];
                    var entryOffset = 0;
                    while (true) {
                      final page = await widget.api.fetchSerialLedgerEntries(
                        row['name'].toString(),
                        start: entryOffset,
                      );
                      entries.addAll(page);
                      if (page.length < 500) break;
                      entryOffset += page.length;
                      if (entries.length >= 10000) {
                        throw const FormatException('تجاوز سجل الرقم التسلسلي 10,000 حركة.');
                      }
                    }
                    if (!mounted || !sheetContext.mounted) return;
                    Navigator.pop(sheetContext);

                    await showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => SafeArea(
                        child: entries.isEmpty
                            ? ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  Text('تفاصيل الرقم ${row['name']}', style: Theme.of(context).textTheme.titleLarge),
                                  Text('الحالة الحالية: ${row['status'] ?? '—'}'),
                                  Text('المستودع الحالي: ${row['warehouse'] ?? '—'}'),
                                  Text('الدفعة: ${row['batch_no'] ?? '—'}'),
                                  Text('مستند الشراء: ${row['purchase_document_no'] ?? '—'}'),
                                  Text('مستند التسليم: ${row['delivery_document_no'] ?? '—'}'),
                                  const Text('لا توجد قيود Serial and Batch Bundle ظاهرة لهذا الرقم ضمن صلاحيات المستخدم أو إصدار الخادم.'),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: entries.length + 1,
                                itemBuilder: (historyContext, historyIndex) {
                                  if (historyIndex == 0) {
                                    return Text('السجل التاريخي للرقم ${row['name']}',
                                      style: Theme.of(historyContext).textTheme.titleLarge);
                                  }
                                  final entry = entries[historyIndex - 1];
                                  final bundle = entry['bundle'] as core.Map<String, dynamic>? ?? const <String, dynamic>{};
                                  return ListTile(
                                    title: Text('${bundle['posting_date'] ?? '—'} • ${bundle['voucher_type'] ?? '—'} ${bundle['voucher_no'] ?? ''}'),
                                    subtitle: Text('المستودع: ${bundle['warehouse'] ?? '—'} • الدفعة: ${entry['batch_no'] ?? '—'} • الكمية: ${entry['qty'] ?? '—'} • الاتجاه: ${bundle['type_of_transaction'] ?? '—'}'),
                                  );
                                },
                              ),
                      ),
                    );
                  } catch (error) {
                    if (mounted) notice(error.toString().replaceFirst('Exception: ', ''));
                  }
                },
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) notice(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      search.dispose();
    }
  }

  Future<List<core.Map<String, dynamic>>?> _purchaseOrderReceiptLinesDialog(
      core.Map<String, dynamic> order) async {
    final orderItems = (order['items'] as List? ?? [])
        .whereType<core.Map<String, dynamic>>()
        .where((row) {
          final ordered = double.tryParse(row['qty']?.toString() ?? '') ?? 0;
          final received = double.tryParse(row['received_qty']?.toString() ?? '') ?? 0;
          return ordered - received > 0.000001 &&
              row['name'] is String && row['item_code'] is String;
        }).toList();
    if (orderItems.isEmpty) {
      notice('لا توجد كميات متبقية للاستلام في أمر الشراء.');
      return null;
    }
    final rows = <core.Map<String, dynamic>>[];
    for (final source in orderItems) {
      final remaining = (double.tryParse(source['qty']?.toString() ?? '') ?? 0) -
          (double.tryParse(source['received_qty']?.toString() ?? '') ?? 0);
      final itemCode = source['item_code'].toString();
      final matchingItems = widget.items.where((x) => x.code == itemCode).toList();
      final item = matchingItems.isEmpty ? null : matchingItems.first;
      final suggestedWarehouse = source['warehouse']?.toString();
      final availableWarehouses = widget.warehouses.where((w) =>
          w.company == order['company']).toList();
      rows.add({
        'source': source,
        'qty': TextEditingController(text: remaining.toString()),
        'rate': TextEditingController(text: (source['rate'] ?? 0).toString()),
        'serial_no': TextEditingController(),
        'batch_no': TextEditingController(),
        'expiry_date': TextEditingController(),
        'warehouse': availableWarehouses.any((w) => w.id == suggestedWarehouse)
            ? suggestedWarehouse
            : null,
      });
      if (item == null) {
        // Keep the row visible; the master-data validation below will explain
        // when the selected company's item list is incomplete.
      }
    }
    try {
      return await showDialog<List<core.Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
          title: Text('استلام من أمر الشراء ${order['name']}'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تظهر الكميات المتبقية فقط. لا يمكن استلام كمية أكبر من المتبقي في كل بند.'),
              ...List.generate(rows.length, (index) {
                final row = rows[index];
                final source = row['source'] as core.Map<String, dynamic>;
                final code = source['item_code'].toString();
                final matchingItems = widget.items.where((x) => x.code == code).toList();
                final item = matchingItems.isEmpty ? null : matchingItems.first;
                final remaining = (double.tryParse(source['qty']?.toString() ?? '') ?? 0) -
                    (double.tryParse(source['received_qty']?.toString() ?? '') ?? 0);
                final warehouses = widget.warehouses.where((w) =>
                    w.company == order['company']).toList();
                return Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(
                  padding: const EdgeInsets.all(10), child: Column(children: [
                    Row(children: [
                      Expanded(child: Text('${source['item_name'] ?? code}',
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (rows.length > 1) IconButton(
                        tooltip: 'استبعاد البند',
                        onPressed: () => refresh(() {
                          final removed = rows.removeAt(index);
                          (removed['qty'] as TextEditingController).dispose();
                          (removed['rate'] as TextEditingController).dispose();
                          (removed['serial_no'] as TextEditingController).dispose();
                          (removed['batch_no'] as TextEditingController).dispose();
                          (removed['expiry_date'] as TextEditingController).dispose();
                        }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ]),
                    Text('المتبقي من أمر الشراء: ${remaining.toStringAsFixed(3)}'
                        '${item == null ? ' • الصنف غير موجود ضمن البيانات المحمّلة' : ''}'),
                    _field(row['qty'] as TextEditingController, 'الكمية المستلمة', number: true),
                    _field(row['rate'] as TextEditingController, 'سعر الوحدة', number: true),
                    if (item?.hasSerialNo == true)
                      TextField(controller: row['serial_no'] as TextEditingController, minLines: 2, maxLines: 4,
                        decoration: const InputDecoration(labelText: 'الأرقام التسلسلية', helperText: 'رقم لكل وحدة.')),
                    if (item?.hasBatchNo == true)
                      TextField(controller: row['batch_no'] as TextEditingController, decoration: const InputDecoration(labelText: 'رقم الدفعة')),
                    if (item?.hasExpiryDate == true)
                      TextField(controller: row['expiry_date'] as TextEditingController,
                        decoration: const InputDecoration(labelText: 'تاريخ انتهاء الدفعة (YYYY-MM-DD)')),
                    DropdownButtonFormField<String>(
                initialValue: row['warehouse'] as String?,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'مستودع الاستلام'),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text('اختر المستودع')),
                        ...warehouses.map((w) => DropdownMenuItem(value: w.id,
                          child: Text('${w.name} (${w.id})', overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => refresh(() => row['warehouse'] = v),
                    ),
                  ]),
                ));
              }),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              final result = <core.Map<String, dynamic>>[];
              for (final row in rows) {
                final source = row['source'] as core.Map<String, dynamic>;
                final code = source['item_code'].toString();
                final matchingItems = widget.items.where((x) => x.code == code).toList();
                final item = matchingItems.isEmpty ? null : matchingItems.first;
                final remaining = (double.tryParse(source['qty']?.toString() ?? '') ?? 0) -
                    (double.tryParse(source['received_qty']?.toString() ?? '') ?? 0);
                final qty = double.tryParse((row['qty'] as TextEditingController).text.trim());
                final rate = double.tryParse((row['rate'] as TextEditingController).text.trim());
                if (item == null) { notice('الصنف ' + code + ' غير موجود ضمن الأصناف المحمّلة.'); return; }
                if (qty == null || !qty.isFinite || qty <= 0 || qty > remaining + 0.000001 ||
                    rate == null || !rate.isFinite || rate < 0 ||
                    row['warehouse'] is! String || (row['warehouse'] as String).isEmpty) {
                  notice('تحقق من الكمية المتبقية والسعر ومستودع كل بند.');
                  return;
                }
                final receiptLine = <String, dynamic>{};
                for (final field in const [
                  'item_code', 'item_name', 'description', 'uom', 'stock_uom',
                  'conversion_factor', 'expense_account', 'cost_center', 'project',
                  'item_tax_template', 'item_tax_rate', 'manufacturer',
                  'manufacturer_part_no', 'supplier_part_no', 'bom',
                  'material_request', 'material_request_item', 'is_free_item',
                  'discount_percentage', 'discount_amount',
                ]) {
                  if (source[field] != null) receiptLine[field] = source[field];
                }
                try {
                  receiptLine.addAll(buildSerialBatchFields(item: item, quantity: qty,
                    serialNumbers: (row['serial_no'] as TextEditingController).text,
                    batchNumber: (row['batch_no'] as TextEditingController).text));
                } catch (error) { notice(error.toString().replaceFirst('FormatException: ', '')); return; }
                final expiry = (row['expiry_date'] as TextEditingController).text.trim();
                receiptLine.addAll({
                  'item_code': code,
                  if (expiry.isNotEmpty) 'expiry_date': expiry,
                  'qty': qty,
                  'rate': rate,
                  'warehouse': row['warehouse'],
                  'purchase_order': order['name'],
                  'purchase_order_item': source['name'],
                });
                result.add(receiptLine);
              }
              if (result.isNotEmpty) Navigator.pop(dialogContext, result);
            }, child: const Text('إنشاء سند الاستلام')),
          ],
        )),
      );
    } finally {
      for (final row in rows) {
        (row['qty'] as TextEditingController).dispose();
        (row['rate'] as TextEditingController).dispose();
        (row['serial_no'] as TextEditingController).dispose();
        (row['batch_no'] as TextEditingController).dispose();
        (row['expiry_date'] as TextEditingController).dispose();
      }
    }
  }

  Future<void> purchaseReceiptFromOrder() =>
      _runExclusive(_purchaseReceiptFromOrder);

  Future<void> _purchaseReceiptFromOrder() async {
    try {
      final orders = <core.Map<String, dynamic>>[];
      var orderOffset = 0;
      while (true) {
        final page = await widget.api.fetchPurchaseOrders(start: orderOffset);
        orders.addAll(page);
        if (page.length < FrappeApi.pageSize) break;
        orderOffset += page.length;
        if (orders.length >= 5000) {
          throw const FormatException(
            'تجاوز عدد أوامر الشراء حد التحميل الآمن (5000). استخدم البحث في ERPNext لتقليل النتائج.',
          );
        }
      }
      if (!mounted) return;
      if (orders.isEmpty) {
        notice('لا توجد أوامر شراء مرحلة متاحة، أو لا تتوفر صلاحية قراءتها.');
        return;
      }
      final orderSearch = TextEditingController();
      String? selected = orders.first['name'].toString();
      final orderName = await showDialog<String>(
        context: context,
        builder: (c) => StatefulBuilder(builder: (context, refresh) {
          final query = orderSearch.text.trim().toLowerCase();
          final filteredOrders = orders.where((order) {
            final searchable = [
              order['name'], order['supplier'], order['supplier_name'],
            ].whereType<Object>().join(' ').toLowerCase();
            return query.isEmpty || searchable.contains(query);
          }).toList(growable: false);
          if (!filteredOrders.any((order) => order['name'].toString() == selected)) {
            selected = filteredOrders.isEmpty ? null : filteredOrders.first['name'].toString();
          }
          return AlertDialog(
            title: const Text('اختيار أمر شراء'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: orderSearch,
                onChanged: (_) => refresh(() {}),
                decoration: const InputDecoration(
                  labelText: 'بحث برقم الأمر أو المورد',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              if (filteredOrders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('لا توجد أوامر شراء تطابق البحث.'),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'أمر الشراء المرحّل'),
                  items: filteredOrders.map((order) => DropdownMenuItem(
                    value: order['name'].toString(),
                    child: Text('${order['name']} • ${order['supplier_name'] ?? order['supplier'] ?? ''}',
                        overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => refresh(() { selected = v; }),
                ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
              FilledButton(
                onPressed: selected == null ? null : () => Navigator.pop(c, selected),
                child: const Text('متابعة'),
              ),
            ],
          );
        }),
      );
      orderSearch.dispose();
      if (orderName == null || !mounted) return;
      final order = await widget.api.fetchPurchaseOrderDocument(orderName);
      final lines = await _purchaseOrderReceiptLinesDialog(order);
      if (lines == null || !mounted) return;
      final doc = await widget.api.createPurchaseReceipt({
        'doctype': 'Purchase Receipt',
        'company': order['company'],
        'supplier': order['supplier'],
        'posting_date': DateTime.now().toIso8601String().substring(0, 10),
        'items': lines,
      });
      if (await confirm('ترحيل سند الاستلام',
          'تم إنشاء ${doc['name'] ?? ''} وربطه بأمر الشراء $orderName. سيتم تحديث الكميات المستلمة في الأمر والمخزون.')) {
        try {
          final submitted = await widget.api.submitPurchaseReceipt(doc);
          notice('تم ترحيل سند الاستلام ${submitted['name'] ?? doc['name']}');
          await load();
          widget.onChanged?.call();
        } catch (e) {
          notice('حُفظ سند الاستلام ${doc['name'] ?? ''} كمسودة. راجعه قبل إنشاء سند آخر. ${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('حُفظت مسودة سند الاستلام ${doc['name'] ?? ''}');
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> purchaseReceipt() =>
      _runExclusive(_purchaseReceipt);

  Future<void> _purchaseReceipt() async {
    if (widget.companies.isEmpty || widget.suppliers.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) {
      notice('حمّل الشركات والموردين والأصناف والمستودعات أولاً.');
      return;
    }
    var company = widget.companies.first.name;
    var supplier = widget.suppliers.first.id;
    String? warehouse;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
      builder: (context, refresh) {
        final available = widget.warehouses.where((w) => w.company == company).toList();
        if (!available.any((w) => w.id == warehouse)) warehouse = null;
        return AlertDialog(
          title: const Text('استلام بضاعة من مورد'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
                initialValue: company, isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(),
              onChanged: (v) => refresh(() { if (v != null) { company = v; warehouse = null; } }),
            ),
            DropdownButtonFormField<String>(
                initialValue: supplier, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المورد'),
              items: widget.suppliers.map((x) => DropdownMenuItem(value: x.id,
                child: Text('${x.name} (${x.id})', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => refresh(() { if (v != null) supplier = v; }),
            ),
            DropdownButtonFormField<String>(
                initialValue: warehouse, isExpanded: true,
              decoration: const InputDecoration(labelText: 'مستودع الاستلام'),
              items: available.map((w) => DropdownMenuItem(value: w.id,
                child: Text('${w.name} (${w.id})', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => refresh(() => warehouse = v),
            ),
            const Text('يمكن إضافة عدة أصناف في سند الاستلام نفسه.'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if (company.isNotEmpty && supplier.isNotEmpty && warehouse != null) Navigator.pop(c, true);
            }, child: const Text('التالي')),
          ],
        );
      },
    ));
    if (ok != true || warehouse == null || !mounted) return;
    final lines = await _stockItemLinesDialog(title: 'أصناف سند الاستلام', includeRate: true);
    if (lines == null || !mounted) return;
    try {
      final doc = await widget.api.createPurchaseReceipt({
        'doctype': 'Purchase Receipt', 'company': company, 'supplier': supplier,
        'posting_date': DateTime.now().toIso8601String().substring(0, 10),
        'items': lines.map((row) => {
          'item_code': row['item_code'], 'qty': row['qty'],
          'rate': row['valuation_rate'], 'warehouse': warehouse,
          if (row['use_serial_batch_fields'] != null) 'use_serial_batch_fields': row['use_serial_batch_fields'],
          if (row['serial_no'] != null) 'serial_no': row['serial_no'],
          if (row['batch_no'] != null) 'batch_no': row['batch_no'],
        }).toList(),
      });
      if (await confirm('ترحيل سند الاستلام',
          'تم إنشاء سند الاستلام ${doc['name'] ?? ''} بعدد ${lines.length} صنف. الترحيل سيضيف الكميات للمخزون.')) {
        try {
          final result = await widget.api.submitPurchaseReceipt(doc);
          notice('تم ترحيل سند الاستلام ${result['name'] ?? doc['name']}');
          await load();
          widget.onChanged?.call();
        } catch (e) {
          notice('حُفظ سند الاستلام ${doc['name'] ?? ''} كمسودة. راجعه قبل إنشاء سند آخر. ${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('حُفظت مسودة سند الاستلام ${doc['name'] ?? ''}');
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> reconcile() =>
      _runExclusive(_reconcile);

  Future<void> _reconcile() async {
    if (widget.companies.isEmpty || widget.items.isEmpty || widget.warehouses.isEmpty) {
      notice('حمّل الشركات والأصناف والمستودعات أولاً.');
      return;
    }
    var company = widget.companies.first.name;
    String? warehouse;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
      builder: (context, refresh) {
        final available = widget.warehouses.where((w) => w.company == company).toList();
        if (!available.any((w) => w.id == warehouse)) warehouse = null;
        return AlertDialog(
          title: const Text('جرد وتسوية المخزون'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
                initialValue: company, isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(),
              onChanged: (v) => refresh(() { if (v != null) { company = v; warehouse = null; } }),
            ),
            DropdownButtonFormField<String>(
                initialValue: warehouse, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المستودع'),
              items: available.map((w) => DropdownMenuItem(value: w.id,
                child: Text('${w.name} (${w.id})', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => refresh(() => warehouse = v),
            ),
            const Text('أدخل الكمية الفعلية لكل صنف. الكمية صفر مسموحة.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if (company.isNotEmpty && warehouse != null) Navigator.pop(c, true);
            }, child: const Text('التالي')),
          ],
        );
      },
    ));
    if (ok != true || warehouse == null || !mounted) return;
    final lines = await _stockItemLinesDialog(
      title: 'أصناف الجرد والكميات الفعلية',
      includeRate: true,
      allowZeroQuantity: true,
      reconciliationWarehouse: warehouse,
    );
    if (lines == null || !mounted) return;
    try {
      final doc = await widget.api.createStockReconciliation(
        company: company,
        warehouse: warehouse!,
        items: lines,
      );
      if (await confirm('تأكيد تسوية المخزون',
          'تم إنشاء مسودة ${doc['name'] ?? ''} بعدد ${lines.length} صنف. ستضبط الأرصدة إلى الكميات الفعلية المدخلة. هل تريد الترحيل؟')) {
        try {
          final result = await widget.api.submitStockReconciliation(doc);
          notice('تم ترحيل التسوية ${result['name'] ?? doc['name']}');
          await load();
          widget.onChanged?.call();
        } catch (e) {
          notice('حُفظت مسودة التسوية ${doc['name'] ?? ''} ولم يؤكد ترحيلها. راجعها قبل إنشاء تسوية أخرى. ${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        notice('حُفظت مسودة التسوية ${doc['name'] ?? ''}');
      }
    } catch (e) {
      notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(labelText: label)));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('عمليات المخزون'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('الاستلام والصرف والتحويل والجرد تُنفّذ بمستندات ERPNext الرسمية. لا يتم تعديل Bin مباشرة.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: loadingReorderAlerts ? null : loadReorderAlerts,
        icon: loadingReorderAlerts
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.notifications_active_outlined),
        label: Text(loadingReorderAlerts ? 'جارٍ فحص حدود إعادة الطلب...' : 'فحص الأصناف تحت حد إعادة الطلب'),
      ),
      if (reorderAlertError != null)
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(reorderAlertError!))),
      if (reorderAlerts.isNotEmpty) ...[
        Text('تنبيهات إعادة الطلب (${reorderAlerts.length})', style: Theme.of(context).textTheme.titleMedium),
        ...reorderAlerts.map((alert) => Card(child: ListTile(
          leading: const Icon(Icons.warning_amber_outlined),
          title: Text('${alert.itemCode} • ${alert.warehouse}'),
          subtitle: Text('المتاح المتوقع: ${alert.projectedQty} ${alert.stockUom ?? ''} • حد إعادة الطلب: ${alert.reorderLevel} • كمية الطلب المقترحة: ${alert.reorderQty}'),
          isThreeLine: true,
        ))),
      ] else if (!loadingReorderAlerts && reorderAlertError == null)
        const Text('اضغط فحص الأصناف لعرض الأصناف التي وصلت كميتها المتوقعة إلى حد إعادة الطلب أو أقل.'),

      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonal(onPressed: () => movement('Material Receipt'), child: const Text('استلام مخزون')),
        FilledButton.tonal(onPressed: purchaseReceipt, child: const Text('استلام مشتريات مباشر')),
        FilledButton.tonal(onPressed: purchaseReceiptFromOrder, child: const Text('استلام من أمر شراء')),
        FilledButton.tonal(onPressed: () => movement('Material Issue'), child: const Text('صرف / تسليم')),
        FilledButton.tonal(onPressed: () => _runExclusive(() => _movement('Material Issue', damage: true)), child: const Text('تسجيل تلف وهالك')),
        FilledButton.tonal(onPressed: pickPackShip, child: const Text('التقاط وتجهيز وشحن')),
        FilledButton.tonal(onPressed: showBatchTrace, child: const Text('تتبع الدفعات')),
        FilledButton.tonal(onPressed: showSerialTrace, child: const Text('تتبع الأرقام التسلسلية')),
        FilledButton.tonal(onPressed: () => movement('Material Transfer'), child: const Text('تحويل')),
        FilledButton.icon(onPressed: reconcile, icon: const Icon(Icons.fact_check_outlined), label: const Text('جرد وتسوية')),
      ]),
      const Divider(height: 28),
      Text('المسودات غير المرحلة (' + drafts.length.toString() + ')', style: Theme.of(context).textTheme.titleMedium),
      if (draftError != null) Text(draftError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
      if (drafts.isEmpty && !loading) const ListTile(title: Text('لا توجد مسودات مخزون ظاهرة.')),
      ...drafts.map((draft) => Card(child: ListTile(
        leading: const Icon(Icons.pending_actions_outlined),
        title: Text((draft['doctype'] ?? '').toString() + ' • ' + (draft['name'] ?? '').toString()),
        subtitle: Text((draft['company'] ?? '').toString() + ' • ' + (draft['posting_date'] ?? '').toString()),
        trailing: IconButton(tooltip: 'مراجعة المسودة', onPressed: () => reviewDraft(draft), icon: const Icon(Icons.visibility_outlined)),
        onTap: () => reviewDraft(draft),
      ))),
      if (draftHasMore.values.any((hasMore) => hasMore) || loadingMoreDrafts)
        Center(child: TextButton.icon(
          onPressed: loadingMoreDrafts ? null : loadMoreStockDrafts,
          icon: loadingMoreDrafts
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.expand_more),
          label: const Text('تحميل مسودات مخزون إضافية'),
        )),
      const Divider(height: 28), Text('سجل الحركات', style: Theme.of(context).textTheme.titleMedium),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: loading ? null : () => _pickMovementDate(from: true),
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('من: ${_movementDateLabel(selectedMovementFromDate)}'),
          ),
          OutlinedButton.icon(
            onPressed: loading ? null : () => _pickMovementDate(from: false),
            icon: const Icon(Icons.event_outlined),
            label: Text('إلى: ${_movementDateLabel(selectedMovementToDate)}'),
          ),
          if (selectedMovementFromDate != null || selectedMovementToDate != null)
            TextButton.icon(
              onPressed: loading ? null : () {
                setState(() {
                  selectedMovementFromDate = null;
                  selectedMovementToDate = null;
                });
                load();
              },
              icon: const Icon(Icons.clear),
              label: const Text('مسح الفترة'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
                initialValue: selectedMovementItem,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'تصفية حسب الصنف'),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('كل الأصناف')),
          ...widget.items.map((x) => DropdownMenuItem(value: x.code,
            child: Text('${x.name} (${x.code})', overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (v) { setState(() => selectedMovementItem = v); load(); },
      ),
      DropdownButtonFormField<String>(
        initialValue: selectedMovementCompany,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'تصفية حسب الشركة'),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('كل الشركات')),
          ...widget.companies.map((company) => DropdownMenuItem(value: company.name, child: Text(company.name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (value) { setState(() => selectedMovementCompany = value); load(); },
      ),
      DropdownButtonFormField<String>(
                initialValue: selectedMovementWarehouse,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'تصفية حسب المستودع'),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('كل المستودعات')),
          ...widget.warehouses.map((w) => DropdownMenuItem(value: w.id,
            child: Text('${w.name} (${w.id})', overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (v) { setState(() => selectedMovementWarehouse = v); load(); },
      ),
      if (loading) const LinearProgressIndicator(), if (error != null) Text(error!),
      if (movements.isEmpty && !loading) const ListTile(title: Text('لا توجد حركات ظاهرة أو لا تتوفر صلاحية قراءة سجل المخزون.')),
      ...movements.map((x) => Card(child: ListTile(leading: const Icon(Icons.swap_horiz),
        title: Text((x['item_code'] ?? '—').toString() + ' • ' + (x['warehouse'] ?? '—').toString()),
        subtitle: Text((x['posting_date'] ?? '').toString() + ' • ' + (x['voucher_type'] ?? '').toString() + ' • ' + (x['voucher_no'] ?? '').toString()),
        trailing: Text((x['actual_qty'] ?? 0).toString()),
        onTap: () => showMovementDetails(x)))),
      if (hasMore || loadingMore) Center(child: TextButton.icon(onPressed: loadingMore ? null : loadMoreMovements, icon: loadingMore ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more), label: const Text('تحميل حركات إضافية'))),
    ]),
  );
}
