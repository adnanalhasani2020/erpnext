// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin BankReconciliationApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchReconciliationAccounts({
      required String company,
      required String partyType,
    }) async {
      final normalizedCompany = company.trim();
      if (normalizedCompany.isEmpty ||
          !{'Customer', 'Supplier'}.contains(partyType)) {
        throw const FormatException('حدد الشركة ونوع الطرف الصحيحين.');
      }
      final accountType = partyType == 'Customer' ? 'Receivable' : 'Payable';
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Account',
        fields: const ['name', 'account_type', 'account_currency', 'company'],
        filters: [
          ['company', '=', normalizedCompany],
          ['account_type', '=', accountType],
          ['is_group', '=', 0],
          ['disabled', '=', 0],
        ],
        orderBy: 'name asc',
        pageLength: 500,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل حسابات الذمم للشركة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة حسابات الذمم غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['company'] == normalizedCompany &&
              row['account_type'] == accountType)
          .map((row) => core.Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchBankAccounts({
      required String company,
    }) async {
      final normalizedCompany = company.trim();
      if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض الحسابات البنكية.');
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Bank Account',
        fields: const [
          'name', 'account', 'account_name', 'company', 'is_default',
          'is_company_account', 'disabled', 'account_type', 'bank',
        ],
        filters: [
          ['company', '=', normalizedCompany],
          ['is_company_account', '=', 1],
          ['disabled', '=', 0],
        ],
        orderBy: 'is_default desc, account_name asc',
        pageLength: 500,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل الحسابات البنكية للشركة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة الحسابات البنكية غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['company'] == normalizedCompany &&
              (row['is_company_account'] == 1 || row['is_company_account'] == true) &&
              (row['disabled'] != 1 && row['disabled'] != true) &&
              (row['name']?.toString().isNotEmpty ?? false) &&
              (row['account']?.toString().isNotEmpty ?? false))
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> createBankStatementImportPreview({
      required String bankAccount,
      required String company,
      required String fileName,
      required List<int> fileBytes,
    }) async {
      final account = bankAccount.trim();
      final cleanCompany = company.trim();
      final lowerName = fileName.trim().toLowerCase();
      final isMt940 = lowerName.endsWith('.txt') || lowerName.endsWith('.mt940') ||
          lowerName.endsWith('.940') || lowerName.endsWith('.sta');
      final supported = lowerName.endsWith('.csv') ||
          lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls') || isMt940;
      if (account.isEmpty || cleanCompany.isEmpty || fileBytes.isEmpty ||
          !supported || fileBytes.length > 15 * 1024 * 1024) {
        throw const FormatException('اختر ملف CSV أو Excel أو MT940 صالحاً، بحجم لا يتجاوز 15 ميجابايت.');
      }
      final accountResponse = await _send('GET',
        '/api/resource/Bank%20Account/' + Uri.encodeComponent(account));
      final accountData = _decode(accountResponse.body);
      if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300) {
        throw Exception(_message(accountData, 'تعذر التحقق من الحساب البنكي.'));
      }
      final bankAccountDoc = accountData['data'];
      if (bankAccountDoc is! core.Map<String, dynamic> ||
          bankAccountDoc['name'] != account || bankAccountDoc['company'] != cleanCompany ||
          (bankAccountDoc['bank']?.toString().trim().isNotEmpty ?? false) == false) {
        throw const FormatException('الحساب البنكي لا يتبع الشركة أو لا يرتبط ببنك مهيأ.');
      }
      final createdResponse = await _sendJson('POST', '/api/resource/Bank%20Statement%20Import', {
        'doctype': 'Bank Statement Import',
        'company': cleanCompany,
        'bank_account': account,
        'bank': bankAccountDoc['bank'],
        'reference_doctype': 'Bank Transaction',
        'import_type': 'Insert New Records',
        'submit_after_import': 1,
        'mute_emails': 1,
        'use_csv_sniffer': 1,
        'import_mt940_fromat': isMt940 ? 1 : 0,
      });
      final createdData = _decode(createdResponse.body);
      if (createdResponse.statusCode < 200 || createdResponse.statusCode >= 300) {
        throw Exception(_message(createdData, 'تعذر إنشاء مستند استيراد كشف البنك. تحقق من صلاحية Bank Statement Import.'));
      }
      final created = createdData['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Bank Statement Import' ||
          (created['name']?.toString().isEmpty ?? true) ||
          created['company'] != cleanCompany || created['bank_account'] != account) {
        throw const FormatException('لم يؤكد ERPNext إنشاء مستند استيراد كشف البنك.');
      }
      final importId = created['name'].toString();
      final boundary = '----ERPNextMobile' + DateTime.now().microsecondsSinceEpoch.toString();
      final request = await _client.postUrl(Uri.parse('$_baseUrl/api/method/upload_file'));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
      if (_cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader,
          _cookies.entries.map((entry) => entry.key + '=' + entry.value).join('; '));
        final csrf = _cookies['csrf_token'];
        if (csrf != null && csrf.isNotEmpty) request.headers.set('X-Frappe-CSRF-Token', csrf);
      }
      void field(String name, String value) {
        request.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n'));
      }
      field('is_private', '1');
      field('doctype', 'Bank Statement Import');
      field('docname', importId);
      field('fieldname', 'import_file');
      request.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="file"; filename="$fileName"\r\nContent-Type: application/octet-stream\r\n\r\n'));
      request.add(fileBytes);
      request.add(utf8.encode('\r\n--$boundary--\r\n'));
      final uploadResponse = await request.close().timeout(const Duration(seconds: 90));
      final uploadBody = await utf8.decoder.bind(uploadResponse).join().timeout(const Duration(seconds: 90));
      final uploadData = _decode(uploadBody);
      _captureCookies(uploadResponse);
      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        throw Exception(_message(uploadData, 'فشل رفع ملف كشف البنك إلى ERPNext.'));
      }
      final uploaded = uploadData['message'];
      final fileUrl = uploaded is core.Map<String, dynamic> ? uploaded['file_url']?.toString() : null;
      if (fileUrl == null || fileUrl.isEmpty) {
        throw const FormatException('رفع الملف لم يُرجع رابط ملف صالحاً.');
      }
      final attachResponse = await _sendJson('PUT',
        '/api/resource/Bank%20Statement%20Import/' + Uri.encodeComponent(importId),
        {'import_file': fileUrl});
      final attachData = _decode(attachResponse.body);
      if (attachResponse.statusCode < 200 || attachResponse.statusCode >= 300) {
        throw Exception(_message(attachData, 'تم رفع الملف لكن تعذر ربطه بمستند الاستيراد.'));
      }
      var effectiveFileUrl = fileUrl;
      if (isMt940) {
        final conversionResponse = await _sendJson('POST',
          '/api/method/erpnext.accounts.doctype.bank_statement_import.bank_statement_import.convert_mt940_to_csv',
          {'data_import': importId, 'mt940_file_path': fileUrl});
        final conversionData = _decode(conversionResponse.body);
        final converted = conversionData['message'];
        if (conversionResponse.statusCode < 200 || conversionResponse.statusCode >= 300 ||
            converted is! String || converted.isEmpty) {
          throw Exception(_message(conversionData, 'تعذر تحويل ملف MT940 إلى CSV داخل ERPNext.'));
        }
        effectiveFileUrl = converted;
      }
      final previewResponse = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.bank_statement_import.bank_statement_import.get_preview_from_template',
        {'data_import': importId, 'import_file': effectiveFileUrl});
      final previewData = _decode(previewResponse.body);
      if (previewResponse.statusCode < 200 || previewResponse.statusCode >= 300) {
        throw Exception(_message(previewData, 'رفع الملف ناجح، لكن ERPNext لم يتمكن من قراءة المعاينة. راجع إعداد مطابقة أعمدة البنك.'));
      }
      final preview = previewData['message'];
      if (preview is! core.Map<String, dynamic>) {
        throw const FormatException('لم يُرجع ERPNext معاينة صالحة لملف كشف البنك.');
      }
      final columns = preview['columns'];
      final columnNames = columns is List
          ? columns.map((column) => column is core.Map
              ? (column['content'] ?? column['header_title'] ?? column['fieldname'])?.toString().toLowerCase().trim() ?? ''
              : '').toList()
          : <String>[];
      // The selected Bank Account is already attached to the import document.
      // Do not reject a valid mapped statement merely because the preview omits
      // a redundant Bank Account column; ERPNext validates the actual import.
      return {
        'name': importId,
        'file_url': effectiveFileUrl,
        'preview': preview,
        'warnings': preview['warnings'] is List ? preview['warnings'] : const [],
        'columns': columnNames,
      };
    }

  Future<core.Map<String, dynamic>> fetchBankReconciliationBalances({
      required String bankAccount,
      required String company,
      required String date,
    }) async {
      final account = bankAccount.trim(), normalizedCompany = company.trim();
      final parsed = DateTime.tryParse(date.trim());
      if (account.isEmpty || normalizedCompany.isEmpty || parsed == null ||
          parsed.toIso8601String().substring(0, 10) != date.trim()) {
        throw const FormatException('حدد الحساب البنكي والشركة وتاريخ كشف صحيحاً.');
      }
      final accountResponse = await _send(
        'GET', '/api/resource/Bank%20Account/' + Uri.encodeComponent(account),
      );
      final accountData = _decode(accountResponse.body);
      if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300) {
        throw Exception(_message(accountData, 'تعذر التحقق من الحساب البنكي.'));
      }
      final bank = accountData['data'];
      if (bank is! core.Map<String, dynamic> || bank['name'] != account ||
          bank['company'] != normalizedCompany) {
        throw const FormatException('الحساب البنكي لا يتبع الشركة المحددة.');
      }
      final uri = Uri.parse('$_baseUrl/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.get_account_balance')
          .replace(queryParameters: {
        'bank_account': account,
        'company': normalizedCompany,
        'till_date': date.trim(),
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل رصيد الحساب البنكي من ERPNext.'));
      }
      final balance = double.tryParse(data['message']?.toString() ?? '');
      if (balance == null || !balance.isFinite) {
        throw const FormatException('لم يرجع ERPNext رصيداً بنكياً صالحاً.');
      }
      return {
        'bank_account': account,
        'company': normalizedCompany,
        'date': date.trim(),
        'system_balance': balance,
      };
    }

  Future<List<core.Map<String, dynamic>>> fetchBankTransactions({
      required String bankAccount,
      required String company,
      String? fromDate,
      String? toDate,
      int start = 0,
    }) async {
      final account = bankAccount.trim(), normalizedCompany = company.trim();
      if (account.isEmpty || normalizedCompany.isEmpty || start < 0) {
        throw const FormatException('حدد الشركة والحساب البنكي وبداية صفحة صحيحة.');
      }
      String? dateValue(String? raw, String label) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty) return null;
        final parsed = DateTime.tryParse(value);
        if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
          throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
        }
        return value;
      }
      final from = dateValue(fromDate, 'تاريخ البداية');
      final to = dateValue(toDate, 'تاريخ النهاية');
      if (from != null && to != null && from.compareTo(to) > 0) {
        throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
      }
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Bank Transaction',
        fields: const [
          'name', 'date', 'deposit', 'withdrawal', 'currency', 'description',
          'transaction_type', 'bank_account', 'company', 'allocated_amount',
          'unallocated_amount', 'reference_number', 'party_type', 'party',
          'status', 'docstatus',
        ],
        filters: [
          ['bank_account', '=', account],
          ['company', '=', normalizedCompany],
          ['docstatus', '=', 1],
          ['unallocated_amount', '>', 0],
          if (from != null) ['date', '>=', from],
          if (to != null) ['date', '<=', to],
        ],
        orderBy: 'date asc, name asc',
        start: start,
        pageLength: 100,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل حركات الحساب البنكي.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة حركات الحساب البنكي غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['bank_account'] == account &&
              row['company'] == normalizedCompany && row['docstatus'] == 1)
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchLinkedBankVouchers({
      required String transactionName,
      required String bankAccount,
      required String company,
      String? fromDate,
      String? toDate,
    }) async {
      final id = transactionName.trim(), account = bankAccount.trim();
      final normalizedCompany = company.trim();
      if (id.isEmpty || account.isEmpty || normalizedCompany.isEmpty) {
        throw const FormatException('بيانات حركة البنك والشركة غير مكتملة.');
      }
      String? normalizeDate(String? raw, String label) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty) return null;
        final parsed = DateTime.tryParse(value);
        if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
          throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
        }
        return value;
      }
      final from = normalizeDate(fromDate, 'تاريخ البداية');
      final to = normalizeDate(toDate, 'تاريخ النهاية');
      if (from != null && to != null && from.compareTo(to) > 0) {
        throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
      }
      final transactionResponse = await _send(
        'GET', '/api/resource/Bank%20Transaction/' + Uri.encodeComponent(id),
      );
      final transactionData = _decode(transactionResponse.body);
      if (transactionResponse.statusCode < 200 || transactionResponse.statusCode >= 300) {
        throw Exception(_message(transactionData, 'تعذر إعادة قراءة حركة البنك قبل المطابقة.'));
      }
      final transaction = transactionData['data'];
      if (transaction is! core.Map<String, dynamic> ||
          transaction['name'] != id || transaction['bank_account'] != account ||
          transaction['company'] != normalizedCompany || transaction['docstatus'] != 1) {
        throw const FormatException('حركة البنك لا تتبع الحساب أو الشركة المحددة أو أنها غير مرحّلة.');
      }
      final uri = Uri.parse('$_baseUrl/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.get_linked_payments')
          .replace(queryParameters: {
        'bank_transaction_name': id,
        'document_types': jsonEncode(['payment_entry', 'journal_entry', 'sales_invoice', 'purchase_invoice']),
        if (from != null) 'from_date': from,
        if (to != null) 'to_date': to,
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر جلب المستندات المرشحة لمطابقة حركة البنك.'));
      }
      final rows = data['message'];
      if (rows is! List) throw const FormatException('استجابة المستندات المرشحة غير متوقعة.');
      const allowed = {'Payment Entry', 'Journal Entry', 'Sales Invoice', 'Purchase Invoice'};
      return rows.whereType<core.Map<String, dynamic>>()
          .where((row) => allowed.contains(row['doctype']) &&
              (row['name']?.toString().trim().isNotEmpty ?? false))
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> reconcileBankTransaction({
      required String transactionName,
      required String bankAccount,
      required String company,
      required List<core.Map<String, dynamic>> vouchers,
      String? fromDate,
      String? toDate,
    }) async {
      final id = transactionName.trim(), account = bankAccount.trim();
      final normalizedCompany = company.trim();
      if (id.isEmpty || account.isEmpty || normalizedCompany.isEmpty || vouchers.isEmpty) {
        throw const FormatException('حدد حركة البنك ومستنداً واحداً على الأقل للمطابقة.');
      }
      final freshTransactionResponse = await _send(
        'GET', '/api/resource/Bank%20Transaction/' + Uri.encodeComponent(id),
      );
      final freshData = _decode(freshTransactionResponse.body);
      if (freshTransactionResponse.statusCode < 200 || freshTransactionResponse.statusCode >= 300) {
        throw Exception(_message(freshData, 'تعذر التحقق من حركة البنك قبل التسوية.'));
      }
      final transaction = freshData['data'];
      if (transaction is! core.Map<String, dynamic> ||
          transaction['name'] != id || transaction['bank_account'] != account ||
          transaction['company'] != normalizedCompany || transaction['docstatus'] != 1) {
        throw const FormatException('تم رفض التسوية لأن حركة البنك لا تتبع الشركة والحساب المحددين.');
      }
      final unallocated = double.tryParse(transaction['unallocated_amount']?.toString() ?? '') ?? 0;
      final freshCandidates = await fetchLinkedBankVouchers(
        transactionName: id,
        bankAccount: account,
        company: normalizedCompany,
        fromDate: fromDate,
        toDate: toDate,
      );
      final candidateByKey = <String, core.Map<String, dynamic>>{
        for (final row in freshCandidates)
          '${row['doctype']}|${row['name']}': row,
      };
      final selected = <core.Map<String, dynamic>>[];
      final seen = <String>{};
      var total = 0.0;
      const allowed = {
        'Payment Entry',
        'Journal Entry',
        'Sales Invoice',
        'Purchase Invoice',
      };
      for (final row in vouchers) {
        final doctype = row['payment_doctype']?.toString() ?? '';
        final name = row['payment_name']?.toString().trim() ?? '';
        final amount = double.tryParse(row['amount']?.toString() ?? '') ?? 0;
        final key = '$doctype|$name';
        final candidate = candidateByKey[key];
        final candidateAmount = double.tryParse(candidate?['paid_amount']?.toString() ?? '') ?? 0;
        if (!allowed.contains(doctype) || name.isEmpty || !seen.add(key) ||
            !amount.isFinite || amount <= 0 || candidate == null ||
            amount > candidateAmount + 0.000001) {
          throw const FormatException('توجد بيانات مستند أو مبلغ غير صالح أو لم يعد مرشحاً للمطابقة في ERPNext.');
        }
        total += amount;
        selected.add({'payment_doctype': doctype, 'payment_name': name, 'amount': amount});
      }
      if (total > unallocated + 0.000001) {
        throw const FormatException('إجمالي المطابقة يتجاوز المبلغ غير المخصص في حركة البنك.');
      }
      final response = await _sendJson(
        'POST',
        '/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.reconcile_vouchers',
        {'bank_transaction_name': id, 'vouchers': jsonEncode(selected)},
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'رفض ERPNext مطابقة حركة البنك.'));
      }
      final updated = data['message'];
      if (updated is! core.Map<String, dynamic> || updated['name'] != id ||
          updated['bank_account'] != account || updated['company'] != normalizedCompany) {
        throw const FormatException('لم يؤكد ERPNext تحديث حركة البنك الصحيحة.');
      }
      return core.Map<String, dynamic>.from(updated);
    }

  Future<core.Map<String, dynamic>> _runPaymentReconciliationMethod({
      required core.Map<String, dynamic> document,
      required String method,
      core.Map<String, dynamic>? args,
    }) async {
      if (document['doctype'] != 'Payment Reconciliation') {
        throw const FormatException('مستند تسوية المدفوعات غير صحيح.');
      }
      final response = await _sendJson(
        'POST',
        '/api/method/run_doc_method',
        {
          'docs': jsonEncode(document),
          'method': method,
          if (args != null) 'args': args,
        },
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تنفيذ خطوة تسوية المدفوعات ($method).'));
      }
      final docs = data['docs'];
      if (docs is! List || docs.isEmpty || docs.first is! core.Map<String, dynamic>) {
        throw Exception('لم يُرجع ERPNext مستند تسوية محدثاً بعد تنفيذ $method.');
      }
      final updated = core.Map<String, dynamic>.from(docs.first as core.Map);
      if (updated['doctype'] != 'Payment Reconciliation' ||
          updated['company'] != document['company'] ||
          updated['party_type'] != document['party_type'] ||
          updated['party'] != document['party'] ||
          updated['receivable_payable_account'] != document['receivable_payable_account']) {
        throw const FormatException('تغيرت هوية مستند التسوية في استجابة ERPNext.');
      }
      return updated;
    }

  Future<core.Map<String, dynamic>> fetchUnreconciledPaymentEntries({
      required String company,
      required String partyType,
      required String party,
      required String receivablePayableAccount,
      String? fromInvoiceDate,
      String? toInvoiceDate,
      String? fromPaymentDate,
      String? toPaymentDate,
      int invoiceLimit = 50,
      int paymentLimit = 50,
      String? bankCashAccount,
      String? defaultAdvanceAccount,
      String? costCenter,
      String? project,
      String? invoiceName,
      String? paymentName,
      double? minimumInvoiceAmount,
      double? maximumInvoiceAmount,
      double? minimumPaymentAmount,
      double? maximumPaymentAmount,
    }) async {
      final cleanCompany = company.trim();
      final cleanParty = party.trim();
      final cleanAccount = receivablePayableAccount.trim();
      double? validateAmount(double? value, String label) {
        if (value == null) return null;
        if (!value.isFinite || value < 0) {
          throw FormatException('$label يجب أن يكون رقماً موجباً أو صفراً.');
        }
        return value;
      }
      final minInvoice = validateAmount(minimumInvoiceAmount, 'الحد الأدنى للفاتورة');
      final maxInvoice = validateAmount(maximumInvoiceAmount, 'الحد الأعلى للفاتورة');
      final minPayment = validateAmount(minimumPaymentAmount, 'الحد الأدنى للدفعة');
      final maxPayment = validateAmount(maximumPaymentAmount, 'الحد الأعلى للدفعة');
      if ((minInvoice != null && maxInvoice != null && minInvoice > maxInvoice) ||
          (minPayment != null && maxPayment != null && minPayment > maxPayment)) {
        throw const FormatException('الحد الأدنى للمبلغ يجب ألا يتجاوز الحد الأعلى.');
      }
      if (cleanCompany.isEmpty || cleanParty.isEmpty || cleanAccount.isEmpty ||
          !{'Customer', 'Supplier'}.contains(partyType) ||
          invoiceLimit < 0 || invoiceLimit > 500 ||
          paymentLimit < 0 || paymentLimit > 500) {
        throw const FormatException('أكمل الشركة والطرف وحساب الذمم، وحدد حدود تحميل بين 0 و500.');
      }
      String? validateDate(String? raw, String label) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty) return null;
        final parsed = DateTime.tryParse(value);
        if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
          throw FormatException('$label غير صحيح.');
        }
        return value;
      }
      final invoiceFrom = validateDate(fromInvoiceDate, 'بداية تاريخ الفواتير');
      final invoiceTo = validateDate(toInvoiceDate, 'نهاية تاريخ الفواتير');
      final paymentFrom = validateDate(fromPaymentDate, 'بداية تاريخ المدفوعات');
      final paymentTo = validateDate(toPaymentDate, 'نهاية تاريخ المدفوعات');
      if ((invoiceFrom != null && invoiceTo != null && invoiceFrom.compareTo(invoiceTo) > 0) ||
          (paymentFrom != null && paymentTo != null && paymentFrom.compareTo(paymentTo) > 0)) {
        throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
      }
      final document = <String, dynamic>{
        'doctype': 'Payment Reconciliation',
        'company': cleanCompany,
        'party_type': partyType,
        'party': cleanParty,
        'receivable_payable_account': cleanAccount,
        'invoice_limit': invoiceLimit,
        'payment_limit': paymentLimit,
        if (invoiceFrom != null) 'from_invoice_date': invoiceFrom,
        if (invoiceTo != null) 'to_invoice_date': invoiceTo,
        if (paymentFrom != null) 'from_payment_date': paymentFrom,
        if (paymentTo != null) 'to_payment_date': paymentTo,
        if (bankCashAccount?.trim().isNotEmpty == true) 'bank_cash_account': bankCashAccount!.trim(),
        if (defaultAdvanceAccount?.trim().isNotEmpty == true) 'default_advance_account': defaultAdvanceAccount!.trim(),
        if (costCenter?.trim().isNotEmpty == true) 'cost_center': costCenter!.trim(),
        if (project?.trim().isNotEmpty == true) 'project': project!.trim(),
        if (invoiceName?.trim().isNotEmpty == true) 'invoice_name': invoiceName!.trim(),
        if (paymentName?.trim().isNotEmpty == true) 'payment_name': paymentName!.trim(),
        if (minInvoice != null) 'minimum_invoice_amount': minInvoice,
        if (maxInvoice != null) 'maximum_invoice_amount': maxInvoice,
        if (minPayment != null) 'minimum_payment_amount': minPayment,
        if (maxPayment != null) 'maximum_payment_amount': maxPayment,
        'invoices': <core.Map<String, dynamic>>[],
        'payments': <core.Map<String, dynamic>>[],
        'allocation': <core.Map<String, dynamic>>[],
      };
      final result = await _runPaymentReconciliationMethod(
        document: document,
        method: 'get_unreconciled_entries',
      );
      if (result['invoices'] is! List || result['payments'] is! List) {
        throw const FormatException('لم يُرجع ERPNext قوائم الفواتير والمدفوعات غير المسواة.');
      }
      return result;
    }

  Future<core.Map<String, dynamic>> allocatePaymentReconciliation(
      core.Map<String, dynamic> document,
    ) async {
      final invoices = document['invoices'];
      final payments = document['payments'];
      if (document['doctype'] != 'Payment Reconciliation' ||
          invoices is! List || invoices.isEmpty ||
          payments is! List || payments.isEmpty) {
        throw const FormatException('يجب تحميل فواتير ومدفوعات غير مسواة قبل إنشاء التوزيع.');
      }
      final result = await _runPaymentReconciliationMethod(
        document: document,
        method: 'allocate_entries',
        args: {
          'invoices': invoices,
          'payments': payments,
        },
      );
      final allocation = result['allocation'];
      if (allocation is! List || allocation.isEmpty) {
        throw const FormatException('لم ينتج ERPNext أي تخصيص قابل للتسوية.');
      }
      return result;
    }

  Future<core.Map<String, dynamic>> reconcilePaymentAllocations(
      core.Map<String, dynamic> document,
    ) async {
      final allocation = document['allocation'];
      if (document['doctype'] != 'Payment Reconciliation' ||
          allocation is! List || allocation.isEmpty) {
        throw const FormatException('لا توجد تخصيصات مؤكدة لترحيل التسوية.');
      }
      return _runPaymentReconciliationMethod(
        document: document,
        method: 'reconcile',
      );
    }

  Future<core.Map<String, dynamic>> startBankStatementImport(String importName) async {
      final id = importName.trim();
      if (id.isEmpty) throw const FormatException('رقم مستند الاستيراد غير موجود.');
      final response = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.bank_statement_import.bank_statement_import.form_start_import',
        {'data_import': id});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'رفض ERPNext بدء استيراد كشف البنك.'));
      }
      final job = data['message'];
      if (job != null && (job is! String || job.isEmpty)) {
        throw const FormatException('أعاد ERPNext معرف مهمة استيراد غير صالح.');
      }
      return {'name': id, 'job_id': job, 'status': 'Queued'};
    }

  Future<core.Map<String, dynamic>> fetchBankStatementImportStatus(String importName) async {
      final id = importName.trim();
      if (id.isEmpty) throw const FormatException('رقم مستند الاستيراد غير موجود.');
      final response = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.bank_statement_import.bank_statement_import.get_import_status',
        {'docname': id});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر قراءة حالة استيراد كشف البنك.'));
      final status = data['message'];
      if (status is! core.Map<String, dynamic>) throw const FormatException('استجابة حالة الاستيراد غير صحيحة.');
      return core.Map<String, dynamic>.from(status);
    }

  Future<core.Map<String, dynamic>> saveBankStatementClosingBalance({
      required String bankAccount, required String company,
      required String statementDate, required double closingBalance,
      String? importName,
    }) async {
      final account = bankAccount.trim(), cleanCompany = company.trim();
      final date = _validateLedgerDate(statementDate, 'تاريخ رصيد كشف البنك');
      if (account.isEmpty || cleanCompany.isEmpty || date == null ||
          !closingBalance.isFinite || (importName?.trim().isEmpty ?? false)) {
        throw const FormatException('بيانات رصيد كشف البنك الختامي غير مكتملة أو غير صحيحة.');
      }
      final accountResponse = await _send('GET',
        '/api/resource/Bank%20Account/' + Uri.encodeComponent(account));
      final accountData = _decode(accountResponse.body);
      final bank = accountData['data'];
      if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
          bank is! core.Map<String, dynamic> || bank['company'] != cleanCompany || bank['name'] != account) {
        throw const FormatException('الحساب البنكي لا يطابق الشركة؛ لم يُحفظ الرصيد.');
      }
      final content = jsonEncode({
        'kind': 'bank_statement_closing_balance_v1', 'bank_account': account,
        'company': cleanCompany, 'statement_date': date,
        'closing_balance': closingBalance,
        'currency': bank['account_currency'] ?? bank['currency'],
        'bank_statement_import': importName?.trim(),
      });
      final response = await _sendJson('POST', '/api/resource/Comment', {
        'doctype': 'Comment', 'comment_type': 'Info',
        'reference_doctype': 'Bank Account', 'reference_name': account, 'content': content,
      });
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ رصيد الكشف كسجل دائم في سجل الحساب البنكي.'));
      final saved = data['data'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Comment' ||
          saved['reference_doctype'] != 'Bank Account' || saved['reference_name'] != account) {
        throw const FormatException('لم يؤكد ERPNext حفظ سجل رصيد كشف البنك.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<core.Map<String, dynamic>?> fetchLatestBankStatementClosingBalance({
      required String bankAccount, required String company,
    }) async {
      final account = bankAccount.trim(), cleanCompany = company.trim();
      if (account.isEmpty || cleanCompany.isEmpty) throw const FormatException('حدد الحساب البنكي والشركة.');
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Comment',
        fields: const ['name', 'content', 'creation', 'reference_doctype', 'reference_name'],
        filters: [
          ['reference_doctype', '=', 'Bank Account'],
          ['reference_name', '=', account], ['comment_type', '=', 'Info'],
        ],
        orderBy: 'creation desc', pageLength: 100,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل أرصدة كشف البنك المحفوظة.'));
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة أرصدة كشف البنك غير صحيحة.');
      for (final raw in rows) {
        if (raw is! core.Map<String, dynamic>) continue;
        try {
          final decoded = jsonDecode(raw['content']?.toString() ?? '');
          if (decoded is core.Map<String, dynamic> &&
              decoded['kind'] == 'bank_statement_closing_balance_v1' &&
              decoded['bank_account'] == account && decoded['company'] == cleanCompany) {
            return {...decoded, 'comment_name': raw['name'], 'creation': raw['creation']};
          }
        } catch (_) {}
      }
      return null;
    }
}
