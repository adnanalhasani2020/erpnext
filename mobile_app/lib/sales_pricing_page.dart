// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import 'api/frappe_api.dart';

class SalesPricingPage extends StatefulWidget {
  const SalesPricingPage({super.key, required this.api});

  final FrappeApi api;

  @override
  State<SalesPricingPage> createState() => _SalesPricingPageState();
}

class _SalesPricingPageState extends State<SalesPricingPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _priceLists = const [];
  List<Map<String, dynamic>> _prices = const [];
  String? _selectedPriceList;
  bool _loadingLists = true;
  bool _loading = false;
  bool _saving = false;
  bool _hasMore = false;
  bool _showDiscounts = false;
  bool _loadingDiscounts = false;
  List<Map<String, dynamic>> _discountRules = const [];
  String? _error;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadDiscounts() async {
    setState(() {
      _loadingDiscounts = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchSellingPricingRules();
      if (!mounted) return;
      setState(() => _discountRules = rows);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingDiscounts = false);
    }
  }

  Future<Map<String, dynamic>?> _showDiscountEditor({
    Map<String, dynamic>? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController(text: existing?['title']?.toString() ?? '');
    final value = TextEditingController(
      text: (existing?['discount_percentage'] ?? existing?['discount_amount'] ?? '').toString(),
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
          existing?['territory']?.toString() ?? '',
    );
    var discountType = existing?['rate_or_discount']?.toString() == 'Discount Amount'
        ? 'Discount Amount'
        : 'Discount Percentage';
    var applyOn = existing?['apply_discount_on']?.toString() == 'Net Total'
        ? 'Net Total'
        : 'Grand Total';
    var applicableFor = existing?['applicable_for']?.toString() ?? '';
    final result = await showDialog<Map<String, dynamic>>(
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
                      initialValue: discountType,
                      decoration: const InputDecoration(labelText: 'نوع الخصم'),
                      items: const [
                        DropdownMenuItem(value: 'Discount Percentage', child: Text('نسبة مئوية')),
                        DropdownMenuItem(value: 'Discount Amount', child: Text('مبلغ ثابت')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => discountType = v);
                      },
                    ),
                    TextFormField(
                      controller: value,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: discountType == 'Discount Percentage' ? 'نسبة الخصم %' : 'قيمة الخصم',
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
                    TextFormField(
                      controller: currency,
                      decoration: const InputDecoration(labelText: 'العملة'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'العملة مطلوبة' : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: applyOn,
                      decoration: const InputDecoration(labelText: 'يطبق الخصم على'),
                      items: const [
                        DropdownMenuItem(value: 'Grand Total', child: Text('الإجمالي النهائي')),
                        DropdownMenuItem(value: 'Net Total', child: Text('الإجمالي الصافي')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => applyOn = v);
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
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => applicableFor = v);
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
                  'discount_type': discountType,
                  'discount_value': double.parse(value.text.trim()),
                  'currency': currency.text.trim(),
                  'apply_discount_on': applyOn,
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
    return result;
  }

  Future<void> _editDiscount({Map<String, dynamic>? existing}) async {
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
        priceList: _selectedPriceList!,
        currency: values['currency'] as String,
        discountType: values['discount_type'] as String,
        discountValue: values['discount_value'] as double,
        validFrom: values['valid_from'] as String,
        validUpto: values['valid_upto'] as String,
        company: values['company'] as String,
        applicableFor: (values['applicable_for'] as String).isEmpty
            ? null
            : values['applicable_for'] as String,
        applicableValue: values['applicable_value'] as String,
        applyDiscountOn: values['apply_discount_on'] as String,
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

  Future<void> _disableDiscount(Map<String, dynamic> rule) async {
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

  Future<Map<String, dynamic>?> _showEditor(
      {Map<String, dynamic>? existing}) async {
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
    final result = await showDialog<Map<String, dynamic>>(
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

  Future<void> _editPrice({Map<String, dynamic>? existing}) async {
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

  Map<String, dynamic>? get _selectedList {
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
                  child: Text('إدارة أسعار البيع',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loading || _loadingLists ? null : _loadPriceLists,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'إدارة أسعار الأصناف وقواعد خصومات البيع داخل ERPNext وفق صلاحيات المستخدم.',
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
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
            const SizedBox(height: 12),
            if (_loadingLists)
              const LinearProgressIndicator()
            else if (_priceLists.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('لا توجد قوائم أسعار بيع مفعّلة أو لا تتوفر صلاحية قراءتها.'),
                ),
              )
            else if (!_showDiscounts)
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
              decoration: InputDecoration(
                labelText: 'بحث برمز الصنف',
                suffixIcon: IconButton(
                  onPressed: _loading ? null : () => _loadPrices(),
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
