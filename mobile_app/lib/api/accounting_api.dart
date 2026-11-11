// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin AccountingApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchSupplierLedger({
      required String supplier, int start = 0, String? company,
      String? fromDate, String? toDate, String? account, String? voucherType,
    }) => _fetchPartyLedger(
      partyType: 'Supplier', party: supplier, start: start, company: company,
      fromDate: fromDate, toDate: toDate, account: account, voucherType: voucherType,
    );

  Future<List<core.Map<String, dynamic>>> fetchCustomerLedger({
      required String customer, int start = 0, String? company,
      String? fromDate, String? toDate, String? account, String? voucherType,
    }) => _fetchPartyLedger(
      partyType: 'Customer', party: customer, start: start, company: company,
      fromDate: fromDate, toDate: toDate, account: account, voucherType: voucherType,
    );

  String? _validateLedgerDate(String? raw, String label) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
        throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
      }
      return value;
    }

  Future<List<core.Map<String, dynamic>>> _fetchPartyLedger({
      required String partyType, required String party, int start = 0,
      String? company, String? fromDate, String? toDate,
      String? account, String? voucherType,
    }) async {
      final cleanParty = party.trim();
      final cleanCompany = company?.trim() ?? '';
      final cleanAccount = account?.trim() ?? '';
      final cleanVoucherType = voucherType?.trim() ?? '';
      final from = _validateLedgerDate(fromDate, 'تاريخ البداية');
      final to = _validateLedgerDate(toDate, 'تاريخ النهاية');
      if (cleanParty.isEmpty || start < 0 ||
          !{'Customer', 'Supplier'}.contains(partyType) ||
          (from != null && to != null && from.compareTo(to) > 0)) {
        throw const FormatException('حدد الطرف ونطاق تاريخ صحيحاً.');
      }
      final filters = <List<dynamic>>[
        ['party_type', '=', partyType], ['party', '=', cleanParty],
        ['is_cancelled', '=', 0],
        if (cleanCompany.isNotEmpty) ['company', '=', cleanCompany],
        if (from != null) ['posting_date', '>=', from],
        if (to != null) ['posting_date', '<=', to],
        if (cleanAccount.isNotEmpty) ['account', '=', cleanAccount],
        if (cleanVoucherType.isNotEmpty) ['voucher_type', '=', cleanVoucherType],
      ];
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'GL Entry',
        fields: const [
          'name', 'posting_date', 'account', 'against', 'debit', 'credit',
          'voucher_type', 'voucher_no', 'remarks', 'company', 'party',
          'account_currency',
        ],
        filters: filters, orderBy: 'posting_date asc, creation asc, name asc',
        start: start, pageLength: 100,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل كشف حساب الطرف من GL Entry.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة كشف الحساب غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchPartyLedgerOpeningBalance({
      required String partyType, required String party, required String beforeDate,
      String? company, String? account, String? voucherType,
    }) async {
      final cleanParty = party.trim();
      final before = _validateLedgerDate(beforeDate, 'تاريخ بداية الكشف');
      if (cleanParty.isEmpty || before == null ||
          !{'Customer', 'Supplier'}.contains(partyType)) {
        throw const FormatException('بيانات رصيد افتتاح كشف الحساب غير صحيحة.');
      }
      final filters = <List<dynamic>>[
        ['party_type', '=', partyType], ['party', '=', cleanParty],
        ['is_cancelled', '=', 0], ['posting_date', '<', before],
        if (company?.trim().isNotEmpty == true) ['company', '=', company!.trim()],
        if (account?.trim().isNotEmpty == true) ['account', '=', account!.trim()],
        if (voucherType?.trim().isNotEmpty == true) ['voucher_type', '=', voucherType!.trim()],
      ];
      final uri = Uri.parse('$_baseUrl/api/method/frappe.client.get_list').replace(
        queryParameters: {
          'doctype': 'GL Entry',
          'fields': jsonEncode(['sum(debit) as debit', 'sum(credit) as credit']),
          'filters': jsonEncode(filters),
          'limit_page_length': '1',
        },
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حساب الرصيد الافتتاحي من دفتر الأستاذ.'));
      }
      final rows = data['message'];
      if (rows is! List || rows.isEmpty || rows.first is! core.Map<String, dynamic>) {
        return {'debit': 0.0, 'credit': 0.0, 'balance': 0.0};
      }
      final row = rows.first as core.Map<String, dynamic>;
      final debit = double.tryParse(row['debit']?.toString() ?? '') ?? 0.0;
      final credit = double.tryParse(row['credit']?.toString() ?? '') ?? 0.0;
      if (!debit.isFinite || !credit.isFinite) {
        throw const FormatException('أعاد ERPNext إجماليات غير صالحة للرصيد الافتتاحي.');
      }
      return {'debit': debit, 'credit': credit, 'balance': debit - credit};
    }

  Future<List<core.Map<String, dynamic>>> fetchAccountingAccounts({
      required String company,
      int start = 0,
      String? search,
      String? rootType,
      bool includeDisabled = false,
    }) async {
      final normalizedCompany = company.trim();
      if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض دليل الحسابات.');
      final query = search?.trim();
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Account',
        fields: const ['name', 'account_name', 'parent_account', 'account_type',
          'root_type', 'account_currency', 'company', 'is_group', 'disabled'],
        filters: [
          ['company', '=', normalizedCompany],
          if (rootType != null && rootType.trim().isNotEmpty) ['root_type', '=', rootType.trim()],
          if (!includeDisabled) ['disabled', '=', 0],
        ],
        orFilters: query == null || query.isEmpty ? null : [
          ['name', 'like', '%$query%'],
          ['account_name', 'like', '%$query%'],
          ['account_type', 'like', '%$query%'],
        ],
        orderBy: 'lft asc, name asc',
        start: start,
        pageLength: 200,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل دليل الحسابات للشركة المحددة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة دليل الحسابات غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['company'] == normalizedCompany)
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> saveAccountingAccount({
      String? name, required String company, required String accountName,
      required String parentAccount, required bool isGroup,
      String accountType = '', String accountCurrency = '', bool disabled = false,
    }) async {
      final co = company.trim(), label = accountName.trim(), parent = parentAccount.trim();
      if (co.isEmpty || label.isEmpty || parent.isEmpty) throw const FormatException('اسم الحساب والشركة والحساب الأب مطلوبة.');
      final companyResponse = await _send('GET', '/api/resource/Company/' + Uri.encodeComponent(co));
      final companyData = _decode(companyResponse.body);
      final companyDoc = companyData['data'];
      if (companyResponse.statusCode < 200 || companyResponse.statusCode >= 300 ||
          companyDoc is! core.Map<String, dynamic> || companyDoc['name'] != co) {
        throw Exception(_message(companyData, 'تعذر التحقق من الشركة قبل حفظ الحساب.'));
      }
      final parentResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(parent));
      final parentData = _decode(parentResponse.body);
      final parentDoc = parentData['data'];
      if (parentResponse.statusCode < 200 || parentResponse.statusCode >= 300 ||
          parentDoc is! core.Map<String, dynamic> || parentDoc['company'] != co ||
          (parentDoc['is_group'] != 1 && parentDoc['is_group'] != true) ||
          parentDoc['disabled'] == 1 || parentDoc['disabled'] == true ||
          !{'Asset', 'Liability', 'Equity', 'Income', 'Expense'}.contains(parentDoc['root_type']) ||
          !{'Balance Sheet', 'Profit and Loss'}.contains(parentDoc['report_type'])) {
        throw const FormatException('الحساب الأب يجب أن يكون حساباً تجميعياً نشطاً وصالحاً تابعاً للشركة.');
      }
      final currency = accountCurrency.trim().isEmpty
          ? (parentDoc['account_currency']?.toString().trim() ?? '')
          : accountCurrency.trim();
      if (currency.isEmpty) throw const FormatException('عملة الحساب الأب غير محددة؛ حدد عملة صالحة.');
      final baseCurrency = companyDoc['default_currency']?.toString().trim() ?? '';
      if (currency != baseCurrency) {
        final currencyResponse = await _send('GET', '/api/resource/Currency/' + Uri.encodeComponent(currency));
        final currencyData = _decode(currencyResponse.body);
        final currencyDoc = currencyData['data'];
        if (currencyResponse.statusCode < 200 || currencyResponse.statusCode >= 300 ||
            currencyDoc is! core.Map<String, dynamic> ||
            currencyDoc['enabled'] == 0 || currencyDoc['enabled'] == false) {
          throw FormatException('العملة $currency غير معرفة أو غير مفعلة في ERPNext.');
        }
      }
      final payload = <String, dynamic>{
        'account_name': label,
        'account_currency': currency,
        'disabled': disabled ? 1 : 0,
        if (!isGroup && accountType.trim().isNotEmpty) 'account_type': accountType.trim(),
      };
      final id = name?.trim() ?? '';
      if (id.isNotEmpty) {
        final currentResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(id));
        final currentData = _decode(currentResponse.body);
        final current = currentData['data'];
        if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300 ||
            current is! core.Map<String, dynamic> || current['name'] != id ||
            current['company'] != co || current['is_group'] == 1 || current['is_group'] == true ||
            current['parent_account'] != parent ||
            current['root_type'] != parentDoc['root_type'] ||
            current['report_type'] != parentDoc['report_type']) {
          throw const FormatException('لا يمكن تعديل الحساب؛ أعد تحميله وتحقق من الشركة والحساب الأب وتصنيفه.');
        }
        final response = await _sendJson('PUT', '/api/resource/Account/' + Uri.encodeComponent(id), payload);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحديث الحساب.'));
        final saved = data['data'];
        if (saved is! core.Map<String, dynamic> || saved['name'] != id || saved['company'] != co) throw const FormatException('لم يؤكد ERPNext تحديث الحساب.');
        return core.Map<String, dynamic>.from(saved);
      }
      payload.addAll({'doctype':'Account','company':co,'parent_account':parent,'root_type':parentDoc['root_type'],'report_type':parentDoc['report_type'],'is_group':isGroup ? 1 : 0});
      final response = await _sendJson('POST', '/api/resource/Account', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء الحساب.'));
      final saved = data['data'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Account' || saved['company'] != co || (saved['name']?.toString().isEmpty ?? true)) throw const FormatException('لم يؤكد ERPNext إنشاء الحساب.');
      return core.Map<String, dynamic>.from(saved);
    }

  Future<List<core.Map<String, dynamic>>> fetchJournalEntryDrafts({required String company, int start = 0, String? search, int? docStatus}) async {
      final normalized = company.trim();
      if (normalized.isEmpty) throw const FormatException('حدد الشركة أولاً.');
      final query = search?.trim() ?? '';
      final uri = FrappeApi.buildResourcePageUri(baseUrl: _baseUrl, resource: 'Journal Entry',
        fields: const ['name', 'posting_date', 'company', 'total_debit', 'total_credit', 'user_remark', 'docstatus'],
        filters: [['company', '=', normalized], if (docStatus == null) ['docstatus', 'in', [0, 1, 2]] else ['docstatus', '=', docStatus],],
        orFilters: query.isEmpty ? null : [['name', 'like', '%$query%'], ['user_remark', 'like', '%$query%']],
        orderBy: 'modified desc, name desc', start: start, pageLength: 50);
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل سجل القيود اليومية.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة القيود اليومية غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().where((row) => row['company'] == normalized && (docStatus == null ? (row['docstatus'] == 0 || row['docstatus'] == 1 || row['docstatus'] == 2) : row['docstatus'] == docStatus))
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchJournalEntryDocument(String name) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم القيد غير موجود.');
      final response = await _send('GET', '/api/resource/Journal%20Entry/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل القيد اليومي.'));
      final doc = data['data'];
      if (doc is! core.Map<String, dynamic> || doc['name'] != id || doc['doctype'] != 'Journal Entry') throw const FormatException('هوية القيد المسترجع غير مطابقة.');
      return core.Map<String, dynamic>.from(doc);
    }

  Future<core.Map<String, dynamic>> saveJournalEntryDraft({String? name, required String company, required String postingDate, required String remark, required List<core.Map<String, dynamic>> accounts}) async {
      final normalizedCompany = company.trim();
      final date = DateTime.tryParse(postingDate.trim());
      if (normalizedCompany.isEmpty || date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) throw const FormatException('الشركة وتاريخ القيد بصيغة YYYY-MM-DD حقول مطلوبة.');
      if (accounts.length < 2) throw const FormatException('القيد يتطلب حسابين على الأقل.');
      final companyResponse = await _send('GET', '/api/resource/Company/' + Uri.encodeComponent(normalizedCompany));
      final companyData = _decode(companyResponse.body);
      final companyDoc = companyData['data'];
      if (companyResponse.statusCode < 200 || companyResponse.statusCode >= 300 || companyDoc is! core.Map<String, dynamic>) throw Exception(_message(companyData, 'تعذر التحقق من الشركة.'));
      final currency = companyDoc['default_currency']?.toString() ?? '';
      if (currency.isEmpty) throw const FormatException('عملة الشركة غير محددة في ERPNext.');
      final clean = <core.Map<String, dynamic>>[];
      var debitTotal = 0.0, creditTotal = 0.0;
      var hasForeignCurrency = false;
      for (final row in accounts) {
        final account = row['account']?.toString().trim() ?? '';
        final debit = row['debit'] is num ? (row['debit'] as num).toDouble() : double.tryParse(row['debit']?.toString() ?? '') ?? 0;
        final credit = row['credit'] is num ? (row['credit'] as num).toDouble() : double.tryParse(row['credit']?.toString() ?? '') ?? 0;
        if (account.isEmpty || !debit.isFinite || !credit.isFinite || debit < 0 || credit < 0 || (debit > 0 && credit > 0) || (debit == 0 && credit == 0)) throw const FormatException('كل سطر يجب أن يحتوي حساباً ومبلغاً مديناً أو دائناً واحداً فقط.');
        final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(account));
        final accountData = _decode(accountResponse.body);
        final accountDoc = accountData['data'];
        if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 || accountDoc is! core.Map<String, dynamic> || accountDoc['company'] != normalizedCompany || accountDoc['is_group'] == 1 || accountDoc['is_group'] == true || accountDoc['disabled'] == 1 || accountDoc['disabled'] == true) throw FormatException('الحساب ' + account + ' غير صالح أو لا يتبع الشركة المحددة أو ليس حساب حركة.');
        final accountCurrency = accountDoc['account_currency']?.toString().trim().isNotEmpty == true
            ? accountDoc['account_currency'].toString().trim()
            : currency;
        final requestedRate = row['exchange_rate'] is num
            ? (row['exchange_rate'] as num).toDouble()
            : double.tryParse(row['exchange_rate']?.toString() ?? '') ?? 0.0;
        if (accountCurrency == currency && requestedRate != 1.0) {
          throw FormatException('سعر تحويل حساب العملة الأساسية يجب أن يساوي 1: $account');
        }
        final exchangeRate = accountCurrency == currency ? 1.0 : requestedRate;
        if (!exchangeRate.isFinite || exchangeRate <= 0) {
          throw FormatException('أدخل سعر تحويل موجباً للحساب $account بعملة $accountCurrency.');
        }
        if (accountCurrency != currency) hasForeignCurrency = true;
        final costCenter = row['cost_center']?.toString().trim() ?? '';
        if (costCenter.isNotEmpty) {
          final costResponse = await _send('GET',
            '/api/resource/Cost%20Center/' + Uri.encodeComponent(costCenter));
          final costData = _decode(costResponse.body);
          final costDoc = costData['data'];
          if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
              costDoc is! core.Map<String, dynamic> || costDoc['company'] != normalizedCompany ||
              costDoc['is_group'] == 1 || costDoc['is_group'] == true ||
              costDoc['disabled'] == 1 || costDoc['disabled'] == true) {
            throw FormatException('مركز التكلفة $costCenter غير صالح أو لا يتبع الشركة المحددة أو ليس مركز حركة.');
          }
        }
        final project = row['project']?.toString().trim() ?? '';
        if (project.isNotEmpty) {
          final projectResponse = await _send('GET',
            '/api/resource/Project/' + Uri.encodeComponent(project));
          final projectData = _decode(projectResponse.body);
          final projectDoc = projectData['data'];
          if (projectResponse.statusCode < 200 || projectResponse.statusCode >= 300 ||
              projectDoc is! core.Map<String, dynamic> || projectDoc['company'] != normalizedCompany) {
            throw FormatException('المشروع $project غير صالح أو لا يتبع الشركة المحددة.');
          }
        }
        final partyType = row['party_type']?.toString().trim() ?? '';
        final party = row['party']?.toString().trim() ?? '';
        if (partyType.isEmpty != party.isEmpty) {
          throw FormatException('يجب تحديد نوع الطرف والطرف معاً للحساب $account.');
        }
        final referenceType = row['reference_type']?.toString().trim() ?? '';
        final referenceName = row['reference_name']?.toString().trim() ?? '';
        if (referenceType.isEmpty != referenceName.isEmpty) {
          throw FormatException('يجب تحديد نوع المرجع ورقمه معاً للحساب $account.');
        }
        final againstType = row['against_voucher_type']?.toString().trim() ?? '';
        final againstVoucher = row['against_voucher']?.toString().trim() ?? '';
        if (againstType.isEmpty != againstVoucher.isEmpty) {
          throw FormatException('يجب تحديد نوع المستند المقابل ورقمه معاً للحساب $account.');
        }
        final baseDebit = debit * exchangeRate;
        final baseCredit = credit * exchangeRate;
        if (!baseDebit.isFinite || !baseCredit.isFinite) {
          throw FormatException('قيمة التحويل للحساب $account تتجاوز النطاق المسموح.');
        }
        debitTotal += baseDebit;
        creditTotal += baseCredit;
        clean.add({
          'doctype': 'Journal Entry Account',
          'account': account,
          'account_currency': accountCurrency,
          'exchange_rate': exchangeRate,
          'debit_in_account_currency': debit,
          'credit_in_account_currency': credit,
          'debit': baseDebit,
          'credit': baseCredit,
          if (costCenter.isNotEmpty) 'cost_center': costCenter,
          if (project.isNotEmpty) 'project': project,
          if (partyType.isNotEmpty) 'party_type': partyType,
          if (party.isNotEmpty) 'party': party,
          if (referenceType.isNotEmpty) 'reference_type': referenceType,
          if (referenceName.isNotEmpty) 'reference_name': referenceName,
          if (againstType.isNotEmpty) 'against_voucher_type': againstType,
          if (againstVoucher.isNotEmpty) 'against_voucher': againstVoucher,
          if (row['is_advance'] != null) 'is_advance': row['is_advance'],
        });
      }
      if (debitTotal <= 0 || (debitTotal - creditTotal).abs() > 0.005) throw FormatException('القيد غير متوازن. المدين ' + debitTotal.toStringAsFixed(2) + ' والدائن ' + creditTotal.toStringAsFixed(2) + '.');
      final id = name?.trim() ?? '';
      final payload = <String, dynamic>{'doctype': 'Journal Entry', 'voucher_type': 'Journal Entry', 'company': normalizedCompany, 'posting_date': postingDate.trim(), 'user_remark': remark.trim(), 'multi_currency': hasForeignCurrency ? 1 : 0, 'accounts': clean};
      if (id.isEmpty) {
        final response = await _sendJson('POST', '/api/resource/Journal%20Entry', payload);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء مسودة القيد.'));
        final created = data['data'];
        if (created is! core.Map<String, dynamic> || created['doctype'] != 'Journal Entry' || created['name'] is! String || created['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext إنشاء مسودة القيد.');
        return core.Map<String, dynamic>.from(created);
      }
      final current = await fetchJournalEntryDocument(id);
      if (current['company'] != normalizedCompany || current['docstatus'] != 0) throw const FormatException('لا يمكن تعديل القيد: تغيرت الشركة أو لم تعد حالته مسودة.');
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': {...current, ...payload, 'name': id}});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحديث مسودة القيد.'));
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Journal Entry' || saved['name'] != id || saved['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext تحديث مسودة القيد.');
      return core.Map<String, dynamic>.from(saved);
    }

  Future<core.Map<String, dynamic>> submitJournalEntry(String name, {required String company}) async {
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('رقم القيد غير موجود.');
      final current = await fetchJournalEntryDocument(id);
      if (current['company'] != company || current['docstatus'] != 0) throw const FormatException('لا يمكن ترحيل القيد: تغيرت الشركة أو لم تعد حالته مسودة.');
      final accounts = current['accounts'];
      if (accounts is! List || accounts.length < 2) throw const FormatException('القيد لا يحتوي سطرين صالحين على الأقل.');
      final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر ترحيل القيد اليومي.'));
      final submitted = data['message'];
      if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != 'Journal Entry' || submitted['name'] != id || submitted['docstatus'] != 1) throw const FormatException('لم يؤكد ERPNext ترحيل القيد اليومي.');
      return core.Map<String, dynamic>.from(submitted);
    }

  Future<core.Map<String, dynamic>> cancelJournalEntry(String name, {required String company}) async {
      final id = name.trim(), normalizedCompany = company.trim();
      if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم القيد والشركة مطلوبان.');
      final current = await fetchJournalEntryDocument(id);
      if (current['company'] != normalizedCompany || current['docstatus'] != 1) {
        throw const FormatException('يمكن إلغاء القيد المرحّل التابع للشركة المحددة فقط.');
      }
      final reversalRemark = 'قيد عكسي للقيد $id';
      final reversalUri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Journal Entry',
        fields: const ['name', 'docstatus'],
        filters: [['company', '=', normalizedCompany], ['user_remark', '=', reversalRemark]],
        orderBy: 'modified desc', pageLength: 20,
      );
      final reversalResponse = await _sendUri('GET', reversalUri);
      final reversalData = _decode(reversalResponse.body);
      if (reversalResponse.statusCode < 200 || reversalResponse.statusCode >= 300) {
        throw Exception(_message(reversalData, 'تعذر التحقق من وجود قيد عكسي قبل الإلغاء.'));
      }
      final reversalRows = reversalData['data'];
      if (reversalRows is! List) throw const FormatException('استجابة التحقق من القيد العكسي غير متوقعة.');
      if (reversalRows.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
        throw const FormatException('ألغِ أو احسم القيد العكسي أولاً قبل إلغاء القيد الأصلي.');
      }
      final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إلغاء القيد. تحقق من صلاحية الإلغاء والقيود المرتبطة.'));
      }
      final canceled = data['message'];
      if (canceled is! core.Map<String, dynamic> || canceled['doctype'] != 'Journal Entry' ||
          canceled['name'] != id || canceled['docstatus'] != 2) {
        throw const FormatException('لم يؤكد ERPNext إلغاء القيد.');
      }
      return core.Map<String, dynamic>.from(canceled);
    }

  Future<core.Map<String, dynamic>> createJournalEntryReversalDraft({
      required String name,
      required String company,
      required String postingDate,
    }) async {
      final id = name.trim(), normalizedCompany = company.trim();
      final date = DateTime.tryParse(postingDate.trim());
      if (id.isEmpty || normalizedCompany.isEmpty || date == null ||
          date.toIso8601String().substring(0, 10) != postingDate.trim()) {
        throw const FormatException('رقم القيد والشركة وتاريخ العكس الصحيح مطلوبة.');
      }
      final original = await fetchJournalEntryDocument(id);
      if (original['doctype'] != 'Journal Entry' || original['company'] != normalizedCompany ||
          original['docstatus'] != 1 || original['accounts'] is! List) {
        throw const FormatException('يمكن إنشاء قيد عكسي من قيد مرحّل تابع للشركة المحددة فقط.');
      }
      final reversalRemark = 'قيد عكسي للقيد $id';
      final existingUri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Journal Entry',
        fields: const ['name', 'docstatus', 'user_remark'],
        filters: [['company', '=', normalizedCompany], ['user_remark', '=', reversalRemark]],
        orderBy: 'modified desc', pageLength: 20,
      );
      final existingResponse = await _sendUri('GET', existingUri);
      final existingData = _decode(existingResponse.body);
      if (existingResponse.statusCode < 200 || existingResponse.statusCode >= 300) {
        throw Exception(_message(existingData, 'تعذر التحقق من وجود قيد عكسي سابق.'));
      }
      final existingRows = existingData['data'];
      if (existingRows is! List) throw const FormatException('استجابة التحقق من القيود العكسية غير متوقعة.');
      if (existingRows.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
        throw const FormatException('يوجد بالفعل قيد عكسي غير ملغى لهذا القيد.');
      }
      final reversedLines = <core.Map<String, dynamic>>[];
      for (final raw in (original['accounts'] as List).whereType<core.Map<String, dynamic>>()) {
        reversedLines.add({
          'account': raw['account']?.toString() ?? '',
          'debit': raw['credit_in_account_currency'] ?? raw['credit'] ?? 0,
          'credit': raw['debit_in_account_currency'] ?? raw['debit'] ?? 0,
          'exchange_rate': raw['exchange_rate'] ?? 1,
          'cost_center': raw['cost_center'] ?? '',
          'project': raw['project'] ?? '',
          'party_type': raw['party_type'] ?? '',
          'party': raw['party'] ?? '',
          'reference_type': raw['reference_type'] ?? '',
          'reference_name': raw['reference_name'] ?? '',
          'against_voucher_type': raw['against_voucher_type'] ?? '',
          'against_voucher': raw['against_voucher'] ?? '',
          'is_advance': raw['is_advance'],
        });
      }
      return saveJournalEntryDraft(
        company: normalizedCompany,
        postingDate: postingDate.trim(),
        remark: reversalRemark,
        accounts: reversedLines,
      );
    }

  Future<core.Map<String, dynamic>> fetchPartyLedgerTotals({
      required String partyType, required String party,
      String? company, String? fromDate, String? toDate,
      String? account, String? voucherType,
    }) async {
      final cleanParty = party.trim();
      final from = _validateLedgerDate(fromDate, 'تاريخ البداية');
      final to = _validateLedgerDate(toDate, 'تاريخ النهاية');
      if (cleanParty.isEmpty || !{'Customer', 'Supplier'}.contains(partyType) ||
          (from != null && to != null && from.compareTo(to) > 0)) {
        throw const FormatException('بيانات إجماليات كشف الحساب غير صحيحة.');
      }
      final filters = <List<dynamic>>[
        ['party_type', '=', partyType], ['party', '=', cleanParty],
        ['is_cancelled', '=', 0],
        if (company?.trim().isNotEmpty == true) ['company', '=', company!.trim()],
        if (from != null) ['posting_date', '>=', from],
        if (to != null) ['posting_date', '<=', to],
        if (account?.trim().isNotEmpty == true) ['account', '=', account!.trim()],
        if (voucherType?.trim().isNotEmpty == true) ['voucher_type', '=', voucherType!.trim()],
      ];
      final uri = Uri.parse('$_baseUrl/api/method/frappe.client.get_list').replace(
        queryParameters: {
          'doctype': 'GL Entry',
          'fields': jsonEncode(['sum(debit) as debit', 'sum(credit) as credit']),
          'filters': jsonEncode(filters), 'limit_page_length': '1',
        },
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حساب إجماليات كشف الحساب.'));
      }
      final rows = data['message'];
      if (rows is! List || rows.isEmpty || rows.first is! core.Map<String, dynamic>) {
        return {'debit': 0.0, 'credit': 0.0, 'balance': 0.0};
      }
      final row = rows.first as core.Map<String, dynamic>;
      final debit = double.tryParse(row['debit']?.toString() ?? '') ?? 0.0;
      final credit = double.tryParse(row['credit']?.toString() ?? '') ?? 0.0;
      if (!debit.isFinite || !credit.isFinite) throw const FormatException('إجماليات دفتر الأستاذ غير صالحة.');
      return {'debit': debit, 'credit': credit, 'balance': debit - credit};
    }
}
