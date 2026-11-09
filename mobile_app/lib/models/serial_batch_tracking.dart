// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import '../api/frappe_api.dart';
import 'erp_models.dart';
List<String> parseSerialNumbers(String value) => value.split(RegExp(r'[\r\n,;]+')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList(growable: false);
Map<String, dynamic> buildSerialBatchFields({required ErpItem item, required double quantity, required String serialNumbers, required String batchNumber}) {
  if (!item.hasSerialNo && !item.hasBatchNo) return const {};
  if (!quantity.isFinite || quantity <= 0) throw const FormatException('كمية الصنف المتتبع يجب أن تكون أكبر من صفر.');
  final serials = parseSerialNumbers(serialNumbers);
  final batch = batchNumber.trim();
  if (item.hasSerialNo) {
    final rounded = quantity.round();
    if ((quantity - rounded).abs() > 0.000001 || serials.length != rounded) throw FormatException('أدخل رقماً تسلسلياً مستقلاً لكل وحدة من الصنف ${item.code}.');
    if (serials.toSet().length != serials.length) throw FormatException('توجد أرقام تسلسلية مكررة للصنف ${item.code}.');
  } else if (serials.isNotEmpty) {
    throw FormatException('الصنف ${item.code} لا يستخدم أرقاماً تسلسلية.');
  }
  if (item.hasBatchNo && batch.isEmpty) throw FormatException('رقم الدفعة مطلوب للصنف ${item.code}. قسّم الكمية إلى بنود منفصلة عند استخدام عدة دفعات.');
  if (!item.hasBatchNo && batch.isNotEmpty) throw FormatException('الصنف ${item.code} لا يستخدم الدفعات.');
  return {'use_serial_batch_fields': 1, if (item.hasSerialNo) 'serial_no': serials.join('\n'), if (item.hasBatchNo) 'batch_no': batch};
}


Future<Map<String, dynamic>?> showAvailableSerialBatchPicker({
  required BuildContext context,
  required FrappeApi api,
  required ErpItem item,
  required double quantity,
  required String warehouse,
}) async {
  if (quantity <= 0 || !quantity.isFinite ||
      (item.hasSerialNo && (quantity - quantity.round()).abs() > 0.000001)) {
    throw const FormatException('كمية الصنف غير صالحة لاختيار أرقامه.');
  }
  if (item.hasSerialNo && quantity > 200) {
    throw const FormatException('اختيار أكثر من 200 رقم تسلسلي في عملية واحدة غير مدعوم.');
  }
  final batches = item.hasBatchNo
      ? await api.fetchAvailableBatches(itemCode: item.code, warehouse: warehouse)
      : <Map<String, dynamic>>[];
  if (item.hasBatchNo && batches.isEmpty) {
    throw FormatException('لا توجد دفعات موجبة متاحة للصنف ' + item.code + ' في المستودع المحدد.');
  }
  String? selectedBatch = item.hasBatchNo ? batches.first['batch_no']?.toString() : null;
  List<String> availableSerials = [];
  if (item.hasSerialNo) {
    availableSerials = await api.fetchAvailableSerialNumbers(
      itemCode: item.code,
      warehouse: warehouse,
      quantity: (quantity.round() * 5).clamp(quantity.round(), 200).toInt(),
      batchNumbers: selectedBatch == null ? const [] : [selectedBatch],
    );
    if (availableSerials.length < quantity.round()) {
      throw FormatException('المتاح من الأرقام التسلسلية للصنف ' + item.code + ' أقل من الكمية المطلوبة.');
    }
  }
  if (!context.mounted) return null;
  final selectedSerials = <String>{};
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, refresh) {
      final batchRow = batches.where((row) => row['batch_no'] == selectedBatch).toList();
      final availableQty = batchRow.isEmpty ? 0.0 : (double.tryParse(batchRow.first['qty']?.toString() ?? '') ?? 0);
      return AlertDialog(
        title: Text('اختيار تتبع ' + item.name),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('المستودع: ' + warehouse + ' • الكمية المطلوبة: ' + quantity.toString()),
            if (item.hasBatchNo) ...[
              DropdownButtonFormField<String>(
                initialValue: selectedBatch,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الدفعة المتاحة'),
                items: batches.map((row) {
                  final batchNo = row['batch_no'].toString();
                  final qty = row['qty'] ?? 0;
                  final expiry = row['expiry_date'];
                  return DropdownMenuItem(value: batchNo,
                    child: Text(batchNo + ' • متاح: ' + qty.toString() +
                      (expiry == null ? '' : ' • انتهاء: ' + expiry.toString()), overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  selectedSerials.clear();
                  refresh(() { selectedBatch = value; availableSerials = []; });
                  if (item.hasSerialNo) {
                    try {
                      final serials = await api.fetchAvailableSerialNumbers(
                        itemCode: item.code, warehouse: warehouse,
                        quantity: (quantity.round() * 5).clamp(quantity.round(), 200).toInt(),
                        batchNumbers: [value],
                      );
                      if (!dialogContext.mounted) return;
                      refresh(() => availableSerials = serials);
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
                    }
                  }
                },
              ),
              Text('الكمية المتاحة في الدفعة: ' + availableQty.toString()),
              if (availableQty + 0.000001 < quantity)
                const Text('الكمية المطلوبة أكبر من المتاح في هذه الدفعة؛ اختر دفعة أخرى أو قسّم البند.', style: TextStyle(color: Colors.red)),
            ],
            if (item.hasSerialNo) ...[
              const SizedBox(height: 10),
              Text('اختر ' + quantity.round().toString() + ' رقماً من المتاح (' + availableSerials.length.toString() + ')'),
              if (availableSerials.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
              else
                ...availableSerials.map((serial) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selectedSerials.contains(serial),
                  title: Text(serial),
                  onChanged: (checked) => refresh(() {
                    if (checked == true && selectedSerials.length < quantity.round()) {
                      selectedSerials.add(serial);
                    } else {
                      selectedSerials.remove(serial);
                    }
                  }),
                )),
            ],
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: (item.hasBatchNo && availableQty + 0.000001 < quantity) ||
                (item.hasSerialNo && selectedSerials.length != quantity.round())
                ? null
                : () {
                    try {
                      Navigator.pop(dialogContext, buildSerialBatchFields(
                        item: item, quantity: quantity,
                        serialNumbers: selectedSerials.join('\n'),
                        batchNumber: selectedBatch ?? '',
                      ));
                    } catch (error) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
                    }
                  },
            child: const Text('اعتماد الاختيار'),
          ),
        ],
      );
    }),
  );
}
