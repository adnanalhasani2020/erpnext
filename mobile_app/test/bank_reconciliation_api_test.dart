import 'dart:convert';
import 'dart:io';

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

    test('applies account and voucher-type filters to customer ledger queries', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      List<dynamic>? filters;
      server.listen((request) async {
        filters = jsonDecode(request.uri.queryParameters['filters']!) as List<dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': []}));
        await request.response.close();
      });
      final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
      try {
        await api.fetchCustomerLedger(
          customer: 'CUST-1',
          company: 'COMP-1',
          account: 'Debtors - CO',
          voucherType: 'Sales Invoice',
        );
        expect(filters, contains(['account', '=', 'Debtors - CO']));
        expect(filters, contains(['voucher_type', '=', 'Sales Invoice']));
        expect(filters, contains(['company', '=', 'COMP-1']));
        expect(filters, contains(['party', '=', 'CUST-1']));
      } finally {
        api.dispose();
        await server.close(force: true);
      }
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
