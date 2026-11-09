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
              'إدارة أسعار الأصناف داخل قوائم أسعار البيع الموجودة في ERPNext. '
              'تُحفظ التغييرات في Item Price وفق صلاحيات المستخدم.',
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
                value: _selectedPriceList,
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
            const SizedBox(height: 10),
            TextField(
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
                  child: Text('أسعار الأصناف (' + _prices.length.toString() + ')',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                FilledButton.tonalIcon(
                  onPressed: _saving || _selectedPriceList == null
                      ? null
                      : () => _editPrice(),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة سعر'),
                ),
              ],
            ),
            if (_loading || _saving) const LinearProgressIndicator(),
            Expanded(
              child: _prices.isEmpty
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
                    ),
            ),
            if (_hasMore || (_loading && _prices.isNotEmpty))
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
