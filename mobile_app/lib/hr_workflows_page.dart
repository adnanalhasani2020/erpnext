import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';
import 'hr_workflow_lists.dart';
import 'workspace_web_page.dart';

class HrWorkflowsPage extends StatefulWidget {
  const HrWorkflowsPage({super.key, required this.api, required this.companies, this.initialDoctype, this.standalone = false});
  final FrappeApi api;
  final List<ErpCompany> companies;
  final String? initialDoctype;
  final bool standalone;

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
  int _loadGeneration = 0;
  int _offset = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String? _error;
  List<core.Map<String, dynamic>> _employees = [];
  List<core.Map<String, dynamic>> _attendance = [];
  List<core.Map<String, dynamic>> _leaveApplications = [];
  List<core.Map<String, dynamic>> _expenseClaims = [];
  List<core.Map<String, dynamic>> _salarySlips = [];

  @override
  void initState() {
    super.initState();
    final initialTab = switch (widget.initialDoctype) {
      'Employee' => 0,
      'Attendance' => 1,
      'Leave Application' => 2,
      'Expense Claim' => 3,
      'Salary Slip' => 4,
      _ => 0,
    };
    _tabs = TabController(length: 5, initialIndex: initialTab, vsync: this)..addListener(_onTabChanged);
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
    3 => 'Expense Claim',
    _ => 'Salary Slip',
  };

