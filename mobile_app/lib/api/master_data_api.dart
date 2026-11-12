// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin MasterDataApiMixin on _FrappeApiCore {
  Future<List<ErpCompany>> fetchCompanies() async {
      const companyPageSize = FrappeApi.pageSize;
      const maxCompanyCount = 10000;
      final companies = <ErpCompany>[];
      var start = 0;
  
      while (true) {
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Company',
          fields: const ['name', 'abbr', 'default_currency'],
          orderBy: 'name asc',
          start: start,
          pageLength: companyPageSize,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر جلب الشركات. تحقق من صلاحية قراءة Company.'));
        }
        final rows = data['data'];
        if (rows is! List) {
          throw Exception('استجابة الشركات من ERPNext غير متوقعة.');
        }
  
        final page = rows
            .whereType<core.Map<String, dynamic>>()
            .map(ErpCompany.fromJson)
            .toList(growable: false);
        companies.addAll(page);
        if (rows.length < companyPageSize) {
          return companies;
        }
        if (companies.length > maxCompanyCount) {
          throw const FormatException(
            'تجاوز عدد الشركات الحد الآمن للتحميل دفعة واحدة؛ استخدم البحث أو راجع إعدادات ERPNext.',
          );
        }
        start += rows.length;
      }
    }

  Future<List<ErpItem>> fetchItems({int start = 0, String? search}) async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Item',
        fields: ['item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item', 'brand', 'has_serial_no', 'has_batch_no', 'has_expiry_date'],
        filters: [['disabled', '=', 0]],
        orFilters: search == null || search.trim().isEmpty
            ? null
            : [
                ['item_code', 'like', '%${search.trim()}%'],
                ['item_name', 'like', '%${search.trim()}%'],
              ],
        orderBy: 'modified desc, item_code asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر جلب الأصناف. تحقق من صلاحية قراءة Item.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة الأصناف من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map(ErpItem.fromJson).toList(growable: false);
    }

  Future<List<ErpCustomer>> fetchCustomers({int start = 0, String? search}) async {
      final uri = Uri.parse('$_baseUrl/api/resource/Customer').replace(queryParameters: {
        'fields': jsonEncode(['name', 'customer_name', 'customer_type', 'customer_group', 'territory']),
        'filters': jsonEncode([['disabled', '=', 0]]),
        if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","customer_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
        'limit_page_length': FrappeApi.pageSize.toString(),
        'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'customer_name asc, name asc',
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب العملاء. تحقق من صلاحية قراءة Customer.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة العملاء من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map(ErpCustomer.fromJson).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchCustomerDocument(String customerId) async {
      final id = customerId.trim();
      if (id.isEmpty) throw const FormatException('حدد العميل أولاً.');
      final uri = Uri.parse(
        '$_baseUrl/api/resource/Customer/' + Uri.encodeComponent(id),
      ).replace(queryParameters: {
        'fields': jsonEncode([
          'name', 'customer_name', 'customer_type', 'customer_group',
          'territory', 'mobile_no', 'email_id', 'website', 'tax_id',
          'default_currency', 'default_price_list', 'disabled',
        ]),
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل ملف العميل.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> || document['name'] != id) {
        throw Exception('استجابة ملف العميل غير صحيحة.');
      }
      return core.Map<String, dynamic>.from(document);
    }

  Future<core.Map<String, dynamic>> updateCustomerProfile({
      required String customerId,
      required core.Map<String, dynamic> values,
    }) async {
      final id = customerId.trim();
      final customerName = values['customer_name']?.toString().trim() ?? '';
      final customerType = values['customer_type']?.toString().trim() ?? '';
      final customerGroup = values['customer_group']?.toString().trim() ?? '';
      final territory = values['territory']?.toString().trim() ?? '';
      if (id.isEmpty || customerName.isEmpty ||
          !{'Company', 'Individual'}.contains(customerType) ||
          customerGroup.isEmpty || territory.isEmpty) {
        throw const FormatException('اسم العميل ونوعه ومجموعة العميل والمنطقة حقول مطلوبة.');
      }
      final allowedFields = <String>{
        'customer_name', 'customer_type', 'customer_group', 'territory',
        'mobile_no', 'email_id', 'website', 'tax_id',
        'default_currency', 'default_price_list',
      };
      final payload = <String, dynamic>{};
      for (final entry in values.entries) {
        if (allowedFields.contains(entry.key)) {
          payload[entry.key] = entry.value is String
              ? (entry.value as String).trim()
              : entry.value;
        }
      }
      payload['customer_name'] = customerName;
      payload['customer_type'] = customerType;
      payload['customer_group'] = customerGroup;
      payload['territory'] = territory;
  
      // Re-read the document before updating so a stale or mismatched identity
      // cannot be used to change a different Customer record.
      final current = await fetchCustomerDocument(id);
      if (current['name'] != id) {
        throw const FormatException('تغير سجل العميل؛ حدّث القائمة ثم أعد المحاولة.');
      }
      final response = await _sendJson(
        'PUT',
        '/api/resource/Customer/' + Uri.encodeComponent(id),
        payload,
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ تعديلات العميل.'));
      }
      final updated = data['data'];
      if (updated is! core.Map<String, dynamic> || updated['name'] != id ||
          updated['customer_name'] != customerName) {
        throw Exception('لم يؤكد ERPNext حفظ ملف العميل؛ أعد تحميل الملف قبل أي تعديل آخر.');
      }
      return core.Map<String, dynamic>.from(updated);
    }

  Future<List<ErpSupplier>> fetchSuppliers({int start = 0, String? search}) async {
      final uri = Uri.parse('$_baseUrl/api/resource/Supplier').replace(queryParameters: {
        'fields': jsonEncode(['name', 'supplier_name', 'supplier_group', 'supplier_type']),
        'filters': jsonEncode([['disabled', '=', 0]]),
        if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","supplier_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
        'limit_page_length': FrappeApi.pageSize.toString(),
        'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'supplier_name asc, name asc',
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب الموردين. تحقق من صلاحية قراءة Supplier.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة الموردين من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map(ErpSupplier.fromJson).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchMasterDataOptions(String doctype) async {
      if (!FrappeApi._masterDataFields.containsKey(doctype)) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
      const maxRows = 2000;
      final result = <core.Map<String, dynamic>>[];
      var start = 0;
      while (true) {
        final page = await fetchMasterDataRows(doctype: doctype, start: start);
        result.addAll(page);
        if (page.length < FrappeApi.pageSize) return result;
        start += page.length;
        if (result.length >= maxRows) return result;
      }
    }

  Future<List<core.Map<String, dynamic>>> fetchMasterDataRows({
      required String doctype,
      int start = 0,
      String? search,
    }) async {
      final fields = FrappeApi._masterDataFields[doctype];
      if (fields == null) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
      final query = search?.trim();
      final searchable = switch (doctype) {
        'Item' => const ['name', 'item_name', 'item_group'],
        'Supplier' => const ['name', 'supplier_name', 'supplier_group'],
        'Customer' => const ['name', 'customer_name', 'customer_group', 'territory'],
        'Customer Group' => const ['name', 'customer_group_name', 'parent_customer_group'],
        'Territory' => const ['name', 'territory_name', 'parent_territory'],
        'Sales Person' => const ['name', 'sales_person_name', 'parent_sales_person', 'employee'],
        'Warehouse' => const ['name', 'warehouse_name', 'company'],
        'Item Group' => const ['name', 'item_group_name', 'parent_item_group'],
        'UOM' => const ['name', 'uom_name'],
        'Supplier Group' => const ['name', 'supplier_group_name', 'parent_supplier_group'],
        'Price List' => const ['name', 'price_list_name', 'currency'],
        _ => const <String>[],
      };
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: doctype,
        fields: fields,
        filters: const [],
        orFilters: query == null || query.isEmpty
            ? null
            : searchable.map((field) => [field, 'like', '%$query%']).toList(),
        orderBy: doctype == 'Warehouse' ? 'lft asc, name asc' : 'modified desc, name asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل بيانات $doctype. تحقق من صلاحية القراءة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة بيانات $doctype غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchWarehouseChildren({
    required String parentWarehouse,
    String? company,
    String? search,
    int start = 0,
  }) async {
    final parent = parentWarehouse.trim();
    if (parent.isEmpty) throw const FormatException('حدد المجموعة الأب لعرض المستودعات الفرعية.');
    final query = search?.trim();
    final uri = FrappeApi.buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Warehouse',
      fields: const ['name', 'warehouse_name', 'parent_warehouse', 'company', 'is_group', 'disabled', 'lft', 'rgt'],
      filters: [
        ['parent_warehouse', '=', parent],
        if (company != null && company.trim().isNotEmpty) ['company', '=', company.trim()],
      ],
      orFilters: query == null || query.isEmpty ? null : [
        ['name', 'like', '%$query%'],
        ['warehouse_name', 'like', '%$query%'],
      ],
      orderBy: 'lft asc, name asc',
      start: start,
      pageLength: FrappeApi.pageSize,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل المستودعات الفرعية من ERPNext.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة المستودعات الفرعية غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .where((row) => row['parent_warehouse']?.toString() == parent)
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchMasterDataDocument({
      required String doctype,
      required String name,
    }) async {
      if (!FrappeApi._masterDataFields.containsKey(doctype)) {
        throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
      }
      final id = name.trim();
      if (id.isEmpty) throw const FormatException('حدد السجل أولاً.');
      final uri = Uri.parse('$_baseUrl/api/resource/${Uri.encodeComponent(doctype)}/${Uri.encodeComponent(id)}')
          .replace(queryParameters: {'fields': jsonEncode(FrappeApi._masterDataFields[doctype])});
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل السجل.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> || document['name'] != id) {
        throw Exception('لم تتطابق هوية السجل المسترجع مع المطلوب.');
      }
      return core.Map<String, dynamic>.from(document);
    }

  Future<core.Map<String, dynamic>> saveMasterDataDocument({
      required String doctype,
      String? name,
      required core.Map<String, dynamic> values,
    }) async {
      final allowed = FrappeApi._masterDataWritableFields[doctype];
      if (allowed == null) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
      final payload = <String, dynamic>{};
      for (final entry in values.entries) {
        if (allowed.contains(entry.key)) {
          payload[entry.key] = entry.value is String
              ? (entry.value as String).trim()
              : entry.value;
        }
      }
      if (doctype == 'Item' && payload['barcodes'] is List) {
        final seen = <String>{};
        final raw = payload['barcodes'] as List;
        payload['barcodes'] = raw.map((entry) {
          if (entry is! core.Map) throw const FormatException('جدول الباركود غير صالح.');
          final barcode = entry['barcode']?.toString().trim() ?? '';
          final type = entry['barcode_type']?.toString().trim() ?? '';
          if (barcode.isEmpty || !seen.add(barcode)) {
            throw const FormatException('كل باركود يجب أن يكون غير فارغ وغير مكرر.');
          }
          return {'doctype': 'Item Barcode', 'barcode': barcode,
            if (type.isNotEmpty) 'barcode_type': type};
        }).toList();
      }
      String requiredValue(String key) => payload[key]?.toString().trim() ?? '';
      switch (doctype) {
        case 'Item':
          if (requiredValue('item_code').isEmpty || requiredValue('item_name').isEmpty ||
              requiredValue('item_group').isEmpty || requiredValue('stock_uom').isEmpty) {
            throw const FormatException('رمز الصنف واسمه ومجموعته ووحدة القياس حقول مطلوبة.');
          }
          if (payload['has_serial_no'] == true && payload['has_batch_no'] == true) {
            throw const FormatException('لا يمكن تفعيل التتبع بالرقم التسلسلي والدفعة معاً.');
          }
          final rawUoms = payload['uoms'];
          if (rawUoms != null) {
            if (rawUoms is! List) throw const FormatException('جدول تحويل وحدات الصنف غير صالح.');
            final seenUoms = <String>{};
            for (final raw in rawUoms) {
              if (raw is! core.Map) throw const FormatException('يوجد صف غير صالح في تحويل وحدات الصنف.');
              final uom = raw['uom']?.toString().trim() ?? '';
              final factorValue = raw['conversion_factor'];
              final factor = factorValue is num ? factorValue.toDouble() : double.tryParse(factorValue?.toString() ?? '');
              if (uom.isEmpty || uom == requiredValue('stock_uom') || !seenUoms.add(uom) ||
                  factor == null || !factor.isFinite || factor <= 0) {
                throw const FormatException('كل وحدة بديلة يجب أن تكون مختلفة عن وحدة المخزون، وغير مكررة، ومعامل تحويلها أكبر من صفر.');
              }
            }
            payload['uoms'] = rawUoms.map((raw) => {
              'doctype': 'UOM Conversion Detail',
              'uom': raw['uom'].toString().trim(),
              'conversion_factor': raw['conversion_factor'] is num
                  ? raw['conversion_factor']
                  : double.parse(raw['conversion_factor'].toString()),
            }).toList();
          }
          break;
        case 'Supplier':
          if (requiredValue('supplier_name').isEmpty ||
              !{'Company', 'Individual'}.contains(requiredValue('supplier_type')) ||
              requiredValue('supplier_group').isEmpty) {
            throw const FormatException('اسم المورد ونوعه ومجموعته حقول مطلوبة.');
          }
          break;
        case 'Customer':
          if (requiredValue('customer_name').isEmpty ||
              !{'Company', 'Individual'}.contains(requiredValue('customer_type')) ||
              requiredValue('customer_group').isEmpty ||
              requiredValue('territory').isEmpty) {
            throw const FormatException('اسم العميل ونوعه ومجموعته ومنطقته حقول مطلوبة.');
          }
          break;
        case 'Customer Group':
          if (requiredValue('customer_group_name').isEmpty) {
            throw const FormatException('اسم مجموعة العملاء مطلوب.');
          }
          break;
        case 'Territory':
          if (requiredValue('territory_name').isEmpty) {
            throw const FormatException('اسم المنطقة مطلوب.');
          }
          break;
        case 'Sales Person':
          final commissionText = requiredValue('commission_rate');
          final commissionRate = commissionText.isEmpty ? 0.0 : double.tryParse(commissionText);
          if (requiredValue('sales_person_name').isEmpty ||
              commissionRate == null || !commissionRate.isFinite ||
              commissionRate < 0 || commissionRate > 100) {
            throw const FormatException('اسم مندوب المبيعات ونسبة العمولة يجب أن تكون بين 0 و100.');
          }
          break;
        case 'Warehouse':
          if (requiredValue('warehouse_name').isEmpty || requiredValue('company').isEmpty) {
            throw const FormatException('اسم المستودع والشركة حقول مطلوبة.');
          }
          break;
        case 'Item Group':
          if (requiredValue('item_group_name').isEmpty) throw const FormatException('اسم مجموعة الأصناف مطلوب.');
          break;
        case 'UOM':
          if (requiredValue('uom_name').isEmpty) throw const FormatException('اسم وحدة القياس مطلوب.');
          break;
        case 'Supplier Group':
          if (requiredValue('supplier_group_name').isEmpty) throw const FormatException('اسم مجموعة الموردين مطلوب.');
          break;
        case 'Price List':
          if (requiredValue('price_list_name').isEmpty || requiredValue('currency').isEmpty) {
            throw const FormatException('اسم قائمة الأسعار والعملة حقول مطلوبة.');
          }
          if (payload['selling'] != true && payload['buying'] != true) {
            throw const FormatException('حدد استخدام القائمة للمبيعات أو المشتريات على الأقل.');
          }
          break;
      }
      final id = name?.trim();
      if (id != null && id.isNotEmpty) {
        // Preserve autoname/identity fields across all supported master doctypes.
        const identityFields = {'item_code', 'warehouse_name', 'item_group_name', 'uom_name', 'supplier_group_name', 'customer_group_name', 'territory_name', 'sales_person_name', 'price_list_name'};
        payload.removeWhere((key, value) => identityFields.contains(key));
        final current = await fetchMasterDataDocument(doctype: doctype, name: id);
        if (current['name'] != id) throw const FormatException('تغير السجل؛ أعد تحميله قبل التعديل.');
      }
      final path = '/api/resource/${Uri.encodeComponent(doctype)}'
          '${id == null || id.isEmpty ? '' : '/${Uri.encodeComponent(id)}'}';
      final response = await _sendJson(id == null || id.isEmpty ? 'POST' : 'PUT', path, payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ السجل. راجع الحقول المطلوبة وصلاحيات ERPNext.'));
      }
      final saved = data['data'];
      if (saved is! core.Map<String, dynamic> || (saved['name']?.toString().isNotEmpty != true)) {
        throw Exception('لم يؤكد ERPNext حفظ السجل؛ أعد تحميل القائمة قبل المتابعة.');
      }
      if (id != null && id.isNotEmpty && saved['name'] != id) {
        throw Exception('تغيرت هوية السجل بعد الحفظ؛ أوقف العملية وراجع ERPNext.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

}
