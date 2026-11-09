import 'erp_models.dart';
List<String> parseSerialNumbers(String value) => value.split(RegExp(r'[\r\n,;]+')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList(growable: false);
Map<String, dynamic> buildSerialBatchFields({required ErpItem item, required double quantity, required String serialNumbers, required String batchNumber}) {
  if (!item.hasSerialNo && !item.hasBatchNo) return const {};
  if (!quantity.isFinite || quantity <= 0) throw const FormatException('كمية الصنف المتتبع يجب أن تكون أكبر من صفر.');
  final serials = parseSerialNumbers(serialNumbers);
  final batch = batchNumber.trim();
  if (item.hasSerialNo) {
    final rounded = quantity.round();
    if ((quantity - rounded).abs() > 0.000001 || serials.length != rounded) throw FormatException('أدخل رقماً تسلسلياً مستقلاً لكل وحدة من الصنف ' + item.code + '.');
    if (serials.toSet().length != serials.length) throw FormatException('توجد أرقام تسلسلية مكررة للصنف ' + item.code + '.');
  } else if (serials.isNotEmpty) {
    throw FormatException('الصنف ' + item.code + ' لا يستخدم أرقاماً تسلسلية.');
  }
  if (item.hasBatchNo && batch.isEmpty) throw FormatException('رقم الدفعة مطلوب للصنف ' + item.code + '. قسّم الكمية إلى بنود منفصلة عند استخدام عدة دفعات.');
  if (!item.hasBatchNo && batch.isNotEmpty) throw FormatException('الصنف ' + item.code + ' لا يستخدم الدفعات.');
  return {'use_serial_batch_fields': 1, if (item.hasSerialNo) 'serial_no': serials.join('\n'), if (item.hasBatchNo) 'batch_no': batch};
}
