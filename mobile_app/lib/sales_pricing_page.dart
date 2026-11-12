import 'dart:core';
import 'dart:core' as core;
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'sales_margin_analysis_page.dart';
import 'promotional_schemes_page.dart';
import 'workspace_web_page.dart';

class SalesPricingPage extends StatefulWidget {
  const SalesPricingPage({super.key, required this.api, this.initialDoctype});

  final FrappeApi api;
  final String? initialDoctype;

  @override
  State<SalesPricingPage> createState() => _SalesPricingPageState();
}

class _SalesPricingPageState extends State<SalesPricingPage> {
  final _searchController = TextEditingController();
  List<core.Map<String, dynamic>> _priceLists = const [];
  List<core.Map<String, dynamic>> _prices = const [];
  String? _selectedPriceList;
  bool _loadingLists = true;
  bool _loading = false;
  bool _saving = false;
  bool _hasMore = false;
  bool _showDiscounts = false;
  bool _loadingDiscounts = false;
  bool _discountHasMore = false;
  List<core.Map<String, dynamic>> _discountRules = const [];
  String? _error;
  int _offset = 0;
  int _discountOffset = 0;

  @override
  void initState() {
    super.initState();
    _showDiscounts = widget.initialDoctype == 'Pricing Rule';
    _loadPriceLists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPriceLists() async {
    setState(() {
      _loadingLists = true;
      _error = null;
    });
    try {
      final lists = await widget.api.fetchSellingPriceLists();
      if (!mounted) return;
      setState(() {
        _priceLists = lists;
        _selectedPriceList = lists.isEmpty ? null : lists.first['name']?.toString();
      });
      if (_selectedPriceList != null) await _loadPrices();
      if (_showDiscounts) await _loadDiscounts();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingLists = false);
    }
  }

