// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin PurchasesApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchPurchaseOrders({int start = 0, String? search}) async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Purchase Order',
        fields: const ['name', 'supplier', 'supplier_name', 'company', 'transaction_date', 'status', 'per_received'],
        filters: const [['docstatus', '=', 1]],
        orFilters: search == null || search.trim().isEmpty ? null : [
          ['name', 'like', '%${search.trim()}%'],
          ['supplier', 'like', '%${search.trim()}%'],
          ['supplier_name', 'like', '%${search.trim()}%'],
        ],
        orderBy: 'transaction_date desc, name desc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل أوامر الشراء المرحلة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة أوامر الشراء غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchPurchaseOrderDocument(String name) async {
      if (name.trim().isEmpty) throw const FormatException('رقم أمر الشراء غير موجود.');
      final response = await _send('GET',
          '/api/resource/Purchase%20Order/' + Uri.encodeComponent(name));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل أمر الشراء.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> ||
          document['doctype'] != 'Purchase Order' ||
          document['docstatus'] != 1) {
        throw const FormatException('أمر الشراء غير مرحّل أو أن بياناته غير مكتملة.');
      }
      return document;
    }

  Future<List<core.Map<String, dynamic>>> fetchPurchaseOrderRecords({int start = 0, String? search}) async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Purchase Order',
        fields: const ['name', 'supplier', 'supplier_name', 'company', 'transaction_date', 'status', 'docstatus', 'per_received', 'per_billed', 'grand_total', 'currency'],
        orFilters: search == null || search.trim().isEmpty ? null : [
          ['name', 'like', '%${search.trim()}%'],
          ['supplier', 'like', '%${search.trim()}%'],
          ['supplier_name', 'like', '%${search.trim()}%'],
        ],
        orderBy: 'modified desc, name desc', start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل سجل أوامر الشراء.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة سجل أوامر الشراء غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
    }

  Future<core.Map<String, dynamic>> _fetchPurchaseOrderAnyStatus(String name) async {
      if (name.trim().isEmpty) throw const FormatException('رقم أمر الشراء غير موجود.');
      final response = await _send('GET', '/api/resource/Purchase%20Order/' + Uri.encodeComponent(name.trim()));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل أمر الشراء.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> || document['doctype'] != 'Purchase Order' || document['name'] != name.trim()) {
        throw const FormatException('لم يؤكد ERPNext هوية أمر الشراء المطلوب.');
      }
      return document;
    }

  Future<core.Map<String, dynamic>> fetchPurchaseOrderRecordDocument(String name) => _fetchPurchaseOrderAnyStatus(name);

  Future<core.Map<String, dynamic>> createPurchaseOrder(core.Map<String, dynamic> document) async {
      _validatePurchaseOrder(document);
      await _validateDocumentWarehouses(document);
      final response = await _sendJson('POST', '/api/resource/Purchase%20Order', document);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء أمر الشراء.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Purchase Order' || created['name'] is! String || created['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة أمر الشراء.');
      }
      return created;
    }

  void _validatePurchaseOrder(core.Map<String, dynamic> document) {
      final items = document['items'];
      if (document['doctype'] != 'Purchase Order' || document['company'] is! String || (document['company'] as String).trim().isEmpty ||
          document['supplier'] is! String || (document['supplier'] as String).trim().isEmpty || items is! List || items.isEmpty) {
        throw const FormatException('حدد الشركة والمورد وأضف صنفاً واحداً على الأقل لأمر الشراء.');
      }
      for (final row in items) {
        if (row is! core.Map<String, dynamic> || row['item_code'] is! String || (row['item_code'] as String).trim().isEmpty ||
            row['qty'] is! num || !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
            row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
            !((row['qty'] as num) * (row['rate'] as num)).isFinite) {
          throw const FormatException('تحقق من صنف وكمية وسعر كل بند في أمر الشراء.');
        }
      }
    }

  Future<core.Map<String, dynamic>> updateDraftPurchaseOrder({required String name, required core.Map<String, dynamic> changes}) async {
      _validatePurchaseOrder(changes);
      await _validateDocumentWarehouses(changes);
      final current = await _fetchPurchaseOrderAnyStatus(name);
      if (current['docstatus'] != 0) throw const FormatException('يمكن تعديل أوامر الشراء غير المرحلة فقط.');
      final payload = core.Map<String, dynamic>.from(current)
        ..['company'] = changes['company']
        ..['supplier'] = changes['supplier']
        ..['transaction_date'] = changes['transaction_date'] ?? current['transaction_date']
        ..['schedule_date'] = changes['schedule_date'] ?? current['schedule_date']
        ..['items'] = changes['items'];
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تعديل مسودة أمر الشراء.'));
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Purchase Order' || saved['name'] != name || saved['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext حفظ مسودة أمر الشراء.');
      }
      return saved;
    }

  Future<core.Map<String, dynamic>> submitPurchaseOrder(core.Map<String, dynamic> document) => _submitMobileDocument(document, 'Purchase Order');

  Future<core.Map<String, dynamic>> cancelPurchaseOrder(String name) async {
      final key = 'cancel-purchase-order:$name';
      if (!_inFlightPurchaseActions.add(key)) throw const FormatException('إلغاء أمر الشراء قيد التنفيذ بالفعل.');
      try {
        final current = await _fetchPurchaseOrderAnyStatus(name);
        if (current['docstatus'] != 1) throw const FormatException('يمكن إلغاء أمر الشراء المرحّل فقط.');
        final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إلغاء أمر الشراء. قد توجد مستندات استلام أو فواتير مرتبطة.'));
        final cancelled = data['message'];
        if (cancelled is! core.Map<String, dynamic> || cancelled['doctype'] != 'Purchase Order' || cancelled['name'] != name || cancelled['docstatus'] != 2) {
          throw Exception('لم يؤكد ERPNext إلغاء أمر الشراء.');
        }
        return cancelled;
      } finally {
        _inFlightPurchaseActions.remove(key);
      }
    }

  Future<List<ErpPurchaseInvoice>> fetchPurchaseInvoices({int start = 0, String? search}) async {
      final uri = Uri.parse('$_baseUrl/api/resource/Purchase%20Invoice').replace(queryParameters: {
        'fields': jsonEncode(['name', 'supplier', 'supplier_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status', 'is_return', 'return_against']),
        'limit_page_length': FrappeApi.pageSize.toString(),
        if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","supplier","supplier_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
        'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'posting_date desc, name desc',
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب فواتير المشتريات. تحقق من صلاحية قراءة Purchase Invoice.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة فواتير المشتريات من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map(ErpPurchaseInvoice.fromJson).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> createPurchaseInvoice(core.Map<String, dynamic> invoice) async {
      if (invoice['update_stock'] == 1 || invoice['update_stock'] == true) {
        final items = invoice['items'];
        if (items is List) await _ensureIncomingBatchNumbers(items);
      }
      _validatePurchase(invoice);
      await _validateDocumentWarehouses(invoice);
      final response = await _sendJson('POST', '/api/resource/Purchase%20Invoice', invoice);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ فاتورة المشتريات.'));
      final doc = data['data'];
      if (doc is! core.Map<String, dynamic> ||
          doc['doctype'] != 'Purchase Invoice' ||
          doc['name'] is! String ||
          doc['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة فاتورة المشتريات.');
      }
      return doc;
    }

  void _validatePurchase(core.Map<String, dynamic> doc) {
      final items = doc['items'];
      if (doc['doctype'] != 'Purchase Invoice' || doc['supplier'] is! String ||
          (doc['supplier'] as String).trim().isEmpty || doc['company'] is! String ||
          (doc['company'] as String).trim().isEmpty || items is! List || items.isEmpty) {
        throw const FormatException('حدد الشركة والمورد وأضف صنفاً واحداً على الأقل.');
      }
      doc['items'] = _cleanSerialBatchRows(items);
      for (final row in items) {
        if (row is! core.Map<String, dynamic> || row['item_code'] is! String ||
            (row['item_code'] as String).trim().isEmpty || row['qty'] is! num ||
            !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
            row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
            !((row['qty'] as num) * (row['rate'] as num)).isFinite) {
          throw const FormatException('تحقق من رمز الصنف والكمية والسعر، وتأكد أن إجمالي البند ضمن النطاق الرقمي.');
        }
      }
    }

  Future<core.Map<String, dynamic>> updateDraftPurchaseInvoice({
      required String invoiceName, required core.Map<String, dynamic> changes,
    }) async {
      if (changes['update_stock'] == 1 || changes['update_stock'] == true) {
        final items = changes['items'];
        if (items is List) await _ensureIncomingBatchNumbers(items);
      }
      _validatePurchase(changes);
      await _validateDocumentWarehouses(changes);
      if (invoiceName.trim().isEmpty) throw const FormatException('رقم المسودة غير موجود.');
      final current = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
      if (current['docstatus'] != 0) throw const FormatException('يمكن تعديل المسودات غير المرحلة فقط.');
      final payload = core.Map<String, dynamic>.from(current)
        ..['supplier'] = changes['supplier']
        ..['company'] = changes['company']
        ..['posting_date'] = changes['posting_date'] ?? current['posting_date']
        ..['update_stock'] = changes['update_stock'] == true || changes['update_stock'] == 1 ? 1 : 0
        ..['items'] = changes['items'];
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تعديل مسودة المشتريات.'));
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> || saved['name'] != invoiceName || saved['docstatus'] != 0) throw Exception('لم يتم تأكيد حفظ المسودة.');
      return saved;
    }

  Future<core.Map<String, dynamic>> submitPurchaseInvoice(core.Map<String, dynamic> doc) =>
        _submitMobileDocument(doc, 'Purchase Invoice');

  Future<core.Map<String, double>> fetchPurchaseReturnableQuantities(String invoiceName) async {
      if (invoiceName.trim().isEmpty) throw const FormatException('رقم فاتورة المشتريات غير موجود.');
      final source = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
      if (source['docstatus'] != 1 || source['is_return'] == 1 || source['is_return'] == true) {
        throw const FormatException('حساب الكميات المتبقية يتطلب فاتورة مشتريات أصلية مرحلة.');
      }
      final mapped = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.purchase_invoice.mapper.make_debit_note',
        {'source_name': invoiceName});
      final data = _decode(mapped.body);
      if (mapped.statusCode < 200 || mapped.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حساب الكميات المتبقية للمرتجع.'));
      }
      final raw = data['message'];
      if (raw is! core.Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
          (raw['is_return'] != 1 && raw['is_return'] != true) ||
          raw['return_against'] != invoiceName || raw['items'] is! List) {
        throw Exception('لم يؤكد ERPNext بيانات الكميات القابلة للإرجاع.');
      }
      final result = <String, double>{};
      for (final row in (raw['items'] as List).whereType<core.Map<String, dynamic>>()) {
        final sourceItem = row['purchase_invoice_item']?.toString();
        final qty = double.tryParse(row['qty']?.toString() ?? '');
        if (sourceItem == null || sourceItem.isEmpty || qty == null || !qty.isFinite || qty == 0) continue;
        if (result.containsKey(sourceItem)) {
          throw const FormatException('تكررت إحالة بند الفاتورة الأصلية في بيانات المرتجع.');
        }
        result[sourceItem] = qty.abs();
      }
      return result;
    }

  Future<core.Map<String, dynamic>> createPurchaseReturn(String invoiceName, {core.Map<String, double?>? quantitiesBySourceItem}) async {
      final actionKey = 'purchase-return:$invoiceName';
      if (!_inFlightPurchaseActions.add(actionKey)) {
        throw const FormatException('إنشاء مرتجع المشتريات قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      final source = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
      if (source['docstatus'] != 1 || source['is_return'] == 1 || source['is_return'] == true) {
        throw const FormatException('المرتجع يتطلب فاتورة مشتريات أصلية مرحلة.');
      }
      final pendingUri = Uri.parse('$_baseUrl/api/resource/Purchase%20Invoice').replace(queryParameters: {
        'fields': jsonEncode(['name']),
        'filters': jsonEncode([['return_against', '=', invoiceName], ['is_return', '=', 1], ['docstatus', '=', 0]]),
        'limit_page_length': '1',
      });
      final pending = await _sendUri('GET', pendingUri);
      final pendingData = _decode(pending.body);
      if (pending.statusCode < 200 || pending.statusCode >= 300) throw Exception(_message(pendingData, 'تعذر فحص المرتجعات السابقة.'));
      if (pendingData['data'] is List && (pendingData['data'] as List).isNotEmpty) {
        throw const FormatException('توجد مسودة مرتجع سابقة لهذه الفاتورة؛ راجعها قبل إنشاء أخرى.');
      }
      final mapped = await _sendJson('POST',
        '/api/method/erpnext.accounts.doctype.purchase_invoice.mapper.make_debit_note',
        {'source_name': invoiceName});
      final mappedData = _decode(mapped.body);
      if (mapped.statusCode < 200 || mapped.statusCode >= 300) throw Exception(_message(mappedData, 'تعذر تجهيز مرتجع المشتريات.'));
      final raw = mappedData['message'];
      if (raw is! core.Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
          (raw['is_return'] != 1 && raw['is_return'] != true) || raw['return_against'] != invoiceName ||
          raw['items'] is! List || (raw['items'] as List).isEmpty) {
        throw Exception('لم يؤكد ERPNext بيانات مرتجع المشتريات.');
      }
      final mappedItems = (raw['items'] as List).whereType<core.Map<String, dynamic>>().toList();
      if (quantitiesBySourceItem != null) {
        final selectedItems = <core.Map<String, dynamic>>[];
        final matchedSourceRows = <String>{};
        for (var index = 0; index < mappedItems.length; index++) {
          final sourceItemName = mappedItems[index]['purchase_invoice_item']?.toString();
          final requested = sourceItemName == null ? null : quantitiesBySourceItem[sourceItemName];
          if (sourceItemName != null && requested != null && requested > 0) {
            if (!matchedSourceRows.add(sourceItemName)) {
              throw const FormatException('أعاد ERPNext أكثر من بند لنفس سطر الفاتورة الأصلية؛ أوقفنا إنشاء المرتجع لتجنب تكرار الكمية.');
            }
          }
          if (requested == null || requested == 0) continue;
          if (!requested.isFinite || requested < 0) {
            throw const FormatException('أدخل كمية مرتجع صحيحة موجبة أو اترك البند دون إرجاع.');
          }
          final mappedQty = double.tryParse(mappedItems[index]['qty']?.toString() ?? '') ?? 0;
          if (mappedQty == 0 || requested > mappedQty.abs() + 0.000001) {
            throw FormatException('كمية المرتجع للصنف ${mappedItems[index]['item_code'] ?? index + 1} تتجاوز الكمية المتبقية المسموح بها في ERPNext.');
          }
          final line = core.Map<String, dynamic>.from(mappedItems[index]);
          line['qty'] = mappedQty.isNegative ? -requested : requested;
          selectedItems.add(line);
        }
        final unmatchedSelections = quantitiesBySourceItem.entries
            .where((entry) => entry.value != null && entry.value! > 0 &&
                !matchedSourceRows.contains(entry.key))
            .map((entry) => entry.key).toList();
        if (unmatchedSelections.isNotEmpty) {
          throw FormatException('لم يعد الصنف المرتبط بالسطر ${unmatchedSelections.first} متاحاً للإرجاع وفق بيانات ERPNext الحالية. حدّث الفاتورة وحاول مجدداً.');
        }
        if (selectedItems.isEmpty) {
          throw const FormatException('حدد كمية مرتجع واحدة على الأقل.');
        }
        raw['items'] = selectedItems;
      }
      final inserted = await _sendJson('POST', '/api/resource/Purchase%20Invoice', core.Map<String, dynamic>.from(raw));
      final data = _decode(inserted.body);
      if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ مسودة المرتجع.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Purchase Invoice' ||
          created['name'] is! String ||
          created['docstatus'] != 0 ||
          (created['is_return'] != 1 && created['is_return'] != true) ||
          created['return_against'] != invoiceName) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة مرتجع مشتريات مرتبطة بالفاتورة الأصلية؛ تحقق من السجل قبل إعادة المحاولة.');
      }
      return created;
      } finally {
        _inFlightPurchaseActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> cancelPurchaseInvoice(String name) async {
      final actionKey = 'cancel-purchase:$name';
      if (!_inFlightPurchaseActions.add(actionKey)) {
        throw const FormatException('إلغاء فاتورة المشتريات قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      if (name.trim().isEmpty) throw const FormatException('رقم فاتورة المشتريات غير موجود.');
      final current = await fetchInvoiceDocument('Purchase Invoice', name);
      if (current['doctype'] != 'Purchase Invoice' || current['name'] != name || current['docstatus'] != 1) {
        throw const FormatException('إلغاء الفاتورة متاح للمستندات المرحلة فقط.');
      }
      final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {
        'doctype': 'Purchase Invoice',
        'name': name,
      });
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إلغاء فاتورة المشتريات. قد توجد دفعات أو مرتجعات أو مستندات مرتبطة.'));
      }
      final canceled = data['message'];
      if (canceled is! core.Map<String, dynamic> ||
          canceled['doctype'] != 'Purchase Invoice' ||
          canceled['name'] != name ||
          canceled['docstatus'] != 2) {
        throw Exception('لم يؤكد ERPNext إلغاء الفاتورة. أعد تحميلها للتحقق قبل أي إجراء آخر.');
      }
      return canceled;
      } finally {
        _inFlightPurchaseActions.remove(actionKey);
      }
    }
}
