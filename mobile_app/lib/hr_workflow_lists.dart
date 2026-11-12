import 'package:flutter/material.dart';

typedef HrRecord = Map<String, dynamic>;

class HrLoadMoreTile extends StatelessWidget {
  const HrLoadMoreTile({super.key, required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Center(child: OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.expand_more),
      label: Text(loading ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد'),
    )),
  );
}

class HrEmployeeList extends StatelessWidget {
  const HrEmployeeList({super.key, required this.rows, required this.loading, required this.saving, required this.hasMore, required this.loadingMore, required this.onLoadMore, required this.onEdit});
  final List<HrRecord> rows;
  final bool loading, saving, hasMore, loadingMore;
  final VoidCallback onLoadMore;
  final ValueChanged<HrRecord> onEdit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && !loading) return const Center(child: Text('لا توجد سجلات موظفين أو لا تتوفر صلاحية القراءة.'));
    return ListView.builder(
      itemCount: rows.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) return HrLoadMoreTile(loading: loadingMore, onPressed: onLoadMore);
        final row = rows[index];
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
          title: Text((row['employee_name'] ?? row['name'] ?? '—').toString()),
          subtitle: Text([row['name'], row['department'], row['designation'], row['status']]
            .where((value) => value != null && value.toString().isNotEmpty).join(' • ')),
          isThreeLine: true,
          onTap: saving ? null : () => onEdit(row),
          trailing: IconButton(
            tooltip: 'تعديل بيانات الموظف',
            onPressed: saving ? null : () => onEdit(row),
            icon: const Icon(Icons.edit_outlined),
          ),
        ));
      },
    );
  }
}

class HrDocumentList extends StatelessWidget {
  const HrDocumentList({super.key, required this.rows, required this.doctype, required this.loading, required this.saving, required this.hasMore, required this.loadingMore, required this.onLoadMore, required this.onEditAttendance, required this.onSubmit, required this.onWorkflow});
  final List<HrRecord> rows;
  final String doctype;
  final bool loading, saving, hasMore, loadingMore;
  final VoidCallback onLoadMore;
  final ValueChanged<HrRecord> onEditAttendance;
  final void Function(String, HrRecord) onSubmit;
  final void Function(String, HrRecord) onWorkflow;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && !loading) return Center(child: Text('لا توجد سجلات ${doctype == 'Attendance' ? 'حضور' : 'إجازات'} أو لا تتوفر صلاحية القراءة.'));
    return ListView.builder(
      itemCount: rows.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) return HrLoadMoreTile(loading: loadingMore, onPressed: onLoadMore);
        final row = rows[index];
        final name = row['name']?.toString() ?? '';
        final draft = row['docstatus'] == 0 || row['docstatus'] == '0';
        final title = doctype == 'Attendance'
          ? '${row['employee_name'] ?? row['employee'] ?? 'موظف'} • ${row['status'] ?? '—'}'
          : '${row['employee_name'] ?? row['employee'] ?? 'موظف'} • ${row['leave_type'] ?? 'إجازة'}';
        final detail = doctype == 'Attendance'
          ? row['attendance_date']?.toString() ?? ''
          : '${row['from_date'] ?? ''} — ${row['to_date'] ?? ''} • ${row['status'] ?? 'مسودة'}';
        return Card(child: ListTile(
          leading: CircleAvatar(child: Icon(draft ? Icons.edit_note : Icons.check_circle_outline)),
          title: Text(title),
          subtitle: Text('$name\n$detail'),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (draft && doctype == 'Attendance')
              IconButton(tooltip: 'تصحيح مسودة الحضور', onPressed: saving ? null : () => onEditAttendance(row), icon: const Icon(Icons.edit_outlined)),
            if (draft)
              IconButton(tooltip: 'إرسال المسودة', onPressed: saving ? null : () => onSubmit(doctype, row), icon: const Icon(Icons.send_outlined)),
            IconButton(tooltip: 'إجراءات سير العمل حسب صلاحيات ERPNext', onPressed: saving ? null : () => onWorkflow(doctype, row), icon: const Icon(Icons.rule_outlined)),
          ]),
        ));
      },
    );
  }
}

class HrSalarySlipList extends StatelessWidget {
  const HrSalarySlipList({super.key, required this.rows, required this.loading, required this.hasMore, required this.loadingMore, required this.onLoadMore, required this.onView});
  final List<HrRecord> rows;
  final bool loading, hasMore, loadingMore;
  final VoidCallback onLoadMore;
  final ValueChanged<HrRecord> onView;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && !loading) return const Center(child: Text('لا توجد كشوف رواتب ظاهرة أو لا تتوفر صلاحية القراءة.'));
    return ListView.builder(
      itemCount: rows.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) return HrLoadMoreTile(loading: loadingMore, onPressed: onLoadMore);
        final row = rows[index];
        final currency = row['currency']?.toString() ?? '';
        String money(String key) {
          final value = row[key];
          if (value is num) return '${value.toStringAsFixed(2)} $currency';
          return '${value ?? '—'} $currency';
        }
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
          title: Text((row['employee_name'] ?? row['employee'] ?? row['name'] ?? 'موظف').toString()),
          subtitle: Text('${row['name']} • ${row['start_date'] ?? ''} — ${row['end_date'] ?? ''}\nالإجمالي: ${money('gross_pay')} • الاستقطاعات: ${money('total_deduction')}'),
          isThreeLine: true,
          onTap: () => onView(row),
          trailing: Text(money('net_pay'), textAlign: TextAlign.end),
        ));
      },
    );
  }
}

class HrExpenseClaimList extends StatelessWidget {
  const HrExpenseClaimList({super.key, required this.rows, required this.loading, required this.saving, required this.hasMore, required this.loadingMore, required this.onLoadMore, required this.onSubmit, required this.onPay, required this.onWorkflow});
  final List<HrRecord> rows;
  final bool loading, saving, hasMore, loadingMore;
  final VoidCallback onLoadMore;
  final void Function(String, HrRecord) onSubmit;
  final ValueChanged<HrRecord> onPay;
  final void Function(String, HrRecord) onWorkflow;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && !loading) return const Center(child: Text('لا توجد مطالبات مصروفات أو لا تتوفر صلاحية القراءة. إنشاء المطالبات واعتمادها يتطلب إعداد أنواع المصروفات والحسابات ومراكز التكلفة في ERPNext.'));
    return ListView.builder(
      itemCount: rows.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) return HrLoadMoreTile(loading: loadingMore, onPressed: onLoadMore);
        final row = rows[index];
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
          title: Text((row['employee_name'] ?? row['employee'] ?? row['name'] ?? 'مطالبة').toString()),
          subtitle: Text('${row['name']} • ${row['posting_date'] ?? ''}\n${row['approval_status'] ?? row['status'] ?? '—'}'),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (row['docstatus'] == 0 || row['docstatus'] == '0')
              IconButton(tooltip: 'إرسال المسودة', onPressed: saving ? null : () => onSubmit('Expense Claim', row), icon: const Icon(Icons.send_outlined)),
            if ((row['docstatus'] == 1 || row['docstatus'] == '1') && row['approval_status'] == 'Approved' && row['status'] != 'Paid')
              IconButton(tooltip: 'سداد المطالبة', onPressed: saving ? null : () => onPay(row), icon: const Icon(Icons.payments_outlined)),
            IconButton(tooltip: 'إجراءات سير العمل حسب صلاحيات ERPNext', onPressed: saving ? null : () => onWorkflow('Expense Claim', row), icon: const Icon(Icons.rule_outlined)),
          ]),
        ));
      },
    );
  }
}
