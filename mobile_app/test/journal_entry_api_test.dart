import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  late FrappeApi api;
  setUp(() => api = FrappeApi());
  tearDown(() => api.dispose());

  group('Journal Entry draft guards', () {
    test('requires a valid ISO posting date before network access', () async {
      await expectLater(
        api.saveJournalEntryDraft(
          company: 'Company A',
          postingDate: '09/11/2026',
          remark: '',
          accounts: const [
            {'account': 'Cash', 'debit': 10, 'credit': 0},
            {'account': 'Sales', 'debit': 0, 'credit': 10},
          ],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires at least two account rows before network access', () async {
      await expectLater(
        api.saveJournalEntryDraft(
          company: 'Company A',
          postingDate: '2026-11-09',
          remark: '',
          accounts: const [
            {'account': 'Cash', 'debit': 10, 'credit': 0},
          ],
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
