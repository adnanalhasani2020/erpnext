import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'workspace_web_page.dart';
import 'models/erp_models.dart';

class PromotionalSchemesPage extends StatefulWidget {
  const PromotionalSchemesPage({super.key, required this.api});
  final FrappeApi api;

  @override
  State<PromotionalSchemesPage> createState() => _PromotionalSchemesPageState();
}

class _PromotionalSchemesPageState extends State<PromotionalSchemesPage> {
  List<core.Map<String, dynamic>> _schemes = [];
  List<ErpCompany> _companies = const [];
  List<core.Map<String, dynamic>> _priceLists = const [];
  bool _loading = false;
  bool _saving = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || (more && !_hasMore)) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (_companies.isEmpty) {
        final results = await Future.wait([widget.api.fetchCompanies(), widget.api.fetchSellingPriceLists()]);
        if (!mounted) return;
        _companies = results[0] as List<ErpCompany>;
        _priceLists = results[1] as List<core.Map<String, dynamic>>;
      }
      final page = await widget.api.fetchSellingPromotionalSchemes(start: more ? _offset : 0);
      if (!mounted) return;
      setState(() {
        if (more) {
          final known = _schemes.map((row) => row['name']?.toString()).toSet();
          _schemes.addAll(page.whereType<core.Map<String, dynamic>>().where((row) => !known.contains(row['name']?.toString())));
        } else {
          _schemes = page;
        }
        _offset = more ? _offset + page.length : page.length;
        _hasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editOrCreate({core.Map<String, dynamic>? existing}) async {
    if (_saving || _companies.isEmpty) return;
    core.Map<String, dynamic>? detail;
    if (existing != null) {
      try {
        detail = await widget.api.fetchSellingPromotionalSchemeDocument(existing['name']?.toString() ?? '');
      } catch (error) {
        if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
        return;
      }
    }
    if (!mounted) return;
    final values = await _showEditor(existing: detail);
    if (values == null || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      final saved = await widget.api.saveSellingPromotionalScheme(
        schemeId: detail?['name']?.toString(),
        name: values['name'] as String,
        company: values['company'] as String,
        currency: values['currency'] as String,
        applyOn: values['apply_on'] as String,
        target: values['target'] as String,
        validFrom: values['valid_from'] as String,
        validUpto: values['valid_upto'] as String,
        priceSlabs: (values['price_slabs'] as List).cast<core.Map<String, dynamic>>(),
        productSlabs: (values['product_slabs'] as List).cast<core.Map<String, dynamic>>(),
        mixedConditions: values['mixed_conditions'] as bool,
        cumulative: values['is_cumulative'] as bool,
      );
      if (!mounted) return;
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail == null ? 'تم إنشاء المخطط ${saved['name']} في ERPNext.' : 'تم تحديث المخطط ${saved['name']} في ERPNext.')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<core.Map<String, dynamic>?> _showEditor({core.Map<String, dynamic>? existing}) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final initialCompany = _companies.where((row) => row.name == existing?['company']).toList();
    var company = initialCompany.isEmpty ? _companies.first.name : initialCompany.first.name;
    final companyCurrency = _companies.where((row) => row.name == company).map((row) => row.defaultCurrency ?? '').toList();
    final currency = TextEditingController(text: existing?['currency']?.toString() ?? (companyCurrency.isEmpty ? '' : companyCurrency.first));
    final from = TextEditingController(text: existing?['valid_from']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10));
    final until = TextEditingController(text: existing?['valid_upto']?.toString() ?? '');
    final existingItems = existing?['items'];
    final existingGroups = existing?['item_groups'];
    final existingBrands = existing?['brands'];
    final existingTarget = existingItems is List && existingItems.isNotEmpty ? existingItems.first['item_code']
        : existingGroups is List && existingGroups.isNotEmpty ? existingGroups.first['item_group']
        : existingBrands is List && existingBrands.isNotEmpty ? existingBrands.first['brand'] : '';
    final target = TextEditingController(text: existingTarget?.toString() ?? '');
    var applyOn = const {'Item Code', 'Item Group', 'Brand'}.contains(existing?['apply_on']) ? existing!['apply_on'].toString() : 'Transaction';
    var mixed = existing?['mixed_conditions'] == 1 || existing?['mixed_conditions'] == true;
    var cumulative = existing?['is_cumulative'] == 1 || existing?['is_cumulative'] == true;
    final existingPriceSlabs = existing?['price_discount_slabs'];
    final fallbackPriceList = _priceLists.isEmpty ? '' : _priceLists.first['name']?.toString() ?? '';
    final priceSlabs = existing == null
        ? (_priceLists.isEmpty ? <_PriceSlabForm>[] : <_PriceSlabForm>[_PriceSlabForm(priceList: fallbackPriceList)])
        : existingPriceSlabs is List
            ? existingPriceSlabs.whereType<core.Map<String, dynamic>>().map((row) => _PriceSlabForm.fromJson(
                row,
                fallbackPriceList: _priceLists.any((priceList) => priceList['name'] == row['for_price_list'])
                    ? row['for_price_list']?.toString() ?? fallbackPriceList
                    : fallbackPriceList,
              )).toList()
            : <_PriceSlabForm>[];
    final existingProductSlabs = existing?['product_discount_slabs'];
    final productSlabs = existingProductSlabs is List
        ? existingProductSlabs.whereType<core.Map<String, dynamic>>().map(_ProductSlabForm.fromJson).toList()
        : <_ProductSlabForm>[];
    try {
      return await showDialog<core.Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, refresh) => AlertDialog(
            title: Text(existing == null ? 'إنشاء مخطط ترويجي متعدد الشرائح' : 'تعديل المخطط الترويجي'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(controller: name, readOnly: existing != null, decoration: const InputDecoration(labelText: 'اسم المخطط (معرّف فريد)'), validator: (v) => v == null || v.trim().isEmpty ? 'اسم المخطط مطلوب' : null),
                      DropdownButtonFormField<String>(
                        initialValue: company,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'الشركة'),
                        items: _companies.map((row) => DropdownMenuItem(value: row.name, child: Text(row.name))).toList(),
                        onChanged: (v) { if (v != null) refresh(() { company = v; final currencies = _companies.where((row) => row.name == v).map((row) => row.defaultCurrency ?? '').toList(); if (currencies.isNotEmpty) currency.text = currencies.first; }); },
                      ),
                      TextFormField(controller: currency, decoration: const InputDecoration(labelText: 'العملة (مثال: YER)'), validator: (v) => v == null || v.trim().isEmpty ? 'العملة مطلوبة' : null),
                      DropdownButtonFormField<String>(
                        initialValue: applyOn,
                        decoration: const InputDecoration(labelText: 'ينطبق على'),
                        items: const [
                          DropdownMenuItem(value: 'Item Code', child: Text('صنف محدد')),
                          DropdownMenuItem(value: 'Item Group', child: Text('مجموعة أصناف')),
                          DropdownMenuItem(value: 'Brand', child: Text('علامة تجارية')),
                          DropdownMenuItem(value: 'Transaction', child: Text('إجمالي المعاملة')),
                        ],
                        onChanged: (v) { if (v != null) refresh(() { applyOn = v; if (v == 'Transaction') target.clear(); }); },
                      ),
                      if (applyOn != 'Transaction') TextFormField(controller: target, decoration: InputDecoration(labelText: applyOn == 'Item Code' ? 'رمز الصنف' : applyOn == 'Item Group' ? 'مجموعة الأصناف' : 'العلامة التجارية'), validator: (v) => applyOn != 'Transaction' && (v == null || v.trim().isEmpty) ? 'قيمة النطاق مطلوبة' : null),
                      TextFormField(controller: from, decoration: const InputDecoration(labelText: 'ساري من YYYY-MM-DD'), validator: (v) => v == null || v.trim().isEmpty ? 'تاريخ البداية مطلوب' : null),
                      TextFormField(controller: until, decoration: const InputDecoration(labelText: 'ساري حتى YYYY-MM-DD (اختياري)')),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('شروط مختلطة عبر الأصناف المحددة'), value: mixed, onChanged: (v) => refresh(() => mixed = v)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('احتساب مشتريات العميل تراكمياً'), value: cumulative, onChanged: (v) => refresh(() => cumulative = v)),
                      const Divider(),
                      Row(children: [
                        const Expanded(child: Text('شرائح خصم الأسعار', style: TextStyle(fontWeight: FontWeight.bold))),
                        IconButton(onPressed: _priceLists.isEmpty ? null : () => refresh(() => priceSlabs.add(_PriceSlabForm(priceList: _priceLists.first['name']?.toString() ?? ''))), icon: const Icon(Icons.add_circle_outline), tooltip: 'إضافة شريحة سعر'),
                      ]),
                      ...priceSlabs.asMap().entries.map((entry) {
                        final index = entry.key;
                        final slab = entry.value;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(children: [
                              Row(children: [Expanded(child: Text('شريحة سعر ${index + 1}')), IconButton(onPressed: () => refresh(() { priceSlabs.removeAt(index).dispose(); }), icon: const Icon(Icons.delete_outline))]),
                              DropdownButtonFormField<String>(
                                initialValue: slab.type,
                                decoration: const InputDecoration(labelText: 'نوع النتيجة'),
                                items: const [
                                  DropdownMenuItem(value: 'Discount Percentage', child: Text('خصم نسبة مئوية')),
                                  DropdownMenuItem(value: 'Discount Amount', child: Text('خصم مبلغ ثابت')),
                                  DropdownMenuItem(value: 'Rate', child: Text('سعر بيع ثابت')),
                                ],
                                onChanged: (v) { if (v != null) refresh(() => slab.type = v); },
                              ),
                              TextFormField(controller: slab.value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'قيمة الشريحة'), validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return n == null || !n.isFinite || n <= 0 || (slab.type == 'Discount Percentage' && n > 100) ? 'قيمة الشريحة غير صحيحة' : null; }),
                              DropdownButtonFormField<String>(
                                initialValue: slab.priceList,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'قائمة الأسعار'),
                                items: _priceLists.map((row) => DropdownMenuItem(value: row['name']?.toString(), child: Text(row['name']?.toString() ?? ''))).toList(),
                                onChanged: (v) { if (v != null) refresh(() => slab.priceList = v); },
                              ),
                              Row(children: [
                                Expanded(child: _numField(slab.minQty, 'أقل كمية')),
                                const SizedBox(width: 8),
                                Expanded(child: _numField(slab.maxQty, 'أعلى كمية (0 بلا حد)')),
                              ]),
                              Row(children: [
                                Expanded(child: _numField(slab.minAmount, 'أقل مبلغ')),
                                const SizedBox(width: 8),
                                Expanded(child: _numField(slab.maxAmount, 'أعلى مبلغ')),
                              ]),
                              Row(children: [
                                Expanded(child: _numField(slab.priority, 'الأولوية 1-20')),
                                const SizedBox(width: 8),
                                Expanded(child: _numField(slab.warehouse, 'المستودع (اختياري)', number: false)),
                              ]),
                              TextFormField(controller: slab.description, decoration: const InputDecoration(labelText: 'وصف الشريحة'), validator: (v) => v == null || v.trim().isEmpty ? 'وصف الشريحة مطلوب' : null),
                              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('السماح بتطبيقها مع قواعد أخرى'), value: slab.applyMultiple, onChanged: (v) => refresh(() => slab.applyMultiple = v ?? false)),
                            ]),
                          ),
                        );
                      }),
                      const Divider(),
                      Row(children: [
                        const Expanded(child: Text('شرائح المنتجات المجانية', style: TextStyle(fontWeight: FontWeight.bold))),
                        IconButton(onPressed: () => refresh(() => productSlabs.add(_ProductSlabForm())), icon: const Icon(Icons.add_circle_outline), tooltip: 'إضافة شريحة منتج مجاني'),
                      ]),
                      ...productSlabs.asMap().entries.map((entry) {
                        final index = entry.key;
                        final slab = entry.value;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(children: [
                              Row(children: [Expanded(child: Text('شريحة مجانية ${index + 1}')), IconButton(onPressed: () => refresh(() => productSlabs.removeAt(index).dispose()), icon: const Icon(Icons.delete_outline))]),
                              Row(children: [
                                Expanded(child: _numField(slab.minQty, 'أقل كمية')),
                                const SizedBox(width: 8),
                                Expanded(child: _numField(slab.maxQty, 'أعلى كمية')),
                              ]),
                              Row(children: [
                                Expanded(child: _numField(slab.minAmount, 'أقل مبلغ')),
                                const SizedBox(width: 8),
                                Expanded(child: _numField(slab.maxAmount, 'أعلى مبلغ')),
                              ]),
                              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('نفس الصنف المشترى مجاني'), value: slab.sameItem, onChanged: (v) => refresh(() => slab.sameItem = v ?? false)),
                              if (!slab.sameItem) TextFormField(controller: slab.freeItem, decoration: const InputDecoration(labelText: 'رمز الصنف المجاني'), validator: (v) => !slab.sameItem && (v == null || v.trim().isEmpty) ? 'حدد الصنف المجاني' : null),
                              _numField(slab.freeQty, 'كمية الصنف المجاني'),
                              Row(children: [
                                Expanded(child: _numField(slab.priority, 'الأولوية 1-20')),
                                const SizedBox(width: 8),
                                Expanded(child: _numField(slab.warehouse, 'المستودع (اختياري)', number: false)),
                              ]),
                              TextFormField(controller: slab.description, decoration: const InputDecoration(labelText: 'وصف الشريحة'), validator: (v) => v == null || v.trim().isEmpty ? 'وصف الشريحة مطلوب' : null),
                              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('السماح بتطبيقها مع قواعد أخرى'), value: slab.applyMultiple, onChanged: (v) => refresh(() => slab.applyMultiple = v ?? false)),
                            ]),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (priceSlabs.isEmpty && productSlabs.isEmpty) return;
                Navigator.pop(dialogContext, {
                  'name': name.text.trim(),
                  'company': company,
                  'currency': currency.text.trim(),
                  'apply_on': applyOn,
                  'target': target.text.trim(),
                  'valid_from': from.text.trim(),
                  'valid_upto': until.text.trim(),
                  'mixed_conditions': mixed,
                  'is_cumulative': cumulative,
                  'price_slabs': priceSlabs.map((slab) => slab.toJson()).toList(),
                  'product_slabs': productSlabs.map((slab) => slab.toJson()).toList(),
                });
              }, child: const Text('حفظ المخطط')),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      currency.dispose();
      from.dispose();
      until.dispose();
      target.dispose();
      for (final slab in priceSlabs) { slab.dispose(); }
      for (final slab in productSlabs) { slab.dispose(); }
    }
  }

  Widget _numField(TextEditingController controller, String label, {bool number = true}) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: TextFormField(
        controller: controller,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: number ? (v) { if (v == null || v.trim().isEmpty) return null; final n = double.tryParse(v.trim()); return n == null || !n.isFinite || n < 0 ? 'أدخل رقماً غير سالب' : null; } : null,
      ));

  Future<void> _setDisabled(core.Map<String, dynamic> scheme, bool disabled) async {
    final id = scheme['name']?.toString() ?? '';
    if (id.isEmpty || _saving) return;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(disabled ? 'إيقاف المخطط الترويجي' : 'تفعيل المخطط الترويجي'),
      content: Text(disabled ? 'سيتم تعطيل المخطط $id في ERPNext دون حذف الشرائح أو السجل.' : 'سيتم إعادة تفعيل المخطط $id في ERPNext.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تعطيل')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.setSellingPromotionalSchemeDisabled(id, disabled: disabled);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المخططات الترويجية'), actions: [
      IconButton(tooltip: 'فتح قائمة الجوال', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceNativeDestinationPage(api: widget.api, title: 'Promotional Scheme', linkType: 'DocTypeList', target: 'Promotional Scheme'))), icon: const Icon(Icons.arrow_forward)),
      IconButton(onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh)),
    ]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _saving || _loading ? null : () => _editOrCreate(),
      icon: const Icon(Icons.add),
      label: const Text('مخطط جديد'),
    ),
    body: Column(children: [
      if (_loading || _saving) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Expanded(child: _schemes.isEmpty && !_loading
        ? const Center(child: Text('لا توجد مخططات ترويجية ظاهرة.'))
        : ListView.builder(itemCount: _schemes.length, itemBuilder: (context, index) {
            final row = _schemes[index];
            final disabled = row['disable'] == 1 || row['disable'] == true;
            return Card(child: ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(row['name']?.toString() ?? '—'),
              subtitle: Text('${row['company'] ?? ''} • ${row['apply_on'] ?? ''} • ${row['valid_from'] ?? 'بلا تاريخ بداية'}${disabled ? ' • معطل' : ''}'),
              isThreeLine: true,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'تعديل المخطط', onPressed: _saving ? null : () => _editOrCreate(existing: row), icon: const Icon(Icons.edit_outlined)),
                IconButton(tooltip: disabled ? 'تفعيل المخطط' : 'إيقاف المخطط', onPressed: _saving ? null : () => _setDisabled(row, !disabled), icon: Icon(disabled ? Icons.play_circle_outline : Icons.block_outlined)),
              ]),
            ));
          })),
      if (_hasMore) Padding(padding: const EdgeInsets.all(12), child: OutlinedButton(onPressed: _loading ? null : () => _load(more: true), child: const Text('تحميل مخططات إضافية'))),
    ]),
  );
}

