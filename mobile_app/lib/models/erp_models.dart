class ErpInvoiceLine {
  const ErpInvoiceLine({required this.itemCode, required this.itemName, required this.qty, required this.rate, required this.amount, this.uom, this.warehouse});
  final String itemCode;
  final String itemName;
  final double qty;
  final double rate;
  final double amount;
  final String? uom;
  final String? warehouse;
  factory ErpInvoiceLine.fromJson(Map<String, dynamic> json) {
    final code = json['item_code'];
    final name = json['item_name'];
    if (code is! String || code.isEmpty || name is! String || name.isEmpty) throw const FormatException('بيانات بند الفاتورة الأساسية ناقصة.');
    double number(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }
    return ErpInvoiceLine(itemCode: code, itemName: name, qty: number(json['qty']), rate: number(json['rate']), amount: number(json['amount']),
      uom: json['uom'] is String ? json['uom'] as String : null,
      warehouse: json['warehouse'] is String ? json['warehouse'] as String : null);
  }
}
class ErpSupplier {
  const ErpSupplier({required this.id, required this.name, this.group, this.type});
  final String id;
  final String name;
  final String? group;
  final String? type;
  factory ErpSupplier.fromJson(Map<String, dynamic> json) {
    final id = json['name'];
    final name = json['supplier_name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) throw const FormatException('بيانات المورد الأساسية ناقصة.');
    return ErpSupplier(id: id, name: name,
      group: json['supplier_group'] is String ? json['supplier_group'] as String : null,
      type: json['supplier_type'] is String ? json['supplier_type'] as String : null);
  }
}

class ErpPurchaseInvoice {
  const ErpPurchaseInvoice({required this.id, required this.supplier, required this.supplierName, this.postingDate, this.dueDate, this.currency, required this.grandTotal, required this.outstandingAmount, this.status, this.isReturn = false, this.returnAgainst});
  final String id;
  final String supplier;
  final String supplierName;
  final String? postingDate;
  final String? dueDate;
  final String? currency;
  final double grandTotal;
  final double outstandingAmount;
  final String? status;
  final bool isReturn;
  final String? returnAgainst;
  factory ErpPurchaseInvoice.fromJson(Map<String, dynamic> json) {
    final id = json['name'];
    final supplier = json['supplier'];
    final supplierName = json['supplier_name'];
    if (id is! String || id.isEmpty || supplier is! String || supplier.isEmpty || supplierName is! String || supplierName.isEmpty) throw const FormatException('بيانات فاتورة المشتريات الأساسية ناقصة.');
    double amount(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }
    return ErpPurchaseInvoice(id: id, supplier: supplier, supplierName: supplierName,
      postingDate: json['posting_date'] is String ? json['posting_date'] as String : null,
      dueDate: json['due_date'] is String ? json['due_date'] as String : null,
      currency: json['currency'] is String ? json['currency'] as String : null,
      grandTotal: amount(json['grand_total']), outstandingAmount: amount(json['outstanding_amount']),
      status: json['status'] is String ? json['status'] as String : null,
      isReturn: json['is_return'] == 1 || json['is_return'] == true,
      returnAgainst: json['return_against'] is String ? json['return_against'] as String : null);
  }
}
class ErpCustomer {
  const ErpCustomer({required this.id, required this.name, this.type, this.group, this.territory});
  final String id;
  final String name;
  final String? type;
  final String? group;
  final String? territory;
  factory ErpCustomer.fromJson(Map<String, dynamic> json) {
    final id = json['name'];
    final name = json['customer_name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('بيانات العميل الأساسية ناقصة.');
    }
    return ErpCustomer(id: id, name: name,
      type: json['customer_type'] is String ? json['customer_type'] as String : null,
      group: json['customer_group'] is String ? json['customer_group'] as String : null,
      territory: json['territory'] is String ? json['territory'] as String : null);
  }
}

class ErpSalesInvoice {
  const ErpSalesInvoice({required this.id, required this.customer, required this.customerName, this.postingDate, this.dueDate, this.currency, required this.grandTotal, required this.outstandingAmount, this.status, this.isReturn = false, this.returnAgainst});
  final String id;
  final String customer;
  final String customerName;
  final String? postingDate;
  final String? dueDate;
  final String? currency;
  final double grandTotal;
  final double outstandingAmount;
  final String? status;
  final bool isReturn;
  final String? returnAgainst;
  factory ErpSalesInvoice.fromJson(Map<String, dynamic> json) {
    final id = json['name'];
    final customer = json['customer'];
    final customerName = json['customer_name'];
    if (id is! String || id.isEmpty || customer is! String || customer.isEmpty || customerName is! String || customerName.isEmpty) {
      throw const FormatException('بيانات فاتورة المبيعات الأساسية ناقصة.');
    }
    double amount(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }
    return ErpSalesInvoice(id: id, customer: customer, customerName: customerName,
      postingDate: json['posting_date'] is String ? json['posting_date'] as String : null,
      dueDate: json['due_date'] is String ? json['due_date'] as String : null,
      currency: json['currency'] is String ? json['currency'] as String : null,
      grandTotal: amount(json['grand_total']), outstandingAmount: amount(json['outstanding_amount']),
      status: json['status'] is String ? json['status'] as String : null,
      isReturn: json['is_return'] == 1 || json['is_return'] == true,
      returnAgainst: json['return_against'] is String ? json['return_against'] as String : null);
  }
}
class ErpCompany {
  const ErpCompany({required this.name, this.abbr});
  final String name;
  final String? abbr;

