// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin ReportsApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchSalesDashboardInvoices({
      required String company,
      required String fromDate,
      required String toDate,
    }) async {
      final normalizedCompany = company.trim();
      final startDate = DateTime.tryParse(fromDate);
      final endDate = DateTime.tryParse(toDate);
      if (normalizedCompany.isEmpty || startDate == null || endDate == null ||
          startDate.isAfter(endDate)) {
        throw const FormatException('حدد الشركة وفترة زمنية صحيحة للوحة المبيعات.');
      }
      const maxRows = 10000;
      final rows = <core.Map<String, dynamic>>[];
      var start = 0;
      while (true) {
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Sales Invoice',
          fields: const [
            'name', 'customer', 'customer_name', 'posting_date', 'currency',
            'grand_total', 'outstanding_amount', 'status',
          ],
          filters: [
            ['docstatus', '=', 1],
            ['is_return', '=', 0],
            ['company', '=', normalizedCompany],
            ['posting_date', 'between', [fromDate, toDate]],
          ],
          orderBy: 'posting_date desc, name desc',
          start: start,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل بيانات لوحة المبيعات. تحقق من صلاحية قراءة Sales Invoice.'));
        }
        final page = data['data'];
        if (page is! List) {
          throw Exception('استجابة لوحة المبيعات من ERPNext غير متوقعة.');
        }
        for (final row in page) {
          if (row is! core.Map<String, dynamic> ||
              row['name'] is! String ||
              row['customer'] is! String ||
              row['currency'] is! String) {
            throw const FormatException('تحتوي بيانات لوحة المبيعات على فاتورة غير مكتملة.');
          }
          final total = double.tryParse(row['grand_total']?.toString() ?? '');
          final outstanding = double.tryParse(row['outstanding_amount']?.toString() ?? '');
          if (total == null || !total.isFinite ||
              outstanding == null || !outstanding.isFinite ||
              outstanding < -0.01 || outstanding > total.abs() + 0.01) {
            throw const FormatException('تحتوي بيانات لوحة المبيعات على مبالغ غير صالحة.');
          }
          rows.add(row);
        }
        if (rows.length > maxRows) {
          throw const FormatException('تجاوزت لوحة المبيعات 10000 فاتورة؛ قلّص الفترة الزمنية.');
        }
        if (page.length < FrappeApi.pageSize) return rows;
        start += page.length;
      }
    }


  Future<core.Map<String, dynamic>> fetchSalesDashboardSummary({
      required String company,
      required String fromDate,
      required String toDate,
    }) async {
      final normalizedCompany = company.trim();
      final startDate = DateTime.tryParse(fromDate);
      final endDate = DateTime.tryParse(toDate);
      if (normalizedCompany.isEmpty || startDate == null || endDate == null ||
          startDate.isAfter(endDate) ||
          startDate.toIso8601String().substring(0, 10) != fromDate ||
          endDate.toIso8601String().substring(0, 10) != toDate) {
        throw const FormatException('حدد الشركة وفترة زمنية صحيحة للوحة المبيعات.');
      }
      final filters = <List<dynamic>>[
        ['docstatus', '=', 1],
        ['is_return', '=', 0],
        ['company', '=', normalizedCompany],
        ['posting_date', 'between', [fromDate, toDate]],
      ];
      Future<List<core.Map<String, dynamic>>> groupedRows({
        required List<dynamic> fields,
        required String groupBy,
        required String orderBy,
        List<List<dynamic>>? filtersOverride,
        int start = 0,
        int pageLength = 500,
      }) async {
        final uri = Uri.parse('$_baseUrl/api/method/frappe.client.get_list').replace(
          queryParameters: {
            'doctype': 'Sales Invoice',
            'fields': jsonEncode(fields),
            'filters': jsonEncode(filtersOverride ?? filters),
            'group_by': groupBy,
            'order_by': orderBy,
            'limit_start': start.toString(),
            'limit_page_length': pageLength.toString(),
          },
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل التجميعات الخادمية للوحة المبيعات.'));
        }
        final rows = data['message'];
        if (rows is! List) throw const FormatException('استجابة تجميعات لوحة المبيعات غير متوقعة.');
        return rows.whereType<core.Map<String, dynamic>>()
            .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
      }

      final currencyRows = await groupedRows(
        fields: const [
          'currency',
          {'SUM': 'grand_total', 'as': 'total'},
          {'SUM': 'outstanding_amount', 'as': 'outstanding'},
          {'COUNT': 'name', 'as': 'invoice_count'},
        ],
        groupBy: 'currency',
        orderBy: 'currency asc',
        pageLength: 1000,
      );
      final totalsByCurrency = <String, core.Map<String, dynamic>>{};
      var invoiceCount = 0;
      for (final row in currencyRows) {
        final currency = row['currency']?.toString().trim() ?? '';
        final total = double.tryParse(row['total']?.toString() ?? '');
        final outstanding = double.tryParse(row['outstanding']?.toString() ?? '');
        final count = int.tryParse(row['invoice_count']?.toString() ?? '');
        if (currency.isEmpty || total == null || outstanding == null || count == null ||
            !total.isFinite || !outstanding.isFinite || count < 0 ||
            outstanding < -0.01 || outstanding > total.abs() + 0.01) {
          throw const FormatException('أعاد ERPNext إجماليات مبيعات أو أرصدة غير صالحة.');
        }
        invoiceCount += count;
        totalsByCurrency[currency] = {
          'currency': currency,
          'total': total,
          'outstanding': outstanding,
          'invoice_count': count,
          'return_total': 0.0,
          'return_invoice_count': 0,
          'net_total': total,
        };
      }
      final returnRows = await groupedRows(
        fields: const [
          'currency',
          {'SUM': 'grand_total', 'as': 'total'},
          {'COUNT': 'name', 'as': 'invoice_count'},
        ],
        groupBy: 'currency',
        orderBy: 'currency asc',
        filtersOverride: [
          ['docstatus', '=', 1],
          ['is_return', '=', 1],
          ['company', '=', normalizedCompany],
          ['posting_date', 'between', [fromDate, toDate]],
        ],
        pageLength: 1000,
      );
      for (final row in returnRows) {
        final currency = row['currency']?.toString().trim() ?? '';
        final rawTotal = double.tryParse(row['total']?.toString() ?? '');
        final count = int.tryParse(row['invoice_count']?.toString() ?? '');
        if (currency.isEmpty || rawTotal == null || !rawTotal.isFinite ||
            count == null || count < 0) {
          throw const FormatException('أعاد ERPNext إجماليات مرتجعات غير صالحة.');
        }
        final returnTotal = rawTotal.abs();
        final entry = totalsByCurrency.putIfAbsent(currency, () => {
          'currency': currency,
          'total': 0.0,
          'outstanding': 0.0,
          'invoice_count': 0,
          'return_total': 0.0,
          'return_invoice_count': 0,
          'net_total': 0.0,
        });
        entry['return_total'] = returnTotal;
        entry['return_invoice_count'] = count;
        entry['net_total'] = (entry['total'] as double) - returnTotal;
      }
      final currencyTotals = totalsByCurrency.values.toList()
        ..sort((a, b) => (a['currency'] as String).compareTo(b['currency'] as String));

      Future<List<core.Map<String, dynamic>>> fetchDailyTotals({
        required List<List<dynamic>> dailyFilters,
      }) async {
        final result = <core.Map<String, dynamic>>[];
        var offset = 0;
        while (true) {
          final page = await groupedRows(
            fields: const [
              'posting_date',
              'currency',
              {'SUM': 'grand_total', 'as': 'total'},
              {'COUNT': 'name', 'as': 'invoice_count'},
            ],
            groupBy: 'posting_date, currency',
            orderBy: 'posting_date asc, currency asc',
            filtersOverride: dailyFilters,
            start: offset,
            pageLength: 500,
          );
          result.addAll(page);
          if (result.length > 10000) {
            throw const FormatException('تجاوزت بيانات الاتجاه الشهري 10000 مجموعة؛ قلّص فترة التقرير.');
          }
          if (page.length < 500) break;
          offset += page.length;
        }
        return result;
      }

      final dailySales = await fetchDailyTotals(dailyFilters: filters);
      final dailyReturns = await fetchDailyTotals(dailyFilters: [
        ['docstatus', '=', 1],
        ['is_return', '=', 1],
        ['company', '=', normalizedCompany],
        ['posting_date', 'between', [fromDate, toDate]],
      ]);
      final monthlyByCurrency = <String, Map<String, core.Map<String, dynamic>>>{};
      void addMonthlyRows(List<core.Map<String, dynamic>> rows, {required bool isReturn}) {
        for (final row in rows) {
          final postingDate = row['posting_date']?.toString() ?? '';
          final currency = row['currency']?.toString().trim() ?? '';
          final rawAmount = double.tryParse(row['total']?.toString() ?? '');
          final count = int.tryParse(row['invoice_count']?.toString() ?? '');
          if (postingDate.length < 7 || DateTime.tryParse(postingDate) == null ||
              currency.isEmpty || rawAmount == null || !rawAmount.isFinite ||
              count == null || count < 0) {
            throw const FormatException('أعاد ERPNext تجميعاً يومياً غير صالح للوحة المبيعات.');
          }
          final month = postingDate.substring(0, 7);
          final months = monthlyByCurrency.putIfAbsent(currency, () => {});
          final entry = months.putIfAbsent(month, () => {
            'month': month,
            'total': 0.0,
            'return_total': 0.0,
            'net_total': 0.0,
            'invoice_count': 0,
            'return_invoice_count': 0,
          });
          if (isReturn) {
            entry['return_total'] = (entry['return_total'] as double) + rawAmount.abs();
            entry['return_invoice_count'] = (entry['return_invoice_count'] as int) + count;
          } else {
            entry['total'] = (entry['total'] as double) + rawAmount;
            entry['invoice_count'] = (entry['invoice_count'] as int) + count;
          }
          entry['net_total'] = (entry['total'] as double) - (entry['return_total'] as double);
        }
      }
      addMonthlyRows(dailySales, isReturn: false);
      addMonthlyRows(dailyReturns, isReturn: true);
      final monthlyTotalsByCurrency = <String, List<core.Map<String, dynamic>>>{
        for (final entry in monthlyByCurrency.entries)
          entry.key: entry.value.values.toList()
            ..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String)),
      };

      final customerRows = <core.Map<String, dynamic>>[];
      var customerOffset = 0;
      while (true) {
        final page = await groupedRows(
          fields: const [
            'currency', 'customer', 'customer_name',
            {'SUM': 'grand_total', 'as': 'total'},
          ],
          groupBy: 'currency, customer, customer_name',
          orderBy: 'currency asc, customer asc',
          start: customerOffset,
          pageLength: 500,
        );
        customerRows.addAll(page);
        if (customerRows.length > 10000) {
          throw const FormatException('تجاوز عدد مجموعات العملاء 10000؛ قلّص فترة التقرير.');
        }
        if (page.length < 500) break;
        customerOffset += page.length;
      }

      final customersByCurrency = <String, List<core.Map<String, dynamic>>>{};
      for (final row in customerRows) {
        final currency = row['currency']?.toString().trim() ?? '';
        final customer = row['customer']?.toString().trim() ?? '';
        final total = double.tryParse(row['total']?.toString() ?? '');
        if (currency.isEmpty || customer.isEmpty || total == null || !total.isFinite) {
          throw const FormatException('أعاد ERPNext تجميع عملاء غير صالح للوحة المبيعات.');
        }
        customersByCurrency.putIfAbsent(currency, () => [])
            .add({
              'customer': customer,
              'customer_name': row['customer_name']?.toString().trim().isNotEmpty == true
                  ? row['customer_name'].toString()
                  : customer,
              'total': total,
            });
      }
      for (final rows in customersByCurrency.values) {
        rows.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
      }
      return {
        'currency_totals': currencyTotals,
        'top_customers_by_currency': {
          for (final entry in customersByCurrency.entries)
            entry.key: entry.value.take(5).toList(growable: false),
        },
        'monthly_totals_by_currency': monthlyTotalsByCurrency,
        'total_invoices': invoiceCount,
      };
    }

  Future<List<core.Map<String, dynamic>>> fetchOutstandingInvoices({
      required bool receivable,
      String? company,
    }) async {
      const maxRows = 10000;
      final doctype = receivable ? 'Sales Invoice' : 'Purchase Invoice';
      final partyField = receivable ? 'customer' : 'supplier';
      final partyNameField = receivable ? 'customer_name' : 'supplier_name';
      final filters = <List<dynamic>>[
        ['docstatus', '=', 1],
        ['outstanding_amount', '>', 0],
        ['is_return', '=', 0],
        if (company != null && company.trim().isNotEmpty)
          ['company', '=', company.trim()],
      ];
      final rows = <core.Map<String, dynamic>>[];
      var start = 0;
      while (true) {
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: doctype,
          fields: [
            'name', partyField, partyNameField, 'company', 'posting_date',
            'due_date', 'currency', 'grand_total', 'outstanding_amount',
          ],
          filters: filters,
          orderBy: 'due_date asc, posting_date asc, name asc',
          start: start,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(
            data,
            receivable
                ? 'تعذر تحميل الفواتير المستحقة للعملاء.'
                : 'تعذر تحميل الفواتير المستحقة للموردين.',
          ));
        }
        final page = data['data'];
        if (page is! List) {
          throw Exception('استجابة تقرير الفواتير المستحقة غير متوقعة.');
        }
        final validRows = page.whereType<core.Map<String, dynamic>>().toList();
        rows.addAll(validRows);
        if (rows.length > maxRows) {
          throw const FormatException(
            'تجاوز التقرير 10000 فاتورة مستحقة؛ حدد شركة لتقليل نطاق التقرير.',
          );
        }
        if (page.length < FrappeApi.pageSize) return rows;
        start += page.length;
      }
    }

  Future<core.Map<String, dynamic>> runStandardReport({
      required String reportName,
      required core.Map<String, dynamic> filters,
    }) async {
      const allowedReports = {
        'Profit and Loss Statement',
        'Balance Sheet',
        'Cash Flow',
        'General Ledger',
        'Trial Balance',
        'Sales Register',
        'Sales Analytics',
        'Sales Person Commission Summary',
        'Sales Person-wise Transaction Summary',
        'Purchase Register',
        'Bank Reconciliation Statement',
        'Payment Ledger',
        'Stock Balance',
        'Stock Ledger',
      };
      if (!allowedReports.contains(reportName)) {
        throw FormatException('التقرير غير مدعوم في التطبيق: $reportName');
      }
      final company = filters['company']?.toString().trim() ?? '';
      if (company.isEmpty) {
        throw const FormatException('حدد الشركة قبل تشغيل التقرير المالي.');
      }
      final response = await _sendJson(
        'POST',
        '/api/method/frappe.desk.query_report.run',
        {
          'report_name': reportName,
          'filters': filters,
          'ignore_prepared_report': true,
        },
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تشغيل تقرير $reportName. تحقق من صلاحيات التقرير.'));
      }
      final message = data['message'];
      if (message is! core.Map) {
        throw Exception('استجابة تقرير $reportName من ERPNext غير متوقعة.');
      }
      final result = core.Map<String, dynamic>.from(message);
      if (result['columns'] is! List || result['result'] is! List) {
        throw Exception('لم يُرجع ERPNext أعمدة وبيانات صالحة لتقرير $reportName.');
      }
      return result;
    }
}