class _PriceSlabForm {
  _PriceSlabForm({required this.priceList});
  _PriceSlabForm.fromJson(core.Map<String, dynamic> row, {required String fallbackPriceList})
      : priceList = row['for_price_list']?.toString() ?? fallbackPriceList {
    type = row['rate_or_discount']?.toString() ?? 'Discount Percentage';
    value.text = (row['rate'] ?? row['discount_percentage'] ?? row['discount_amount'] ?? '').toString();
    minQty.text = (row['min_qty'] ?? 0).toString();
    maxQty.text = (row['max_qty'] ?? 0).toString();
    minAmount.text = (row['min_amount'] ?? 0).toString();
    maxAmount.text = (row['max_amount'] ?? 0).toString();
    priority.text = (row['priority'] ?? '1').toString();
    warehouse.text = row['warehouse']?.toString() ?? '';
    description.text = row['rule_description']?.toString() ?? 'شريحة ترويجية';
    applyMultiple = row['apply_multiple_pricing_rules'] == 1 || row['apply_multiple_pricing_rules'] == true;
  }
  String type = 'Discount Percentage';
  String priceList;
  final value = TextEditingController();
  final minQty = TextEditingController(text: '0');
  final maxQty = TextEditingController(text: '0');
  final minAmount = TextEditingController(text: '0');
  final maxAmount = TextEditingController(text: '0');
  final priority = TextEditingController(text: '1');
  final warehouse = TextEditingController();
  final description = TextEditingController(text: 'شريحة ترويجية');
  bool applyMultiple = false;

