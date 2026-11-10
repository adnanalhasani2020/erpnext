import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  late FrappeApi api;

  setUp(() => api = FrappeApi());
  tearDown(() => api.dispose());


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
  });
}
