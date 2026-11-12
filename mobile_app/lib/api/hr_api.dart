// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin HrApiMixin on _FrappeApiCore {
  Future<core.Map<String, dynamic>> createEmployee({
      required String company,
      required String employeeName,
      required String dateOfBirth,
      required String dateOfJoining,
      required String gender,
      String department = '',
      String designation = '',
      String cellNumber = '',
      String email = '',
    }) async {
      final normalizedCompany = company.trim();
      final displayName = employeeName.trim();
      final birthText = dateOfBirth.trim();
      final joiningText = dateOfJoining.trim();
      final birth = DateTime.tryParse(birthText);
      final joining = DateTime.tryParse(joiningText);
      if (normalizedCompany.isEmpty || displayName.isEmpty ||
          birth == null || joining == null ||
          birth.toIso8601String().substring(0, 10) != birthText ||
          joining.toIso8601String().substring(0, 10) != joiningText ||
          !joining.isAfter(birth)) {
        throw const FormatException('الشركة والاسم وتاريخا الميلاد والتعيين الصحيحة مطلوبة، ويجب أن يكون التعيين بعد الميلاد.');
      }
      if (!const {'Male', 'Female', 'Other'}.contains(gender)) {
        throw const FormatException('حدد الجنس من الخيارات المدعومة.');
      }
      final normalizedEmail = email.trim();
      if (normalizedEmail.isNotEmpty) {
        final parts = normalizedEmail.split('@');
        if (parts.length != 2 || parts.first.isEmpty ||
            !parts.last.contains('.') || parts.last.startsWith('.') ||
            parts.last.endsWith('.')) {
          throw const FormatException('عنوان البريد الإلكتروني غير صحيح.');
        }
      }
      final nameParts = displayName.split(' ').where((part) => part.trim().isNotEmpty).toList(growable: false);
      if (nameParts.isEmpty) throw const FormatException('اسم الموظف مطلوب.');
      final payload = <String, dynamic>{
        'doctype': 'Employee',
        'first_name': nameParts.first,
        if (nameParts.length > 1) 'last_name': nameParts.skip(1).join(' '),
        'company': normalizedCompany,
        'date_of_birth': birthText,
        'date_of_joining': joiningText,
        'gender': gender,
        'status': 'Active',
        if (department.trim().isNotEmpty) 'department': department.trim(),
        if (designation.trim().isNotEmpty) 'designation': designation.trim(),
        if (cellNumber.trim().isNotEmpty) 'cell_number': cellNumber.trim(),
        if (normalizedEmail.isNotEmpty) 'prefered_email': normalizedEmail,
      };
      final response = await _sendJson('POST', '/api/resource/Employee', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إنشاء الموظف. تحقق من الحقول الإلزامية وصلاحية Employee في ERPNext.'));
      }
      final created = data['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Employee' ||
          created['name'] is! String || created['name'].toString().isEmpty ||
          created['company'] != normalizedCompany ||
          created['employee_name'] != displayName ||
          created['docstatus'] != 0) {
        throw const FormatException('لم يؤكد ERPNext إنشاء سجل الموظف المطابق.');
      }
      return core.Map<String, dynamic>.from(created);
    }

  Future<core.Map<String, dynamic>> updateEmployeeProfile({
      required String employee,
      required String company,
      required String employeeName,
      String department = '',
      String designation = '',
      String cellNumber = '',
      String email = '',
      String status = 'Active',
    }) async {
      final id = employee.trim(), normalizedCompany = company.trim();
      final displayName = employeeName.trim();
      if (id.isEmpty || normalizedCompany.isEmpty || displayName.isEmpty) {
        throw const FormatException('رقم الموظف والشركة والاسم حقول مطلوبة.');
      }
      final normalizedEmail = email.trim();
      if (normalizedEmail.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
        throw const FormatException('عنوان البريد الإلكتروني غير صحيح.');
      }
      if (!const {'Active', 'Inactive', 'Left', 'Suspended'}.contains(status)) {
        throw const FormatException('حالة الموظف المحددة غير مدعومة.');
      }
      final current = await _fetchHrEmployee(id, normalizedCompany);
      final payload = <String, dynamic>{
        ...current,
        'employee_name': displayName,
        'department': department.trim().isEmpty ? null : department.trim(),
        'designation': designation.trim().isEmpty ? null : designation.trim(),
        'cell_number': cellNumber.trim(),
        'prefered_email': normalizedEmail,
        'status': status,
      };
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحديث بيانات الموظف. تحقق من صلاحية Employee.'));
      }
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Employee' ||
          saved['name'] != id || saved['company'] != normalizedCompany ||
          saved['employee_name'] != displayName || saved['status'] != status) {
        throw const FormatException('لم يؤكد ERPNext حفظ بيانات الموظف المطابقة.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<core.Map<String, dynamic>> updateAttendanceDraft({
      required String name,
      required String company,
      required String attendanceDate,
      required String status,
      String leaveType = '',
    }) async {
      final id = name.trim(), normalizedCompany = company.trim();
      final date = DateTime.tryParse(attendanceDate.trim());
      if (id.isEmpty || normalizedCompany.isEmpty || date == null ||
          date.toIso8601String().substring(0, 10) != attendanceDate.trim()) {
        throw const FormatException('رقم سجل الحضور والشركة والتاريخ الصحيح مطلوبة.');
      }
      if (!const {'Present', 'Absent', 'On Leave', 'Half Day', 'Work From Home'}.contains(status)) {
        throw const FormatException('حالة الحضور المحددة غير مدعومة.');
      }
      final response = await _send('GET', '/api/resource/Attendance/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إعادة قراءة سجل الحضور.'));
      }
      final current = data['data'];
      if (current is! core.Map<String, dynamic> || current['doctype'] != 'Attendance' ||
          current['name'] != id || current['company'] != normalizedCompany ||
          current['docstatus'] != 0 || current['employee'] is! String) {
        throw const FormatException('يمكن تصحيح مسودات الحضور التابعة للشركة المحددة فقط.');
      }
      await _fetchHrEmployee(current['employee'].toString(), normalizedCompany);
      if (status == 'On Leave' && leaveType.trim().isEmpty) {
        throw const FormatException('حدد نوع الإجازة عند تسجيل حالة في إجازة.');
      }
      final duplicateUri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Attendance',
        fields: const ['name', 'docstatus'],
        filters: [
          ['employee', '=', current['employee']],
          ['attendance_date', '=', attendanceDate.trim()],
        ],
        orderBy: 'attendance_date asc',
        pageLength: 20,
      );
      final duplicateResponse = await _sendUri('GET', duplicateUri);
      final duplicateData = _decode(duplicateResponse.body);
      if (duplicateResponse.statusCode < 200 || duplicateResponse.statusCode >= 300) {
        throw Exception(_message(duplicateData, 'تعذر التحقق من تكرار الحضور.'));
      }
      final duplicates = duplicateData['data'];
      if (duplicates is! List || duplicates.whereType<core.Map<String, dynamic>>()
          .any((row) => row['name'] != id && row['docstatus'] != 2)) {
        throw const FormatException('يوجد سجل حضور آخر للموظف في التاريخ المحدد.');
      }
      final payload = <String, dynamic>{
        ...current,
        'attendance_date': attendanceDate.trim(),
        'status': status,
        'leave_type': status == 'On Leave' ? leaveType.trim() : null,
      };
      final savedResponse = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final savedData = _decode(savedResponse.body);
      if (savedResponse.statusCode < 200 || savedResponse.statusCode >= 300) {
        throw Exception(_message(savedData, 'تعذر حفظ تصحيح الحضور.'));
      }
      final saved = savedData['message'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Attendance' ||
          saved['name'] != id || saved['company'] != normalizedCompany ||
          saved['docstatus'] != 0 || saved['attendance_date'] != attendanceDate.trim()) {
        throw const FormatException('لم يؤكد ERPNext حفظ مسودة الحضور المصححة.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<List<core.Map<String, dynamic>>> fetchLeaveTypes() async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Leave Type',
        fields: const ['name', 'is_lwp', 'allow_negative', 'max_days_allowed', 'is_carry_forward'],
        orderBy: 'name asc', pageLength: 200,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل أنواع الإجازات. تحقق من صلاحية Leave Type.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة أنواع الإجازات غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> createLeaveType({
      required String name,
      bool isLeaveWithoutPay = false,
      bool allowNegative = false,
      double? maxDaysAllowed,
    }) async {
      final normalized = name.trim();
      if (normalized.isEmpty) throw const FormatException('اسم نوع الإجازة مطلوب.');
      if (maxDaysAllowed != null &&
          (!maxDaysAllowed.isFinite || maxDaysAllowed <= 0)) {
        throw const FormatException('الحد الأقصى للإجازة يجب أن يكون أكبر من صفر.');
      }
      final payload = <String, dynamic>{
        'doctype': 'Leave Type',
        'leave_type_name': normalized,
        'is_lwp': isLeaveWithoutPay ? 1 : 0,
        'allow_negative': allowNegative ? 1 : 0,
        if (maxDaysAllowed != null) 'max_days_allowed': maxDaysAllowed,
      };
      final response = await _sendJson('POST', '/api/resource/Leave%20Type', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إنشاء نوع الإجازة. تحقق من صلاحية إدارة Leave Type.'));
      }
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Leave Type' ||
          created['name'] is! String || created['name'].toString().isEmpty) {
        throw const FormatException('لم يؤكد ERPNext إنشاء نوع الإجازة.');
      }
      return core.Map<String, dynamic>.from(created);
    }

  Future<core.Map<String, dynamic>> updateLeaveType({
      required String name,
      required bool isLeaveWithoutPay,
      required bool allowNegative,
      double? maxDaysAllowed,
    }) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('اسم نوع الإجازة مطلوب.');
      if (maxDaysAllowed != null &&
          (!maxDaysAllowed.isFinite || maxDaysAllowed <= 0)) {
        throw const FormatException('الحد الأقصى للإجازة يجب أن يكون أكبر من صفر.');
      }
      final currentResponse = await _send(
        'GET', '/api/resource/Leave%20Type/' + Uri.encodeComponent(id),
      );
      final currentData = _decode(currentResponse.body);
      if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300) {
        throw Exception(_message(currentData, 'تعذر إعادة قراءة نوع الإجازة قبل التعديل.'));
      }
      final current = currentData['data'];
      if (current is! core.Map<String, dynamic> ||
          current['doctype'] != 'Leave Type' || current['name'] != id) {
        throw const FormatException('هوية نوع الإجازة المسترجع غير مطابقة.');
      }
      final payload = <String, dynamic>{
        ...current,
        'is_lwp': isLeaveWithoutPay ? 1 : 0,
        'allow_negative': allowNegative ? 1 : 0,
        'max_days_allowed': maxDaysAllowed,
      };
      final response = await _sendJson(
        'POST', '/api/method/frappe.client.save', {'doc': payload},
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحديث نوع الإجازة. قد توجد قيود أو صلاحيات تمنع التعديل.'));
      }
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> ||
          saved['doctype'] != 'Leave Type' || saved['name'] != id ||
          saved['is_lwp'] != (isLeaveWithoutPay ? 1 : 0) ||
          saved['allow_negative'] != (allowNegative ? 1 : 0)) {
        throw const FormatException('لم يؤكد ERPNext حفظ إعدادات نوع الإجازة.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<List<core.Map<String, dynamic>>> fetchHrRecords({
      required String doctype,
      String? company,
      int start = 0,
      String? search,
    }) async {
      final fields = FrappeApi._hrFields[doctype];
      if (fields == null) throw ArgumentError.value(doctype, 'doctype', 'نوع سجل موارد بشرية غير مدعوم.');
      final normalizedCompany = company?.trim() ?? '';
      final query = search?.trim() ?? '';
      final searchFields = switch (doctype) {
        'Employee' => const ['name', 'employee_name', 'department', 'designation'],
        'Attendance' => const ['name', 'employee', 'employee_name'],
        'Leave Application' => const ['name', 'employee', 'employee_name', 'leave_type'],
        'Expense Claim' => const ['name', 'employee', 'employee_name'],
        'Salary Slip' => const ['name', 'employee', 'employee_name', 'payroll_frequency'],
        _ => const <String>[],
      };
      final filters = <List<dynamic>>[];
      if (normalizedCompany.isNotEmpty) filters.add(['company', '=', normalizedCompany]);
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: doctype,
        fields: fields,
        filters: filters,
        orFilters: query.isEmpty ? null : searchFields.map((field) => [field, 'like', '%$query%']).toList(),
        orderBy: doctype == 'Employee' ? 'employee_name asc, name asc' : 'modified desc, name desc',
        start: start,
        pageLength: 50,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل سجلات $doctype. تحقق من صلاحية القراءة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة سجلات $doctype غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => normalizedCompany.isEmpty || row['company'] == normalizedCompany)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> _fetchHrEmployee(String employee, String company) async {
      final id = employee.trim(), normalizedCompany = company.trim();
      if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('حدد الموظف والشركة.');
      final response = await _send('GET', '/api/resource/Employee/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر التحقق من الموظف. تحقق من صلاحية قراءة Employee.'));
      }
      final row = data['data'];
      if (row is! core.Map<String, dynamic> || row['name'] != id ||
          row['company'] != normalizedCompany || row['status'] == 'Left' ||
          row['status'] == 'Inactive') {
        throw const FormatException('الموظف غير موجود أو لا يتبع الشركة المحددة أو غير نشط.');
      }
      return core.Map<String, dynamic>.from(row);
    }

  Future<core.Map<String, dynamic>> createAttendanceDraft({
      required String employee,
      required String company,
      required String attendanceDate,
      required String status,
      String? leaveType,
    }) async {
      final date = DateTime.tryParse(attendanceDate.trim());
      if (date == null || date.toIso8601String().substring(0, 10) != attendanceDate.trim()) {
        throw const FormatException('تاريخ الحضور يجب أن يكون بصيغة YYYY-MM-DD.');
      }
      if (!const {'Present', 'Absent', 'On Leave', 'Half Day', 'Work From Home'}.contains(status)) {
        throw const FormatException('حالة الحضور المحددة غير مدعومة.');
      }
      if (status == 'On Leave' && (leaveType?.trim().isEmpty ?? true)) {
        throw const FormatException('حدد نوع الإجازة عند تسجيل حالة في إجازة.');
      }
      await _fetchHrEmployee(employee, company);
      final duplicateUri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Attendance',
        fields: const ['name', 'docstatus'],
        filters: [
          ['employee', '=', employee.trim()],
          ['attendance_date', '=', attendanceDate.trim()],
        ],
        orderBy: 'modified desc',
        pageLength: 10,
      );
      final duplicateResponse = await _sendUri('GET', duplicateUri);
      final duplicateData = _decode(duplicateResponse.body);
      if (duplicateResponse.statusCode < 200 || duplicateResponse.statusCode >= 300) {
        throw Exception(_message(duplicateData, 'تعذر التحقق من سجلات الحضور السابقة.'));
      }
      final existingAttendance = duplicateData['data'];
      if (existingAttendance is! List) throw const FormatException('استجابة التحقق من تكرار الحضور غير متوقعة.');
      if (existingAttendance.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
        throw const FormatException('يوجد سجل حضور أو مسودة لهذا الموظف في التاريخ المحدد.');
      }
      final payload = <String, dynamic>{
        'doctype': 'Attendance',
        'employee': employee.trim(),
        'company': company.trim(),
        'attendance_date': attendanceDate.trim(),
        'status': status,
        if (leaveType?.trim().isNotEmpty ?? false) 'leave_type': leaveType!.trim(),
      };
      final response = await _sendJson('POST', '/api/resource/Attendance', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إنشاء مسودة الحضور.'));
      }
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Attendance' ||
          created['name'] is! String || created['docstatus'] != 0 ||
          created['employee'] != employee.trim() || created['company'] != company.trim()) {
        throw const FormatException('لم يؤكد ERPNext إنشاء مسودة الحضور المطابقة.');
      }
      return core.Map<String, dynamic>.from(created);
    }

  Future<core.Map<String, dynamic>> createLeaveApplicationDraft({
      required String employee,
      required String company,
      required String leaveType,
      required String fromDate,
      required String toDate,
      String description = '',
    }) async {
      final from = DateTime.tryParse(fromDate.trim()), to = DateTime.tryParse(toDate.trim());
      if (from == null || to == null ||
          from.toIso8601String().substring(0, 10) != fromDate.trim() ||
          to.toIso8601String().substring(0, 10) != toDate.trim() ||
          to.isBefore(from)) {
        throw const FormatException('تحقق من تاريخ بداية الإجازة ونهايتها بصيغة YYYY-MM-DD.');
      }
      if (leaveType.trim().isEmpty) throw const FormatException('حدد نوع الإجازة.');
      await _fetchHrEmployee(employee, company);
      final payload = <String, dynamic>{
        'doctype': 'Leave Application',
        'employee': employee.trim(),
        'company': company.trim(),
        'leave_type': leaveType.trim(),
        'from_date': fromDate.trim(),
        'to_date': toDate.trim(),
        'description': description.trim(),
      };
      final response = await _sendJson('POST', '/api/resource/Leave%20Application', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إنشاء طلب الإجازة.'));
      }
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Leave Application' ||
          created['name'] is! String || created['docstatus'] != 0 ||
          created['employee'] != employee.trim() || created['company'] != company.trim()) {
        throw const FormatException('لم يؤكد ERPNext إنشاء طلب الإجازة المطابق.');
      }
      return core.Map<String, dynamic>.from(created);
    }

  Future<core.Map<String, dynamic>> updateLeaveApplicationDraft({
      required String name,
      required String company,
      required String leaveType,
      required String fromDate,
      required String toDate,
      String description = '',
    }) async {
      final id = name.trim(), normalizedCompany = company.trim();
      final from = DateTime.tryParse(fromDate.trim());
      final to = DateTime.tryParse(toDate.trim());
      if (id.isEmpty || normalizedCompany.isEmpty || from == null || to == null ||
          from.toIso8601String().substring(0, 10) != fromDate.trim() ||
          to.toIso8601String().substring(0, 10) != toDate.trim() ||
          to.isBefore(from)) {
        throw const FormatException('تحقق من رقم الطلب والشركة وتاريخ بداية الإجازة ونهايتها.');
      }
      final normalizedType = leaveType.trim();
      if (normalizedType.isEmpty) throw const FormatException('حدد نوع الإجازة.');
      final response = await _send('GET', '/api/resource/Leave%20Application/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إعادة قراءة طلب الإجازة.'));
      }
      final current = data['data'];
      if (current is! core.Map<String, dynamic> || current['doctype'] != 'Leave Application' ||
          current['name'] != id || current['company'] != normalizedCompany ||
          current['docstatus'] != 0 || current['employee'] is! String) {
        throw const FormatException('يمكن تعديل مسودات طلبات الإجازة التابعة للشركة المحددة فقط.');
      }
      await _fetchHrEmployee(current['employee'].toString(), normalizedCompany);
      final typeResponse = await _send('GET', '/api/resource/Leave%20Type/' + Uri.encodeComponent(normalizedType));
      final typeData = _decode(typeResponse.body);
      if (typeResponse.statusCode < 200 || typeResponse.statusCode >= 300) {
        throw Exception(_message(typeData, 'تعذر التحقق من نوع الإجازة المحدد.'));
      }
      final type = typeData['data'];
      if (type is! core.Map<String, dynamic> || type['doctype'] != 'Leave Type' || type['name'] != normalizedType) {
        throw const FormatException('نوع الإجازة المحدد غير موجود في ERPNext.');
      }
      final payload = <String, dynamic>{
        ...current,
        'leave_type': normalizedType,
        'from_date': fromDate.trim(),
        'to_date': toDate.trim(),
        'description': description.trim(),
      };
      final savedResponse = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final savedData = _decode(savedResponse.body);
      if (savedResponse.statusCode < 200 || savedResponse.statusCode >= 300) {
        throw Exception(_message(savedData, 'تعذر حفظ تعديلات طلب الإجازة.'));
      }
      final saved = savedData['message'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Leave Application' ||
          saved['name'] != id || saved['company'] != normalizedCompany ||
          saved['docstatus'] != 0 || saved['leave_type'] != normalizedType ||
          saved['from_date'] != fromDate.trim() || saved['to_date'] != toDate.trim()) {
        throw const FormatException('لم يؤكد ERPNext حفظ مسودة طلب الإجازة المعدلة.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<List<core.Map<String, dynamic>>> fetchExpenseClaimTypes() async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Expense Claim Type',
        fields: const ['name', 'default_account', 'disabled'],
        filters: const [['disabled', '=', 0]],
        orderBy: 'name asc',
        pageLength: 100,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل أنواع المصروفات.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة أنواع المصروفات غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['disabled'] != 1 && row['disabled'] != true)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> createExpenseClaimDraft({
      required String employee,
      required String company,
      required String postingDate,
      required String expenseType,
      required String amount,
      required String account,
      String description = '',
      String costCenter = '',
    }) async {
      final date = DateTime.tryParse(postingDate.trim());
      final value = double.tryParse(amount.trim());
      if (date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) {
        throw const FormatException('تاريخ المطالبة يجب أن يكون بصيغة YYYY-MM-DD.');
      }
      if (value == null || !value.isFinite || value <= 0) {
        throw const FormatException('أدخل مبلغ مصروف أكبر من صفر.');
      }
      if (expenseType.trim().isEmpty) {
        throw const FormatException('نوع المصروف حقل مطلوب.');
      }
      await _fetchHrEmployee(employee, company);
      final typeResponse = await _send('GET', '/api/resource/Expense%20Claim%20Type/' + Uri.encodeComponent(expenseType.trim()));
      final typeData = _decode(typeResponse.body);
      final type = typeData['data'];
      if (typeResponse.statusCode < 200 || typeResponse.statusCode >= 300 ||
          type is! core.Map<String, dynamic> || type['name'] != expenseType.trim() ||
          type['disabled'] == 1 || type['disabled'] == true) {
        throw const FormatException('نوع المصروف غير موجود أو معطل في ERPNext.');
      }
      final configuredAccount = type['default_account']?.toString().trim() ?? '';
      final selectedAccount = configuredAccount.isNotEmpty ? configuredAccount : account.trim();
      if (selectedAccount.isEmpty) throw const FormatException('حدد حساب المصروف أو استخدم نوعاً له حساب افتراضي.');
      final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(selectedAccount));
      final accountData = _decode(accountResponse.body);
      final accountDoc = accountData['data'];
      if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
          accountDoc is! core.Map<String, dynamic> || accountDoc['company'] != company.trim() ||
          accountDoc['is_group'] == 1 || accountDoc['is_group'] == true ||
          accountDoc['disabled'] == 1 || accountDoc['disabled'] == true) {
        throw const FormatException('حساب المصروف غير صالح أو لا يتبع الشركة المحددة أو ليس حساب حركة.');
      }
      final normalizedCostCenter = costCenter.trim();
      if (normalizedCostCenter.isNotEmpty) {
        final costResponse = await _send('GET', '/api/resource/Cost%20Center/' + Uri.encodeComponent(normalizedCostCenter));
        final costData = _decode(costResponse.body);
        final costDoc = costData['data'];
        if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
            costDoc is! core.Map<String, dynamic> || costDoc['company'] != company.trim() ||
            costDoc['is_group'] == 1 || costDoc['is_group'] == true ||
            costDoc['disabled'] == 1 || costDoc['disabled'] == true) {
          throw const FormatException('مركز التكلفة غير صالح أو لا يتبع الشركة المحددة.');
        }
      }
      final payload = <String, dynamic>{
        'doctype': 'Expense Claim',
        'employee': employee.trim(),
        'company': company.trim(),
        'posting_date': postingDate.trim(),
        'expenses': [{
          'doctype': 'Expense Claim Detail',
          'expense_type': expenseType.trim(),
          'expense_date': postingDate.trim(),
          'amount': value,
          'default_account': selectedAccount,
          'description': description.trim(),
          if (normalizedCostCenter.isNotEmpty) 'cost_center': normalizedCostCenter,
        }],
      };
      final response = await _sendJson('POST', '/api/resource/Expense%20Claim', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إنشاء مسودة مطالبة المصروفات.'));
      }
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Expense Claim' ||
          created['name'] is! String || created['docstatus'] != 0 ||
          created['employee'] != employee.trim() || created['company'] != company.trim()) {
        throw const FormatException('لم يؤكد ERPNext إنشاء مطالبة المصروفات المطابقة.');
      }
      return core.Map<String, dynamic>.from(created);
    }

  Future<core.Map<String, dynamic>> createExpenseClaimDraftLines({
      required String employee,
      required String company,
      required String postingDate,
      required List<core.Map<String, dynamic>> expenses,
    }) async {
      final date = DateTime.tryParse(postingDate.trim());
      if (date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) {
        throw const FormatException('تاريخ المطالبة يجب أن يكون بصيغة YYYY-MM-DD.');
      }
      if (expenses.isEmpty || expenses.length > 50) {
        throw const FormatException('أضف بند مصروف واحداً على الأقل، وبحد أقصى 50 بنداً.');
      }
      await _fetchHrEmployee(employee, company);
      final typeCache = <String, core.Map<String, dynamic>>{};
      final accountCache = <String, core.Map<String, dynamic>>{};
      final costCenterCache = <String, core.Map<String, dynamic>>{};
      final cleanExpenses = <core.Map<String, dynamic>>[];
      for (var index = 0; index < expenses.length; index++) {
        final row = expenses[index];
        final typeName = row['expense_type']?.toString().trim() ?? '';
        final amount = row['amount'] is num
            ? (row['amount'] as num).toDouble()
            : double.tryParse(row['amount']?.toString() ?? '') ?? double.nan;
        if (typeName.isEmpty || !amount.isFinite || amount <= 0) {
          throw FormatException('تحقق من نوع ومبلغ بند المصروف رقم ${index + 1}.');
        }
        var type = typeCache[typeName];
        if (type == null) {
          final typeResponse = await _send('GET', '/api/resource/Expense%20Claim%20Type/' + Uri.encodeComponent(typeName));
          final typeData = _decode(typeResponse.body);
          final rawType = typeData['data'];
          if (typeResponse.statusCode < 200 || typeResponse.statusCode >= 300 ||
              rawType is! core.Map<String, dynamic> || rawType['name'] != typeName ||
              rawType['disabled'] == 1 || rawType['disabled'] == true) {
            throw FormatException('نوع المصروف غير موجود أو معطل: $typeName');
          }
          type = core.Map<String, dynamic>.from(rawType);
          typeCache[typeName] = type;
        }
        final configuredAccount = type['default_account']?.toString().trim() ?? '';
        final account = configuredAccount.isNotEmpty
            ? configuredAccount
            : (row['default_account']?.toString().trim() ?? '');
        if (account.isEmpty) throw FormatException('حدد حساباً لبند المصروف: $typeName');
        var accountDoc = accountCache[account];
        if (accountDoc == null) {
          final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(account));
          final accountData = _decode(accountResponse.body);
          final rawAccount = accountData['data'];
          if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
              rawAccount is! core.Map<String, dynamic> || rawAccount['company'] != company.trim() ||
              rawAccount['is_group'] == 1 || rawAccount['is_group'] == true ||
              rawAccount['disabled'] == 1 || rawAccount['disabled'] == true) {
            throw FormatException('حساب المصروف غير صالح أو لا يتبع الشركة: $account');
          }
          accountDoc = core.Map<String, dynamic>.from(rawAccount);
          accountCache[account] = accountDoc;
        }
        final costCenter = row['cost_center']?.toString().trim() ?? '';
        if (costCenter.isNotEmpty && !costCenterCache.containsKey(costCenter)) {
          final costResponse = await _send('GET', '/api/resource/Cost%20Center/' + Uri.encodeComponent(costCenter));
          final costData = _decode(costResponse.body);
          final rawCostCenter = costData['data'];
          if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
              rawCostCenter is! core.Map<String, dynamic> || rawCostCenter['company'] != company.trim() ||
              rawCostCenter['is_group'] == 1 || rawCostCenter['is_group'] == true ||
              rawCostCenter['disabled'] == 1 || rawCostCenter['disabled'] == true) {
            throw FormatException('مركز التكلفة غير صالح أو لا يتبع الشركة: $costCenter');
          }
          costCenterCache[costCenter] = core.Map<String, dynamic>.from(rawCostCenter);
        }
        cleanExpenses.add({
          'doctype': 'Expense Claim Detail',
          'expense_type': typeName,
          'expense_date': postingDate.trim(),
          'amount': amount,
          'default_account': account,
          'description': row['description']?.toString().trim() ?? '',
          if (costCenter.isNotEmpty) 'cost_center': costCenter,
        });
      }
      final response = await _sendJson('POST', '/api/resource/Expense%20Claim', {
        'doctype': 'Expense Claim',
        'employee': employee.trim(),
        'company': company.trim(),
        'posting_date': postingDate.trim(),
        'expenses': cleanExpenses,
      });
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إنشاء مسودة مطالبة المصروفات متعددة البنود.'));
      }
      final created = data['data'];
      final savedExpenses = created is core.Map<String, dynamic> ? created['expenses'] : null;
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Expense Claim' ||
          created['name'] is! String || created['docstatus'] != 0 ||
          created['employee'] != employee.trim() || created['company'] != company.trim() ||
          savedExpenses is! List || savedExpenses.length != cleanExpenses.length) {
        throw const FormatException('لم يؤكد ERPNext إنشاء مطالبة المصروفات متعددة البنود المطابقة.');
      }
      return core.Map<String, dynamic>.from(created);
    }

  Future<core.Map<String, dynamic>> submitHrDraft({
      required String doctype,
      required String name,
      required String company,
    }) async {
      if (doctype != 'Attendance' && doctype != 'Leave Application' && doctype != 'Expense Claim') {
        throw ArgumentError.value(doctype, 'doctype', 'ترحيل هذا النوع من سجلات الموارد البشرية غير مدعوم.');
      }
      final id = name.trim(), normalizedCompany = company.trim();
      if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم المستند والشركة مطلوبان.');
      final response = await _send('GET', '/api/resource/' +
        Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إعادة قراءة المستند قبل الترحيل.'));
      }
      final current = data['data'];
      if (current is! core.Map<String, dynamic> || current['doctype'] != doctype ||
          current['name'] != id || current['company'] != normalizedCompany ||
          current['docstatus'] != 0 || (current['employee']?.toString().isEmpty ?? true)) {
        throw const FormatException('تم رفض الترحيل لأن هوية المستند أو الشركة أو حالته تغيرت.');
      }
      final submittedResponse = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
      final submittedData = _decode(submittedResponse.body);
      if (submittedResponse.statusCode < 200 || submittedResponse.statusCode >= 300) {
        throw Exception(_message(submittedData, 'تعذر ترحيل مستند الموارد البشرية.'));
      }
      final submitted = submittedData['message'];
      if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != doctype ||
          submitted['name'] != id || submitted['company'] != normalizedCompany ||
          submitted['docstatus'] != 1) {
        throw const FormatException('لم يؤكد ERPNext ترحيل المستند المطلوب.');
      }
      return core.Map<String, dynamic>.from(submitted);
    }
}
