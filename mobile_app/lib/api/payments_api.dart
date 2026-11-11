// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin PaymentsApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchSupplierPayments({int start = 0, String? search}) async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Payment Entry',
        fields: const [
          'name', 'posting_date', 'party', 'party_name', 'paid_amount',
          'paid_from', 'reference_no', 'reference_date', 'status', 'docstatus',
        ],
        filters: const [
          ['payment_type', '=', 'Pay'],
          ['party_type', '=', 'Supplier'],
          ['docstatus', '=', 1],
        ],
        orFilters: search == null || search.trim().isEmpty ? null : [
          ['name', 'like', '%${search.trim()}%'],
          ['party', 'like', '%${search.trim()}%'],
          ['party_name', 'like', '%${search.trim()}%'],
        ],
        orderBy: 'posting_date desc, name desc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل سجل دفعات الموردين. تحقق من صلاحية قراءة Payment Entry.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة سجل دفعات الموردين غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchDraftSupplierPayments({
      int start = 0,
      String? search,
    }) async {
      final query = search?.trim() ?? '';
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Payment Entry',
        fields: const [
          'name', 'posting_date', 'party', 'party_name', 'paid_amount', 'payment_type', 'party_type',
          'paid_from', 'reference_no', 'reference_date', 'status', 'docstatus',
        ],
        filters: const [
          ['payment_type', '=', 'Pay'],
          ['party_type', '=', 'Supplier'],
          ['docstatus', '=', 0],
        ],
        orFilters: query.isEmpty ? null : [
          ['name', 'like', '%$query%'],
          ['party', 'like', '%$query%'],
          ['party_name', 'like', '%$query%'],
        ],
        orderBy: 'modified desc, name desc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل مسودات دفعات الموردين.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة مسودات دفعات الموردين غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['docstatus'] == 0 &&
              row['payment_type'] == 'Pay' && row['party_type'] == 'Supplier')
          .toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDraftDocument(String name) =>
        _fetchPaymentEntryDraft(
          name,
          paymentType: 'Pay',
          partyType: 'Supplier',
        );

  Future<core.Map<String, dynamic>> submitSupplierPaymentDraft(
      core.Map<String, dynamic> draft,
    ) async {
      if (draft['doctype'] != 'Payment Entry' ||
          draft['payment_type'] != 'Pay' ||
          draft['party_type'] != 'Supplier') {
        throw const FormatException('المستند ليس مسودة سند صرف مورد صحيحة.');
      }
      return _submitMobileDocument(draft, 'Payment Entry');
    }

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDocument(String name) async {
      if (name.trim().isEmpty) throw const FormatException('رقم سند صرف المورد غير موجود.');
      final response = await _send(
        'GET',
        '/api/resource/Payment%20Entry/' + Uri.encodeComponent(name),
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل سند صرف المورد.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> ||
          document['doctype'] != 'Payment Entry' ||
          document['payment_type'] != 'Pay' ||
          document['party_type'] != 'Supplier' ||
          document['docstatus'] != 1 ||
          document['references'] is! List) {
        throw const FormatException('سند الصرف غير مرحّل أو لا يخص دفعات الموردين.');
      }
      return document;
    }

  Future<List<ErpPaymentAccount>> fetchPaymentAccounts(String company) async {
      final normalizedCompany = company.trim();
      if (normalizedCompany.isEmpty) {
        throw const FormatException('اسم الشركة غير موجود لتحميل حسابات التحصيل.');
      }
  
      const accountPageSize = FrappeApi.pageSize;
      const maxAccountCount = 10000;
      final accounts = <ErpPaymentAccount>[];
      var start = 0;
      while (true) {
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Account',
          fields: const ['name', 'account_name', 'account_type', 'account_currency'],
          filters: [
            ['company', '=', normalizedCompany],
            ['disabled', '=', 0],
            ['is_group', '=', 0],
            ['account_type', 'in', ['Cash', 'Bank']],
          ],
          orderBy: 'account_type asc, account_name asc',
          start: start,
          pageLength: accountPageSize,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل حسابات الصندوق والبنك للشركة.'));
        }
        final rows = data['data'];
        if (rows is! List) {
          throw Exception('استجابة حسابات التحصيل من ERPNext غير متوقعة.');
        }
        accounts.addAll(
          rows
              .whereType<core.Map<String, dynamic>>()
              .map(ErpPaymentAccount.fromJson),
        );
        if (rows.length < accountPageSize) {
          return accounts;
        }
        if (accounts.length > maxAccountCount) {
          throw const FormatException(
            'تجاوز عدد حسابات التحصيل الحد الآمن للتحميل دفعة واحدة.',
          );
        }
        start += rows.length;
      }
    }

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDocument(String name) async {
      if (name.trim().isEmpty) throw const FormatException('رقم سند القبض غير موجود.');
      final response = await _send(
        'GET',
        '/api/resource/Payment%20Entry/${Uri.encodeComponent(name.trim())}',
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر التحقق من حالة سند القبض.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> ||
          document['doctype'] != 'Payment Entry' ||
          document['name'] != name.trim()) {
        throw const FormatException('بيانات سند القبض غير مؤكدة.');
      }
      return document;
    }

  Future<core.Map<String, dynamic>> receiveSalesInvoicePayment({
      required String invoiceName,
      required double amount,
      String? bankAccount,
    }) async {
      final actionKey = 'receipt:$invoiceName';
      if (!_inFlightSalesActions.add(actionKey)) {
        throw const FormatException('تسجيل دفعة هذه الفاتورة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      if (invoiceName.trim().isEmpty || !amount.isFinite || amount <= 0) {
        throw const FormatException('أدخل رقم الفاتورة ومبلغ دفعة صحيحاً أكبر من صفر.');
      }
      final invoice = await fetchInvoiceDocument('Sales Invoice', invoiceName);
      if (invoice['docstatus'] != 1) {
        throw const FormatException('لا يمكن تسجيل دفعة إلا على فاتورة مبيعات مرحّلة.');
      }
      final outstanding = double.tryParse(invoice['outstanding_amount']?.toString() ?? '') ?? 0;
      if (outstanding <= 0 || amount > outstanding + 0.000001) {
        throw FormatException('مبلغ الدفعة يتجاوز المبلغ المستحق المتبقي (${outstanding.toStringAsFixed(2)}).');
      }
      final setup = await _sendJson(
        'POST',
        '/api/method/erpnext.accounts.doctype.payment_entry.payment_entry.get_payment_entry',
        {
          'dt': 'Sales Invoice',
          'dn': invoiceName,
          'party_amount': amount,
          if (bankAccount != null && bankAccount.trim().isNotEmpty) 'bank_account': bankAccount.trim(),
        },
      );
      final setupData = _decode(setup.body);
      if (setup.statusCode < 200 || setup.statusCode >= 300) {
        throw Exception(_message(setupData, 'تعذر تجهيز سند القبض. تحقق من الحسابات الافتراضية وصلاحيات Payment Entry.'));
      }
      final rawDocument = setupData['message'];
      if (rawDocument is! core.Map<String, dynamic> ||
          rawDocument['doctype'] != 'Payment Entry' ||
          rawDocument['payment_type'] != 'Receive' ||
          rawDocument['party_type'] != 'Customer' ||
          rawDocument['party'] != invoice['customer'] ||
          rawDocument['company'] != invoice['company']) {
        throw const FormatException('بيانات سند القبض التي جهزها ERPNext لا تطابق العميل والشركة والفاتورة المطلوبة.');
      }
      if (bankAccount != null && bankAccount.trim().isNotEmpty &&
          rawDocument['paid_to'] != bankAccount.trim()) {
        throw const FormatException('حساب الصندوق أو البنك الذي جهزه ERPNext لا يطابق الحساب الذي اخترته.');
      }
      final references = rawDocument['references'];
      if (references is! List || references.isEmpty) {
        throw Exception('لم يربط ERPNext سند القبض بفاتورة المبيعات.');
      }
      // ERPNext may split one invoice across several payment-term references.
      // Keep its allocations intact and verify their combined amount instead of
      // overwriting every row with the full payment amount.
      var allocatedTotal = 0.0;
      for (final row in references) {
        if (row is! core.Map<String, dynamic> ||
            row['reference_doctype'] != 'Sales Invoice' ||
            row['reference_name'] != invoiceName) {
          continue;
        }
        final allocated = row['allocated_amount'];
        if (allocated is num) {
          allocatedTotal += allocated.toDouble();
        } else {
          allocatedTotal += double.tryParse(allocated?.toString() ?? '') ?? 0;
        }
      }
      if ((allocatedTotal - amount).abs() > 0.01) {
        throw FormatException(
          'وزّع ERPNext مبلغ الدفعة على شروط السداد بقيمة ${allocatedTotal.toStringAsFixed(2)} بدلاً من ${amount.toStringAsFixed(2)}؛ لم يتم إنشاء سند القبض.',
        );
      }
      final paymentDraft = core.Map<String, dynamic>.from(rawDocument);
  
      final insert = await _sendJson('POST', '/api/resource/Payment%20Entry', paymentDraft);
      final insertData = _decode(insert.body);
      if (insert.statusCode < 200 || insert.statusCode >= 300) {
        throw Exception(_message(insertData, 'تعذر حفظ سند القبض.'));
      }
      final created = insertData['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Payment Entry' ||
          created['name'] is! String ||
          created['docstatus'] != 0 ||
          created['payment_type'] != 'Receive' ||
          created['party_type'] != 'Customer' ||
          created['party'] != invoice['customer']) {
        throw Exception('استجابة حفظ سند القبض غير متوقعة؛ تحقق من سجل Payment Entry قبل إعادة المحاولة.');
      }
      try {
        return await _submitMobileDocument(created, 'Payment Entry');
      } catch (error) {
        // A timeout or lost response must not cause a second receipt to be created.
        // Re-read the same Payment Entry before reporting an uncertain outcome.
        try {
          final confirmed = await _fetchPaymentEntryDocument(created['name'].toString());
          if (confirmed['docstatus'] == 1 &&
              confirmed['payment_type'] == 'Receive' &&
              confirmed['party_type'] == 'Customer' &&
              confirmed['party'] == invoice['customer']) {
            return confirmed;
          }
        } catch (_) {
          // Keep the original uncertainty message below; never retry creation here.
        }
        throw Exception('تم إنشاء سند القبض ${created['name']}، لكن لم يتم تأكيد ترحيله. راجع حالة هذا السند في ERPNext قبل محاولة تسجيل دفعة أخرى. التفاصيل: ${error.toString().replaceFirst('Exception: ', '')}');
      }
      } finally {
        _inFlightSalesActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> payPurchaseInvoice({
      required String invoiceName, required double amount, String? bankAccount,
    }) async {
      final actionKey = 'purchase-payment:$invoiceName';
      if (!_inFlightPaymentActions.add(actionKey)) {
        throw const FormatException('سداد هذه الفاتورة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      if (invoiceName.trim().isEmpty || !amount.isFinite || amount <= 0) throw const FormatException('أدخل فاتورة ومبلغ دفعة صحيحاً.');
      final invoice = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
      if (invoice['docstatus'] != 1 || invoice['is_return'] == 1 || invoice['is_return'] == true) {
        throw const FormatException('سداد المورد يتطلب فاتورة مشتريات أصلية مرحلة.');
      }
      final outstanding = double.tryParse(invoice['outstanding_amount']?.toString() ?? '') ?? 0;
      if (outstanding <= 0 || amount > outstanding + 0.000001) throw const FormatException('مبلغ الدفعة يتجاوز المستحق المتبقي.');
      final setup = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.payment_entry.payment_entry.get_payment_entry',
        {'dt': 'Purchase Invoice', 'dn': invoiceName, 'party_amount': amount,
         if (bankAccount != null && bankAccount.trim().isNotEmpty) 'bank_account': bankAccount.trim()});
      final setupData = _decode(setup.body);
      if (setup.statusCode < 200 || setup.statusCode >= 300) throw Exception(_message(setupData, 'تعذر تجهيز سند صرف المورد.'));
      final raw = setupData['message'];
      if (raw is! core.Map<String, dynamic> || raw['payment_type'] != 'Pay' ||
          raw['party_type'] != 'Supplier' || raw['party'] != invoice['supplier']) {
        throw Exception('بيانات سند الصرف لا تطابق المورد المطلوب.');
      }
      if (bankAccount != null && bankAccount.trim().isNotEmpty &&
          raw['paid_from'] != bankAccount.trim()) {
        throw Exception('حساب الصندوق أو البنك الذي جهزه ERPNext لا يطابق الحساب الذي اخترته.');
      }
      final refs = raw['references'];
      if (refs is! List || refs.isEmpty) throw Exception('لم يربط ERPNext سند الصرف بالفاتورة.');
      var allocated = 0.0;
      for (final row in refs) {
        if (row is core.Map<String, dynamic> && row['reference_doctype'] == 'Purchase Invoice' &&
            row['reference_name'] == invoiceName) {
          allocated += double.tryParse(row['allocated_amount']?.toString() ?? '') ?? 0;
        }
      }
      if ((allocated - amount).abs() > 0.01) throw const FormatException('توزيع الدفعة من ERPNext لا يطابق المبلغ المطلوب.');
      final inserted = await _sendJson('POST', '/api/resource/Payment%20Entry', core.Map<String, dynamic>.from(raw));
      final insertedData = _decode(inserted.body);
      if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(insertedData, 'تعذر حفظ سند الصرف.'));
      final created = insertedData['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Payment Entry' ||
          created['name'] is! String ||
          created['docstatus'] != 0 ||
          created['payment_type'] != 'Pay' ||
          created['party_type'] != 'Supplier' ||
          created['party'] != invoice['supplier'] ||
          created['company'] != invoice['company'] ||
          (bankAccount != null && bankAccount.trim().isNotEmpty &&
              created['paid_from'] != bankAccount.trim()) ||
          created['references'] is! List) {
        throw Exception('استجابة حفظ سند الصرف لا تطابق المورد أو الشركة أو الحساب أو حالة المسودة؛ تحقق من سجل Payment Entry قبل إعادة المحاولة.');
      }
      var createdAllocation = 0.0;
      for (final row in created['references'] as List) {
        if (row is core.Map<String, dynamic> &&
            row['reference_doctype'] == 'Purchase Invoice' &&
            row['reference_name'] == invoiceName) {
          createdAllocation += double.tryParse(row['allocated_amount']?.toString() ?? '') ?? 0;
        }
      }
      if ((createdAllocation - amount).abs() > 0.01) {
        throw const FormatException('سند الصرف المحفوظ لا يحتوي على توزيع مطابق للفاتورة والمبلغ المطلوب؛ لا تحاول إنشاء دفعة ثانية قبل مراجعة السند.');
      }
      try {
        return await _submitMobileDocument(created, 'Payment Entry');
      } catch (error) {
        // Confirm the same voucher after a lost response; never create a second payment here.
        try {
          final confirmed = await _fetchPaymentEntryDocument(created['name'].toString());
          if (confirmed['docstatus'] == 1 &&
              confirmed['payment_type'] == 'Pay' &&
              confirmed['party_type'] == 'Supplier') {
            return confirmed;
          }
        } catch (_) {
          // Keep the original uncertainty message below.
        }
        throw Exception('تم حفظ سند الصرف ' + created['name'].toString() + ' لكن لم يؤكد ERPNext ترحيله. راجع حالة هذا السند قبل تسجيل دفعة أخرى. ' + error.toString().replaceFirst('Exception: ', ''));
      }
      } finally {
        _inFlightPaymentActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDraft(String name, {required String paymentType, required String partyType}) async {
      if (name.trim().isEmpty) throw const FormatException('رقم سند الدفع غير موجود.');
      final response = await _send('GET',
        '/api/resource/Payment%20Entry/' + Uri.encodeComponent(name.trim()),
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل مسودة سند الدفع.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> ||
          document['doctype'] != 'Payment Entry' ||
          document['name'] != name.trim() || document['docstatus'] != 0 ||
          document['payment_type'] != paymentType ||
          document['party_type'] != partyType ||
          document['references'] is! List) {
        throw const FormatException('سند الدفع لم يعد مسودة أو أن بياناته غير صحيحة.');
      }
      return document;
    }

  Future<core.Map<String, dynamic>> payExpenseClaim({
      required String claimName,
      required double amount,
      String? bankAccount,
    }) async {
      final id = claimName.trim();
      if (id.isEmpty || !amount.isFinite || amount <= 0) {
        throw const FormatException('حدد مطالبة المصروف ومبلغ سداد موجباً.');
      }
      final actionKey = 'expense-claim-payment:$id';
      if (!_inFlightPaymentActions.add(actionKey)) {
        throw const FormatException('سداد هذه المطالبة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
        final claimResponse = await _send(
          'GET', '/api/resource/Expense%20Claim/' + Uri.encodeComponent(id),
        );
        final claimData = _decode(claimResponse.body);
        if (claimResponse.statusCode < 200 || claimResponse.statusCode >= 300) {
          throw Exception(_message(claimData, 'تعذر تحميل مطالبة المصروف قبل السداد.'));
        }
        final claim = claimData['data'];
        if (claim is! core.Map<String, dynamic> ||
            claim['doctype'] != 'Expense Claim' || claim['name'] != id ||
            claim['docstatus'] != 1 || claim['approval_status'] != 'Approved' ||
            (claim['employee']?.toString().trim().isEmpty ?? true) ||
            (claim['company']?.toString().trim().isEmpty ?? true)) {
          throw const FormatException('لا يمكن سداد إلا مطالبة مصروف مرحّلة ومعتمدة تابعة لموظف وشركة صحيحين.');
        }
        final sanctioned = double.tryParse(claim['total_sanctioned_amount']?.toString() ?? '') ?? 0;
        final reimbursed = double.tryParse(claim['total_amount_reimbursed']?.toString() ?? '') ?? 0;
        final outstanding = sanctioned - reimbursed;
        if (!sanctioned.isFinite || !reimbursed.isFinite || !outstanding.isFinite ||
            outstanding <= 0 || amount > outstanding + 0.000001) {
          throw FormatException('مبلغ السداد يتجاوز المتبقي المعتمد للمطالبة (${outstanding.toStringAsFixed(2)}).');
        }
        final pendingUri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Payment Entry',
          fields: const ['name', 'docstatus', 'payment_type', 'party_type', 'party', 'company'],
          filters: [
            ['company', '=', claim['company']],
            ['party_type', '=', 'Employee'],
            ['party', '=', claim['employee']],
            ['payment_type', '=', 'Pay'],
            ['docstatus', '=', 0],
          ],
          orderBy: 'modified desc, name desc',
          pageLength: 100,
        );
        final pendingResponse = await _sendUri('GET', pendingUri);
        final pendingData = _decode(pendingResponse.body);
        if (pendingResponse.statusCode < 200 || pendingResponse.statusCode >= 300) {
          throw Exception(_message(pendingData, 'تعذر التحقق من مسودات سداد المطالبة قبل إنشاء دفعة جديدة.'));
        }
        final pendingRows = pendingData['data'];
        if (pendingRows is! List) {
          throw const FormatException('استجابة مسودات دفعات الموظف غير متوقعة.');
        }
        for (final raw in pendingRows.whereType<core.Map<String, dynamic>>()) {
          final pendingName = raw['name']?.toString().trim() ?? '';
          if (pendingName.isEmpty || raw['company'] != claim['company'] ||
              raw['party'] != claim['employee'] || raw['docstatus'] != 0) {
            continue;
          }
          final pending = await _fetchPaymentEntryDraft(
            pendingName, paymentType: 'Pay', partyType: 'Employee',
          );
          final pendingReferences = pending['references'];
          if (pending['company'] == claim['company'] &&
              pending['party'] == claim['employee'] &&
              pendingReferences is List &&
              pendingReferences.whereType<core.Map<String, dynamic>>().any((reference) =>
                reference['reference_doctype'] == 'Expense Claim' &&
                reference['reference_name'] == id)) {
            throw FormatException('يوجد بالفعل سند دفع مسودة ($pendingName) مرتبط بهذه المطالبة. راجعه أو ألغِه قبل إنشاء سند آخر.');
          }
        }
        final selectedAccount = bankAccount?.trim() ?? '';
        if (selectedAccount.isNotEmpty) {
          final accountResponse = await _send(
            'GET', '/api/resource/Account/' + Uri.encodeComponent(selectedAccount),
          );
          final accountData = _decode(accountResponse.body);
          final account = accountData['data'];
          if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
              account is! core.Map<String, dynamic> ||
              account['company'] != claim['company'] ||
              account['is_group'] == 1 || account['is_group'] == true ||
              account['disabled'] == 1 || account['disabled'] == true ||
              !{'Cash', 'Bank'}.contains(account['account_type'])) {
            throw const FormatException('حساب الصندوق أو البنك غير صالح أو لا يتبع شركة المطالبة.');
          }
        }
        final setup = await _sendJson(
          'POST',
          '/api/method/erpnext.accounts.doctype.payment_entry.payment_entry.get_payment_entry',
          {
            'dt': 'Expense Claim',
            'dn': id,
            'party_amount': amount,
            if (selectedAccount.isNotEmpty) 'bank_account': selectedAccount,
          },
        );
        final setupData = _decode(setup.body);
        if (setup.statusCode < 200 || setup.statusCode >= 300) {
          throw Exception(_message(setupData, 'تعذر تجهيز سند سداد مطالبة المصروف من ERPNext.'));
        }
        final rawDraft = setupData['message'];
        if (rawDraft is! core.Map<String, dynamic> ||
            rawDraft['doctype'] != 'Payment Entry' ||
            rawDraft['payment_type'] != 'Pay' ||
            rawDraft['party_type'] != 'Employee' ||
            rawDraft['party'] != claim['employee'] ||
            rawDraft['company'] != claim['company'] ||
            (selectedAccount.isNotEmpty && rawDraft['paid_from'] != selectedAccount)) {
          throw const FormatException('سند الدفع الذي جهزه ERPNext لا يطابق الموظف أو الشركة أو الحساب المحدد.');
        }
        final references = rawDraft['references'];
        if (references is! List) {
          throw const FormatException('سند الدفع لا يحتوي مراجع مطالبة المصروف.');
        }
        var allocated = 0.0;
        for (final raw in references.whereType<core.Map<String, dynamic>>()) {
          if (raw['reference_doctype'] != 'Expense Claim' || raw['reference_name'] != id) continue;
          allocated += double.tryParse(raw['allocated_amount']?.toString() ?? '') ?? 0;
        }
        if ((allocated - amount).abs() > 0.01) {
          throw FormatException('تخصيص سند الدفع للمطالبة (${allocated.toStringAsFixed(2)}) لا يطابق مبلغ السداد المطلوب (${amount.toStringAsFixed(2)}).');
        }
        final insert = await _sendJson('POST', '/api/resource/Payment%20Entry', rawDraft);
        final insertData = _decode(insert.body);
        if (insert.statusCode < 200 || insert.statusCode >= 300) {
          throw Exception(_message(insertData, 'تعذر حفظ سند سداد مطالبة المصروف.'));
        }
        final created = insertData['data'];
        if (created is! core.Map<String, dynamic> ||
            created['doctype'] != 'Payment Entry' ||
            created['name'] is! String || created['docstatus'] != 0 ||
            created['payment_type'] != 'Pay' || created['party_type'] != 'Employee' ||
            created['party'] != claim['employee'] || created['company'] != claim['company']) {
          throw const FormatException('لم يؤكد ERPNext حفظ مسودة سند سداد المطالبة المطابقة.');
        }
        try {
          final submitted = await _submitMobileDocument(created, 'Payment Entry');
          if (submitted['payment_type'] != 'Pay' ||
              submitted['party_type'] != 'Employee' ||
              submitted['party'] != claim['employee'] ||
              submitted['company'] != claim['company'] ||
              submitted['docstatus'] != 1) {
            throw const FormatException('لم يؤكد ERPNext ترحيل سند سداد الموظف المطابق.');
          }
          return submitted;
        } catch (error) {
          try {
            final confirmed = await _fetchPaymentEntryDocument(created['name'].toString());
            if (confirmed['docstatus'] == 1 &&
                confirmed['payment_type'] == 'Pay' &&
                confirmed['party_type'] == 'Employee' &&
                confirmed['party'] == claim['employee'] &&
                confirmed['company'] == claim['company']) {
              return confirmed;
            }
          } catch (_) {
            // Preserve the original uncertain result and never create another payment.
          }
          throw Exception('تم إنشاء سند الدفع ${created['name']} لكن لم يتأكد ترحيله. راجع السند في ERPNext قبل أي محاولة أخرى. ${error.toString().replaceFirst('Exception: ', '')}');
        }
      } finally {
        _inFlightPaymentActions.remove(actionKey);
      }
    }
}
