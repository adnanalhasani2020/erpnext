import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  late FrappeApi api;

  setUp(() => api = FrappeApi());
  tearDown(() => api.dispose());



  group('Expense Claim payment', () {
    test('rejects blank claim and non-positive amounts before network access', () async {
      await expectLater(
        api.payExpenseClaim(claimName: ' ', amount: 10),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        api.payExpenseClaim(claimName: 'EXP-001', amount: 0),
        throwsA(isA<FormatException>()),
      );
    });

    test('creates and submits an ERPNext Payment Entry for an approved employee claim', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <String>[];
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        final segments = request.uri.pathSegments;
        final path = segments.join('/');
        calls.add('${request.method} $path');
        if (request.method == 'GET' && path.endsWith('Expense Claim/EXP-001')) {
          request.response.write(jsonEncode({'data': {
            'doctype': 'Expense Claim',
            'name': 'EXP-001',
            'company': 'Company A',
            'employee': 'EMP-001',
            'docstatus': 1,
            'approval_status': 'Approved',
            'total_sanctioned_amount': 100,
            'total_amount_reimbursed': 20,
          }}));
        } else if (request.method == 'GET' && segments.last == 'Payment Entry') {
          request.response.write(jsonEncode({'data': []}));
        } else if (request.method == 'POST' && path.endsWith('/get_payment_entry')) {
          request.response.write(jsonEncode({'message': {
            'doctype': 'Payment Entry',
            'name': 'PE-001',
            'company': 'Company A',
            'payment_type': 'Pay',
            'party_type': 'Employee',
            'party': 'EMP-001',
            'paid_amount': 30,
            'docstatus': 0,
            'references': [{
              'reference_doctype': 'Expense Claim',
              'reference_name': 'EXP-001',
              'allocated_amount': 30,
            }],
          }}));
        } else if (request.method == 'POST' && path.endsWith('Payment Entry')) {
          request.response.write(jsonEncode({'data': {
            'doctype': 'Payment Entry',
            'name': 'PE-001',
            'company': 'Company A',
            'payment_type': 'Pay',
            'party_type': 'Employee',
            'party': 'EMP-001',
            'docstatus': 0,
            'references': [{
              'reference_doctype': 'Expense Claim',
              'reference_name': 'EXP-001',
              'allocated_amount': 30,
            }],
          }}));
        } else if (request.method == 'GET' && path.endsWith('Payment Entry/PE-001')) {
          request.response.write(jsonEncode({'data': {
            'doctype': 'Payment Entry',
            'name': 'PE-001',
            'company': 'Company A',
            'payment_type': 'Pay',
            'party_type': 'Employee',
            'party': 'EMP-001',
            'docstatus': 0,
            'references': [{
              'reference_doctype': 'Expense Claim',
              'reference_name': 'EXP-001',
              'allocated_amount': 30,
            }],
          }}));
        } else if (request.method == 'POST' && path.endsWith('/frappe.client.submit')) {
          request.response.write(jsonEncode({'message': {
            'doctype': 'Payment Entry',
            'name': 'PE-001',
            'company': 'Company A',
            'payment_type': 'Pay',
            'party_type': 'Employee',
            'party': 'EMP-001',
            'docstatus': 1,
            'references': [{
              'reference_doctype': 'Expense Claim',
              'reference_name': 'EXP-001',
              'allocated_amount': 30,
            }],
          }}));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'message': 'Not found'}));
        }
        await request.response.close();
      });
      final client = FrappeApi()..configure('http://127.0.0.1:${server.port}');
      try {
        final result = await client.payExpenseClaim(
          claimName: 'EXP-001',
          amount: 30,
        );
        expect(result['name'], 'PE-001');
        expect(result['docstatus'], 1);
        expect(result['party_type'], 'Employee');
        expect(calls.where((call) => call.contains('Payment Entry')).length, greaterThanOrEqualTo(2));
      } finally {
        client.dispose();
        await server.close(force: true);
      }
    });
  });

  group('Journal entry safety validation', () {
    test('rejects malformed journal dates before network access', () async {
      await expectLater(
        api.saveJournalEntryDraft(
          company: 'Company A',
          postingDate: '09/11/2026',
          remark: 'Test',
          accounts: const [
            {'account': 'Cash - AC', 'debit': 10},
            {'account': 'Sales - AC', 'credit': 10},
          ],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires at least two journal lines before network access', () async {
      await expectLater(
        api.saveJournalEntryDraft(
          company: 'Company A',
          postingDate: '2026-11-09',
          remark: 'Test',
          accounts: const [
            {'account': 'Cash - AC', 'debit': 10},
          ],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty journal cancellation identifiers before network access', () async {
      await expectLater(
        api.cancelJournalEntry(' ', company: 'Company A'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed reversal dates before network access', () async {
      await expectLater(
        api.createJournalEntryReversalDraft(
          name: 'JV-0001',
          company: 'Company A',
          postingDate: 'tomorrow',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HR workflow validation', () {
    test('rejects incomplete workflow transition identity before network access', () async {
      await expectLater(
        api.fetchWorkflowTransitions(doctype: 'Leave Application', name: ' ', company: 'Company A'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects incomplete workflow action before network access', () async {
      await expectLater(
        api.applyWorkflowAction(
          doctype: 'Leave Application', name: 'LEAVE-001',
          company: 'Company A', action: ' ',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('submits the reviewed payroll employee list without refilling it', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <String>[];
      List<dynamic>? submittedEmployees;
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final path = request.uri.pathSegments.join('/');
        calls.add('${request.method} $path');
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && path.endsWith('Payroll Entry/PE-001')) {
          request.response.write(jsonEncode({'data': {
            'doctype': 'Payroll Entry',
            'name': 'PE-001',
            'company': 'Company A',
            'docstatus': 0,
            'employees': [
              {'employee': 'EMP-REVIEWED', 'salary_structure': 'Reviewed Structure'},
            ],
          }}));
        } else if (request.method == 'POST' && path.endsWith('/frappe.client.submit')) {
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final doc = payload['doc'] as Map<String, dynamic>;
          submittedEmployees = doc['employees'] as List<dynamic>;
          request.response.write(jsonEncode({'message': {
            ...doc,
            'docstatus': 1,
          }}));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'message': 'Not found'}));
        }
        await request.response.close();
      });
      final client = FrappeApi()..configure('http://127.0.0.1:${server.port}');
      try {
        final result = await client.submitPayrollEntry(
          name: 'PE-001', company: 'Company A',
        );
        expect(result['docstatus'], 1);
        expect(submittedEmployees, hasLength(1));
        expect((submittedEmployees!.single as Map<String, dynamic>)['employee'], 'EMP-REVIEWED');
        expect(calls.where((call) => call.contains('run_doc_method')), isEmpty);
      } finally {
        client.dispose();
        await server.close(force: true);
      }
    });

    test('rejects malformed payroll dates before network access', () async {
      await expectLater(
        api.createPayrollEntryDraft(
          company: 'Company A',
          postingDate: 'today',
          startDate: '2026-11-01',
          endDate: '2026-11-30',
          payrollFrequency: 'Monthly',
          costCenter: 'Main - A',
          currency: 'USD',
          payrollPayableAccount: 'Payroll Payable - A',
          exchangeRate: 1,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unsupported payroll frequency before network access', () async {
      await expectLater(
        api.createPayrollEntryDraft(
          company: 'Company A',
          postingDate: '2026-11-30',
          startDate: '2026-11-01',
          endDate: '2026-11-30',
          payrollFrequency: 'Quarterly',
          costCenter: 'Main - A',
          currency: 'USD',
          payrollPayableAccount: 'Payroll Payable - A',
          exchangeRate: 1,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects blank payroll identifiers before network access', () async {
      await expectLater(
        api.fillPayrollEmployees(name: ' ', company: 'Company A'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        api.submitPayrollEntry(name: 'PAY-001', company: ' '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unsupported HR doctypes before network access', () async {
      await expectLater(
        api.fetchHrRecords(doctype: 'Payroll Entry'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects malformed attendance dates before network access', () async {
      await expectLater(
        api.createAttendanceDraft(
          employee: 'EMP-001',
          company: 'Company A',
          attendanceDate: '09/11/2026',
          status: 'Present',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unsupported attendance status before network access', () async {
      await expectLater(
        api.createAttendanceDraft(
          employee: 'EMP-001',
          company: 'Company A',
          attendanceDate: '2026-11-09',
          status: 'Late',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects reversed leave dates before network access', () async {
      await expectLater(
        api.createLeaveApplicationDraft(
          employee: 'EMP-001',
          company: 'Company A',
          leaveType: 'Annual Leave',
          fromDate: '2026-11-10',
          toDate: '2026-11-09',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-positive expense amounts before network access', () async {
      await expectLater(
        api.createExpenseClaimDraft(
          employee: 'EMP-001',
          company: 'Company A',
          postingDate: '2026-11-09',
          expenseType: 'Travel',
          amount: '0',
          account: 'Travel Expenses - AC',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires an expense type before network access', () async {
      await expectLater(
        api.createExpenseClaimDraft(
          employee: 'EMP-001',
          company: 'Company A',
          postingDate: '2026-11-09',
          expenseType: '',
          amount: '10',
          account: 'Travel Expenses - AC',
        ),
        throwsA(isA<FormatException>()),
      );
    });


    test('rejects empty employee profile updates before network access', () async {
      await expectLater(
        api.updateEmployeeProfile(
          employee: 'EMP-001',
          company: 'Company A',
          employeeName: ' ',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed email in employee profile before network access', () async {
      await expectLater(
        api.updateEmployeeProfile(
          employee: 'EMP-001',
          company: 'Company A',
          employeeName: 'Employee One',
          email: 'not-an-email',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid attendance correction before network access', () async {
      await expectLater(
        api.updateAttendanceDraft(
          name: 'ATT-001',
          company: 'Company A',
          attendanceDate: '2026-11-09',
          status: 'Late',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects blank leave type names before network access', () async {
      await expectLater(
        api.createLeaveType(name: ' '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-positive leave type limits before network access', () async {
      await expectLater(
        api.createLeaveType(name: 'Annual', maxDaysAllowed: 0),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty multi-line expense claims before network access', () async {
      await expectLater(
        api.createExpenseClaimDraftLines(
          employee: 'EMP-001',
          company: 'Company A',
          postingDate: '2026-11-09',
          expenses: const [],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires leave type for leave attendance before network access', () async {
      await expectLater(
        api.createAttendanceDraft(
          employee: 'EMP-001',
          company: 'Company A',
          attendanceDate: '2026-11-09',
          status: 'On Leave',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts exactly 10,000 salary slips and checks the next row', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final pageLengths = <int>[];
      server.listen((request) async {
        final start = int.tryParse(request.uri.queryParameters['limit_start'] ?? '') ?? 0;
        final pageLength = int.tryParse(request.uri.queryParameters['limit_page_length'] ?? '') ?? 0;
        pageLengths.add(pageLength);
        final count = start < 10000 ? pageLength : 0;
        final rows = List.generate(count, (index) => {
          'name': 'SAL-' + (start + index).toString(),
          'company': 'Company A',
          'payroll_entry': 'PE-001',
          'employee': 'EMP-' + (start + index).toString(),
          'employee_name': 'Employee ' + (start + index).toString(),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': rows}));
        await request.response.close();
      });
      api.configure('http://127.0.0.1:' + server.port.toString());
      try {
        final slips = await api.fetchPayrollSalarySlips(
          payrollEntry: 'PE-001',
          company: 'Company A',
        );
        expect(slips, hasLength(10000));
        expect(pageLengths, hasLength(21));
        expect(pageLengths.last, 1);
      } finally {
        await server.close(force: true);
      }
    });

    test('rejects the 10,001st salary slip rather than silently truncating', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final start = int.tryParse(request.uri.queryParameters['limit_start'] ?? '') ?? 0;
        final pageLength = int.tryParse(request.uri.queryParameters['limit_page_length'] ?? '') ?? 0;
        final count = start < 10000 ? pageLength : 1;
        final rows = List.generate(count, (index) => {
          'name': 'SAL-' + (start + index).toString(),
          'company': 'Company A',
          'payroll_entry': 'PE-001',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': rows}));
        await request.response.close();
      });
      api.configure('http://127.0.0.1:' + server.port.toString());
      try {
        await expectLater(
          api.fetchPayrollSalarySlips(payrollEntry: 'PE-001', company: 'Company A'),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await server.close(force: true);
      }
    });
  });
}
