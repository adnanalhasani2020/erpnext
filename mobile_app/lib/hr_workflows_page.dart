import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class HrWorkflowsPage extends StatefulWidget {
  const HrWorkflowsPage({super.key, required this.api, required this.companies});
  final FrappeApi api;
  final List<ErpCompany> companies;

  @override
  State<HrWorkflowsPage> createState() => _HrWorkflowsPageState();
}

class _HrWorkflowsPageState extends State<HrWorkflowsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _company;
  final _search = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _leaveApplications = [];
  List<Map<String, dynamic>> _expenseClaims = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)..addListener(_onTabChanged);
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    _load();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging && mounted) _load();
  }

  String get _activeDoctype => switch (_tabs.index) {
    0 => 'Employee',
    1 => 'Attendance',
    2 => 'Leave Application',
    _ => 'Expense Claim',
  };

  Future<void> _load() async {
    if (!mounted || _loading) return;
    setState(() { _loading = true; _error = null; });
    final generation = widget.api.sessionGeneration;
    try {
      final rows = await widget.api.fetchHrRecords(
        doctype: _activeDoctype,
        company: _company,
        search: _search.text.trim(),
      );
      if (!mounted || generation != widget.api.sessionGeneration) return;
      setState(() {
        switch (_activeDoctype) {
          case 'Employee': _employees = rows;
          case 'Attendance': _attendance = rows;
          case 'Leave Application': _leaveApplications = rows;
          case 'Expense Claim': _expenseClaims = rows;
        }
      });
    } catch (error) {
      if (mounted && generation == widget.api.sessionGeneration) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && generation == widget.api.sessionGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createAttendance() async {
    final employee = TextEditingController();
    final date = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    String status = 'Present';
    String leaveType = '';
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) =>
        AlertDialog(
          title: const Text('تسجيل حضور أو انصراف'),
          content: Form(key: formKey, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: employee, decoration: const InputDecoration(labelText: 'رقم الموظف'), validator: _required),
              TextFormField(controller: date, decoration: const InputDecoration(labelText: 'تاريخ الحضور YYYY-MM-DD'), validator: _dateRequired),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: const [
                  DropdownMenuItem(value: 'Present', child: Text('حاضر')),
                  DropdownMenuItem(value: 'Absent', child: Text('غائب')),
                  DropdownMenuItem(value: 'On Leave', child: Text('في إجازة')),
                  DropdownMenuItem(value: 'Half Day', child: Text('نصف يوم')),
                  DropdownMenuItem(value: 'Work From Home', child: Text('عمل من المنزل')),
                ],
                onChanged: (value) => refresh(() => status = value ?? 'Present'),
              ),
              if (status == 'On Leave')
                TextFormField(controller: TextEditingController(text: leaveType),
                  decoration: const InputDecoration(labelText: 'نوع الإجازة'),
                  onChanged: (value) => leaveType = value),
              const SizedBox(height: 8),
              const Text('سيُنشأ السجل كمسودة، ثم يمكنك مراجعته وترحيله.'),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
            }, child: const Text('حفظ المسودة')),
          ],
        ),
      ),
    );
    if (created == true && mounted) {
      await _runSave(() async {
        final row = await widget.api.createAttendanceDraft(
          employee: employee.text, company: _company ?? '',
          attendanceDate: date.text, status: status, leaveType: leaveType,
        );
        if (!mounted) return;
        _showMessage('تم إنشاء مسودة الحضور: ${row['name']}');
        _tabs.animateTo(1);
        await _load();
      });
    }
    employee.dispose();
    date.dispose();
  }

  Future<void> _createLeaveApplication() async {
    final employee = TextEditingController();
    final leaveType = TextEditingController();
    final fromDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final toDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final description = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('طلب إجازة جديد'),
        content: Form(key: formKey, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: employee, decoration: const InputDecoration(labelText: 'رقم الموظف'), validator: _required),
            TextFormField(controller: leaveType, decoration: const InputDecoration(labelText: 'نوع الإجازة في ERPNext'), validator: _required),
            TextFormField(controller: fromDate, decoration: const InputDecoration(labelText: 'من تاريخ YYYY-MM-DD'), validator: _dateRequired),
            TextFormField(controller: toDate, decoration: const InputDecoration(labelText: 'إلى تاريخ YYYY-MM-DD'), validator: _dateRequired),
            TextFormField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'السبب / ملاحظات')),
            const SizedBox(height: 8),
            const Text('يُحفظ الطلب كمسودة؛ اعتماد الإجازة يخضع لمسار الموافقات في ERPNext.'),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
          }, child: const Text('حفظ المسودة')),
        ],
      ),
    );
    if (created == true && mounted) {
      await _runSave(() async {
        final row = await widget.api.createLeaveApplicationDraft(
          employee: employee.text, company: _company ?? '',
          leaveType: leaveType.text, fromDate: fromDate.text,
          toDate: toDate.text, description: description.text,
        );
        if (!mounted) return;
        _showMessage('تم إنشاء طلب الإجازة: ${row['name']}');
        _tabs.animateTo(2);
        await _load();
      });
    }
    employee.dispose(); leaveType.dispose(); fromDate.dispose();
    toDate.dispose(); description.dispose();
  }

  Future<void> _submit(String doctype, Map<String, dynamic> row) async {
    final name = row['name']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الترحيل'),
        content: Text('هل تريد ترحيل المستند $name؟ سيطبق ERPNext صلاحياته والتحقق المحاسبي والإداري.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ترحيل')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runSave(() async {
      await widget.api.submitHrDraft(doctype: doctype, name: name, company: _company ?? '');
      if (!mounted) return;
      _showMessage('تم ترحيل $name بنجاح.');
      await _load();
    });
  }

  Future<void> _runSave(Future<void> Function() action) async {
    if (_saving || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;

  String? _dateRequired(String? value) {
    if (_required(value) != null) return 'أدخل التاريخ';
    final date = DateTime.tryParse(value!.trim());
    return date == null || date.toIso8601String().substring(0, 10) != value.trim()
        ? 'استخدم الصيغة YYYY-MM-DD' : null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _tabs.index == 1 || _tabs.index == 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموارد البشرية'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, tooltip: 'تحديث', icon: const Icon(Icons.refresh)),
          if (canCreate)
            IconButton(
              onPressed: _saving ? null : (_tabs.index == 1 ? _createAttendance : _createLeaveApplication),
              tooltip: 'إضافة سجل',
              icon: const Icon(Icons.add_circle_outline),
            ),
        ],
        bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [
          Tab(text: 'الموظفون'),
          Tab(text: 'الحضور'),
          Tab(text: 'الإجازات'),
          Tab(text: 'المطالبات'),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(children: [
            DropdownButtonFormField<String>(
              value: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
              onChanged: (value) { setState(() => _company = value); _load(); },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'بحث في سجلات القسم الحالي',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); _load(); }),
              ),
              onSubmitted: (_) => _load(),
            ),
          ]),
        ),
        if (_loading || _saving) const LinearProgressIndicator(),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [TextButton(onPressed: () => setState(() => _error = null), child: const Text('إغلاق'))],
          ),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _employeeList(),
          _documentList(_attendance, 'Attendance'),
          _documentList(_leaveApplications, 'Leave Application'),
          _expenseList(),
        ])),
      ]),
    );
  }

  Widget _employeeList() {
    if (_employees.isEmpty && !_loading) return const Center(child: Text('لا توجد سجلات موظفين أو لا تتوفر صلاحية القراءة.'));
    return ListView.builder(
      itemCount: _employees.length,
      itemBuilder: (context, index) {
        final row = _employees[index];
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
          title: Text((row['employee_name'] ?? row['name'] ?? '—').toString()),
          subtitle: Text([
            row['name'], row['department'], row['designation'], row['status'],
          ].where((value) => value != null && value.toString().isNotEmpty).join(' • ')),
          isThreeLine: true,
        ));
      },
    );
  }

  Widget _documentList(List<Map<String, dynamic>> rows, String doctype) {
    if (rows.isEmpty && !_loading) return Center(child: Text('لا توجد سجلات ${doctype == 'Attendance' ? 'حضور' : 'إجازات'} أو لا تتوفر صلاحية القراءة.'));
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
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
          trailing: draft ? IconButton(
            tooltip: 'ترحيل',
            onPressed: _saving ? null : () => _submit(doctype, row),
            icon: const Icon(Icons.send_outlined),
          ) : Text(row['docstatus'] == 1 ? 'مرحّل' : '—'),
        ));
      },
    );
  }

  Widget _expenseList() {
    if (_expenseClaims.isEmpty && !_loading) {
      return const Center(child: Text('لا توجد مطالبات مصروفات أو لا تتوفر صلاحية القراءة. إنشاء المطالبات واعتمادها يتطلب إعداد أنواع المصروفات والحسابات ومراكز التكلفة في ERPNext.'));
    }
    return ListView.builder(
      itemCount: _expenseClaims.length,
      itemBuilder: (context, index) {
        final row = _expenseClaims[index];
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
          title: Text((row['employee_name'] ?? row['employee'] ?? row['name'] ?? 'مطالبة').toString()),
          subtitle: Text('${row['name']} • ${row['posting_date'] ?? ''}\n${row['approval_status'] ?? row['status'] ?? '—'}'),
          isThreeLine: true,
          trailing: Text((row['total_claimed_amount'] ?? '—').toString()),
        ));
      },
    );
  }
}
