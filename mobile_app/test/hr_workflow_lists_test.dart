import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/hr_workflow_lists.dart';

void main() {
  testWidgets('employee list delegates edits and pagination', (tester) async {
    Map<String, dynamic>? edited;
    var loadedMore = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HrEmployeeList(
      rows: const [{'name': 'EMP-001', 'employee_name': 'موظف تجريبي', 'department': 'المبيعات'}],
      loading: false,
      saving: false,
      hasMore: true,
      loadingMore: false,
      onLoadMore: () => loadedMore = true,
      onEdit: (row) => edited = row,
    ))));
    await tester.tap(find.text('موظف تجريبي'));
    expect(edited?['name'], 'EMP-001');
    await tester.tap(find.text('تحميل المزيد'));
    expect(loadedMore, isTrue);
  });

  testWidgets('attendance list exposes draft correction, submit and workflow callbacks', (tester) async {
    Map<String, dynamic>? edited;
    String? submittedType;
    String? workflowType;
    final row = <String, dynamic>{
      'name': 'ATT-001',
      'employee_name': 'موظف',
      'status': 'Present',
      'attendance_date': '2026-11-12',
      'docstatus': 0,
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HrDocumentList(
      rows: [row],
      doctype: 'Attendance',
      loading: false,
      saving: false,
      hasMore: false,
      loadingMore: false,
      onLoadMore: () {},
      onEditAttendance: (value) => edited = value,
      onSubmit: (doctype, value) => submittedType = doctype,
      onWorkflow: (doctype, value) => workflowType = doctype,
    ))));
    await tester.tap(find.byTooltip('تصحيح مسودة الحضور'));
    await tester.tap(find.byTooltip('إرسال المسودة'));
    await tester.tap(find.byTooltip('إجراءات سير العمل حسب صلاحيات ERPNext'));
    expect(edited?['name'], 'ATT-001');
    expect(submittedType, 'Attendance');
    expect(workflowType, 'Attendance');
  });

  testWidgets('expense claim only offers payment for approved submitted unpaid claims', (tester) async {
    Map<String, dynamic>? paid;
    final row = <String, dynamic>{
      'name': 'EXP-001',
      'employee_name': 'موظف',
      'docstatus': 1,
      'approval_status': 'Approved',
      'status': 'Unpaid',
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HrExpenseClaimList(
      rows: [row],
      loading: false,
      saving: false,
      hasMore: false,
      loadingMore: false,
      onLoadMore: () {},
      onSubmit: (doctype, value) {},
      onPay: (value) => paid = value,
      onWorkflow: (doctype, value) {},
    ))));
    await tester.tap(find.byTooltip('سداد المطالبة'));
    expect(paid?['name'], 'EXP-001');
  });

  testWidgets('salary slip list opens its details callback', (tester) async {
    Map<String, dynamic>? opened;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HrSalarySlipList(
      rows: const [{'name': 'SAL-001', 'employee_name': 'موظف', 'net_pay': 1250, 'currency': 'YER'}],
      loading: false,
      hasMore: false,
      loadingMore: false,
      onLoadMore: () {},
      onView: (row) => opened = row,
    ))));
    await tester.tap(find.text('موظف'));
    expect(opened?['name'], 'SAL-001');
  });
}