  Future<void> _loadPrices({bool more = false}) async {
    final list = _selectedPriceList;
    if (list == null || list.isEmpty || _loading || (more && !_hasMore)) return;
    setState(() {
      _loading = true;
      if (!more) _error = null;
    });
    try {
      final page = await widget.api.fetchItemPrices(
        priceList: list,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        start: more ? _offset : 0,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _prices = [..._prices, ...page];
        } else {
          _prices = page;
        }
        _offset = _prices.length;
        _hasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDiscounts({bool more = false}) async {
    if (_loadingDiscounts || (more && !_discountHasMore)) return;
    setState(() {
      _loadingDiscounts = true;
      if (!more) {
        _error = null;
        _discountRules = const [];
        _discountOffset = 0;
        _discountHasMore = false;
      }
    });
    try {
      final page = await widget.api.fetchSellingPricingRules(
        start: more ? _discountOffset : 0,
      );
      if (!mounted) return;
      setState(() {
        final normalizedPage = page.whereType<core.Map<String, dynamic>>().toList(growable: false);
        final combined = more ? [..._discountRules, ...normalizedPage] : normalizedPage;
        final seen = <String>{};
        _discountRules = combined.where((row) {
          final id = row['name']?.toString() ?? '';
          return id.isNotEmpty && seen.add(id);
        }).toList(growable: false);
        _discountOffset = more ? _discountOffset + page.length : page.length;
        _discountHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingDiscounts = false);
    }
  }

  Future<core.Map<String, dynamic>?> _showDiscountEditor({
    core.Map<String, dynamic>? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController(text: existing?['title']?.toString() ?? '');
    final value = TextEditingController(
      text: (existing?['discount_percentage'] ?? existing?['discount_amount'] ?? existing?['rate'] ?? existing?['margin_rate_or_amount'] ?? '').toString(),
    );
    final currency = TextEditingController(
      text: existing?['currency']?.toString() ??
          _selectedList?['currency']?.toString() ?? '',
    );
    final from = TextEditingController(
      text: existing?['valid_from']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10),
    );
    final until = TextEditingController(text: existing?['valid_upto']?.toString() ?? '');
    final company = TextEditingController(text: existing?['company']?.toString() ?? '');
    final target = TextEditingController(
      text: existing?['customer']?.toString() ??
          existing?['customer_group']?.toString() ??
          existing?['territory']?.toString() ??
          existing?['sales_partner']?.toString() ??
          existing?['campaign']?.toString() ?? '',
    );
    final existingItems = existing?['items'];
    final existingGroups = existing?['item_groups'];
    final existingBrands = existing?['brands'];
    final existingItem = existingItems is List && existingItems.isNotEmpty && existingItems.first is core.Map
        ? existingItems.first as core.Map
        : existingGroups is List && existingGroups.isNotEmpty && existingGroups.first is core.Map
            ? existingGroups.first as core.Map
            : existingBrands is List && existingBrands.isNotEmpty && existingBrands.first is core.Map
                ? existingBrands.first as core.Map : null;
    final itemCode = TextEditingController(
      text: existingItem?['item_code']?.toString() ?? existingItem?['item_group']?.toString() ?? existingItem?['brand']?.toString() ?? '',
    );
    final freeItem = TextEditingController(text: existing?['free_item']?.toString() ?? '');
    final freeQty = TextEditingController(text: existing?['free_qty']?.toString() ?? '1');
    var priceOrProductDiscount = existing?['price_or_product_discount']?.toString() == 'Product' ? 'Product' : 'Price';
    var sameItem = existing?['same_item'] == 1 || existing?['same_item'] == true;
    var dontEnforceFreeItemQty = existing?['dont_enforce_free_item_qty'] == 1 || existing?['dont_enforce_free_item_qty'] == true;
    var marginType = existing?['margin_type']?.toString() == 'Amount' ? 'Amount' : 'Percentage';
    final minQty = TextEditingController(text: existing?['min_qty']?.toString() ?? '');
    final minAmount = TextEditingController(text: existing?['min_amt']?.toString() ?? '');
    final maxAmount = TextEditingController(text: existing?['max_amt']?.toString() ?? '');
    final maxQty = TextEditingController(text: existing?['max_qty']?.toString() ?? '');
    final warehouse = TextEditingController(text: existing?['warehouse']?.toString() ?? '');
    final priority = TextEditingController(text: existing?['priority']?.toString() ?? '0');
    var applyMultipleRules = existing?['apply_multiple_pricing_rules'] == 1 || existing?['apply_multiple_pricing_rules'] == true;
    var cumulative = existing?['is_cumulative'] == 1 || existing?['is_cumulative'] == true;
    var mixedConditions = existing?['mixed_conditions'] == 1 || existing?['mixed_conditions'] == true;
    var applyOn = const {'Item Code', 'Item Group', 'Brand'}.contains(existing?['apply_on']?.toString())
        ? existing!['apply_on'].toString()
        : 'Transaction';
    var discountType = existing?['margin_type']?.toString().isNotEmpty == true
        ? 'Margin'
        : const {'Rate', 'Discount Amount'}.contains(existing?['rate_or_discount']?.toString())
            ? existing!['rate_or_discount'].toString()
            : 'Discount Percentage';
    var applyDiscountOn = existing?['apply_discount_on']?.toString() == 'Net Total'
        ? 'Net Total'
        : 'Grand Total';
    var applicableFor = existing?['applicable_for']?.toString() ?? '';
    final result = await showDialog<core.Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'إضافة قاعدة خصم' : 'تعديل قاعدة الخصم'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'اسم قاعدة الخصم'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: priceOrProductDiscount,
                      decoration: const InputDecoration(labelText: 'نوع العرض'),
                      items: const [
                        DropdownMenuItem(value: 'Price', child: Text('تعديل السعر أو الخصم')),
                        DropdownMenuItem(value: 'Product', child: Text('منتج مجاني (اشترِ واحصل على)')),
                      ],
                      onChanged: (v) { if (v != null) setDialogState(() => priceOrProductDiscount = v); },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: applyOn,
                      decoration: const InputDecoration(labelText: 'نوع العرض'),
                      items: const [
                        DropdownMenuItem(value: 'Transaction', child: Text('خصم على إجمالي المعاملة')),
                        DropdownMenuItem(value: 'Item Code', child: Text('صنف محدد')),
                        DropdownMenuItem(value: 'Item Group', child: Text('مجموعة أصناف')),
                        DropdownMenuItem(value: 'Brand', child: Text('علامة تجارية')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            applyOn = v;
                            if (v == 'Transaction') { itemCode.clear(); minQty.clear(); }
                          });
                        }
                      },
                    ),
                    if (applyOn != 'Transaction') ...[
                      TextFormField(
                        controller: itemCode,
                        decoration: InputDecoration(labelText: applyOn == 'Item Code' ? 'رمز الصنف' : applyOn == 'Item Group' ? 'اسم مجموعة الأصناف' : 'اسم العلامة التجارية'),
                        validator: (v) => applyOn != 'Transaction' && (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
                      ),
                      TextFormField(
                        controller: minQty,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'الحد الأدنى للكمية',
                          helperText: 'يُطبق العرض عند بلوغ هذه الكمية أو تجاوزها.',
                        ),
                        validator: (v) {
                          if (applyOn != 'Item Code') return null;
                          final n = double.tryParse(v?.trim() ?? '');
                          return n == null || !n.isFinite || n <= 0
                              ? 'أدخل كمية دنيا أكبر من صفر'
                              : null;
                        },
                      ),
                    ],
                    if (priceOrProductDiscount == 'Price') DropdownButtonFormField<String>(
                      initialValue: discountType,
                      decoration: const InputDecoration(labelText: 'نوع الخصم'),
                      items: const [
                        DropdownMenuItem(value: 'Rate', child: Text('تحديد سعر بيع ثابت')),
                        DropdownMenuItem(value: 'Discount Percentage', child: Text('نسبة مئوية')),
                        DropdownMenuItem(value: 'Discount Amount', child: Text('مبلغ ثابت')),
                        DropdownMenuItem(value: 'Margin', child: Text('هامش ربح على السعر الأساسي')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => discountType = v);
                      },
                    ),
                    if (priceOrProductDiscount == 'Price') TextFormField(
                      controller: value,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: discountType == 'Discount Percentage' ? 'نسبة الخصم %' : discountType == 'Rate' ? 'سعر البيع الجديد' : discountType == 'Margin' ? 'قيمة الهامش' : 'قيمة الخصم',
                      ),
                      validator: (v) {
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || !n.isFinite || n <= 0 ||
                            (discountType == 'Discount Percentage' && n > 100)) {
                          return 'أدخل قيمة خصم صحيحة';
                        }
                        return null;
                      },
                    ),
                    if (applyOn != 'Transaction') TextFormField(
                      controller: maxQty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الحد الأعلى للكمية (اختياري، صفر بلا حد)'),
                      validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return v == null || v.trim().isEmpty || (n != null && n.isFinite && n >= 0) ? null : 'أدخل كمية صحيحة'; },
                    ),
                    TextFormField(
                      controller: minAmount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الحد الأدنى لقيمة الفاتورة (اختياري)'),
                      validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return v == null || v.trim().isEmpty || (n != null && n.isFinite && n >= 0) ? null : 'أدخل مبلغاً صحيحاً'; },
                    ),
                    TextFormField(
                      controller: maxAmount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الحد الأعلى لقيمة الفاتورة (اختياري)'),
                      validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return v == null || v.trim().isEmpty || (n != null && n.isFinite && n >= 0) ? null : 'أدخل مبلغاً صحيحاً'; },
                    ),
                    TextFormField(
                      controller: priority,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'أولوية القاعدة (0 أو أكبر)'),
                      validator: (v) { final n = int.tryParse(v?.trim() ?? ''); return n != null && n >= 0 && n <= 20 ? null : 'الأولوية يجب أن تكون بين 0 و20'; },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('السماح بتطبيقها مع قواعد خصم أخرى'),
                      value: applyMultipleRules,
                      onChanged: (v) => setDialogState(() => applyMultipleRules = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('احتساب الكميات المختلطة للأصناف المشمولة'),
                      value: mixedConditions,
                      onChanged: (v) => setDialogState(() => mixedConditions = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('قاعدة تراكمية'),
                      value: cumulative,
                      onChanged: (v) => setDialogState(() => cumulative = v),
                    ),
                    if (priceOrProductDiscount == 'Price' && discountType == 'Margin')
                      DropdownButtonFormField<String>(
                        initialValue: marginType,
                        decoration: const InputDecoration(labelText: 'طريقة حساب الهامش'),
                        items: const [
                          DropdownMenuItem(value: 'Percentage', child: Text('نسبة مئوية')),
                          DropdownMenuItem(value: 'Amount', child: Text('مبلغ ثابت')),
                        ],
                        onChanged: (v) { if (v != null) setDialogState(() => marginType = v); },
                      ),
                    if (priceOrProductDiscount == 'Product') ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('نفس الصنف المشترى هو المجاني'),
                        value: sameItem,
                        onChanged: (v) => setDialogState(() => sameItem = v),
                      ),
                      if (!sameItem) TextFormField(
                        controller: freeItem,
                        decoration: const InputDecoration(labelText: 'رمز الصنف المجاني'),
                        validator: (v) => priceOrProductDiscount == 'Product' && !sameItem && (v == null || v.trim().isEmpty) ? 'حدد الصنف المجاني' : null,
                      ),
                      TextFormField(
                        controller: freeQty,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'كمية الصنف المجاني'),
                        validator: (v) { if (priceOrProductDiscount != 'Product') return null; final n = double.tryParse(v?.trim() ?? ''); return n == null || !n.isFinite || n <= 0 ? 'أدخل كمية أكبر من صفر' : null; },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('السماح بتعديل أو حذف الكمية المجانية'),
                        value: dontEnforceFreeItemQty,
                        onChanged: (v) => setDialogState(() => dontEnforceFreeItemQty = v),
                      ),
                    ],
                    TextFormField(
                      controller: currency,
                      decoration: const InputDecoration(labelText: 'العملة'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'العملة مطلوبة' : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: applyDiscountOn,
                      decoration: const InputDecoration(labelText: 'يطبق الخصم على'),
                      items: const [
                        DropdownMenuItem(value: 'Grand Total', child: Text('الإجمالي النهائي')),
                        DropdownMenuItem(value: 'Net Total', child: Text('الإجمالي الصافي')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => applyDiscountOn = v);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: applicableFor.isEmpty ? '' : applicableFor,
                      decoration: const InputDecoration(labelText: 'نطاق التطبيق (اختياري)'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('كل العملاء ضمن القائمة')),
                        DropdownMenuItem(value: 'Customer', child: Text('عميل محدد')),
                        DropdownMenuItem(value: 'Customer Group', child: Text('مجموعة عملاء')),
                        DropdownMenuItem(value: 'Territory', child: Text('منطقة')),
                        DropdownMenuItem(value: 'Sales Partner', child: Text('شريك مبيعات')),
                        DropdownMenuItem(value: 'Campaign', child: Text('حملة تسويقية')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            applicableFor = v;
                            if (v.isEmpty) target.clear();
                          });
                        }
                      },
                    ),
                    if (applicableFor.isNotEmpty)
                      TextFormField(
                        controller: target,
                        decoration: const InputDecoration(labelText: 'رمز العميل أو اسم المجموعة/المنطقة'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'قيمة نطاق التطبيق مطلوبة' : null,
                      ),
                    TextFormField(
                      controller: from,
                      decoration: const InputDecoration(labelText: 'ساري من (YYYY-MM-DD)'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'تاريخ البداية مطلوب' : null,
                    ),
                    TextFormField(
                      controller: until,
                      decoration: const InputDecoration(labelText: 'ساري حتى (YYYY-MM-DD) - اختياري'),
                    ),
                    TextFormField(
                      controller: warehouse,
                      decoration: const InputDecoration(labelText: 'المستودع المقيد للعرض (اختياري)'),
                    ),
                    TextFormField(
                      controller: company,
                      decoration: const InputDecoration(labelText: 'الشركة (اختياري)'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.of(dialogContext).pop({
                  'title': title.text.trim(),
                  'price_or_product_discount': priceOrProductDiscount,
                  'discount_type': discountType,
                  'discount_value': value.text.trim().isEmpty ? 0.0 : double.parse(value.text.trim()),
                  'margin_type': marginType,
                  'free_item': freeItem.text.trim(),
                  'free_qty': freeQty.text.trim().isEmpty ? 1.0 : double.parse(freeQty.text.trim()),
                  'same_item': sameItem,
                  'dont_enforce_free_item_qty': dontEnforceFreeItemQty,
                  'currency': currency.text.trim(),
                  'apply_discount_on': applyDiscountOn,
                  'apply_on': applyOn,
                  'item_code': itemCode.text.trim(),
                  'min_qty': applyOn != 'Transaction' ? double.parse(minQty.text.trim()) : 0.0,
                  'min_amount': minAmount.text.trim().isEmpty ? 0.0 : double.parse(minAmount.text.trim()),
                  'max_amount': maxAmount.text.trim().isEmpty ? 0.0 : double.parse(maxAmount.text.trim()),
                  'max_qty': maxQty.text.trim().isEmpty ? 0.0 : double.parse(maxQty.text.trim()),
                  'warehouse': warehouse.text.trim(),
                  'priority': int.parse(priority.text.trim()),
                  'apply_multiple_rules': applyMultipleRules,
                  'cumulative': cumulative,
                  'mixed_conditions': mixedConditions,
                  'applicable_for': applicableFor,
                  'applicable_value': target.text.trim(),
                  'valid_from': from.text.trim(),
                  'valid_upto': until.text.trim(),
                  'company': company.text.trim(),
                });
              },
              child: const Text('متابعة الحفظ'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    value.dispose();
    currency.dispose();
    from.dispose();
    until.dispose();
    company.dispose();
    target.dispose();
    itemCode.dispose();
    freeItem.dispose();
    freeQty.dispose();
    minQty.dispose();
    minAmount.dispose();
    maxAmount.dispose();
    maxQty.dispose();
    warehouse.dispose();
    priority.dispose();
    return result;
  }

  Future<void> _editDiscount({core.Map<String, dynamic>? existing}) async {
    if (_saving || _selectedPriceList == null) return;
    final values = await _showDiscountEditor(existing: existing);
    if (values == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveSellingPricingRule(
        ruleId: existing?['name']?.toString(),
        title: values['title'] as String,
        priceList: existing?['for_price_list']?.toString() ?? _selectedPriceList!,
        currency: values['currency'] as String,
        priceOrProductDiscount: values['price_or_product_discount'] as String,
        discountType: values['discount_type'] as String,
        discountValue: values['discount_value'] as double,
        validFrom: values['valid_from'] as String,
        validUpto: values['valid_upto'] as String,
        company: values['company'] as String,
        warehouse: values['warehouse'] as String,
        applicableFor: (values['applicable_for'] as String).isEmpty
            ? null
            : values['applicable_for'] as String,
        applicableValue: values['applicable_value'] as String,
        applyDiscountOn: values['apply_discount_on'] as String,
        applyOn: values['apply_on'] as String,
        itemCode: values['item_code'] as String,
        minQty: values['min_qty'] as double,
        minAmount: values['min_amount'] as double,
        maxAmount: values['max_amount'] as double,
        maxQty: values['max_qty'] as double,
        priority: values['priority'] as int,
        applyMultipleRules: values['apply_multiple_rules'] as bool,
        cumulative: values['cumulative'] as bool,
        mixedConditions: values['mixed_conditions'] as bool,
        marginType: values['margin_type'] as String,
        freeItem: values['free_item'] as String,
        freeQty: values['free_qty'] as double,
        sameItem: values['same_item'] as bool,
        dontEnforceFreeItemQty: values['dont_enforce_free_item_qty'] as bool,
      );
      if (!mounted) return;
      await _loadDiscounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ قاعدة الخصم في ERPNext.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disableDiscount(core.Map<String, dynamic> rule) async {
    final id = rule['name']?.toString() ?? '';
    if (id.isEmpty || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إيقاف قاعدة الخصم؟'),
        content: Text('سيتم تعطيل قاعدة الخصم ' + (rule['title']?.toString() ?? id) + ' في ERPNext.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إيقاف')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.disableSellingPricingRule(id);
      await _loadDiscounts();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildDiscountList() {
    if (_loadingDiscounts && _discountRules.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_discountRules.isEmpty) {
      return const Center(child: Text('لا توجد قواعد خصم بيع ظاهرة.'));
    }
    return ListView.builder(
      itemCount: _discountRules.length,
      itemBuilder: (context, index) {
        final row = _discountRules[index];
        final disabled = row['disable'] == 1 || row['disable'] == true;
        final kind = row['rate_or_discount']?.toString() ?? '';
        final amount = kind == 'Discount Amount'
            ? (row['discount_amount']?.toString() ?? '—') + ' ' + (row['currency']?.toString() ?? '')
            : (row['discount_percentage']?.toString() ?? '—') + '%';
        final scope = row['applicable_for']?.toString() ?? '';
        final scopeValue = row['customer'] ?? row['customer_group'] ?? row['territory'];
        return Card(
          child: ListTile(
            title: Text(row['title']?.toString() ?? row['name']?.toString() ?? 'قاعدة خصم'),
            subtitle: Text([
              amount,
              row['for_price_list']?.toString() ?? '',
              if (row['apply_on'] == 'Item Code' && row['items'] is List &&
                  (row['items'] as List).isNotEmpty)
                'صنف: ' + (((row['items'] as List).first is core.Map)
                    ? ((row['items'] as List).first as core.Map)['item_code']?.toString() ?? ''
                    : ''),
              if (row['apply_on'] == 'Item Code' && row['items'] is List &&
                  (row['items'] as List).isNotEmpty &&
                  (row['items'] as List).first is core.Map)
                'الكمية الدنيا: ' + (((row['items'] as List).first as core.Map)['min_qty']?.toString() ?? ''),
              if (scope.isNotEmpty) scope + ': ' + (scopeValue?.toString() ?? ''),
              if (row['valid_from'] != null) 'من ' + row['valid_from'].toString(),
              if (row['valid_upto'] != null) 'إلى ' + row['valid_upto'].toString(),
              if (disabled) 'معطلة',
            ].where((v) => v.isNotEmpty).join(' • ')),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _editDiscount(existing: row);
                if (action == 'disable') _disableDiscount(row);
              },
              itemBuilder: (context) => [
                if (!disabled)
                  const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                if (!disabled)
                  const PopupMenuItem(value: 'disable', child: Text('إيقاف')),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<core.Map<String, dynamic>?> _showEditor(
      {core.Map<String, dynamic>? existing}) async {
    final formKey = GlobalKey<FormState>();
    final item = TextEditingController(
        text: existing?['item_code']?.toString() ?? '');
    final rate = TextEditingController(
        text: existing?['price_list_rate']?.toString() ?? '');
    final currency = TextEditingController(
        text: existing?['currency']?.toString() ??
            _selectedList?['currency']?.toString() ?? '');
    final uom = TextEditingController(text: existing?['uom']?.toString() ?? '');
    final validFrom =
        TextEditingController(text: existing?['valid_from']?.toString() ?? '');
    final validUpto =
        TextEditingController(text: existing?['valid_upto']?.toString() ?? '');
    final minQty = TextEditingController(
        text: existing?['min_qty']?.toString() ?? '0');
    final result = await showDialog<core.Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'إضافة سعر بيع' : 'تعديل سعر البيع'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: item,
                    enabled: existing == null,
                    decoration: const InputDecoration(labelText: 'رمز الصنف'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'رمز الصنف مطلوب'
                        : null,
                  ),
                  TextFormField(
                    controller: rate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'سعر البيع'),
                    validator: (value) {
                      final parsed = double.tryParse(value?.trim() ?? '');
                      return parsed == null || !parsed.isFinite || parsed <= 0
                          ? 'أدخل سعراً أكبر من صفر'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: currency,
                    decoration: const InputDecoration(labelText: 'العملة'),
                  ),
                  TextFormField(
                    controller: uom,
                    decoration: const InputDecoration(labelText: 'وحدة القياس (اختياري)'),
                  ),
                  TextFormField(
                    controller: validFrom,
                    decoration: const InputDecoration(
                        labelText: 'ساري من (YYYY-MM-DD)'),
                  ),
                  TextFormField(
                    controller: validUpto,
                    decoration: const InputDecoration(
                        labelText: 'ساري حتى (YYYY-MM-DD)'),
                  ),
                  TextFormField(
                    controller: minQty,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'الحد الأدنى للكمية'),
                    validator: (value) {
                      final parsed = double.tryParse(value?.trim() ?? '');
                      return parsed == null || !parsed.isFinite || parsed < 0
                          ? 'أدخل كمية صحيحة'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(dialogContext).pop({
                'item_code': item.text.trim(),
                'rate': double.parse(rate.text.trim()),
                'currency': currency.text.trim(),
                'uom': uom.text.trim(),
                'valid_from': validFrom.text.trim(),
                'valid_upto': validUpto.text.trim(),
                'min_qty': double.parse(minQty.text.trim()),
              });
            },
            child: const Text('متابعة الحفظ'),
          ),
        ],
      ),
    );
    item.dispose();
    rate.dispose();
    currency.dispose();
    uom.dispose();
    validFrom.dispose();
    validUpto.dispose();
    minQty.dispose();
    return result;
  }

  Future<void> _editPrice({core.Map<String, dynamic>? existing}) async {
    if (_saving || _selectedPriceList == null) return;
    final values = await _showEditor(existing: existing);
    if (values == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveItemSellingPrice(
        priceId: existing?['name']?.toString(),
        itemCode: values['item_code'] as String,
        priceList: _selectedPriceList!,
        rate: values['rate'] as double,
        currency: values['currency'] as String,
        uom: values['uom'] as String,
        validFrom: values['valid_from'] as String,
        validUpto: values['valid_upto'] as String,
        minQty: values['min_qty'] as double,
      );
      if (!mounted) return;
      await _loadPrices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ سعر البيع في ERPNext.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  core.Map<String, dynamic>? get _selectedList {
    for (final row in _priceLists) {
      if (row['name'] == _selectedPriceList) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .92,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.initialDoctype == 'Pricing Rule' ? 'قواعد خصومات البيع' : 'أسعار الأصناف',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (widget.initialDoctype != null)
                  IconButton(
                    tooltip: 'فتح شاشة ERPNext الأصلية',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => WorkspaceWebPage(
                        api: widget.api,
                        title: widget.initialDoctype!,
                        linkType: 'DocTypeList',
                        target: widget.initialDoctype!,
                      ),
                    )),
                    icon: const Icon(Icons.open_in_browser),
                  ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loading || _loadingLists ? null : _loadPriceLists,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (widget.initialDoctype == null) const Text(
              'إدارة أسعار الأصناف وقواعد خصومات البيع داخل ERPNext وفق صلاحيات المستخدم.',
            ),
            if (widget.initialDoctype == null) const SizedBox(height: 8),
            if (widget.initialDoctype == null) SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('أسعار الأصناف')),
                ButtonSegment(value: true, label: Text('قواعد الخصم')),
              ],
              selected: {_showDiscounts},
              onSelectionChanged: _saving ? null : (selection) {
                final next = selection.first;
                setState(() => _showDiscounts = next);
                if (next && _discountRules.isEmpty) _loadDiscounts();
              },
            ),
            if (widget.initialDoctype == null && _selectedPriceList != null) Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _loading || _saving ? null : () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SalesMarginAnalysisPage(api: widget.api, priceList: _selectedPriceList!),
                  ));
                },
                icon: const Icon(Icons.query_stats),
                label: const Text('تحليل أثر الخصومات على هامش الربح'),
              ),
            ),
            if (widget.initialDoctype == null) Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _loading || _saving ? null : () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PromotionalSchemesPage(api: widget.api),
                  ));
                },
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('إدارة المخططات الترويجية متعددة الشرائح'),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingLists)
              const LinearProgressIndicator()
            else if (_priceLists.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('لا توجد قوائم أسعار بيع مفعّلة أو لا تتوفر صلاحية قراءتها.'),
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedPriceList,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'قائمة الأسعار'),
                items: _priceLists
                    .map((row) => DropdownMenuItem(
                          value: row['name']?.toString(),
                          child: Text(
                            (row['name']?.toString() ?? '') +
                                (row['currency'] == null
                                    ? ''
                                    : ' • ' + row['currency'].toString()),
                          ),
                        ))
                    .toList(),
                onChanged: _loading || _saving
                    ? null
                    : (value) {
                        setState(() => _selectedPriceList = value);
                        _loadPrices();
                      },
              ),
            if (!_showDiscounts) const SizedBox(height: 10),
            if (!_showDiscounts) TextField(
              controller: _searchController,
              enabled: !_loading && !_saving,
              decoration: InputDecoration(
                labelText: 'بحث برمز الصنف',
                suffixIcon: IconButton(
                  onPressed: _loading || _saving ? null : () => _loadPrices(),
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _loadPrices(),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _showDiscounts
                        ? 'قواعد خصومات البيع (' + _discountRules.length.toString() + ')'
                        : 'أسعار الأصناف (' + _prices.length.toString() + ')',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _saving || _selectedPriceList == null
                      ? null
                      : () => _showDiscounts ? _editDiscount() : _editPrice(),
                  icon: const Icon(Icons.add),
                  label: Text(_showDiscounts ? 'إضافة خصم' : 'إضافة سعر'),
                ),
              ],
            ),
            if (_loading || _saving || _loadingDiscounts) const LinearProgressIndicator(),
            Expanded(
              child: _showDiscounts
                  ? _buildDiscountList()
                  : (_prices.isEmpty
                      ? Center(
                          child: Text(_loading
                              ? 'جارٍ تحميل الأسعار...'
                              : 'لا توجد أسعار مطابقة.'),
                        )
                      : ListView.builder(
                      itemCount: _prices.length,
                      itemBuilder: (context, index) {
                        final row = _prices[index];
                        final rate = row['price_list_rate']?.toString() ?? '—';
                        final currency = row['currency']?.toString() ?? '';
                        final validity = [
                          if (row['valid_from'] != null)
                            'من ' + row['valid_from'].toString(),
                          if (row['valid_upto'] != null)
                            'إلى ' + row['valid_upto'].toString(),
                          if (row['min_qty'] != null)
                            'أقل كمية ' + row['min_qty'].toString(),
                        ].join(' • ');
                        return Card(
                          child: ListTile(
                            title: Text(row['item_code']?.toString() ?? '—'),
                            subtitle: Text([
                              rate + (currency.isEmpty ? '' : ' ' + currency),
                              if (row['uom'] != null) row['uom'].toString(),
                              if (validity.isNotEmpty) validity,
                            ].join(' • ')),
                            trailing: IconButton(
                              tooltip: 'تعديل السعر',
                              onPressed: _saving
                                  ? null
                                  : () => _editPrice(existing: row),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                        );
                      },
                    )),
            ),
            if (_showDiscounts && (_discountHasMore ||
                (_loadingDiscounts && _discountRules.isNotEmpty)))
              OutlinedButton(
                onPressed: _loadingDiscounts
                    ? null
                    : () => _loadDiscounts(more: true),
                child: const Text('تحميل قواعد خصم إضافية'),
              ),
            if (!_showDiscounts && (_hasMore || (_loading && _prices.isNotEmpty)))
              OutlinedButton(
                onPressed: _loading ? null : () => _loadPrices(more: true),
                child: const Text('تحميل المزيد'),
              ),
          ],
        ),
      ),
    );
  }
}
