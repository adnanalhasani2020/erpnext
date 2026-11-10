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

    test('rejects invalid bank voucher date filters before network access', () async {
      await expectLater(
        api.fetchLinkedBankVouchers(
          transactionName: 'BT-001',
          bankAccount: 'BANK-001',
          company: 'Company A',
          fromDate: '2026-11-30',
          toDate: '2026-11-01',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unsupported bank statement file types before network access', () async {
      await expectLater(
        api.createBankStatementImportPreview(
          bankAccount: 'BANK-001', company: 'Company A',
          fileName: 'statement.pdf', fileBytes: const [1, 2, 3],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty bank statement file before network access', () async {
      await expectLater(
        api.createBankStatementImportPreview(
          bankAccount: 'BANK-001', company: 'Company A',
          fileName: 'statement.csv', fileBytes: const [],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects reversed customer ledger date range before network access', () async {
      await expectLater(
        api.fetchCustomerLedger(
          customer: 'CUST-001', fromDate: '2026-11-30', toDate: '2026-11-01',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects reversed supplier ledger date range before network access', () async {
      await expectLater(
        api.fetchSupplierLedger(
          supplier: 'SUP-001', fromDate: '2026-11-30', toDate: '2026-11-01',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid party ledger totals date range before network access', () async {
      await expectLater(
        api.fetchPartyLedgerTotals(
          partyType: 'Customer', party: 'CUST-001',
          fromDate: '2026-11-30', toDate: '2026-11-01',
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
