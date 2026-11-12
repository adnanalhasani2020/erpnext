// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin InventoryApiMixin on _FrappeApiCore {
  void _validateSerialBatchRows(List<dynamic> items) {
      final seenSerials = <String>{};
      final seenCurrentSerials = <String>{};
      for (final raw in items) {
        if (raw is! core.Map<String, dynamic>) throw const FormatException('بيانات بند الصنف المتتبع غير صحيحة.');
        final serialText = raw['serial_no']?.toString() ?? '';
        final batch = raw['batch_no']?.toString().trim() ?? '';
        final useFields = raw['use_serial_batch_fields'] == 1 || raw['use_serial_batch_fields'] == true;
        if (!useFields && serialText.trim().isEmpty && batch.isEmpty) continue;
        final qty = raw['qty'];
        final currentQty = raw['current_qty'];
        final currentSerialText = raw['current_serial_no']?.toString() ?? '';
        final currentSerials = currentSerialText.split(RegExp(r'[\r\n,;]+')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
        if (qty is! num || !qty.isFinite || qty < 0) throw const FormatException('كمية الصنف المتتبع غير صحيحة.');
        if (currentQty != null && (currentQty is! num || !currentQty.isFinite || currentQty < 0)) {
          throw const FormatException('الكمية الحالية للصنف المتتبع غير صحيحة.');
        }
        if (currentSerials.isNotEmpty &&
            (currentQty is! num || (currentQty - currentQty.round()).abs() > 0.000001 ||
                currentSerials.length != currentQty.round())) {
          throw const FormatException('عدد الأرقام التسلسلية الحالية لا يطابق الرصيد الحالي.');
        }
        for (final serial in currentSerials) {
          if (!seenCurrentSerials.add(serial)) {
            throw FormatException('الرقم التسلسلي الحالي مكرر داخل تسوية الجرد: ' + serial);
          }
        }
        if (qty == 0) {
          if (currentQty is! num || currentQty <= 0 ||
              (currentSerials.isEmpty && batch.isEmpty) || serialText.trim().isNotEmpty) {
            throw const FormatException('تسوية الصنف المتتبع إلى صفر تتطلب لقطة صحيحة للأرقام أو الدفعة الحالية.');
          }
          continue;
        }
        final serials = serialText.split(RegExp(r'[\r\n,;]+')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
        if (serials.isNotEmpty) {
          final rounded = qty.round();
          if ((qty - rounded).abs() > 0.000001 || serials.length != rounded) throw const FormatException('عدد الأرقام التسلسلية يجب أن يساوي كمية الصنف الصحيحة.');
          for (final serial in serials) {
            if (!seenSerials.add(serial)) throw FormatException('الرقم التسلسلي مكرر داخل المستند: ' + serial);
          }
        }
        if (serials.isEmpty && batch.isEmpty) throw const FormatException('أدخل رقماً تسلسلياً أو رقم دفعة للصنف المتتبع.');
      }
    }

  List<core.Map<String, dynamic>> _cleanSerialBatchRows(List<dynamic> items) {
      _validateSerialBatchRows(items);
      return items.whereType<core.Map<String, dynamic>>().map((row) => core.Map<String, dynamic>.from(row)
        ..remove('expiry_date')
        ..remove('manufacturing_date')).toList(growable: false);
    }

  Future<void> _ensureIncomingBatchNumbers(List<dynamic> items) async {
      final seen = <String>{};
      final seenExpiry = <String, String>{};
      for (final raw in items) {
        if (raw is! core.Map<String, dynamic>) continue;
        final batchNo = raw['batch_no']?.toString().trim() ?? '';
        if (batchNo.isEmpty) continue;
        final itemCode = raw['item_code']?.toString().trim() ?? '';
        if (itemCode.isEmpty) {
          throw const FormatException('رمز الصنف مطلوب لإنشاء الدفعة.');
        }
        final key = '$itemCode|$batchNo';
        final expiryDate = raw['expiry_date']?.toString().trim() ?? '';
        if (expiryDate.isNotEmpty) {
          final parsed = DateTime.tryParse(expiryDate);
          final canonical = RegExp(r'^\d{4}-\d{2}-\d{2}$');
          if (parsed == null || !canonical.hasMatch(expiryDate) ||
              parsed.toIso8601String().substring(0, 10) != expiryDate) {
            throw FormatException('تاريخ انتهاء الدفعة $batchNo غير صحيح. استخدم YYYY-MM-DD.');
          }
        }
        if (!seen.add(key)) {
          final previousExpiry = seenExpiry[key] ?? '';
          if (previousExpiry != expiryDate) {
            throw FormatException('توجد بيانات انتهاء متعارضة للدفعة $batchNo.');
          }
          continue;
        }
        seenExpiry[key] = expiryDate;
  
        Future<core.Map<String, dynamic>?> readBatch() async {
          final uri = Uri.parse(
            '$_baseUrl/api/resource/Batch/' + Uri.encodeComponent(batchNo),
          );
          final response = await _sendUri('GET', uri);
          if (response.statusCode == 404) return null;
          final data = _decode(response.body);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception(_message(
              data,
              'تعذر التحقق من سجل الدفعة $batchNo. تحقق من صلاحية قراءة Batch.',
            ));
          }
          final batch = data['data'];
          if (batch is! core.Map<String, dynamic>) {
            throw Exception('استجابة سجل الدفعة غير صحيحة: $batchNo');
          }
          return batch;
        }
  
        void validateExisting(core.Map<String, dynamic> batch) {
          if (batch['item'] != itemCode) {
            throw FormatException('رقم الدفعة $batchNo مسجل لصنف آخر.');
          }
          if (batch['disabled'] == 1 || batch['disabled'] == true) {
            throw FormatException('الدفعة $batchNo معطلة ولا يمكن استخدامها.');
          }
          if (expiryDate.isNotEmpty) {
            final existingExpiry = batch['expiry_date']?.toString().trim() ?? '';
            final normalizedExisting = existingExpiry.length >= 10
                ? existingExpiry.substring(0, 10)
                : existingExpiry;
            if (normalizedExisting != expiryDate) {
              final shownExpiry = existingExpiry.isEmpty ? 'غير محدد' : existingExpiry;
              throw FormatException(
                'تاريخ انتهاء الدفعة $batchNo لا يطابق التاريخ المسجل في ERPNext ($shownExpiry).',
              );
            }
          }
        }
  
        final existing = await readBatch();
        if (existing != null) {
          validateExisting(existing);
          continue;
        }
  
        final itemUri = Uri.parse(
          '$_baseUrl/api/resource/Item/' + Uri.encodeComponent(itemCode),
        ).replace(queryParameters: {
          'fields': jsonEncode(['item_code', 'has_batch_no', 'has_expiry_date']),
        });
        final itemResponse = await _sendUri('GET', itemUri);
        final itemData = _decode(itemResponse.body);
        if (itemResponse.statusCode < 200 || itemResponse.statusCode >= 300 ||
            itemData['data'] is! core.Map<String, dynamic>) {
          throw Exception(_message(
            itemData,
            'تعذر قراءة إعدادات الصنف قبل إنشاء الدفعة.',
          ));
        }
        final item = itemData['data'] as core.Map<String, dynamic>;
        if (item['has_batch_no'] != 1 && item['has_batch_no'] != true) {
          throw FormatException('الصنف $itemCode غير مفعّل لتتبع الدفعات.');
        }
        final requiresExpiry =
            item['has_expiry_date'] == 1 || item['has_expiry_date'] == true;
        if (requiresExpiry && expiryDate.isEmpty) {
          throw FormatException(
            'أدخل تاريخ انتهاء صحيحاً للدفعة $batchNo بصيغة YYYY-MM-DD.',
          );
        }
  
        final payload = <String, dynamic>{
          'doctype': 'Batch',
          'batch_id': batchNo,
          'item': itemCode,
          if (expiryDate.isNotEmpty) 'expiry_date': expiryDate,
        };
        final createdResponse = await _sendJson(
          'POST',
          '/api/resource/Batch',
          payload,
        );
        final createdData = _decode(createdResponse.body);
        if (createdResponse.statusCode >= 200 &&
            createdResponse.statusCode < 300) {
          final created = createdData['data'];
          if (created is! core.Map<String, dynamic> ||
              created['name'] != batchNo ||
              created['item'] != itemCode) {
            throw Exception('لم يؤكد ERPNext إنشاء الدفعة $batchNo.');
          }
          continue;
        }
  
        // A concurrent request may have created the same batch after our read.
        final raced = await readBatch();
        if (raced != null) {
          validateExisting(raced);
          continue;
        }
        throw Exception(_message(
          createdData,
          'تعذر إنشاء الدفعة $batchNo. يحتاج المستخدم إلى صلاحية إنشاء Batch.',
        ));
      }
    }

  Future<List<core.Map<String, dynamic>>> fetchAvailableBatches({
      required String itemCode,
      required String warehouse,
      bool ignoreReservedStock = false,
      bool includeExpired = false,
    }) async {
      if (itemCode.trim().isEmpty || warehouse.trim().isEmpty) {
        throw const FormatException('حدد الصنف والمستودع لعرض الدفعات المتاحة.');
      }
      final uri = Uri.parse('$_baseUrl/api/method/erpnext.stock.doctype.batch.batch.get_batch_qty')
          .replace(queryParameters: {
        'item_code': itemCode.trim(),
        'warehouse': warehouse.trim(),
        if (ignoreReservedStock) 'ignore_reserved_stock': '1',
        if (includeExpired) 'for_stock_levels': '1',
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر جلب الدفعات المتاحة من ERPNext.'));
      }
      final message = data['message'];
      if (message is! List) throw Exception('استجابة الدفعات المتاحة من ERPNext غير متوقعة.');
      return message.whereType<core.Map<String, dynamic>>().map((row) => core.Map<String, dynamic>.from(row))
          .where((row) => row['batch_no'] is String &&
              (double.tryParse(row['qty']?.toString() ?? '') ?? 0) > 0)
          .toList(growable: false);
    }

  Future<List<String>> fetchAvailableSerialNumbers({
      required String itemCode,
      required String warehouse,
      required int quantity,
      List<String> batchNumbers = const [],
    }) async {
      final code = itemCode.trim(), location = warehouse.trim();
      if (code.isEmpty || location.isEmpty || quantity < 1 || quantity > 5000) {
        throw const FormatException('بيانات طلب الأرقام التسلسلية غير صحيحة؛ الحد الأعلى للطلب 5000 رقم.');
      }
      final selected = <String>[];
      final seen = <String>{};
      while (selected.length < quantity) {
        final remaining = quantity - selected.length;
        final chunkSize = remaining > 200 ? 200 : remaining;
        final response = await _sendJson(
          'POST',
          '/api/method/erpnext.stock.doctype.serial_no.serial_no.auto_fetch_serial_number',
          {
            'item_code': code,
            'warehouse': location,
            'qty': chunkSize,
            if (batchNumbers.isNotEmpty) 'batch_nos': jsonEncode(batchNumbers),
            if (selected.isNotEmpty) 'exclude_sr_nos': jsonEncode(selected),
          },
        );
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر جلب الأرقام التسلسلية المتاحة من ERPNext.'));
        }
        final message = data['message'];
        if (message is! List) {
          throw const FormatException('استجابة الأرقام التسلسلية من ERPNext غير متوقعة.');
        }
        final page = message.whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty && seen.add(value))
            .toList(growable: false);
        if (page.isEmpty) break;
        selected.addAll(page);
        if (page.length < chunkSize) break;
      }
      return selected;
    }

  Future<List<ErpWarehouse>> fetchWarehouses({int start = 0, String? search}) async {
      final query = search?.trim();
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Warehouse',
        fields: ['name', 'warehouse_name', 'company', 'is_group'],
        filters: [['disabled', '=', 0], ['is_group', '=', 0]],
        orFilters: query == null || query.isEmpty
            ? null
            : [
                ['name', 'like', '%$query%'],
                ['warehouse_name', 'like', '%$query%'],
                ['company', 'like', '%$query%'],
              ],
        orderBy: 'warehouse_name asc, name asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر جلب المستودعات. تحقق من صلاحية قراءة Warehouse.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة المستودعات من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map(ErpWarehouse.fromJson).toList(growable: false);
    }

  Future<List<ErpStockBalance>> fetchStockBalances({int start = 0, String? search, String? warehouse}) async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Bin',
        fields: ['item_code', 'warehouse', 'actual_qty', 'reserved_qty', 'projected_qty', 'stock_uom', 'valuation_rate', 'stock_value'],
        filters: [
          if (warehouse != null && warehouse.trim().isNotEmpty) ['warehouse', '=', warehouse.trim()],
          if (search != null && search.trim().isNotEmpty) ['item_code', 'like', '%${search.trim()}%'],
        ],
        orFilters: [
          ['actual_qty', '!=', 0],
          ['reserved_qty', '!=', 0],
          ['projected_qty', '!=', 0],
        ],
        orderBy: 'item_code asc, warehouse asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر جلب أرصدة المخزون. تحقق من صلاحية قراءة Bin.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة أرصدة المخزون من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map(ErpStockBalance.fromJson).toList(growable: false);
    }

  Future<List<ErpStockReorderAlert>> fetchStockReorderAlerts() async {
      const maxRules = 10000;
      final rules = <core.Map<String, dynamic>>[];
      var start = 0;
      while (true) {
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Item Reorder',
          fields: const [
            'name', 'parent', 'parenttype', 'parentfield', 'warehouse_group',
            'warehouse', 'warehouse_reorder_level', 'warehouse_reorder_qty',
          ],
          filters: const [
            ['parenttype', '=', 'Item'],
            ['parentfield', '=', 'reorder_levels'],
          ],
          orderBy: 'parent asc, warehouse asc',
          start: start,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل حدود إعادة الطلب. تحقق من صلاحية قراءة Item Reorder.'));
        }
        final page = data['data'];
        if (page is! List) throw Exception('استجابة حدود إعادة الطلب غير متوقعة.');
        rules.addAll(page.whereType<core.Map<String, dynamic>>());
        if (rules.length > maxRules) {
          throw const FormatException('عدد قواعد إعادة الطلب تجاوز 10000؛ راجع نطاق البيانات أو صلاحيات المستخدم.');
        }
        if (page.length < FrappeApi.pageSize) break;
        start += page.length;
      }
      final supportedRules = rules.where((rule) {
        final group = rule['warehouse_group'];
        return rule['parent'] is String &&
            (rule['parent'] as String).isNotEmpty &&
            rule['warehouse'] is String &&
            (rule['warehouse'] as String).isNotEmpty &&
            (group == null || group.toString().trim().isEmpty);
      }).toList(growable: false);
      if (supportedRules.isEmpty) return const [];
  
      final itemCodes = supportedRules.map((rule) => rule['parent'] as String).toSet().toList();
      final warehouses = supportedRules.map((rule) => rule['warehouse'] as String).toSet().toList();
      final bins = <core.Map<String, dynamic>>[];
      var binStart = 0;
      while (true) {
        final uri = FrappeApi.buildResourcePageUri(
          baseUrl: _baseUrl,
          resource: 'Bin',
          fields: const ['item_code', 'warehouse', 'actual_qty', 'projected_qty', 'stock_uom', 'company'],
          filters: [
            ['item_code', 'in', itemCodes],
            ['warehouse', 'in', warehouses],
          ],
          orderBy: 'item_code asc, warehouse asc',
          start: binStart,
        );
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل أرصدة الأصناف لفحص إعادة الطلب.'));
        }
        final page = data['data'];
        if (page is! List) throw Exception('استجابة أرصدة إعادة الطلب غير متوقعة.');
        bins.addAll(page.whereType<core.Map<String, dynamic>>());
        if (page.length < FrappeApi.pageSize) break;
        binStart += page.length;
      }
      final binByKey = <String, core.Map<String, dynamic>>{
        for (final bin in bins)
          if (bin['item_code'] is String && bin['warehouse'] is String)
            '${bin['item_code']}::${bin['warehouse']}': bin,
      };
      double number(dynamic value) {
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString() ?? '') ?? 0;
      }
      final alerts = <ErpStockReorderAlert>[];
      for (final rule in supportedRules) {
        final itemCode = rule['parent'] as String;
        final warehouse = rule['warehouse'] as String;
        final bin = binByKey['$itemCode::$warehouse'];
        final projected = number(bin?['projected_qty']);
        final level = number(rule['warehouse_reorder_level']);
        if (projected <= level) {
          alerts.add(ErpStockReorderAlert(
            itemCode: itemCode,
            warehouse: warehouse,
            actualQty: number(bin?['actual_qty']),
            projectedQty: projected,
            stockUom: bin?['stock_uom'] is String ? bin!['stock_uom'] as String : null,
            company: bin?['company'] is String ? bin!['company'] as String : null,
            reorderLevel: level,
            reorderQty: number(rule['warehouse_reorder_qty']),
          ));
        }
      }
      alerts.sort((a, b) => a.projectedQty.compareTo(b.projectedQty));
      return alerts;
    }

  Future<void> _validateWarehouseForCompany(String warehouseName, String company) async {
      final normalizedWarehouse = warehouseName.trim();
      final normalizedCompany = company.trim();
      if (normalizedWarehouse.isEmpty || normalizedCompany.isEmpty) {
        throw const FormatException('حدد مستودعاً وشركة صالحين.');
      }
      final response = await _send('GET',
        '/api/resource/Warehouse/' + Uri.encodeComponent(normalizedWarehouse),
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر التحقق من المستودع ' + normalizedWarehouse + '.'));
      }
      final warehouse = data['data'];
      if (warehouse is! core.Map<String, dynamic> ||
          warehouse['doctype'] != 'Warehouse' ||
          warehouse['name'] != normalizedWarehouse ||
          warehouse['company'] != normalizedCompany ||
          warehouse['is_group'] == 1 || warehouse['is_group'] == true ||
          warehouse['disabled'] == 1 || warehouse['disabled'] == true) {
        throw FormatException('المستودع ' + normalizedWarehouse + ' غير صالح أو لا يتبع الشركة ' + normalizedCompany + '. اختر مستودعاً فعّالاً تابعاً للشركة.');
      }
    }

  Future<void> _validateDocumentWarehouses(core.Map<String, dynamic> document) async {
      final company = document['company'];
      final items = document['items'];
      if (company is! String || company.trim().isEmpty || items is! List) return;
      final warehouses = <String>{};
      for (final row in items.whereType<core.Map<String, dynamic>>()) {
        final warehouse = row['warehouse'];
        if (warehouse is String && warehouse.trim().isNotEmpty) {
          warehouses.add(warehouse.trim());
        }
      }
      for (final warehouse in warehouses) {
        await _validateWarehouseForCompany(warehouse, company);
      }
    }

  Future<core.Map<String, dynamic>> createStockEntry({
      required String company, required String purpose, required List<core.Map<String, dynamic>> items,
      String? fromWarehouse, String? toWarehouse, String? remarks,
    }) async {
      const validPurposes = {'Material Receipt', 'Material Issue', 'Material Transfer'};
      if (company.trim().isEmpty || !validPurposes.contains(purpose) || items.isEmpty) {
        throw const FormatException('حدد الشركة ونوع الحركة وأضف صنفاً.');
      }
      if (purpose == 'Material Receipt' && (toWarehouse == null || toWarehouse.trim().isEmpty)) throw const FormatException('حدد مستودع الاستلام.');
      if (purpose == 'Material Issue' && (fromWarehouse == null || fromWarehouse.trim().isEmpty)) throw const FormatException('حدد مستودع الصرف.');
      if (purpose == 'Material Transfer' && ((fromWarehouse ?? '').isEmpty || (toWarehouse ?? '').isEmpty || fromWarehouse == toWarehouse)) {
        throw const FormatException('حدد مستودعَي تحويل مختلفين.');
      }
      _validateSerialBatchRows(items);
      if (purpose == 'Material Receipt') await _ensureIncomingBatchNumbers(items);
      for (final row in items) {
        if (row['item_code'] is! String || (row['item_code'] as String).trim().isEmpty ||
            row['qty'] is! num || !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0) {
          throw const FormatException('كل بند يحتاج صنفاً وكمية موجبة.');
        }
        if (purpose == 'Material Receipt' &&
            (row['valuation_rate'] is! num ||
                !(row['valuation_rate'] as num).isFinite ||
                (row['valuation_rate'] as num) <= 0)) {
          throw const FormatException('استلام المخزون يتطلب سعر تقييم أكبر من صفر لكل صنف.');
        }
        if (row.containsKey('valuation_rate') &&
            (row['valuation_rate'] is! num ||
                !(row['valuation_rate'] as num).isFinite ||
                (row['valuation_rate'] as num) < 0 ||
                !((row['qty'] as num) * (row['valuation_rate'] as num)).isFinite)) {
          throw const FormatException('سعر التقييم أو إجمالي قيمة البند غير صحيح.');
        }
      }
      for (final warehouse in {if (fromWarehouse != null) fromWarehouse, if (toWarehouse != null) toWarehouse}) {
        await _validateWarehouseForCompany(warehouse, company);
      }
      final cleanItems = _cleanSerialBatchRows(items);
      final payload = <String, dynamic>{
        'doctype': 'Stock Entry', 'company': company, 'purpose': purpose, 'stock_entry_type': purpose,
        if (fromWarehouse != null) 'from_warehouse': fromWarehouse,
        if (toWarehouse != null) 'to_warehouse': toWarehouse,
        if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
        'items': cleanItems.map((row) {
          final item = core.Map<String, dynamic>.from(row);
          final valuationRate = item.remove('valuation_rate');
          if (valuationRate != null && purpose == 'Material Receipt') {
            item['basic_rate'] = valuationRate;
          }
          if (purpose == 'Material Receipt' || purpose == 'Material Transfer') {
            item['t_warehouse'] = toWarehouse;
          }
          if (purpose == 'Material Issue' || purpose == 'Material Transfer') {
            item['s_warehouse'] = fromWarehouse;
          }
          return item;
        }).toList(),
      };
      final response = await _sendJson('POST', '/api/resource/Stock%20Entry', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء حركة المخزون.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Stock Entry' ||
          created['name'] is! String ||
          created['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة حركة المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
      }
      return created;
    }

  Future<core.Map<String, dynamic>> createPurchaseReceipt(core.Map<String, dynamic> document) async {
      final items = document['items'];
      if (document['doctype'] != 'Purchase Receipt' ||
          document['company'] is! String || (document['company'] as String).trim().isEmpty ||
          document['supplier'] is! String || (document['supplier'] as String).trim().isEmpty ||
          items is! List || items.isEmpty) {
        throw const FormatException('حدد الشركة والمورد وأضف صنفاً لاستلام البضائع.');
      }
      await _ensureIncomingBatchNumbers(items);
      document['items'] = _cleanSerialBatchRows(items);
      for (final row in items) {
        if (row is! core.Map<String, dynamic> || row['item_code'] is! String ||
            (row['item_code'] as String).trim().isEmpty || row['qty'] is! num ||
            !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
            row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
            !((row['qty'] as num) * (row['rate'] as num)).isFinite ||
            row['warehouse'] is! String || (row['warehouse'] as String).trim().isEmpty) {
          throw const FormatException('بيانات استلام البضائع غير مكتملة: الصنف والكمية والسعر والمستودع مطلوبة.');
        }
      }
      // Revalidate purchase-order references against the latest server document
      // immediately before creating the receipt; UI-side quantities may be stale.
      final orderNames = <String>{};
      final sourceRowsByOrder = <String, core.Map<String, core.Map<String, dynamic>>>{};
      for (final row in items) {
        final orderName = row is core.Map<String, dynamic> ? row['purchase_order'] : null;
        final orderItemName = row is core.Map<String, dynamic> ? row['purchase_order_item'] : null;
        if ((orderName == null) != (orderItemName == null)) {
          throw const FormatException('مرجع أمر الشراء وبند الأمر يجب أن يظهرا معاً في بند الاستلام.');
        }
        if (orderName == null) continue;
        if (orderName is! String || orderName.trim().isEmpty ||
            orderItemName is! String || orderItemName.trim().isEmpty) {
          throw const FormatException('مرجع أمر الشراء أو بند الأمر غير صحيح.');
        }
        final normalizedOrder = orderName.trim();
        final normalizedOrderItem = orderItemName.trim();
        orderNames.add(normalizedOrder);
        final byItem = sourceRowsByOrder.putIfAbsent(normalizedOrder, () => <String, core.Map<String, dynamic>>{});
        if (byItem.containsKey(normalizedOrderItem)) {
          throw const FormatException('لا تكرر بند أمر الشراء في سند الاستلام؛ اجمع الكمية في سطر واحد.');
        }
        byItem[normalizedOrderItem] = row;
      }
      for (final orderName in orderNames) {
        final order = await fetchPurchaseOrderDocument(orderName);
        if (order['company'] != document['company'] || order['supplier'] != document['supplier']) {
          throw FormatException('أمر الشراء ' + orderName + ' لا يطابق شركة أو مورد سند الاستلام.');
        }
        final sourceItems = order['items'];
        if (sourceItems is! List) throw FormatException('تعذر قراءة بنود أمر الشراء ' + orderName + '.');
        final sourceByName = <String, core.Map<String, dynamic>>{
          for (final source in sourceItems.whereType<core.Map<String, dynamic>>())
            if (source['name'] is String) source['name'].toString(): source,
        };
        for (final entry in sourceRowsByOrder[orderName]!.entries) {
          final source = sourceByName[entry.key];
          final receiptLine = entry.value;
          if (source == null || source['item_code'] != receiptLine['item_code']) {
            throw FormatException('بند الاستلام ' + entry.key + ' لا يطابق بنداً في أمر الشراء ' + orderName + '.');
          }
          final ordered = double.tryParse(source['qty']?.toString() ?? '') ?? 0;
          final received = double.tryParse(source['received_qty']?.toString() ?? '') ?? 0;
          final remaining = ordered - received;
          final requested = (receiptLine['qty'] as num).toDouble();
          if (!remaining.isFinite || remaining <= 0.000001 || requested > remaining + 0.000001) {
            throw FormatException('كمية الصنف ' + receiptLine['item_code'].toString() + ' تجاوزت المتبقي في أمر الشراء ' + orderName + ' (' + remaining.toStringAsFixed(3) + '). حدّث الأمر قبل إنشاء سند الاستلام.');
          }
        }
      }
      final receiptWarehouses = items.map((row) => (row as core.Map<String, dynamic>)['warehouse'].toString()).toSet();
      for (final warehouse in receiptWarehouses) {
        await _validateWarehouseForCompany(warehouse, document['company'] as String);
      }
      final response = await _sendJson('POST', '/api/resource/Purchase%20Receipt', document);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء سند استلام المشتريات.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Purchase Receipt' ||
          created['name'] is! String ||
          created['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة سند استلام المشتريات؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
      }
      return created;
    }

  Future<core.Map<String, dynamic>> submitPurchaseReceipt(core.Map<String, dynamic> doc) =>
        _submitMobileDocument(doc, 'Purchase Receipt');

  Future<core.Map<String, dynamic>> submitStockEntry(core.Map<String, dynamic> doc) => _submitMobileDocument(doc, 'Stock Entry');

  Future<core.Map<String, dynamic>> createStockReconciliation({
      required String company, required String warehouse, required List<core.Map<String, dynamic>> items, String? remarks,
    }) async {
      if (company.trim().isEmpty || warehouse.trim().isEmpty || items.isEmpty) throw const FormatException('حدد الشركة والمستودع وأصناف الجرد.');
      _validateSerialBatchRows(items);
      await _ensureIncomingBatchNumbers(items);
      final seen = <String>{};
      for (final row in items) {
        final code = row['item_code'];
        final qty = row['qty'];
        final batchNo = row['batch_no']?.toString().trim() ?? '';
        final usesTracking = row['use_serial_batch_fields'] == 1 ||
            row['use_serial_batch_fields'] == true || batchNo.isNotEmpty ||
            (row['serial_no']?.toString().trim().isNotEmpty ?? false);
        if (usesTracking && (row['current_qty'] is! num ||
            !(row['current_qty'] as num).isFinite || (row['current_qty'] as num) < 0)) {
          throw const FormatException('يجب تحميل الكمية الحالية للصنف المتتبع قبل تسوية الجرد.');
        }
        final uniqueKey = code is String ? code + '|' + batchNo : '';
        if (code is! String || code.trim().isEmpty || !seen.add(uniqueKey) || qty is! num || !qty.isFinite || qty < 0) {
          throw const FormatException('أصناف الجرد يجب أن تكون غير مكررة وكمياتها صفر أو أكثر.');
        }
        if (row.containsKey('valuation_rate') &&
            (row['valuation_rate'] is! num ||
                !(row['valuation_rate'] as num).isFinite ||
                (row['valuation_rate'] as num) < 0 ||
                !(qty * (row['valuation_rate'] as num)).isFinite)) {
          throw const FormatException('سعر تقييم بند الجرد أو إجمالي قيمته غير صحيح.');
        }
      }
      await _validateWarehouseForCompany(warehouse, company);
      final payload = <String, dynamic>{
        'doctype': 'Stock Reconciliation', 'company': company, 'purpose': 'Stock Reconciliation',
        'items': _cleanSerialBatchRows(items).map((row) => <String, dynamic>{...row, 'warehouse': warehouse}).toList(),
        if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
      };
      final response = await _sendJson('POST', '/api/resource/Stock%20Reconciliation', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء تسوية المخزون.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Stock Reconciliation' ||
          created['name'] is! String ||
          created['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة تسوية المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
      }
      return created;
    }

  Future<core.Map<String, dynamic>> submitStockReconciliation(core.Map<String, dynamic> doc) =>
        _submitMobileDocument(doc, 'Stock Reconciliation');

  Future<List<core.Map<String, dynamic>>> fetchDraftStockDocuments(String doctype, {int start = 0}) async {
      const allowed = {'Stock Entry', 'Purchase Receipt', 'Stock Reconciliation'};
      if (!allowed.contains(doctype)) throw ArgumentError.value(doctype, 'doctype', 'نوع مستند المخزون غير مدعوم.');
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: doctype,
        fields: const ['name', 'docstatus', 'posting_date', 'company'],
        filters: const [['docstatus', '=', 0]],
        orderBy: 'modified desc, name desc', start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل مسودات ' + doctype + '.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة مسودات ' + doctype + ' غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map((row) => <String, dynamic>{...row, 'doctype': doctype}).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchBatchTraceRecords({int start = 0, String? search, String? itemCode}) async {
      final query = search?.trim();
      final uri = FrappeApi.buildResourcePageUri(baseUrl: _baseUrl, resource: 'Batch',
        fields: const ['name', 'batch_id', 'item', 'expiry_date', 'manufacturing_date', 'disabled', 'creation', 'modified'],
        filters: [if (itemCode != null && itemCode.trim().isNotEmpty) ['item', '=', itemCode.trim()]],
        orFilters: query == null || query.isEmpty ? null : [
          ['name', 'like', '%$query%'], ['batch_id', 'like', '%$query%'], ['item', 'like', '%$query%'],
        ], orderBy: 'modified desc, name desc', start: start);
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل سجل الدفعات.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة سجل الدفعات غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchSerialTraceRecords({int start = 0, String? search, String? itemCode}) async {
      final query = search?.trim();
      final uri = FrappeApi.buildResourcePageUri(baseUrl: _baseUrl, resource: 'Serial No',
        fields: const ['name', 'item_code', 'warehouse', 'batch_no', 'status', 'purchase_document_no', 'delivery_document_no', 'purchase_date', 'delivery_date', 'creation', 'modified'],
        filters: [if (itemCode != null && itemCode.trim().isNotEmpty) ['item_code', '=', itemCode.trim()]],
        orFilters: query == null || query.isEmpty ? null : [
          ['name', 'like', '%$query%'], ['item_code', 'like', '%$query%'], ['batch_no', 'like', '%$query%'],
        ], orderBy: 'modified desc, name desc', start: start);
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل سجل الأرقام التسلسلية.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة سجل الأرقام التسلسلية غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> createPickListFromSalesOrder(String salesOrderName) async {
      final id = salesOrderName.trim();
      if (id.isEmpty) throw const FormatException('حدد أمر البيع أولاً.');
      final order = await fetchSalesWorkflowDocument('Sales Order', id);
      if (order['docstatus'] != 1) throw const FormatException('يمكن إنشاء قائمة الالتقاط من أمر بيع مرحّل فقط.');
      final locations = <core.Map<String, dynamic>>[];
      for (final row in (order['items'] as List? ?? []).whereType<core.Map<String, dynamic>>()) {
        final qty = double.tryParse(row['qty']?.toString() ?? '') ?? 0;
        final delivered = double.tryParse(row['delivered_qty']?.toString() ?? '') ?? 0;
        final remaining = qty - delivered;
        final itemCode = row['item_code']?.toString().trim() ?? '';
        final sourceRow = row['name']?.toString().trim() ?? '';
        if (remaining <= 0.000001) continue;
        if (itemCode.isEmpty || sourceRow.isEmpty || !remaining.isFinite) throw const FormatException('أمر البيع يحتوي بنداً لا يمكن ربطه بقائمة الالتقاط.');
        final factor = double.tryParse(row['conversion_factor']?.toString() ?? '') ?? 1;
        locations.add({'item_code': itemCode, 'qty': remaining, 'stock_qty': remaining * factor,
          'conversion_factor': factor, 'uom': row['uom'] ?? row['stock_uom'], 'sales_order': id,
          'sales_order_item': sourceRow, if (row['warehouse'] is String) 'warehouse': row['warehouse'], 'picked_qty': 0});
      }
      if (locations.isEmpty) throw const FormatException('لا توجد كميات متبقية للالتقاط في أمر البيع.');
      if (locations.length > 500) throw const FormatException('أمر البيع يتجاوز 500 بند؛ قسّمه إلى قوائم التقاط أصغر حتى تبقى مراجعة الكميات والتتبع موثوقة.');
      final payload = <String, dynamic>{'doctype': 'Pick List', 'company': order['company'],
        'customer': order['customer'], 'purpose': 'Delivery', 'items_based_on': 'Sales Order',
        'pick_manually': 1, 'locations': locations};
      final response = await _sendJson('POST', '/api/resource/Pick%20List', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء قائمة الالتقاط.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Pick List' || created['name'] is! String || created['docstatus'] != 0) throw Exception('لم يؤكد ERPNext إنشاء مسودة قائمة الالتقاط.');
      final allocated = await _sendJson('POST', '/api/method/run_doc_method', {
        'docs': jsonEncode(created), 'method': 'set_item_locations', 'args': {'save': true},
      });
      final allocatedData = _decode(allocated.body);
      if (allocated.statusCode < 200 || allocated.statusCode >= 300) throw Exception(_message(allocatedData, 'أُنشئت المسودة لكن تعذر توزيع مواقع الالتقاط. راجع المسودة قبل المتابعة.'));
      final docs = allocatedData['docs'];
      if (docs is! List || docs.isEmpty || docs.first is! core.Map<String, dynamic>) throw Exception('لم يؤكد ERPNext حفظ مواقع الالتقاط.');
      final saved = core.Map<String, dynamic>.from(docs.first as core.Map);
      if (saved['doctype'] != 'Pick List' || saved['name'] != created['name'] || saved['docstatus'] != 0 || saved['locations'] is! List || (saved['locations'] as List).isEmpty) throw Exception('لم يؤكد ERPNext اكتمال توزيع مواقع الالتقاط.');
      return saved;
    }

  Future<core.Map<String, dynamic>> saveStockPickList(String name, List<core.Map<String, dynamic>> locations) async {
      final id = name.trim();
      if (id.isEmpty || locations.isEmpty || locations.length > 500) throw const FormatException('قائمة الالتقاط فارغة أو تجاوزت الحد الآمن البالغ 500 بند.');
      final current = await fetchStockDocument('Pick List', id);
      if (current['docstatus'] != 0 || current['purpose'] != 'Delivery') throw const FormatException('يمكن تعديل قائمة الالتقاط غير المرحلة فقط.');
      for (final row in locations) {
        final item = row['item_code']?.toString().trim() ?? '';
        final warehouse = row['warehouse']?.toString().trim() ?? '';
        final requiredQty = double.tryParse((row['stock_qty'] ?? row['qty'] ?? '').toString());
        final pickedQty = double.tryParse((row['picked_qty'] ?? '').toString());
        if (item.isEmpty || warehouse.isEmpty || requiredQty == null || pickedQty == null || !requiredQty.isFinite || !pickedQty.isFinite || requiredQty < 0 || pickedQty < 0 || pickedQty > requiredQty + 0.000001) {
          throw const FormatException('تحقق من الصنف والمستودع والكمية المطلوبة والملتَقطة في كل بند.');
        }
      }
      final payload = core.Map<String, dynamic>.from(current)..['locations'] = locations;
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ كميات الالتقاط.'));
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Pick List' || saved['name'] != id || saved['docstatus'] != 0 || saved['locations'] is! List) throw Exception('لم يؤكد ERPNext حفظ قائمة الالتقاط؛ حدّث المستند قبل إعادة المحاولة.');
      return saved;
    }

  Future<core.Map<String, dynamic>> submitPickList(core.Map<String, dynamic> doc) => _submitMobileDocument(doc, 'Pick List');

  Future<List<core.Map<String, dynamic>>> createDeliveryNotesFromPickList(String pickListName) async {
      final id = pickListName.trim();
      if (id.isEmpty) throw const FormatException('رقم قائمة الالتقاط مطلوب.');
      final current = await fetchStockDocument('Pick List', id);
      if (current['docstatus'] != 1 || current['purpose'] != 'Delivery') throw const FormatException('يجب ترحيل قائمة التقاط تسليم قبل إنشاء أذونات التسليم.');
      final response = await _sendJson('POST', '/api/method/erpnext.stock.doctype.pick_list.mapper.create_delivery_note', {'source_name': id});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تم ترحيل قائمة الالتقاط لكن تعذر إنشاء إذن التسليم. راجع القائمة قبل إعادة المحاولة.'));
      final message = data['message'];
      final candidates = message is List ? message : message is core.Map ? [message] : const [];
      final notes = candidates.whereType<core.Map<String, dynamic>>().map((row) => core.Map<String, dynamic>.from(row))
        .where((row) => row['doctype'] == 'Delivery Note' && row['name'] is String).toList(growable: false);
      if (notes.isEmpty) throw Exception('لم يُرجع ERPNext أرقام أذونات تسليم مؤكدة. افحص المستندات المرتبطة بقائمة الالتقاط قبل إعادة المحاولة.');
      return notes;
    }

  Future<List<core.Map<String, dynamic>>> fetchBatchLedgerEntries(String batchNo, {int start = 0}) async {
      final batch = batchNo.trim();
      if (batch.isEmpty) throw const FormatException('أدخل رقم الدفعة.');
      final entryUri = FrappeApi.buildResourcePageUri(baseUrl: _baseUrl, resource: 'Serial and Batch Entry',
        fields: const ['parent', 'serial_no', 'batch_no', 'qty'],
        filters: [['batch_no', '=', batch], ['parenttype', '=', 'Serial and Batch Bundle']],
        orderBy: 'creation asc', start: start, pageLength: 500);
      final entryResponse = await _sendUri('GET', entryUri);
      final entryData = _decode(entryResponse.body);
      if (entryResponse.statusCode < 200 || entryResponse.statusCode >= 300) throw Exception(_message(entryData, 'تعذر تحميل قيود الدفعة.'));
      final entryRows = entryData['data'];
      if (entryRows is! List) throw Exception('استجابة قيود الدفعة غير متوقعة.');
      final entries = entryRows.whereType<core.Map<String, dynamic>>().toList(growable: false);
      final parents = entries.map((row) => row['parent']?.toString() ?? '').where((v) => v.isNotEmpty).toSet().toList(growable: false);
      if (parents.isEmpty) return const [];
      final bundleUri = FrappeApi.buildResourcePageUri(baseUrl: _baseUrl, resource: 'Serial and Batch Bundle',
        fields: const ['name', 'item_code', 'warehouse', 'type_of_transaction', 'voucher_type', 'voucher_no', 'posting_date', 'company', 'docstatus'],
        filters: [['name', 'in', parents]], orderBy: 'posting_date asc, creation asc', start: 0, pageLength: 500);
      final bundleResponse = await _sendUri('GET', bundleUri);
      final bundleData = _decode(bundleResponse.body);
      if (bundleResponse.statusCode < 200 || bundleResponse.statusCode >= 300) throw Exception(_message(bundleData, 'تعذر تحميل مستندات حركة الدفعة.'));
      final bundleRows = bundleData['data'];
      if (bundleRows is! List) throw Exception('استجابة مستندات حركة الدفعة غير متوقعة.');
      final byName = <String, core.Map<String, dynamic>>{
        for (final row in bundleRows.whereType<core.Map<String, dynamic>>()) row['name'].toString(): row,
      };
      return entries.map((entry) => <String, dynamic>{...entry, 'bundle': byName[entry['parent']?.toString()] ?? const <String, dynamic>{}}).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchSerialLedgerEntries(String serialNo, {int start = 0}) async {
      final serial = serialNo.trim();
      if (serial.isEmpty) throw const FormatException('أدخل الرقم التسلسلي.');
      final entryUri = FrappeApi.buildResourcePageUri(baseUrl: _baseUrl, resource: 'Serial and Batch Entry',
        fields: const ['parent', 'serial_no', 'batch_no', 'qty'],
        filters: [['serial_no', '=', serial], ['parenttype', '=', 'Serial and Batch Bundle']],
        orderBy: 'creation asc', start: start, pageLength: 500);
      final entryResponse = await _sendUri('GET', entryUri);
      final entryData = _decode(entryResponse.body);
      if (entryResponse.statusCode < 200 || entryResponse.statusCode >= 300) throw Exception(_message(entryData, 'تعذر تحميل قيود الرقم التسلسلي.'));
      final entryRows = entryData['data'];
      if (entryRows is! List) throw Exception('استجابة قيود الرقم التسلسلي غير متوقعة.');
      final entries = entryRows.whereType<core.Map<String, dynamic>>().toList(growable: false);
      final parents = entries.map((row) => row['parent']?.toString() ?? '').where((v) => v.isNotEmpty).toSet().toList(growable: false);
      if (parents.isEmpty) return const [];
      final bundleUri = FrappeApi.buildResourcePageUri(baseUrl: _baseUrl, resource: 'Serial and Batch Bundle',
        fields: const ['name', 'item_code', 'warehouse', 'type_of_transaction', 'voucher_type', 'voucher_no', 'posting_date', 'company', 'docstatus'],
        filters: [['name', 'in', parents]], orderBy: 'posting_date asc, creation asc', start: 0, pageLength: 500);
      final bundleResponse = await _sendUri('GET', bundleUri);
      final bundleData = _decode(bundleResponse.body);
      if (bundleResponse.statusCode < 200 || bundleResponse.statusCode >= 300) throw Exception(_message(bundleData, 'تعذر تحميل مستندات حركة الرقم التسلسلي.'));
      final bundleRows = bundleData['data'];
      if (bundleRows is! List) throw Exception('استجابة مستندات حركة الرقم التسلسلي غير متوقعة.');
      final byName = <String, core.Map<String, dynamic>>{
        for (final row in bundleRows.whereType<core.Map<String, dynamic>>()) row['name'].toString(): row,
      };
      return entries.map((entry) => <String, dynamic>{
        ...entry,
        'bundle': byName[entry['parent']?.toString()] ?? const <String, dynamic>{},
      }).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchStockDocument(String doctype, String name) async {
      const allowed = {'Stock Entry', 'Purchase Receipt', 'Stock Reconciliation', 'Pick List'};
      if (!allowed.contains(doctype) || name.trim().isEmpty) throw ArgumentError('نوع أو رقم مستند المخزون غير صحيح.');
      final response = await _send('GET', '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل مستند المخزون.'));
      final doc = data['data'];
      if (doc is! core.Map<String, dynamic>) throw Exception('تفاصيل مستند المخزون غير متوقعة.');
      return doc;
    }

  Future<List<core.Map<String, dynamic>>> fetchStockMovements({
      int start = 0,
      String? itemCode,
      String? warehouse,
      String? company,
      DateTime? fromDate,
      DateTime? toDate,
      String? batchNo,
    }) async {
      DateTime? dateOnly(DateTime? value) =>
          value == null ? null : DateTime(value.year, value.month, value.day);
      String dateString(DateTime value) =>
          '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  
      final from = dateOnly(fromDate);
      final to = dateOnly(toDate);
      if (from != null && to != null && from.isAfter(to)) {
        throw const FormatException('تاريخ بداية التقرير يجب ألا يتجاوز تاريخ نهايته.');
      }
  
      final filters = <List<dynamic>>[];
      if (itemCode != null && itemCode.trim().isNotEmpty) filters.add(['item_code', '=', itemCode.trim()]);
      if (warehouse != null && warehouse.trim().isNotEmpty) filters.add(['warehouse', '=', warehouse.trim()]);
      if (company != null && company.trim().isNotEmpty) filters.add(['company', '=', company.trim()]);
      if (from != null) filters.add(['posting_date', '>=', dateString(from)]);
      if (to != null) filters.add(['posting_date', '<=', dateString(to)]);
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Stock Ledger Entry',
        fields: const ['name', 'posting_date', 'posting_time', 'item_code', 'warehouse', 'actual_qty', 'qty_after_transaction', 'voucher_type', 'voucher_no', 'company', 'batch_no', 'serial_and_batch_bundle'],
        filters: [...filters, if (batchNo != null && batchNo.trim().isNotEmpty) ['batch_no', '=', batchNo.trim()]], orderBy: 'posting_date desc, posting_time desc, creation desc', start: start);
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل سجل حركات المخزون.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة سجل الحركات غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
    }
  Future<core.Map<String, dynamic>> createStockEntryDraftFromItemDashboard({
    required String itemCode,
    String? sourceWarehouse,
    String? targetWarehouse,
    String? stockEntryType,
    double? qty,
    double? rate,
  }) async {
    final item = itemCode.trim();
    if (item.isEmpty) throw const FormatException('حدد الصنف لإنشاء حركة المخزون.');
    if (sourceWarehouse != null && sourceWarehouse.trim().isEmpty) sourceWarehouse = null;
    if (targetWarehouse != null && targetWarehouse.trim().isEmpty) targetWarehouse = null;
    if (sourceWarehouse != null && targetWarehouse != null && sourceWarehouse == targetWarehouse) {
      throw const FormatException('مستودع المصدر والهدف يجب أن يكونا مختلفين.');
    }
    if (qty != null && (!qty.isFinite || qty < 0)) {
      throw const FormatException('كمية حركة المخزون غير صحيحة.');
    }
    if (rate != null && (!rate.isFinite || rate < 0)) {
      throw const FormatException('معدل التقييم غير صحيح.');
    }
    final args = <String, dynamic>{
      'item_code': item,
      if (sourceWarehouse != null) 'source_warehouse': sourceWarehouse,
      if (targetWarehouse != null) 'target_warehouse': targetWarehouse,
      if (stockEntryType != null && stockEntryType.trim().isNotEmpty) 'stock_entry_type': stockEntryType.trim(),
      if (qty != null) 'qty': qty,
      if (rate != null) 'rate': rate,
    };
    final generation = _sessionGeneration;
    final response = await _sendJson(
      'POST',
      '/api/method/erpnext.stock.dashboard.item_dashboard.make_stock_entry',
      args,
    );
    if (generation != _sessionGeneration) {
      throw Exception('تغيرت جلسة ERPNext أثناء تجهيز حركة المخزون.');
    }
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تجهيز حركة المخزون من ERPNext.'));
    }
    final document = data['message'];
    if (document is! core.Map) {
      throw const FormatException('ERPNext لم يُرجع مسودة Stock Entry صالحة.');
    }
    final draft = core.Map<String, dynamic>.from(document);
    if (draft['doctype']?.toString() != 'Stock Entry' || draft['company'] == null ||
        draft['items'] is! List || (draft['items'] as List).isEmpty) {
      throw const FormatException('مسودة Stock Entry التي أعادها ERPNext غير مكتملة.');
    }
    return draft;
  }

  Future<List<core.Map<String, dynamic>>> fetchStockSummary({
    String? itemCode,
    String? warehouse,
    String? itemGroup,
    int start = 0,
    String sortBy = 'projected_qty',
    String sortOrder = 'asc',
  }) async {
    const allowedSorts = {
      'projected_qty', 'reserved_qty', 'reserved_qty_for_production',
      'reserved_qty_for_sub_contract', 'reserved_qty_for_production_plan',
      'reserved_stock', 'ordered_qty', 'indented_qty', 'planned_qty', 'actual_qty',
    };
    if (!allowedSorts.contains(sortBy) || !{'asc', 'desc'}.contains(sortOrder) || start < 0) {
      throw const FormatException('خيارات ترتيب ملخص المخزون غير صحيحة.');
    }
    final generation = _sessionGeneration;
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.stock.dashboard.item_dashboard.get_data')
        .replace(queryParameters: {
      if (itemCode?.trim().isNotEmpty == true) 'item_code': itemCode!.trim(),
      if (warehouse?.trim().isNotEmpty == true) 'warehouse': warehouse!.trim(),
      if (itemGroup?.trim().isNotEmpty == true) 'item_group': itemGroup!.trim(),
      'start': '$start',
      'sort_by': sortBy,
      'sort_order': sortOrder,
    });
    final response = await _sendUri('GET', uri);
    if (generation != _sessionGeneration) {
      throw const HttpException('تغيرت جلسة ERPNext أثناء تحميل ملخص المخزون.');
    }
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل ملخص المخزون من ERPNext.'));
    }
    final rows = data['message'];
    if (rows is! List) throw const FormatException('استجابة ملخص المخزون غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchWarehouseCapacitySummary({
    required String company,
    String? warehouse,
    String? itemCode,
    String? parentWarehouse,
    int start = 0,
    String sortBy = 'stock_capacity',
    String sortOrder = 'desc',
  }) async {
    const allowedSorts = {'stock_capacity', 'actual_qty', 'percent_occupied'};
    if (company.trim().isEmpty || !allowedSorts.contains(sortBy) ||
        !{'asc', 'desc'}.contains(sortOrder) || start < 0) {
      throw const FormatException('حدد الشركة وتحقق من خيارات ترتيب سعة المستودعات.');
    }
    final generation = _sessionGeneration;
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.stock.dashboard.warehouse_capacity_dashboard.get_data')
        .replace(queryParameters: {
      'company': company.trim(),
      if (warehouse?.trim().isNotEmpty == true) 'warehouse': warehouse!.trim(),
      if (itemCode?.trim().isNotEmpty == true) 'item_code': itemCode!.trim(),
      if (parentWarehouse?.trim().isNotEmpty == true) 'parent_warehouse': parentWarehouse!.trim(),
      'start': '$start',
      'sort_by': sortBy,
      'sort_order': sortOrder,
    });
    final response = await _sendUri('GET', uri);
    if (generation != _sessionGeneration) {
      throw const HttpException('تغيرت جلسة ERPNext أثناء تحميل سعة المستودعات.');
    }
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل سعة المستودعات من ERPNext.'));
    }
    final rows = data['message'];
    if (rows is! List) throw const FormatException('استجابة سعة المستودعات غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

}
