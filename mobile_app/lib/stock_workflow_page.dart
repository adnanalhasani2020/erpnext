import 'dart:core';
import 'dart:core' as core;
// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';
import 'models/serial_batch_tracking.dart';
import 'workspace_web_page.dart';

class StockWorkflowPage extends StatefulWidget {
  const StockWorkflowPage({super.key, required this.api, required this.companies, required this.suppliers, required this.items, required this.warehouses, this.initialItemCode, this.onChanged, this.initialSection});
  final FrappeApi api;
  final String? initialItemCode;
  final String? initialSection;
  final List<ErpCompany> companies;
  final List<ErpSupplier> suppliers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final VoidCallback? onChanged;
  @override State<StockWorkflowPage> createState() => _StockWorkflowPageState();
}

class _StockWorkflowPageState extends State<StockWorkflowPage> {
  bool _showStockSection(String section) => widget.initialSection == null || widget.initialSection == section;

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
    appBar: AppBar(
      title: Text(widget.initialSection ?? 'عمليات المخزون'),
      actions: [
        if (widget.initialSection != null)
          IconButton(tooltip: 'فتح قائمة الجوال', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceWebPage(api: widget.api, title: widget.initialSection!, linkType: 'DocTypeList', target: widget.initialSection!))), icon: const Icon(Icons.arrow_forward)),
        IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('الاستلام والصرف والتحويل والجرد تُنفّذ بمستندات ERPNext الرسمية. لا يتم تعديل Bin مباشرة.'),
      const SizedBox(height: 12),
      if (_showStockSection('Item Reorder')) ...[
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

      ],
      if (widget.initialSection == null || const {'Stock Entry','Purchase Receipt','Pick List','Batch','Serial No','Stock Reconciliation'}.contains(widget.initialSection)) ...[
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (_showStockSection('Stock Entry')) FilledButton.tonal(onPressed: () => movement('Material Receipt'), child: const Text('استلام مخزون')),
        if (_showStockSection('Purchase Receipt')) FilledButton.tonal(onPressed: purchaseReceipt, child: const Text('استلام مشتريات مباشر')),
        if (_showStockSection('Purchase Receipt')) FilledButton.tonal(onPressed: purchaseReceiptFromOrder, child: const Text('استلام من أمر شراء')),
        if (_showStockSection('Stock Entry')) FilledButton.tonal(onPressed: () => movement('Material Issue'), child: const Text('صرف / تسليم')),
        if (_showStockSection('Stock Entry')) FilledButton.tonal(onPressed: () => _runExclusive(() => _movement('Material Issue', damage: true)), child: const Text('تسجيل تلف وهالك')),
        if (_showStockSection('Pick List')) FilledButton.tonal(onPressed: pickPackShip, child: const Text('التقاط وتجهيز وشحن')),
        if (_showStockSection('Batch')) FilledButton.tonal(onPressed: showBatchTrace, child: const Text('تتبع الدفعات')),
        if (_showStockSection('Serial No')) FilledButton.tonal(onPressed: showSerialTrace, child: const Text('تتبع الأرقام التسلسلية')),
        if (_showStockSection('Stock Entry')) FilledButton.tonal(onPressed: () => movement('Material Transfer'), child: const Text('تحويل')),
        if (_showStockSection('Stock Reconciliation')) FilledButton.icon(onPressed: reconcile, icon: const Icon(Icons.fact_check_outlined), label: const Text('جرد وتسوية')),
      ]),
      ],
      if (widget.initialSection == null || const {'Stock Entry','Purchase Receipt','Stock Reconciliation'}.contains(widget.initialSection)) ...[
      const Divider(height: 28),
      Text('المسودات غير المرحلة (' + drafts.where((d) => widget.initialSection == null || d['doctype'] == widget.initialSection).length.toString() + ')', style: Theme.of(context).textTheme.titleMedium),
      if (draftError != null) Text(draftError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
      if (drafts.isEmpty && !loading) const ListTile(title: Text('لا توجد مسودات مخزون ظاهرة.')),
      ...drafts.where((draft) => widget.initialSection == null || draft['doctype'] == widget.initialSection).map((draft) => Card(child: ListTile(
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
      ],
      if (_showStockSection('Stock Entry')) ...[
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
      ],
    ]),
  );
}