  core.Map<String, dynamic> toJson() => {
    'rate_or_discount': type,
    'value': double.tryParse(value.text.trim()) ?? 0,
    'min_qty': double.tryParse(minQty.text.trim()) ?? 0,
    'max_qty': double.tryParse(maxQty.text.trim()) ?? 0,
    'min_amount': double.tryParse(minAmount.text.trim()) ?? 0,
    'max_amount': double.tryParse(maxAmount.text.trim()) ?? 0,
    'priority': priority.text.trim(),
    'warehouse': warehouse.text.trim(),
    'for_price_list': priceList,
    'rule_description': description.text.trim(),
    'apply_multiple_pricing_rules': applyMultiple,
  };

  void dispose() {
    value.dispose(); minQty.dispose(); maxQty.dispose(); minAmount.dispose();
    maxAmount.dispose(); priority.dispose(); warehouse.dispose(); description.dispose();
  }
}

class _ProductSlabForm {
  _ProductSlabForm();
  _ProductSlabForm.fromJson(core.Map<String, dynamic> row) {
    minQty.text = (row['min_qty'] ?? 1).toString();
    maxQty.text = (row['max_qty'] ?? 0).toString();
    minAmount.text = (row['min_amount'] ?? 0).toString();
    maxAmount.text = (row['max_amount'] ?? 0).toString();
    freeItem.text = row['free_item']?.toString() ?? '';
    freeQty.text = (row['free_qty'] ?? 1).toString();
    priority.text = (row['priority'] ?? '1').toString();
    warehouse.text = row['warehouse']?.toString() ?? '';
    description.text = row['rule_description']?.toString() ?? 'شريحة منتج مجاني';
    sameItem = row['same_item'] == 1 || row['same_item'] == true;
    applyMultiple = row['apply_multiple_pricing_rules'] == 1 || row['apply_multiple_pricing_rules'] == true;
  }
  final minQty = TextEditingController(text: '1');
  final maxQty = TextEditingController(text: '0');
  final minAmount = TextEditingController(text: '0');
  final maxAmount = TextEditingController(text: '0');
  final freeItem = TextEditingController();
  final freeQty = TextEditingController(text: '1');
  final priority = TextEditingController(text: '1');
  final warehouse = TextEditingController();
  final description = TextEditingController(text: 'شريحة منتج مجاني');
  bool sameItem = false;
  bool applyMultiple = false;

  core.Map<String, dynamic> toJson() => {
    'min_qty': double.tryParse(minQty.text.trim()) ?? 0,
    'max_qty': double.tryParse(maxQty.text.trim()) ?? 0,
    'min_amount': double.tryParse(minAmount.text.trim()) ?? 0,
    'max_amount': double.tryParse(maxAmount.text.trim()) ?? 0,
    'free_item': freeItem.text.trim(),
    'free_qty': double.tryParse(freeQty.text.trim()) ?? 0,
    'same_item': sameItem,
    'priority': priority.text.trim(),
    'warehouse': warehouse.text.trim(),
    'rule_description': description.text.trim(),
    'apply_multiple_pricing_rules': applyMultiple,
  };

  void dispose() {
    minQty.dispose(); maxQty.dispose(); minAmount.dispose(); maxAmount.dispose();
    freeItem.dispose(); freeQty.dispose(); priority.dispose(); warehouse.dispose(); description.dispose();
  }
}
