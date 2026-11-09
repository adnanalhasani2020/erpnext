import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  late FrappeApi api;

  setUp(() => api = FrappeApi());
  tearDown(() => api.dispose());

  group('HR workflow validation', () {
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
