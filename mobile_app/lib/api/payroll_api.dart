// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin PayrollApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchPayrollCostCenters({
      required String company,
    }) async {
      final normalizedCompany = company.trim();
      if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض مراكز التكلفة.');
      const maxRows = 10000;
      final collected = <core.Map<String, dynamic>>[];
      var start = 0;
      while (true) {
        final requestedPageLength = (maxRows + 1 - collected.length).clamp(1, 500).toInt();
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Cost Center',
          fields: const ['name', 'cost_center_name', 'company', 'is_group', 'disabled'],
          filters: [
            ['company', '=', normalizedCompany],
            ['is_group', '=', 0],
            ['disabled', '=', 0],
          ],
          orderBy: 'lft asc, name asc',
          start: start,
          pageLength: requestedPageLength,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل مراكز التكلفة.'));
        }
        final rows = data['data'];
        if (rows is! List) throw const FormatException('استجابة مراكز التكلفة غير متوقعة.');
        collected.addAll(rows.whereType<core.Map<String, dynamic>>()
            .where((row) => row['company'] == normalizedCompany &&
                row['is_group'] != 1 && row['is_group'] != true)
            .map((row) => core.Map<String, dynamic>.from(row)));
        if (collected.length > maxRows) {
          throw const FormatException('تجاوز عدد مراكز التكلفة 10,000؛ قلّص بيانات الشركة قبل إعداد الرواتب.');
        }
        if (rows.length < requestedPageLength) return collected;
        start += rows.length;
      }
    }

  Future<List<core.Map<String, dynamic>>> fetchPayrollEntries({
      required String company,
      int start = 0,
      String? search,
      int? docStatus,
    }) async {
      final normalizedCompany = company.trim();
      if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض دورات الرواتب.');
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Payroll Entry',
        fields: const [
          'name', 'company', 'posting_date', 'start_date', 'end_date',
          'payroll_frequency', 'status', 'docstatus', 'number_of_employees',
          'salary_slips_created', 'salary_slips_submitted', 'currency',
        ],
        filters: [
          ['company', '=', normalizedCompany],
          if (docStatus != null) ['docstatus', '=', docStatus],
        ],
        orFilters: (search?.trim().isNotEmpty ?? false)
            ? [['name', 'like', '%${search!.trim()}%']]
            : null,
        orderBy: 'modified desc, name desc',
        start: start,
        pageLength: 50,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل دورات الرواتب. تأكد من تثبيت HRMS وصلاحية Payroll Entry.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة دورات الرواتب غير متوقعة.');
      final query = search?.trim() ?? '';
      return rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['company'] == normalizedCompany &&
              (docStatus == null || row['docstatus'] == docStatus) &&
              (query.isEmpty || (row['name']?.toString().toLowerCase().contains(query.toLowerCase()) ?? false)))
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchPayrollEntryDocument({
      required String name,
      required String company,
    }) async {
      final id = name.trim(), normalizedCompany = company.trim();
      if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
      final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل دورة الرواتب.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> || document['doctype'] != 'Payroll Entry' ||
          document['name'] != id || document['company'] != normalizedCompany) {
        throw const FormatException('دورة الرواتب لا تتبع الشركة المحددة أو أن هويتها غير مطابقة.');
      }
      return core.Map<String, dynamic>.from(document);
    }

  Future<List<core.Map<String, dynamic>>> fetchPayrollSalarySlips({
      required String payrollEntry,
      required String company,
    }) async {
      final entry = payrollEntry.trim(), normalizedCompany = company.trim();
      if (entry.isEmpty || normalizedCompany.isEmpty) throw const FormatException('دورة الرواتب والشركة مطلوبتان.');
      const maxRows = 10000;
      final collected = <core.Map<String, dynamic>>[];
      var start = 0;
      while (true) {
        // Fetch one extra row at the boundary so exactly 10,000 slips remain valid.
        final requestedPageLength = (maxRows + 1 - collected.length).clamp(1, 500).toInt();
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Salary Slip',
          fields: const [
            'name', 'employee', 'employee_name', 'company', 'start_date', 'end_date',
            'gross_pay', 'total_deduction', 'net_pay', 'currency', 'docstatus', 'status',
            'payroll_entry',
          ],
          filters: [
            ['company', '=', normalizedCompany],
            ['payroll_entry', '=', entry],
          ],
          orderBy: 'employee_name asc, name asc',
          start: start,
          pageLength: requestedPageLength,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل كشوف الرواتب لدورة الرواتب المحددة.'));
        }
        final rows = data['data'];
        if (rows is! List) throw const FormatException('استجابة كشوف الرواتب غير متوقعة.');
        final page = rows.whereType<core.Map<String, dynamic>>()
            .where((row) => row['company'] == normalizedCompany && row['payroll_entry'] == entry)
            .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
        collected.addAll(page);
        if (collected.length > maxRows) {
          throw const FormatException('تجاوزت كشوف الرواتب حد العرض الآمن 10,000 سجل؛ صفّ الدورة في ERPNext قبل المتابعة.');
        }
        if (rows.length < requestedPageLength) return collected;
        start += rows.length;
      }
    }

  Future<core.Map<String, dynamic>> createPayrollEntryDraft({
      required String company,
      required String postingDate,
      required String startDate,
      required String endDate,
      required String payrollFrequency,
      required String costCenter,
      required String currency,
      required String payrollPayableAccount,
      required double exchangeRate,
      String? paymentAccount,
      String? bankAccount,
    }) async {
      final cleanCompany = company.trim();
      final cleanCostCenter = costCenter.trim();
      final cleanCurrency = currency.trim();
      final payable = payrollPayableAccount.trim();
      final frequency = payrollFrequency.trim();
      String validDate(String value, String label) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed == null || parsed.toIso8601String().substring(0, 10) != value.trim()) {
          throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
        }
        return value.trim();
      }
      final posting = validDate(postingDate, 'تاريخ الترحيل');
      final from = validDate(startDate, 'بداية فترة الرواتب');
      final to = validDate(endDate, 'نهاية فترة الرواتب');
      if (cleanCompany.isEmpty || cleanCostCenter.isEmpty || cleanCurrency.isEmpty ||
          payable.isEmpty || !const {'Monthly', 'Fortnightly', 'Bimonthly', 'Weekly', 'Daily'}.contains(frequency) ||
          !exchangeRate.isFinite || exchangeRate <= 0 || from.compareTo(to) > 0) {
        throw const FormatException('أكمل بيانات دورة الرواتب وتأكد من الفترة والتكرار وسعر الصرف.');
      }
      Future<core.Map<String, dynamic>> readSetupDoc(String doctype, String name, String failure) async {
        final response = await _send(
          'GET',
          '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name),
        );
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, failure));
        }
        final row = data['data'];
        if (row is! core.Map<String, dynamic> || row['doctype'] != doctype || row['name'] != name) {
          throw FormatException('بيانات $doctype غير مطابقة.');
        }
        return row;
      }
      final setup = await Future.wait([
        readSetupDoc('Cost Center', cleanCostCenter, 'تعذر التحقق من مركز التكلفة.'),
        readSetupDoc('Account', payable, 'تعذر التحقق من حساب الرواتب المستحقة.'),
      ]);
      final costCenterDoc = setup[0], payableDoc = setup[1];
      if (costCenterDoc['company'] != cleanCompany || (costCenterDoc['disabled'] == 1 || costCenterDoc['disabled'] == true) ||
          costCenterDoc['is_group'] == 1 || costCenterDoc['is_group'] == true) {
        throw const FormatException('مركز التكلفة يجب أن يكون مركز ترحيل نشطاً تابعاً للشركة المحددة.');
      }
      if (payableDoc['company'] != cleanCompany || (payableDoc['disabled'] == 1 || payableDoc['disabled'] == true) ||
          payableDoc['is_group'] == 1 || payableDoc['is_group'] == true ||
          payableDoc['account_type'] != 'Payable') {
        throw const FormatException('حساب الرواتب يجب أن يكون حساب Payable نشطاً وقابلاً للترحيل ضمن الشركة.');
      }
      final bankId = bankAccount?.trim() ?? '';
      final paymentId = paymentAccount?.trim() ?? '';
      if (bankId.isNotEmpty || paymentId.isNotEmpty) {
        if (bankId.isEmpty || paymentId.isEmpty) {
          throw const FormatException('يجب تحديد حساب البنك وحساب الأستاذ المرتبط به معاً.');
        }
        final bank = await readSetupDoc('Bank Account', bankId, 'تعذر التحقق من حساب البنك.');
        if (bank['company'] != cleanCompany || bank['disabled'] == 1 || bank['disabled'] == true ||
            (bank['is_company_account'] != 1 && bank['is_company_account'] != true) || bank['account'] != paymentId) {
          throw const FormatException('حساب البنك أو حساب الأستاذ المرتبط به لا يتبع الشركة أو غير صالح للصرف.');
        }
        final paymentDoc = await readSetupDoc('Account', paymentId, 'تعذر التحقق من حساب الدفع.');
        if (paymentDoc['company'] != cleanCompany || paymentDoc['disabled'] == 1 || paymentDoc['disabled'] == true ||
            paymentDoc['is_group'] == 1 || paymentDoc['is_group'] == true ||
            !{'Bank', 'Cash'}.contains(paymentDoc['account_type'])) {
          throw const FormatException('حساب الدفع يجب أن يكون حساب بنك أو نقد نشطاً وقابلاً للترحيل ضمن الشركة.');
        }
      }
      final doc = <String, dynamic>{
        'doctype': 'Payroll Entry',
        'company': cleanCompany,
        'posting_date': posting,
        'start_date': from,
        'end_date': to,
        'payroll_frequency': frequency,
        'salary_slip_based_on_timesheet': 0,
        'cost_center': cleanCostCenter,
        'currency': cleanCurrency,
        'exchange_rate': exchangeRate,
        'payroll_payable_account': payable,
        if (paymentAccount?.trim().isNotEmpty == true) 'payment_account': paymentAccount!.trim(),
        if (bankAccount?.trim().isNotEmpty == true) 'bank_account': bankAccount!.trim(),
      };
      final response = await _sendJson('POST', '/api/resource/Payroll%20Entry', doc);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'رفض ERPNext إنشاء دورة الرواتب. تحقق من إعدادات HRMS والحسابات.'));
      }
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Payroll Entry' ||
          created['company'] != cleanCompany || created['docstatus'] != 0 ||
          (created['name']?.toString().trim().isEmpty ?? true)) {
        throw const FormatException('لم يؤكد ERPNext إنشاء مسودة دورة الرواتب الصحيحة.');
      }
      return core.Map<String, dynamic>.from(created);
    }

  Future<core.Map<String, dynamic>> _runPayrollEntryMethod({
      required String name,
      required String company,
      required String method,
      bool requireSubmitted = false,
    }) async {
      const allowedMethods = {'fill_employee_details', 'submit_salary_slips', 'make_bank_entry'};
      if (!allowedMethods.contains(method)) throw ArgumentError.value(method, 'method', 'إجراء رواتب غير مدعوم.');
      final id = name.trim(), normalizedCompany = company.trim();
      if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
      final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إعادة قراءة دورة الرواتب.'));
      }
      final current = data['data'];
      if (current is! core.Map<String, dynamic> || current['doctype'] != 'Payroll Entry' ||
          current['name'] != id || current['company'] != normalizedCompany ||
          (requireSubmitted ? current['docstatus'] != 1 : current['docstatus'] != 0)) {
        throw const FormatException('تم رفض الإجراء لأن دورة الرواتب لا تتبع الشركة أو أن حالتها غير مناسبة.');
      }
      final result = await _sendJson('POST', '/api/method/run_doc_method', {
        'docs': jsonEncode(current),
        'method': method,
      });
      final resultData = _decode(result.body);
      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw Exception(_message(resultData, 'تعذر تنفيذ إجراء الرواتب $method.'));
      }
      final docs = resultData['docs'];
      if (docs is! List || docs.isEmpty || docs.first is! core.Map<String, dynamic>) {
        throw const FormatException('لم يُرجع ERPNext دورة رواتب محدثة بعد تنفيذ الإجراء.');
      }
      final updated = core.Map<String, dynamic>.from(docs.first as core.Map);
      if (updated['doctype'] != 'Payroll Entry' || updated['name'] != id ||
          updated['company'] != normalizedCompany) {
        throw const FormatException('استجابة إجراء الرواتب لا تطابق دورة الرواتب المطلوبة.');
      }
      updated['_mobile_method_message'] = resultData['message'];
      return updated;
    }

  Future<core.Map<String, dynamic>> fillPayrollEmployees({
      required String name,
      required String company,
    }) async {
      final id = name.trim(), normalizedCompany = company.trim();
      final updated = await _runPayrollEntryMethod(
        name: id, company: normalizedCompany, method: 'fill_employee_details',
      );
      final employees = updated['employees'];
      if (employees is! List || employees.isEmpty) {
        throw const FormatException('لم يعثر HRMS على موظفين لهم تعيين هيكل راتب نشط مطابق للفترة والحسابات.');
      }
      final saveResponse = await _sendJson(
        'PUT',
        '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id),
        {
          'employees': employees,
          'number_of_employees': updated['number_of_employees'] ?? employees.length,
        },
      );
      final saveData = _decode(saveResponse.body);
      if (saveResponse.statusCode < 200 || saveResponse.statusCode >= 300) {
        throw Exception(_message(saveData, 'تعذر حفظ قائمة الموظفين في مسودة دورة الرواتب.'));
      }
      final saved = saveData['data'];
      if (saved is! core.Map<String, dynamic> || saved['name'] != id ||
          saved['company'] != normalizedCompany || saved['employees'] is! List ||
          (saved['employees'] as List).length != employees.length) {
        throw const FormatException('لم يؤكد ERPNext حفظ قائمة الموظفين الصحيحة في دورة الرواتب.');
      }
      final unmarked = updated['_mobile_method_message'];
      if (unmarked is List && unmarked.isNotEmpty) {
        throw FormatException('لا يمكن ترحيل الرواتب قبل استكمال تسجيل الحضور لبعض الموظفين. عدد الحالات غير المكتملة: ${unmarked.length}.');
      }
      return {...core.Map<String, dynamic>.from(saved), 'mobile_unmarked_attendance': unmarked ?? const []};
    }

  Future<core.Map<String, dynamic>> submitPayrollSalarySlips({
      required String name,
      required String company,
    }) async {
      final updated = await _runPayrollEntryMethod(
        name: name, company: company, method: 'submit_salary_slips', requireSubmitted: true,
      );
      final slips = await fetchPayrollSalarySlips(payrollEntry: name, company: company);
      final pending = slips.where((row) => row['docstatus'] == 0).length;
      return {...updated, 'mobile_pending_salary_slips': pending};
    }

  Future<core.Map<String, dynamic>> createPayrollBankEntry({
      required String name,
      required String company,
    }) async {
      final document = await fetchPayrollEntryDocument(name: name, company: company);
      if ((document['payment_account']?.toString().trim().isEmpty ?? true) ||
          (document['bank_account']?.toString().trim().isEmpty ?? true)) {
        throw const FormatException('حدد حساب الدفع وحساب البنك في دورة الرواتب قبل إنشاء قيد الصرف.');
      }
      final slips = await fetchPayrollSalarySlips(payrollEntry: name, company: company);
      if (slips.isEmpty || slips.any((row) => row['docstatus'] != 1)) {
        throw const FormatException('لا يمكن إنشاء قيد الصرف قبل اعتماد جميع كشوف الرواتب المرتبطة بالدورة.');
      }
      return _runPayrollEntryMethod(
        name: name, company: company, method: 'make_bank_entry', requireSubmitted: true,
      );
    }

  Future<core.Map<String, dynamic>> submitPayrollEntry({
      required String name,
      required String company,
    }) async {
      final id = name.trim(), normalizedCompany = company.trim();
      if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
      var current = await fetchPayrollEntryDocument(name: id, company: normalizedCompany);
      if (current['docstatus'] != 0) {
        throw const FormatException('لا يمكن ترحيل دورة رواتب لم تعد مسودة.');
      }
      // Preserve the employee rows already reviewed or edited by the user.
      // Populate them only when the draft has not yet been initialized.
      final existingEmployees = current['employees'];
      if (existingEmployees is! List || existingEmployees.isEmpty) {
        await fillPayrollEmployees(name: id, company: normalizedCompany);
        current = await fetchPayrollEntryDocument(name: id, company: normalizedCompany);
      }
      if (current['docstatus'] != 0 || current['employees'] is! List ||
          (current['employees'] as List).isEmpty) {
        throw const FormatException('لا يمكن ترحيل دورة الرواتب قبل تحميل الموظفين والتحقق من الشركة والحالة.');
      }
      final responseSubmit = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
      final submitData = _decode(responseSubmit.body);
      if (responseSubmit.statusCode < 200 || responseSubmit.statusCode >= 300) {
        throw Exception(_message(submitData, 'رفض ERPNext ترحيل دورة الرواتب وإنشاء كشوف الرواتب.'));
      }
      final submitted = submitData['message'];
      if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != 'Payroll Entry' ||
          submitted['name'] != id || submitted['company'] != normalizedCompany ||
          submitted['docstatus'] != 1) {
        throw const FormatException('لم يؤكد ERPNext ترحيل دورة الرواتب.');
      }
      return core.Map<String, dynamic>.from(submitted);
    }

  Future<core.Map<String, dynamic>> fetchSalarySlipDetails({
      required String name,
      required String company,
    }) async {
      final id = name.trim(), normalizedCompany = company.trim();
      if (id.isEmpty || normalizedCompany.isEmpty) {
        throw const FormatException('رقم كشف الراتب والشركة مطلوبان.');
      }
      final response = await _send(
        'GET', '/api/resource/Salary%20Slip/' + Uri.encodeComponent(id),
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل كشف الراتب.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> ||
          document['doctype'] != 'Salary Slip' || document['name'] != id ||
          document['company'] != normalizedCompany) {
        throw const FormatException('كشف الراتب لا ينتمي إلى الشركة المحددة أو أن هويته غير مطابقة.');
      }
      for (final field in const ['earnings', 'deductions']) {
        final rows = document[field];
        if (rows != null && rows is! List) {
          throw FormatException('تفاصيل $field في كشف الراتب غير متوقعة.');
        }
      }
      return core.Map<String, dynamic>.from(document);
    }
}
