// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin BankReconciliationApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchReconciliationAccounts({
      required String company,
      required String partyType,
    }) async {
      final normalizedCompany = company.trim();
      if (normalizedCompany.isEmpty ||
          !{'Customer', 'Supplier', 'Employee'}.contains(partyType)) {
        throw const FormatException('حدد الشركة ونوع الطرف الصحيحين.');
      }
      final accountFilters = <List<dynamic>>[
        ['company', '=', normalizedCompany],
        ['is_group', '=', 0],
        ['disabled', '=', 0],
        if (partyType == 'Employee') ...[
          ['account_type', 'in', ['Receivable', 'Payable']],
          ['root_type', 'in', ['Asset', 'Liability']],
        ] else ...[
          ['account_type', '=', partyType == 'Customer' ? 'Receivable' : 'Payable'],
          ['root_type', '=', partyType == 'Customer' ? 'Asset' : 'Liability'],
        ],
      ];
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Account',
        fields: const ['name', 'account_type', 'root_type', 'account_currency', 'company'],
        filters: accountFilters,
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
          .where((row) {
            if (row['company'] != normalizedCompany) return false;
            if (partyType == 'Employee') {
              return {'Receivable', 'Payable'}.contains(row['account_type']) &&
                  {'Asset', 'Liability'}.contains(row['root_type']);
            }
            return row['account_type'] ==
                    (partyType == 'Customer' ? 'Receivable' : 'Payable') &&
                row['root_type'] == (partyType == 'Customer' ? 'Asset' : 'Liability');
          })
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
          !{'Customer', 'Supplier', 'Employee'}.contains(partyType) ||
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
      core.Map<String, dynamic> document, {
      List<String>? selectedInvoiceNumbers,
      List<String>? selectedPaymentReferences,
    }) async {
      final allInvoices = document['invoices'];
      final allPayments = document['payments'];
      if (document['doctype'] != 'Payment Reconciliation' ||
          allInvoices is! List || allInvoices.isEmpty ||
          allPayments is! List || allPayments.isEmpty) {
        throw const FormatException('يجب تحميل فواتير ومدفوعات غير مسواة قبل إنشاء التوزيع.');
      }
      final invoices = selectedInvoiceNumbers == null
          ? allInvoices
          : allInvoices.whereType<core.Map<String, dynamic>>()
              .where((row) => selectedInvoiceNumbers.contains(row['invoice_number']?.toString()))
              .toList(growable: false);
      final payments = selectedPaymentReferences == null
          ? allPayments
          : allPayments.whereType<core.Map<String, dynamic>>()
              .where((row) => selectedPaymentReferences.contains(row['reference_name']?.toString()))
              .toList(growable: false);
      if (invoices.isEmpty || payments.isEmpty) {
        throw const FormatException('اختر فاتورة واحدة ودفعة واحدة على الأقل لإجراء التخصيص.');
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

  Future<double> calculatePaymentReconciliationDifference({
      required core.Map<String, dynamic> document,
      required core.Map<String, dynamic> allocation,
      required double allocatedAmount,
    }) async {
      if (document['doctype'] != 'Payment Reconciliation' ||
          !allocatedAmount.isFinite || allocatedAmount <= 0) {
        throw const FormatException('بيانات حساب فرق التسوية غير صحيحة.');
      }
      final invoices = document['invoices'];
      final payments = document['payments'];
      if (invoices is! List || payments is! List) {
        throw const FormatException('قوائم الفواتير والمدفوعات غير متاحة لحساب فرق التسوية.');
      }
      final invoiceNumber = allocation['invoice_number']?.toString() ?? '';
      final paymentName = allocation['reference_name']?.toString() ?? '';
      final invoiceRows = invoices.whereType<core.Map<String, dynamic>>()
          .where((row) => row['invoice_number']?.toString() == invoiceNumber).toList();
      final paymentRows = payments.whereType<core.Map<String, dynamic>>()
          .where((row) => row['reference_name']?.toString() == paymentName).toList();
      if (invoiceRows.length != 1 || paymentRows.length != 1) {
        throw const FormatException('تعذر مطابقة الفاتورة والدفعة لهذا التخصيص بصورة فريدة.');
      }
      final response = await _sendJson(
        'POST',
        '/api/method/run_doc_method',
        {
          'docs': jsonEncode(document),
          'method': 'calculate_difference_on_allocation_change',
          'args': {
            'payment_entry': paymentRows,
            'invoice': invoiceRows,
            'allocated_amount': allocatedAmount,
          },
        },
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حساب فرق العملة للتخصيص من ERPNext.'));
      }
      final rawDifference = data['message'];
      final difference = rawDifference is num
          ? rawDifference.toDouble()
          : double.tryParse(rawDifference?.toString() ?? '');
      if (difference == null || !difference.isFinite) {
        throw const FormatException('أعاد ERPNext قيمة غير صالحة لفرق التسوية.');
      }
      return difference;
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

  Future<List<core.Map<String, dynamic>>> fetchProcessPaymentReconciliationJobs({
      int start = 0, String? search, String? company,
    }) async {
      if (start < 0) throw const FormatException('موضع تحميل المهام غير صحيح.');
      final query = search?.trim() ?? '';
      final cleanCompany = company?.trim() ?? '';
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Process Payment Reconciliation',
        fields: const [
          'name', 'company', 'party_type', 'party', 'receivable_payable_account',
          'status', 'docstatus', 'creation', 'modified', 'error_log',
        ],
        filters: cleanCompany.isEmpty ? null : [['company', '=', cleanCompany]],
        orFilters: query.isEmpty ? null : [
          ['name', 'like', '%$query%'],
          ['party', 'like', '%$query%'],
        ],
        orderBy: 'creation desc, name desc',
        start: start,
        pageLength: 50,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل مهام التسوية الآلية. تحقق من صلاحية Process Payment Reconciliation.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة مهام التسوية الآلية غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchProcessPaymentReconciliationJob(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم مهمة التسوية غير موجود.');
      final response = await _send('GET',
        '/api/resource/Process%20Payment%20Reconciliation/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل مهمة التسوية.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> ||
          document['doctype'] != 'Process Payment Reconciliation' || document['name'] != id) {
        throw const FormatException('لم يؤكد ERPNext هوية مهمة التسوية المطلوبة.');
      }
      return core.Map<String, dynamic>.from(document);
    }

  Future<core.Map<String, dynamic>> _validateProcessReconciliationAccount(
      String accountName, String company, {
      Set<String> allowedTypes = const {},
      Set<String> allowedRootTypes = const {},
    }) async {
      final id = accountName.trim();
      if (id.isEmpty) throw const FormatException('أحد الحسابات المطلوبة غير محدد.');
      final response = await _send('GET',
        '/api/resource/Account/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر التحقق من الحساب $id.'));
      }
      final account = data['data'];
      if (account is! core.Map<String, dynamic> || account['name'] != id ||
          account['company'] != company ||
          account['is_group'] == 1 || account['is_group'] == true ||
          account['disabled'] == 1 || account['disabled'] == true ||
          (allowedTypes.isNotEmpty && !allowedTypes.contains(account['account_type']?.toString())) ||
          (allowedRootTypes.isNotEmpty && !allowedRootTypes.contains(account['root_type']?.toString()))) {
        throw FormatException('الحساب $id غير صالح للشركة أو نوع الحساب المطلوب.');
      }
      return core.Map<String, dynamic>.from(account);
    }

  Future<core.Map<String, dynamic>> saveProcessPaymentReconciliationDraft({
      String? name,
      required String company,
      required String partyType,
      required String party,
      required String receivablePayableAccount,
      String? defaultAdvanceAccount,
      String? fromInvoiceDate,
      String? toInvoiceDate,
      String? fromPaymentDate,
      String? toPaymentDate,
      String? costCenter,
      String? bankCashAccount,
    }) async {
      final cleanCompany = company.trim();
      final cleanParty = party.trim();
      final cleanAccount = receivablePayableAccount.trim();
      if (cleanCompany.isEmpty || cleanParty.isEmpty || cleanAccount.isEmpty ||
          !{'Customer', 'Supplier', 'Employee'}.contains(partyType)) {
        throw const FormatException('حدد الشركة والطرف ونوعه وحساب الذمم.');
      }
      String? date(String? raw, String label) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty) return null;
        final parsed = DateTime.tryParse(value);
        if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
          throw FormatException('$label غير صحيح؛ استخدم YYYY-MM-DD.');
        }
        return value;
      }
      final invoiceFrom = date(fromInvoiceDate, 'بداية تاريخ الفواتير');
      final invoiceTo = date(toInvoiceDate, 'نهاية تاريخ الفواتير');
      final paymentFrom = date(fromPaymentDate, 'بداية تاريخ المدفوعات');
      final paymentTo = date(toPaymentDate, 'نهاية تاريخ المدفوعات');
      if ((invoiceFrom != null && invoiceTo != null && invoiceFrom.compareTo(invoiceTo) > 0) ||
          (paymentFrom != null && paymentTo != null && paymentFrom.compareTo(paymentTo) > 0)) {
        throw const FormatException('تاريخ بداية الفلتر يجب ألا يتجاوز تاريخ نهايته.');
      }
      final partyAccount = await _validateProcessReconciliationAccount(
        cleanAccount, cleanCompany,
        allowedTypes: partyType == 'Customer'
            ? const {'Receivable'}
            : partyType == 'Supplier' ? const {'Payable'} : const {'Receivable', 'Payable'},
      );
      if (partyType == 'Customer' && partyAccount['root_type'] != 'Asset' ||
          partyType == 'Supplier' && partyAccount['root_type'] != 'Liability' ||
          partyType == 'Employee' && !{'Asset', 'Liability'}.contains(partyAccount['root_type'])) {
        throw const FormatException('نوع الحساب الرئيسي لا يتوافق مع نوع الطرف.');
      }
      final partyResponse = await _send(
        'GET', '/api/resource/' + Uri.encodeComponent(partyType) + '/' + Uri.encodeComponent(cleanParty),
      );
      final partyData = _decode(partyResponse.body);
      final partyDocument = partyData['data'];
      if (partyResponse.statusCode < 200 || partyResponse.statusCode >= 300 ||
          partyDocument is! core.Map<String, dynamic> || partyDocument['name'] != cleanParty) {
        throw FormatException('تعذر التحقق من وجود $partyType $cleanParty في ERPNext.');
      }
      final advance = defaultAdvanceAccount?.trim() ?? '';
      if (advance.isNotEmpty) {
        await _validateProcessReconciliationAccount(
          advance, cleanCompany,
          allowedTypes: partyType == 'Customer'
              ? const {'Receivable'}
              : const {'Payable'},
          allowedRootTypes: partyType == 'Customer'
              ? const {'Liability'}
              : const {'Asset'},
        );
      }
      final bankCash = bankCashAccount?.trim() ?? '';
      if (bankCash.isNotEmpty) {
        await _validateProcessReconciliationAccount(
          bankCash, cleanCompany,
          allowedTypes: const {'Bank', 'Cash'},
          allowedRootTypes: const {'Asset'},
        );
      }
      final cost = costCenter?.trim() ?? '';
      if (cost.isNotEmpty) {
        final response = await _send('GET',
          '/api/resource/Cost%20Center/' + Uri.encodeComponent(cost));
        final data = _decode(response.body);
        final row = data['data'];
        if (response.statusCode < 200 || response.statusCode >= 300 ||
            row is! core.Map<String, dynamic> || row['company'] != cleanCompany ||
            row['is_group'] == 1 || row['is_group'] == true ||
            row['disabled'] == 1 || row['disabled'] == true) {
          throw const FormatException('مركز التكلفة غير تابع للشركة أو غير صالح للاستخدام.');
        }
      }
      final payload = <String, dynamic>{
        'doctype': 'Process Payment Reconciliation',
        'company': cleanCompany,
        'party_type': partyType,
        'party': cleanParty,
        'receivable_payable_account': cleanAccount,
        'default_advance_account': advance.isEmpty ? null : advance,
        'bank_cash_account': bankCash.isEmpty ? null : bankCash,
        'cost_center': cost.isEmpty ? null : cost,
        'from_invoice_date': invoiceFrom,
        'to_invoice_date': invoiceTo,
        'from_payment_date': paymentFrom,
        'to_payment_date': paymentTo,
      };
      final id = name?.trim() ?? '';
      final response = id.isEmpty
          ? await _sendJson('POST', '/api/resource/Process%20Payment%20Reconciliation', payload)
          : await _sendJson('PUT', '/api/resource/Process%20Payment%20Reconciliation/' + Uri.encodeComponent(id), payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ مهمة التسوية الآلية.'));
      }
      final saved = data['data'];
      if (saved is! core.Map<String, dynamic> ||
          saved['doctype'] != 'Process Payment Reconciliation' ||
          (saved['name']?.toString().isEmpty ?? true) ||
          saved['company'] != cleanCompany || saved['party'] != cleanParty ||
          saved['party_type'] != partyType || saved['receivable_payable_account'] != cleanAccount ||
          saved['docstatus'] != 0) {
        throw const FormatException('لم يؤكد ERPNext حفظ مسودة مهمة التسوية.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<core.Map<String, dynamic>> submitProcessPaymentReconciliation(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم مهمة التسوية غير موجود.');
      final current = await fetchProcessPaymentReconciliationJob(id);
      if (current['docstatus'] != 0) throw const FormatException('يمكن ترحيل مسودة مهمة التسوية فقط.');
      final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر ترحيل مهمة التسوية.'));
      }
      final submitted = data['message'];
      if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != 'Process Payment Reconciliation' ||
          submitted['name'] != id || submitted['docstatus'] != 1 || submitted['status'] != 'Queued') {
        throw Exception('لم يؤكد ERPNext ترحيل مهمة التسوية ووضعها في قائمة الانتظار.');
      }
      return core.Map<String, dynamic>.from(submitted);
    }

  Future<core.Map<String, dynamic>> cancelProcessPaymentReconciliation(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم مهمة التسوية غير موجود.');
      final current = await fetchProcessPaymentReconciliationJob(id);
      if (current['docstatus'] != 1 || current['status'] == 'Running') {
        throw const FormatException('لا يمكن إلغاء المهمة إلا بعد ترحيلها وعندما لا تكون قيد التنفيذ.');
      }
      final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إلغاء مهمة التسوية.'));
      }
      final cancelled = data['message'];
      if (cancelled is! core.Map<String, dynamic> || cancelled['doctype'] != 'Process Payment Reconciliation' ||
          cancelled['name'] != id || cancelled['docstatus'] != 2 || cancelled['status'] != 'Cancelled') {
        throw Exception('لم يؤكد ERPNext إلغاء مهمة التسوية.');
      }
      return core.Map<String, dynamic>.from(cancelled);
    }

  Future<core.Map<String, dynamic>> startProcessPaymentReconciliation(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم مهمة التسوية غير موجود.');
      final current = await fetchProcessPaymentReconciliationJob(id);
      if (current['docstatus'] != 1 || !{'Queued', 'Paused'}.contains(current['status'])) {
        throw const FormatException('بدء أو استئناف المهمة متاح فقط للمهام المرحلة المنتظرة أو المتوقفة.');
      }
      final response = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.process_payment_reconciliation.process_payment_reconciliation.trigger_job_for_doc',
        {'docname': id});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر بدء مهمة التسوية أو استئنافها. تحقق من إعدادات التسوية والجدولة.'));
      }
      final refreshed = await fetchProcessPaymentReconciliationJob(id);
      if (!{'Running', 'Queued'}.contains(refreshed['status'])) {
        throw Exception('لم يؤكد ERPNext بدء المهمة؛ الحالة الحالية: ${refreshed['status'] ?? 'غير معروفة'}.');
      }
      return refreshed;
    }

  Future<core.Map<String, dynamic>> pauseProcessPaymentReconciliation(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم مهمة التسوية غير موجود.');
      final current = await fetchProcessPaymentReconciliationJob(id);
      if (current['docstatus'] != 1 || current['status'] != 'Running') {
        throw const FormatException('إيقاف المهمة متاح فقط عندما تكون قيد التنفيذ.');
      }
      final response = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.process_payment_reconciliation.process_payment_reconciliation.pause_job_for_doc',
        {'docname': id});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إيقاف مهمة التسوية.'));
      }
      final refreshed = await fetchProcessPaymentReconciliationJob(id);
      if (refreshed['status'] != 'Paused') throw Exception('لم يؤكد ERPNext إيقاف المهمة.');
      return refreshed;
    }

  Future<core.Map<String, dynamic>> fetchProcessPaymentReconciliationProgress(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم مهمة التسوية غير موجود.');
      final response = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.process_payment_reconciliation.process_payment_reconciliation.get_reconciled_count',
        {'docname': id});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تقدم مهمة التسوية.'));
      }
      final result = data['message'];
      if (result is! core.Map<String, dynamic>) throw const FormatException('بيانات تقدم مهمة التسوية غير صحيحة.');
      final processed = int.tryParse(result['processed']?.toString() ?? '0');
      final total = int.tryParse(result['total']?.toString() ?? '0');
      if (processed == null || total == null || processed < 0 || total < 0 || processed > total && total > 0) {
        throw const FormatException('أعاد ERPNext أرقام تقدم غير صالحة.');
      }
      return {'processed': processed, 'total': total};
    }

  Future<core.Map<String, dynamic>?> fetchProcessPaymentReconciliationLog(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم مهمة التسوية غير موجود.');
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Process Payment Reconciliation Log',
        fields: const ['name', 'process_pr', 'status', 'allocated', 'reconciled',
          'total_allocations', 'reconciled_entries', 'creation', 'modified'],
        filters: [['process_pr', '=', id]],
        orderBy: 'creation desc, name desc', pageLength: 1,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل سجل تنفيذ مهمة التسوية.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة سجل تنفيذ التسوية غير صحيحة.');
      if (rows.isEmpty) return null;
      final logName = rows.first is core.Map ? rows.first['name']?.toString() ?? '' : '';
      if (logName.isEmpty) throw const FormatException('اسم سجل التنفيذ غير موجود.');
      final detailResponse = await _send('GET',
        '/api/resource/Process%20Payment%20Reconciliation%20Log/' + Uri.encodeComponent(logName));
      final detailData = _decode(detailResponse.body);
      if (detailResponse.statusCode < 200 || detailResponse.statusCode >= 300) {
        throw Exception(_message(detailData, 'تعذر تحميل تفاصيل سجل التنفيذ.'));
      }
      final detail = detailData['data'];
      if (detail is! core.Map<String, dynamic> || detail['name'] != logName ||
          detail['process_pr'] != id || detail['doctype'] != 'Process Payment Reconciliation Log') {
        throw const FormatException('سجل التنفيذ لا يطابق مهمة التسوية المطلوبة.');
      }
      return core.Map<String, dynamic>.from(detail);
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