  factory ErpCompany.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('اسم الشركة مفقود في استجابة ERPNext.');
    }
    final abbr = json['abbr'];
    return ErpCompany(name: name, abbr: abbr is String ? abbr : null);
  }
}


class ErpPaymentAccount {
  const ErpPaymentAccount({
    required this.name,
    required this.accountName,
    required this.accountType,
    this.currency,
  });

  final String name;
  final String accountName;
  final String accountType;
  final String? currency;

  factory ErpPaymentAccount.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final accountType = json['account_type'];
    if (name is! String || name.isEmpty ||
        accountType is! String || (accountType != 'Cash' && accountType != 'Bank')) {
      throw const FormatException('بيانات حساب التحصيل النقدي أو البنكي غير صحيحة.');
    }
    return ErpPaymentAccount(
      name: name,
      accountName: json['account_name'] is String && (json['account_name'] as String).isNotEmpty
          ? json['account_name'] as String
          : name,
      accountType: accountType,
      currency: json['account_currency'] is String ? json['account_currency'] as String : null,
    );
  }
}

class ErpItem {
  const ErpItem({
    required this.code, required this.name, this.group, this.stockUom,
    this.isStockItem = false, this.hasSerialNo = false, this.hasBatchNo = false,
  });
  final String code;
  final String name;
  final String? group;
  final String? stockUom;
  final bool isStockItem;
  final bool hasSerialNo;
  final bool hasBatchNo;

  factory ErpItem.fromJson(Map<String, dynamic> json) {
    final code = json['item_code'];
    final name = json['item_name'];
    if (code is! String || code.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('بيانات الصنف الأساسية ناقصة.');
    }
    return ErpItem(
      code: code,
      name: name,
      group: json['item_group'] is String ? json['item_group'] as String : null,
      stockUom: json['stock_uom'] is String ? json['stock_uom'] as String : null,
      isStockItem: json['is_stock_item'] == 1 || json['is_stock_item'] == true,
      hasSerialNo: json['has_serial_no'] == 1 || json['has_serial_no'] == true,
      hasBatchNo: json['has_batch_no'] == 1 || json['has_batch_no'] == true,
    );
  }
}

class ErpWarehouse {
  const ErpWarehouse({required this.id, required this.name, this.company});
  final String id;
  final String name;
  final String? company;

  factory ErpWarehouse.fromJson(Map<String, dynamic> json) {
    final id = json['name'];
    final name = json['warehouse_name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('بيانات المستودع الأساسية ناقصة.');
    }
    return ErpWarehouse(
      id: id,
      name: name,
      company: json['company'] is String ? json['company'] as String : null,
    );
  }
}


class ErpStockBalance {
  const ErpStockBalance({
    required this.itemCode,
    required this.warehouse,
    required this.actualQty,
    this.reservedQty = 0,
    this.projectedQty = 0,
    this.stockUom,
    this.valuationRate,
    this.stockValue,
  });
  final String itemCode;
  final String warehouse;
  final double actualQty;
  final double reservedQty;
  final double projectedQty;
  final String? stockUom;
  /// ERPNext's current valuation rate for this item/warehouse Bin, when exposed.
  final double? valuationRate;
  /// ERPNext's stock value for this Bin, in the owning company's currency.
  final double? stockValue;
  double get availableQty => actualQty - reservedQty;

  factory ErpStockBalance.fromJson(Map<String, dynamic> json) {
    final itemCode = json['item_code'];
    final warehouse = json['warehouse'];
    final actual = json['actual_qty'];
    if (itemCode is! String || itemCode.isEmpty || warehouse is! String || warehouse.isEmpty || (actual is! num && actual is! String)) {
      throw const FormatException('بيانات رصيد المخزون الأساسية ناقصة.');
    }
    double numberValue(dynamic value) {
      final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
      return parsed != null && parsed.isFinite ? parsed : 0;
    }
    double? optionalNumber(dynamic value) {
      if (value == null || value.toString().trim().isEmpty) return null;
      final parsed = value is num ? value.toDouble() : double.tryParse(value.toString());
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return ErpStockBalance(
      itemCode: itemCode,
      warehouse: warehouse,
      actualQty: numberValue(actual),
      reservedQty: numberValue(json['reserved_qty']),
      projectedQty: numberValue(json['projected_qty']),
      stockUom: json['stock_uom'] is String ? json['stock_uom'] as String : null,
      valuationRate: optionalNumber(json['valuation_rate']),
      stockValue: optionalNumber(json['stock_value']),
    );
  }
}
