import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/models/serial_batch_tracking.dart';
void main() {
  test('serial items require one unique serial per whole unit', () {
    const item = ErpItem(code: 'SER-1', name: 'Serial item', isStockItem: true, hasSerialNo: true);
    final payload = buildSerialBatchFields(item: item, quantity: 2, serialNumbers: 'SN-001\nSN-002', batchNumber: '');
    expect(payload['use_serial_batch_fields'], 1);
    expect(payload['serial_no'], 'SN-001\nSN-002');
    expect(() => buildSerialBatchFields(item: item, quantity: 2, serialNumbers: 'SN-001', batchNumber: ''), throwsFormatException);
    expect(() => buildSerialBatchFields(item: item, quantity: 2, serialNumbers: 'SN-001\nSN-001', batchNumber: ''), throwsFormatException);
    expect(() => buildSerialBatchFields(item: item, quantity: 1.5, serialNumbers: 'SN-001\nSN-002', batchNumber: ''), throwsFormatException);
  });
  test('serial item payload supports batches larger than the former 200-unit cap', () {
    const item = ErpItem(code: 'SER-LARGE', name: 'Large serial item', isStockItem: true, hasSerialNo: true);
    final serials = List.generate(201, (index) => 'SN-${index + 1}');
    final payload = buildSerialBatchFields(
      item: item,
      quantity: 201,
      serialNumbers: serials.join('\\n'),
      batchNumber: '',
    );
    expect((payload['serial_no'] as String).split('\\n'), hasLength(201));
  });
  test('batch items require one batch identifier per line', () {
    const item = ErpItem(code: 'BAT-1', name: 'Batch item', isStockItem: true, hasBatchNo: true);
    final payload = buildSerialBatchFields(item: item, quantity: 12, serialNumbers: '', batchNumber: 'LOT-2026-01');
    expect(payload['use_serial_batch_fields'], 1);
    expect(payload['batch_no'], 'LOT-2026-01');
    expect(() => buildSerialBatchFields(item: item, quantity: 12, serialNumbers: '', batchNumber: ''), throwsFormatException);
  });
  test('combined serial and batch items carry both identifiers', () {
    const item = ErpItem(code: 'MIX-1', name: 'Tracked item', isStockItem: true, hasSerialNo: true, hasBatchNo: true);
    final payload = buildSerialBatchFields(item: item, quantity: 1, serialNumbers: 'SN-100', batchNumber: 'LOT-100');
    expect(payload['serial_no'], 'SN-100');
    expect(payload['batch_no'], 'LOT-100');
  });
  test('ordinary items do not receive tracking fields', () {
    const item = ErpItem(code: 'STD-1', name: 'Standard item', isStockItem: true);
    expect(buildSerialBatchFields(item: item, quantity: 5, serialNumbers: '', batchNumber: ''), isEmpty);
  });
}
