import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  group('Bank reconciliation API validation', () {
    late FrappeApi api;

    setUp(() => api = FrappeApi());
    tearDown(() => api.dispose());

    test('requires company before loading bank accounts', () async {
      await expectLater(
        api.fetchBankAccounts(company: ' '),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a company and bank account before loading transactions', () async {
      await expectLater(
        api.fetchBankTransactions(bankAccount: ' ', company: 'Company A'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects reversed bank transaction date ranges', () async {
      await expectLater(
        api.fetchBankTransactions(
          bankAccount: 'BANK-001',
          company: 'Company A',
          fromDate: '2026-11-30',
          toDate: '2026-11-01',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid bank balance date before network access', () async {
      await expectLater(
        api.fetchBankReconciliationBalances(
          bankAccount: 'BANK-001',
          company: 'Company A',
          date: 'today',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires vouchers before reconciling a bank transaction', () async {
      await expectLater(
        api.reconcileBankTransaction(
          transactionName: 'BT-001',
          bankAccount: 'BANK-001',
          company: 'Company A',
          vouchers: const [],
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