  Future<void> _load() async {
    if (!mounted) return;
    final loadGeneration = ++_loadGeneration;
    final doctype = _activeDoctype;
    final company = _company;
    final search = _search.text.trim();
    setState(() { _loading = true; _error = null; });
    final sessionGeneration = widget.api.sessionGeneration;
    try {
      final rows = await widget.api.fetchHrRecords(
        doctype: doctype,
        company: company,
        search: search,
      );
      if (!mounted || loadGeneration != _loadGeneration || sessionGeneration != widget.api.sessionGeneration) return;
      setState(() {
        _offset = rows.length;
        _hasMore = rows.length == 50;
        switch (doctype) {
          case 'Employee': _employees = rows;
          case 'Attendance': _attendance = rows;
          case 'Leave Application': _leaveApplications = rows;
          case 'Expense Claim': _expenseClaims = rows;
          case 'Salary Slip': _salarySlips = rows;
        }
      });
    } catch (error) {
      if (mounted && loadGeneration == _loadGeneration && sessionGeneration == widget.api.sessionGeneration) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && loadGeneration == _loadGeneration && sessionGeneration == widget.api.sessionGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !mounted) return;
    final doctype = _activeDoctype;
    final company = _company;
    final search = _search.text.trim();
    final offset = _offset;
    final loadGeneration = _loadGeneration;
    final sessionGeneration = widget.api.sessionGeneration;
    setState(() => _loadingMore = true);
    try {
      final rows = await widget.api.fetchHrRecords(
        doctype: doctype, company: company, search: search, start: offset,
      );
      if (!mounted || loadGeneration != _loadGeneration ||
          doctype != _activeDoctype || company != _company ||
          search != _search.text.trim() ||
          sessionGeneration != widget.api.sessionGeneration) {
        return;
      }
      setState(() {
        switch (doctype) {
          case 'Employee': _employees = [..._employees, ...rows];
          case 'Attendance': _attendance = [..._attendance, ...rows];
          case 'Leave Application': _leaveApplications = [..._leaveApplications, ...rows];
          case 'Expense Claim': _expenseClaims = [..._expenseClaims, ...rows];
          case 'Salary Slip': _salarySlips = [..._salarySlips, ...rows];
        }
        _offset += rows.length;
        _hasMore = rows.length == 50;
      });
    } catch (error) {
      if (mounted && sessionGeneration == widget.api.sessionGeneration) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && sessionGeneration == widget.api.sessionGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }


  Future<void> _createEmployee() async {
    final company = _company;
    if (company == null || company.trim().isEmpty) {
      setState(() => _error = 'حدد الشركة قبل إنشاء الموظف.');
      return;
    }
    final name = TextEditingController();
    final birthDate = TextEditingController();
    final joiningDate = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final department = TextEditingController();
    final designation = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final key = GlobalKey<FormState>();
    String gender = 'Male';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('إضافة موظف جديد'),
        content: Form(
          key: key,
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم الموظف'), validator: _required),
              TextFormField(controller: birthDate, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'تاريخ الميلاد YYYY-MM-DD'), validator: _dateRequired),
              TextFormField(controller: joiningDate, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'تاريخ التعيين YYYY-MM-DD'), validator: _dateRequired),
              DropdownButtonFormField<String>(
                initialValue: gender,
                decoration: const InputDecoration(labelText: 'الجنس'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('ذكر')),
                  DropdownMenuItem(value: 'Female', child: Text('أنثى')),
                  DropdownMenuItem(value: 'Other', child: Text('آخر')),
                ],
                onChanged: (value) => refresh(() => gender = value ?? 'Male'),
              ),
              TextFormField(controller: department, decoration: const InputDecoration(labelText: 'القسم')),
              TextFormField(controller: designation, decoration: const InputDecoration(labelText: 'المسمى الوظيفي')),
              TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
              TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
              const SizedBox(height: 8),
              Text('سيُنشأ الموظف بحالة نشط في شركة $company. قد يطلب إعداد ERPNext حقولاً إلزامية إضافية حسب إعداد الموقع.'),
            ],
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (key.currentState?.validate() ?? false) {
                final birth = DateTime.tryParse(birthDate.text.trim());
                final joining = DateTime.tryParse(joiningDate.text.trim());
                if (birth != null && joining != null && !joining.isAfter(birth)) return;
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('إنشاء الموظف'),
          ),
        ],
      )),
    );
    if (confirmed == true && mounted) {
      await _runSave(() async {
        final created = await widget.api.createEmployee(
          company: company,
          employeeName: name.text,
          dateOfBirth: birthDate.text,
          dateOfJoining: joiningDate.text,
          gender: gender,
          department: department.text,
          designation: designation.text,
          cellNumber: phone.text,
          email: email.text,
        );
        if (mounted) {
          _showMessage('تم إنشاء الموظف ${created['name']}.');
          await _load();
        }
      });
    }
    name.dispose();
    birthDate.dispose();
    joiningDate.dispose();
    department.dispose();
    designation.dispose();
    phone.dispose();
    email.dispose();
  }

  Future<void> _editEmployee(core.Map<String, dynamic> row) async {
    final id = row['name']?.toString() ?? '';
    final name = TextEditingController(text: row['employee_name']?.toString() ?? '');
    final department = TextEditingController(text: row['department']?.toString() ?? '');
    final designation = TextEditingController(text: row['designation']?.toString() ?? '');
    final phone = TextEditingController(text: row['cell_number']?.toString() ?? '');
    final email = TextEditingController(text: row['prefered_email']?.toString() ?? '');
    final key = GlobalKey<FormState>();
    String status = row['status']?.toString() ?? 'Active';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text('تعديل بيانات الموظف $id'),
        content: Form(key: key, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم الموظف'), validator: _required),
            TextFormField(controller: department, decoration: const InputDecoration(labelText: 'القسم')),
            TextFormField(controller: designation, decoration: const InputDecoration(labelText: 'المسمى الوظيفي')),
            TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
            TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
            DropdownButtonFormField<String>(
              initialValue: const {'Active', 'Inactive', 'Left', 'Suspended'}.contains(status) ? status : 'Active',
              decoration: const InputDecoration(labelText: 'حالة الموظف'),
              items: const [
                DropdownMenuItem(value: 'Active', child: Text('نشط')),
                DropdownMenuItem(value: 'Inactive', child: Text('غير نشط')),
                DropdownMenuItem(value: 'Left', child: Text('غادر العمل')),
                DropdownMenuItem(value: 'Suspended', child: Text('موقوف')),
              ],
              onChanged: (value) => refresh(() => status = value ?? 'Active'),
            ),
            const SizedBox(height: 8),
            const Text('لا يمكن تغيير الشركة من هذه الشاشة؛ تغيير الحالة يخضع لصلاحيات وسياسات ERPNext.'),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (key.currentState?.validate() ?? false) Navigator.pop(dialogContext, true); }, child: const Text('حفظ')),
        ],
      )),
    );
    if (confirmed == true && mounted) {
      await _runSave(() async {
        await widget.api.updateEmployeeProfile(
          employee: id, company: _company ?? '', employeeName: name.text,
          department: department.text, designation: designation.text,
          cellNumber: phone.text, email: email.text, status: status,
        );
        if (mounted) { _showMessage('تم تحديث بيانات الموظف $id.'); await _load(); }
      });
    }
    name.dispose(); department.dispose(); designation.dispose(); phone.dispose(); email.dispose();
  }

  Future<void> _editAttendance(core.Map<String, dynamic> row) async {
    final id = row['name']?.toString() ?? '';
    final date = TextEditingController(text: row['attendance_date']?.toString() ?? '');
    final leaveType = TextEditingController(text: row['leave_type']?.toString() ?? '');
    String status = row['status']?.toString() ?? 'Present';
    final key = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text('تصحيح مسودة الحضور $id'),
        content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: date, decoration: const InputDecoration(labelText: 'تاريخ الحضور YYYY-MM-DD'), validator: _dateRequired),
          DropdownButtonFormField<String>(
            initialValue: const {'Present','Absent','On Leave','Half Day','Work From Home'}.contains(status) ? status : 'Present',
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
          if (status == 'On Leave') TextFormField(controller: leaveType, decoration: const InputDecoration(labelText: 'نوع الإجازة'), validator: _required),
          const SizedBox(height: 8),
          const Text('التصحيح متاح للمسودات فقط؛ السجلات المرحّلة تبقى خاضعة لإجراءات ERPNext.'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (key.currentState?.validate() ?? false) Navigator.pop(dialogContext, true); }, child: const Text('حفظ التصحيح')),
        ],
      )),
    );
    if (confirmed == true && mounted) {
      await _runSave(() async {
        await widget.api.updateAttendanceDraft(
          name: id, company: _company ?? '', attendanceDate: date.text,
          status: status, leaveType: leaveType.text,
        );
        if (mounted) { _showMessage('تم حفظ تصحيح مسودة الحضور $id.'); await _load(); }
      });
    }
    date.dispose(); leaveType.dispose();
  }

  Future<void> _editLeaveType(core.Map<String, dynamic> row) async {
    final id = row['name']?.toString() ?? '';
    if (id.isEmpty) return;
    final maxDays = TextEditingController(
      text: row['max_days_allowed']?.toString() ?? '',
    );
    bool withoutPay = row['is_lwp'] == 1 || row['is_lwp'] == true;
    bool allowNegative = row['allow_negative'] == 1 || row['allow_negative'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text('تعديل نوع الإجازة: $id'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: maxDays,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'الحد الأقصى للأيام (اتركه فارغاً لإزالة الحد)'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: withoutPay,
            onChanged: (value) => refresh(() => withoutPay = value ?? false),
            title: const Text('إجازة بدون راتب'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: allowNegative,
            onChanged: (value) => refresh(() => allowNegative = value ?? false),
            title: const Text('السماح برصيد سالب'),
          ),
          const Text('سيحفظ التعديل على نوع الإجازة نفسه. وقد يرفض ERPNext التغييرات التي تتعارض مع سجلات أو إعدادات قائمة.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ التعديلات')),
        ],
      )),
    );
    if (confirmed == true && mounted) {
      final raw = maxDays.text.trim();
      final parsed = raw.isEmpty ? null : double.tryParse(raw);
      if (raw.isNotEmpty && (parsed == null || !parsed.isFinite || parsed <= 0)) {
        setState(() => _error = 'أدخل حداً أقصى صحيحاً أكبر من صفر أو اتركه فارغاً.');
      } else {
        await _runSave(() async {
          await widget.api.updateLeaveType(
            name: id,
            isLeaveWithoutPay: withoutPay,
            allowNegative: allowNegative,
            maxDaysAllowed: parsed,
          );
          if (mounted) _showMessage('تم تحديث نوع الإجازة $id.');
        });
      }
    }
    maxDays.dispose();
  }

  Future<void> _manageLeaveTypes() async {
    List<core.Map<String, dynamic>> types;
    try {
      types = await widget.api.fetchLeaveTypes();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    final name = TextEditingController();
    final maxDays = TextEditingController();
    bool withoutPay = false, allowNegative = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('إدارة أنواع الإجازات'),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (types.isEmpty) const Text('لا توجد أنواع إجازات ظاهرة.') else ...types.map((item) => ListTile(
              dense: true,
              title: Text(item['name']?.toString() ?? ''),
              subtitle: Text('${item['is_lwp'] == 1 || item['is_lwp'] == true ? 'بدون راتب' : 'مدفوع'} • الحد: ${item['max_days_allowed'] ?? 'غير محدد'}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () {
                Navigator.pop(dialogContext);
                _editLeaveType(item);
              },
            )),
            const Divider(),
            const Text('إضافة نوع جديد', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم نوع الإجازة')),
            TextField(controller: maxDays, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الحد الأقصى للأيام (اختياري)')),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: withoutPay, onChanged: (v) => refresh(() => withoutPay = v ?? false), title: const Text('إجازة بدون راتب')),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: allowNegative, onChanged: (v) => refresh(() => allowNegative = v ?? false), title: const Text('السماح برصيد سالب')),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إغلاق')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إنشاء النوع')),
        ],
      )),
    );
    if (confirmed == true && name.text.trim().isNotEmpty && mounted) {
      final rawLimit = maxDays.text.trim();
      final parsedLimit = rawLimit.isEmpty ? null : double.tryParse(rawLimit);
      if (rawLimit.isNotEmpty && (parsedLimit == null || !parsedLimit.isFinite || parsedLimit <= 0)) {
        setState(() => _error = 'أدخل حداً أقصى صحيحاً أكبر من صفر أو اترك الحقل فارغاً.');
      } else {
        await _runSave(() async {
          await widget.api.createLeaveType(
            name: name.text, isLeaveWithoutPay: withoutPay,
            allowNegative: allowNegative,
            maxDaysAllowed: parsedLimit,
          );
          if (mounted) _showMessage('تم إنشاء نوع الإجازة. حدّث قائمة الأنواع في ERPNext عند الحاجة.');
        });
      }
    }
    name.dispose(); maxDays.dispose();
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
                initialValue: status,
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
                TextFormField(initialValue: leaveType,
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
    List<core.Map<String, dynamic>> leaveTypes;
    try {
      leaveTypes = await widget.api.fetchLeaveTypes();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    if (leaveTypes.isEmpty) {
      _showMessage('لا توجد أنواع إجازات مهيأة؛ أضف نوعاً من زر إدارة أنواع الإجازات أولاً.');
      return;
    }
    final employee = TextEditingController();
    final fromDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final toDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final description = TextEditingController();
    String? selectedLeaveType = leaveTypes.first['name']?.toString();
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('طلب إجازة جديد'),
        content: Form(key: formKey, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: employee, decoration: const InputDecoration(labelText: 'رقم الموظف'), validator: _required),
            DropdownButtonFormField<String>(
              initialValue: selectedLeaveType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'نوع الإجازة'),
              items: leaveTypes.map((type) => DropdownMenuItem(
                value: type['name']?.toString(),
                child: Text(type['name']?.toString() ?? ''),
              )).toList(),
              onChanged: (value) => refresh(() => selectedLeaveType = value),
              validator: (value) => value == null || value.isEmpty ? 'حدد نوع الإجازة' : null,
            ),
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
      )),
    );
    if (created == true && mounted) {
      await _runSave(() async {
        final row = await widget.api.createLeaveApplicationDraft(
          employee: employee.text, company: _company ?? '',
          leaveType: selectedLeaveType ?? '', fromDate: fromDate.text,
          toDate: toDate.text, description: description.text,
        );
        if (!mounted) return;
        _showMessage('تم إنشاء طلب الإجازة: ${row['name']}');
        _tabs.animateTo(2);
        await _load();
      });
    }
    employee.dispose(); fromDate.dispose(); toDate.dispose(); description.dispose();
  }


  Future<void> _editLeaveApplication(core.Map<String, dynamic> row) async {
    final id = row['name']?.toString().trim() ?? '';
    final company = _company ?? '';
    if (id.isEmpty || company.isEmpty) return;
    List<core.Map<String, dynamic>> leaveTypes;
    try {
      leaveTypes = await widget.api.fetchLeaveTypes();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    final employee = row['employee']?.toString() ?? '';
    final fromDate = TextEditingController(text: row['from_date']?.toString() ?? '');
    final toDate = TextEditingController(text: row['to_date']?.toString() ?? '');
    final description = TextEditingController(text: row['description']?.toString() ?? '');
    final existingType = row['leave_type']?.toString();
    final availableTypes = leaveTypes.map((type) => type['name']?.toString()).whereType<String>().toSet();
    if (existingType == null || !availableTypes.contains(existingType)) {
      fromDate.dispose(); toDate.dispose(); description.dispose();
      _showMessage('نوع الإجازة الحالي غير متاح ضمن الأنواع المقروءة من ERPNext؛ لم نغير بيانات الطلب.');
      return;
    }
    String? selectedLeaveType = existingType;
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text('تعديل مسودة طلب الإجازة $id'),
        content: Form(key: formKey, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(initialValue: employee, readOnly: true, decoration: const InputDecoration(labelText: 'رقم الموظف')),
            DropdownButtonFormField<String>(
              initialValue: selectedLeaveType, isExpanded: true,
              decoration: const InputDecoration(labelText: 'نوع الإجازة'),
              items: leaveTypes.map((type) => DropdownMenuItem(value: type['name']?.toString(), child: Text(type['name']?.toString() ?? ''))).toList(),
              onChanged: (value) => refresh(() => selectedLeaveType = value),
              validator: (value) => value == null || value.isEmpty ? 'حدد نوع الإجازة' : null,
            ),
            TextFormField(controller: fromDate, decoration: const InputDecoration(labelText: 'من تاريخ YYYY-MM-DD'), validator: _dateRequired),
            TextFormField(controller: toDate, decoration: const InputDecoration(labelText: 'إلى تاريخ YYYY-MM-DD'), validator: _dateRequired),
            TextFormField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'السبب / ملاحظات')),
            const SizedBox(height: 8),
            const Text('التعديل متاح للمسودات فقط. سيعيد ERPNext التحقق من رصيد الإجازات والسياسات ومسار الموافقات.'),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final from = DateTime.tryParse(fromDate.text.trim());
            final to = DateTime.tryParse(toDate.text.trim());
            if (from != null && to != null && to.isBefore(from)) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('تاريخ نهاية الإجازة لا يمكن أن يسبق تاريخ بدايتها.')),
              );
              return;
            }
            Navigator.pop(dialogContext, true);
          }, child: const Text('حفظ المسودة')),
        ],
      )),
    );
    if (confirmed == true && mounted) {
      await _runSave(() async {
        await widget.api.updateLeaveApplicationDraft(
          name: id, company: company, leaveType: selectedLeaveType ?? '',
          fromDate: fromDate.text, toDate: toDate.text, description: description.text,
        );
        if (mounted) { _showMessage('تم تحديث مسودة طلب الإجازة $id.'); await _load(); }
      });
    }
    fromDate.dispose(); toDate.dispose(); description.dispose();
  }

  Future<void> _createExpenseClaim() async {
    final employee = TextEditingController();
    final date = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    List<core.Map<String, dynamic>> types = [];
    try {
      types = await widget.api.fetchExpenseClaimTypes();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      employee.dispose(); date.dispose(); return;
    }
    if (!mounted) { employee.dispose(); date.dispose(); return; }
    final lines = <_ExpenseLineDraft>[_ExpenseLineDraft(types.isEmpty ? null : types.first['name']?.toString())];
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refresh) =>
        AlertDialog(
          title: const Text('مطالبة مصروفات متعددة البنود'),
          content: SizedBox(width: double.maxFinite, child: Form(key: formKey, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: employee, decoration: const InputDecoration(labelText: 'رقم الموظف'), validator: _required),
              TextFormField(controller: date, decoration: const InputDecoration(labelText: 'تاريخ المطالبة YYYY-MM-DD'), validator: _dateRequired),
              ...List.generate(lines.length, (index) {
                final line = lines[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text('بند المصروف ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        if (lines.length > 1) IconButton(
                          tooltip: 'حذف البند',
                          onPressed: () => refresh(() { lines.removeAt(index).dispose(); }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ]),
                      DropdownButtonFormField<String>(
                        key: ValueKey('expense-type-$index-${line.selectedType}'),
                        initialValue: line.selectedType,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'نوع المصروف'),
                        items: types.map((row) => DropdownMenuItem(
                          value: row['name']?.toString(),
                          child: Text((row['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (value) => refresh(() => line.selectedType = value),
                        validator: (value) => value == null || value.isEmpty ? 'حدد نوع المصروف' : null,
                      ),
                      TextFormField(controller: line.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'المبلغ'),
                        validator: (value) {
                          final parsed = double.tryParse(value?.trim() ?? '');
                          return parsed == null || !parsed.isFinite || parsed <= 0 ? 'أدخل مبلغاً أكبر من صفر' : null;
                        }),
                      TextFormField(controller: line.account, decoration: const InputDecoration(labelText: 'حساب المصروف (إذا لم يحدد النوع حساباً افتراضياً)')),
                      TextFormField(controller: line.costCenter, decoration: const InputDecoration(labelText: 'مركز التكلفة (اختياري)')),
                      TextFormField(controller: line.description, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف المصروف')),
                    ]),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: lines.length >= 50 ? null : () => refresh(() => lines.add(_ExpenseLineDraft(types.isEmpty ? null : types.first['name']?.toString()))),
                icon: const Icon(Icons.add), label: const Text('إضافة بند مصروف'),
              ),
              const SizedBox(height: 8),
              const Text('تُحفظ جميع البنود في مطالبة واحدة كمسودة، ويطبق ERPNext مسار الموافقات والسياسات المحاسبية.'),
            ],
          )))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
            }, child: const Text('حفظ المطالبة')),
          ],
        ),
      ),
    );
    if (created == true && mounted) {
      await _runSave(() async {
        final row = await widget.api.createExpenseClaimDraftLines(
          employee: employee.text, company: _company ?? '', postingDate: date.text,
          expenses: lines.map((line) => <String, dynamic>{
            'expense_type': line.selectedType ?? '',
            'amount': line.amount.text,
            'default_account': line.account.text,
            'cost_center': line.costCenter.text,
            'description': line.description.text,
          }).toList(),
        );
        if (!mounted) return;
        _showMessage('تم إنشاء مطالبة من ${lines.length} بند: ${row['name']}');
        _tabs.animateTo(3);
        await _load();
      });
    }
    for (final line in lines) { line.dispose(); }
    employee.dispose(); date.dispose();
  }


  Future<void> _payExpenseClaim(core.Map<String, dynamic> row) async {
    final name = row['name']?.toString().trim() ?? '';
    final company = _company ?? '';
    if (name.isEmpty || company.isEmpty) return;
    final sanctioned = double.tryParse(row['total_sanctioned_amount']?.toString() ?? '') ?? 0;
    final reimbursed = double.tryParse(row['total_amount_reimbursed']?.toString() ?? '') ?? 0;
    final outstanding = sanctioned - reimbursed;
    if (!outstanding.isFinite || outstanding <= 0) {
      _showMessage('لا يوجد مبلغ معتمد متبقٍ لسداد هذه المطالبة.');
      return;
    }
    List<ErpPaymentAccount> accounts;
    try {
      accounts = await widget.api.fetchPaymentAccounts(company);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    if (accounts.isEmpty) {
      _showMessage('لا توجد حسابات صندوق أو بنك مفعّلة لهذه الشركة.');
      return;
    }
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    String? selectedAccount = accounts.first.name;
    final formKey = GlobalKey<FormState>();
    final payment = await showDialog<core.Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text('سداد مطالبة المصروف $name'),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('المتبقي من المبلغ المعتمد: ${outstanding.toStringAsFixed(2)}'),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'مبلغ السداد'),
                    validator: (value) {
                      final parsed = double.tryParse(value?.trim() ?? '');
                      if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > outstanding + 0.000001) {
                        return 'أدخل مبلغاً موجباً لا يتجاوز المتبقي المعتمد';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAccount,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الدفع من حساب الصندوق أو البنك'),
                    items: accounts.map((account) => DropdownMenuItem(
                      value: account.name,
                      child: Text('${account.accountName} • ${account.currency ?? ''}', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => refresh(() => selectedAccount = value),
                    validator: (value) => value == null || value.isEmpty ? 'اختر حساب الدفع' : null,
                  ),
                  const SizedBox(height: 8),
                  const Text('سيُنشئ التطبيق سند Payment Entry من نوع Pay للطرف Employee، ويربطه بالمطالبة الأصلية عبر ERPNext.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if ((formKey.currentState?.validate() ?? false) && selectedAccount != null) {
                  Navigator.pop(dialogContext, {
                    'amount': double.parse(amount.text.trim()),
                    'account': selectedAccount,
                  });
                }
              },
              child: const Text('إنشاء سند السداد وترحيله'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    if (payment == null || !mounted) return;
    await _runSave(() async {
      final result = await widget.api.payExpenseClaim(
        claimName: name,
        amount: payment['amount'] as double,
        bankAccount: payment['account'] as String,
      );
      if (!mounted) return;
      _showMessage('أكد ERPNext سداد المطالبة عبر سند ${result['name']}.');
      await _load();
    });
  }

  Future<void> _runWorkflowAction(String doctype, core.Map<String, dynamic> row) async {
    final name = row['name']?.toString() ?? '';
    final company = _company ?? '';
    final generation = widget.api.sessionGeneration;
    await _runSave(() async {
      final transitions = await widget.api.fetchWorkflowTransitions(
        doctype: doctype, name: name, company: company,
      );
      if (!mounted || generation != widget.api.sessionGeneration) return;
      if (transitions.isEmpty) {
        _showMessage('لا توجد إجراءات موافقة متاحة لهذا المستند وفق إعدادات وصلاحيات ERPNext.');
        return;
      }
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('إجراءات المستند $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: transitions.map((transition) {
              final value = transition['action']?.toString() ?? '';
              final next = transition['next_state']?.toString() ?? '';
              return ListTile(
                leading: const Icon(Icons.rule_outlined),
                title: Text(value),
                subtitle: next.isEmpty ? null : Text('الحالة التالية: $next'),
                onTap: () => Navigator.pop(dialogContext, value),
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
          ],
        ),
      );
      if (action == null || action.isEmpty || !mounted ||
          generation != widget.api.sessionGeneration) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('تأكيد الإجراء: $action'),
          content: Text('سيُرسل الإجراء إلى ERPNext للمستند $name. سيعيد الخادم التحقق من الصلاحيات والانتقال المسموح.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد')),
          ],
        ),
      );
      if (confirmed != true || !mounted || generation != widget.api.sessionGeneration) return;
      await widget.api.applyWorkflowAction(
        doctype: doctype, name: name, company: company, action: action,
      );
      if (!mounted) return;
      _showMessage('نفّذ ERPNext الإجراء "$action" للمستند $name.');
      await _load();
    });
  }

  Future<void> _submit(String doctype, core.Map<String, dynamic> row) async {
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
    final canCreate = _tabs.index == 0 || _tabs.index == 1 || _tabs.index == 2 || _tabs.index == 3;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.standalone ? switch (_tabs.index) { 0 => 'الموظفون', 1 => 'الحضور', 2 => 'طلبات الإجازة', 3 => 'مطالبات المصروفات', _ => 'قسائم الرواتب' } : 'الموارد البشرية'),
        actions: [
          if (widget.initialDoctype != null)
            IconButton(tooltip: 'فتح قائمة الجوال', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceNativeDestinationPage(api: widget.api, title: widget.initialDoctype!, linkType: 'DocTypeList', target: widget.initialDoctype!))), icon: const Icon(Icons.arrow_forward)),
          IconButton(onPressed: _loading ? null : _load, tooltip: 'تحديث', icon: const Icon(Icons.refresh)),
          if (_tabs.index == 2)
            IconButton(
              onPressed: _saving ? null : _manageLeaveTypes,
              tooltip: 'إدارة أنواع الإجازات',
              icon: const Icon(Icons.event_available_outlined),
            ),
          if (canCreate)
            IconButton(
              onPressed: _saving ? null : (_tabs.index == 0 ? _createEmployee : _tabs.index == 1 ? _createAttendance : _tabs.index == 2 ? _createLeaveApplication : _createExpenseClaim),
              tooltip: 'إضافة سجل',
              icon: const Icon(Icons.add_circle_outline),
            ),
        ],
        bottom: widget.standalone ? null : TabBar(controller: _tabs, isScrollable: true, tabs: const [
          Tab(text: 'الموظفون'),
          Tab(text: 'الحضور'),
          Tab(text: 'الإجازات'),
          Tab(text: 'المطالبات'),
          Tab(text: 'الرواتب'),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(children: [
            DropdownButtonFormField<String>(
              initialValue: _company,
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
        Expanded(child: widget.standalone ? switch (_tabs.index) {
          0 => HrEmployeeList(rows: _employees, loading: _loading, saving: _saving, onEdit: _editEmployee, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore),
          1 => HrDocumentList(rows: _attendance, doctype: 'Attendance', loading: _loading, saving: _saving, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onEditAttendance: _editAttendance, onEditLeaveApplication: _editLeaveApplication, onSubmit: _submit, onWorkflow: _runWorkflowAction),
          2 => HrDocumentList(rows: _leaveApplications, doctype: 'Leave Application', loading: _loading, saving: _saving, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onEditAttendance: _editAttendance, onEditLeaveApplication: _editLeaveApplication, onSubmit: _submit, onWorkflow: _runWorkflowAction),
          3 => HrExpenseClaimList(rows: _expenseClaims, loading: _loading, saving: _saving, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onSubmit: _submit, onPay: _payExpenseClaim, onWorkflow: _runWorkflowAction),
          _ => HrSalarySlipList(rows: _salarySlips, loading: _loading, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onView: _viewSalarySlip),
        } : TabBarView(controller: _tabs, children: [
          HrEmployeeList(rows: _employees, loading: _loading, saving: _saving, onEdit: _editEmployee, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore),
          HrDocumentList(rows: _attendance, doctype: 'Attendance', loading: _loading, saving: _saving, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onEditAttendance: _editAttendance, onEditLeaveApplication: _editLeaveApplication, onSubmit: _submit, onWorkflow: _runWorkflowAction),
          HrDocumentList(rows: _leaveApplications, doctype: 'Leave Application', loading: _loading, saving: _saving, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onEditAttendance: _editAttendance, onEditLeaveApplication: _editLeaveApplication, onSubmit: _submit, onWorkflow: _runWorkflowAction),
          HrExpenseClaimList(rows: _expenseClaims, loading: _loading, saving: _saving, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onSubmit: _submit, onPay: _payExpenseClaim, onWorkflow: _runWorkflowAction),
          HrSalarySlipList(rows: _salarySlips, loading: _loading, hasMore: _hasMore, loadingMore: _loadingMore, onLoadMore: _loadMore, onView: _viewSalarySlip),
        ])),
      ]),
    );
  }

  Future<void> _viewSalarySlip(core.Map<String, dynamic> row) async {
    final id = row['name']?.toString() ?? '';
    final sessionGeneration = widget.api.sessionGeneration;
    try {
      final slip = await widget.api.fetchSalarySlipDetails(
        name: id, company: _company ?? '',
      );
      // Do not display salary data fetched for a previous signed-in session.
      if (!mounted || sessionGeneration != widget.api.sessionGeneration) return;
      String amount(dynamic value) {
        final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
        return parsed == null ? (value?.toString() ?? '—') : parsed.toStringAsFixed(2);
      }
      Widget componentList(String title, dynamic value) {
        final rows = value is List ? value.whereType<core.Map<String, dynamic>>().toList() : <core.Map<String, dynamic>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (rows.isEmpty) const Text('لا توجد بنود.') else ...rows.map((item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item['salary_component']?.toString() ?? 'بند'),
              trailing: Text(amount(item['amount'])),
            )),
          ],
        );
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('كشف الراتب $id'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الموظف: ${slip['employee_name'] ?? slip['employee'] ?? '—'}'),
                Text('الفترة: ${slip['start_date'] ?? ''} — ${slip['end_date'] ?? ''}'),
                Text('الحالة: ${slip['status'] ?? '—'} • ${slip['docstatus'] == 1 ? 'مرحّل' : 'غير مرحّل'}'),
                const Divider(),
                componentList('الاستحقاقات', slip['earnings']),
                componentList('الاستقطاعات', slip['deductions']),
                const Divider(),
                Text('الإجمالي: ${amount(slip['gross_pay'])} ${slip['currency'] ?? ''}'),
                Text('الاستقطاعات: ${amount(slip['total_deduction'])} ${slip['currency'] ?? ''}'),
                Text('صافي الراتب: ${amount(slip['net_pay'])} ${slip['currency'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
          ],
        ),
      );
    } catch (error) {
      if (mounted && sessionGeneration == widget.api.sessionGeneration) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    }
  }


}

 
class _ExpenseLineDraft {
  _ExpenseLineDraft(this.selectedType);
  String? selectedType;
  final amount = TextEditingController();
  final account = TextEditingController();
  final costCenter = TextEditingController();
  final description = TextEditingController();
  void dispose() {
    amount.dispose();
    account.dispose();
    costCenter.dispose();
    description.dispose();
  }
}
