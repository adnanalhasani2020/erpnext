import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class SalesMarginAnalysisPage extends StatefulWidget {
  const SalesMarginAnalysisPage({super.key, required this.api, required this.priceList});
  final FrappeApi api;
  final String priceList;

  @override
  State<SalesMarginAnalysisPage> createState() => _SalesMarginAnalysisPageState();
}

class _SalesMarginAnalysisPageState extends State<SalesMarginAnalysisPage> {
  List<ErpCompany> _companies = const [];
  String? _company;
  List<core.Map<String, dynamic>> _rows = const [];
  String _search = '';
  bool _loading = true;
  String? _error;
  String _currency = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _number(dynamic value) {
    final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : 0;
  }

  Future<List<T>> _allPages<T>(Future<List<T>> Function(int start) fetch, String label) async {
    final result = <T>[];
    var offset = 0;
    while (true) {
      final page = await fetch(offset);
      result.addAll(page);
      if (page.length < FrappeApi.pageSize) return result;
      offset += page.length;
      if (result.length >= 10000) {
        throw FormatException('تجاوز $label حد 10,000 سجل؛ ضيّق نطاق البيانات قبل التحليل.');
      }
    }
  }

  Future<void> _load() async {
    if (_loading && _companies.isNotEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final companies = await widget.api.fetchCompanies();
      final priceLists = await widget.api.fetchSellingPriceLists();
      final selectedPriceList = priceLists.whereType<core.Map<String, dynamic>>().where((row) => row['name'] == widget.priceList).toList(growable: false);
      final priceCurrency = selectedPriceList.isEmpty ? '' : selectedPriceList.first['currency']?.toString() ?? '';
      final warehouses = await _allPages((start) => widget.api.fetchWarehouses(start: start), 'المستودعات');
      final balances = await _allPages((start) => widget.api.fetchStockBalances(start: start), 'أرصدة المخزون');
      final prices = await _allPages((start) => widget.api.fetchItemPrices(priceList: widget.priceList, start: start), 'أسعار الأصناف');
      final items = await _allPages((start) => widget.api.fetchMasterDataRows(doctype: 'Item', start: start), 'الأصناف');
      final rawRules = await _allPages((start) => widget.api.fetchSellingPricingRules(start: start), 'قواعد الخصم');
      if (!mounted) return;

      final warehouseCompany = <String, String>{
        for (final warehouse in warehouses) warehouse.id: warehouse.company ?? '',
      };
      final selectedCompany = _company != null && companies.any((c) => c.name == _company)
          ? _company
          : (companies.isEmpty ? null : companies.first.name);
      final selectedCompanyCurrency = companies.where((company) => company.name == selectedCompany).map((company) => company.defaultCurrency ?? '').toList(growable: false);
      final companyCurrency = selectedCompanyCurrency.isEmpty ? '' : selectedCompanyCurrency.first;
      final effectivePriceCurrency = priceCurrency.isNotEmpty ? priceCurrency : (prices.isEmpty ? '' : prices.first['currency']?.toString() ?? '');
      if (companyCurrency.isEmpty || effectivePriceCurrency.isEmpty || companyCurrency != effectivePriceCurrency) {
        setState(() { _companies = companies; _company = selectedCompany; _currency = effectivePriceCurrency; _rows = const []; _error = 'تعذر حساب هامش صحيح: عملة الشركة ${companyCurrency.isEmpty ? 'غير محددة' : companyCurrency} تختلف عن عملة قائمة البيع ${effectivePriceCurrency.isEmpty ? 'غير محددة' : effectivePriceCurrency}. اختر قائمة أسعار بنفس العملة أو أضف تحويل عملات موثوقاً.'; });
        return;
      }
      final schemeHeaders = await _allPages(
        (start) => widget.api.fetchSellingPromotionalSchemes(start: start, company: selectedCompany, activeOnly: true),
        'المخططات الترويجية',
      );
      if (schemeHeaders.length > 500) {
        throw const FormatException('عدد المخططات الترويجية يتجاوز 500؛ قلّص النطاق قبل تحليل الهوامش.');
      }
      final schemes = <core.Map<String, dynamic>>[];
      for (var offset = 0; offset < schemeHeaders.length; offset += 10) {
        final batch = schemeHeaders.whereType<core.Map<String, dynamic>>().skip(offset).take(10);
        final documents = await Future.wait(batch.map((row) =>
          widget.api.fetchSellingPromotionalSchemeDocument(row['name']?.toString() ?? ''),
        ));
        schemes.addAll(documents);
      }
      final costByItem = <String, ({double quantity, double value, double fallbackRate})>{};
      for (final balance in balances) {
        if (warehouseCompany[balance.warehouse] != selectedCompany) continue;
        final current = costByItem[balance.itemCode] ?? (quantity: 0.0, value: 0.0, fallbackRate: 0.0);
        final qty = balance.actualQty > 0 ? balance.actualQty : 0.0;
        final value = balance.stockValue != null && balance.stockValue! >= 0
            ? balance.stockValue!
            : qty * (balance.valuationRate ?? 0);
        costByItem[balance.itemCode] = (
          quantity: current.quantity + qty,
          value: current.value + value,
          fallbackRate: current.fallbackRate > 0 ? current.fallbackRate : (balance.valuationRate ?? 0),
        );
      }

      final rules = <core.Map<String, dynamic>>[...rawRules];
      for (final scheme in schemes) {
        final schemeName = scheme['name']?.toString() ?? 'مخطط ترويجي';
        final common = <String, dynamic>{
          'title': schemeName,
          'apply_on': scheme['apply_on'],
          'selling': scheme['selling'],
          'buying': scheme['buying'],
          'disable': scheme['disable'],
          'company': scheme['company'],
          'currency': scheme['currency'],
          'valid_from': scheme['valid_from'],
          'valid_upto': scheme['valid_upto'],
          'items': scheme['items'],
          'item_groups': scheme['item_groups'],
          'brands': scheme['brands'],
          'mixed_conditions': scheme['mixed_conditions'],
          'is_cumulative': scheme['is_cumulative'],
        };
        final priceSlabs = scheme['price_discount_slabs'];
        if (priceSlabs is List) {
          for (final slab in priceSlabs.whereType<core.Map>()) {
            rules.add({
              ...common,
              'price_or_product_discount': 'Price',
              'rate_or_discount': slab['rate_or_discount'],
              'rate': slab['rate'],
              'discount_percentage': slab['discount_percentage'],
              'discount_amount': slab['discount_amount'],
              'for_price_list': slab['for_price_list'],
              'min_qty': slab['min_qty'],
              'max_qty': slab['max_qty'],
              'min_amt': slab['min_amount'],
              'max_amt': slab['max_amount'],
              'priority': slab['priority'],
              'apply_multiple_pricing_rules': slab['apply_multiple_pricing_rules'],
              'warehouse': slab['warehouse'],
              'scheme_name': schemeName,
            });
          }
        }
        final productSlabs = scheme['product_discount_slabs'];
        if (productSlabs is List) {
          for (final slab in productSlabs.whereType<core.Map>()) {
            rules.add({
              ...common,
              'price_or_product_discount': 'Product',
              'same_item': slab['same_item'],
              'free_item': slab['free_item'],
              'free_qty': slab['free_qty'],
              'min_qty': slab['min_qty'],
              'max_qty': slab['max_qty'],
              'min_amt': slab['min_amount'],
              'max_amt': slab['max_amount'],
              'priority': slab['priority'],
              'apply_multiple_pricing_rules': slab['apply_multiple_pricing_rules'],
              'warehouse': slab['warehouse'],
              'scheme_name': schemeName,
            });
          }
        }
      }
      final itemByCode = <String, core.Map<String, dynamic>>{for (final item in items) item['name']?.toString() ?? '': item};
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = <core.Map<String, dynamic>>[];
      for (final price in prices) {
        final code = price['item_code']?.toString() ?? '';
        final rate = _number(price['price_list_rate']);
        final currency = price['currency']?.toString() ?? '';
        final cost = costByItem[code];
        final unitCost = cost == null
            ? null
            : (cost.quantity > 0 ? cost.value / cost.quantity : cost.fallbackRate);
        if (code.isEmpty || rate <= 0 || unitCost == null || unitCost <= 0) continue;
        final masterItem = itemByCode[code];
        final matchingRules = rules.where((rule) {
          if (rule['disable'] == 1 || rule['disable'] == true ||
              ((rule['for_price_list']?.toString().isNotEmpty ?? false) && rule['for_price_list'] != widget.priceList) ||
              _number(rule['min_amt']) > 0 || _number(rule['max_amt']) > 0 ||
              rule['is_cumulative'] == 1 || rule['is_cumulative'] == true ||
              rule['mixed_conditions'] == 1 || rule['mixed_conditions'] == true ||
              (rule['warehouse']?.toString().isNotEmpty ?? false) ||
              ((rule['company']?.toString().isNotEmpty ?? false) && rule['company'] != selectedCompany) ||
              ((rule['currency']?.toString().isNotEmpty ?? false) && rule['currency'] != effectivePriceCurrency)) { return false; }
          final from = rule['valid_from']?.toString() ?? '';
          final until = rule['valid_upto']?.toString() ?? '';
          if (from.isNotEmpty && from.compareTo(today) > 0) return false;
          if (until.isNotEmpty && until.compareTo(today) < 0) return false;
          if ((rule['applicable_for'] ?? '').toString().isNotEmpty) return false;
          final minimumQty = _number(rule['min_qty']);
          if (minimumQty > 1 || (_number(rule['max_qty']) > 0 && _number(rule['max_qty']) < 1)) return false;
          final scope = rule['apply_on']?.toString() ?? '';
          if (scope == 'Transaction') return false;
          final table = scope == 'Item Code' ? rule['items']
              : scope == 'Item Group' ? rule['item_groups']
              : scope == 'Brand' ? rule['brands'] : null;
          if (table is! List) return false;
          return table.whereType<core.Map>().any((item) {
            switch (scope) {
              case 'Item Code': return item['item_code']?.toString() == code;
              case 'Item Group': return item['item_group']?.toString() == masterItem?['item_group']?.toString();
              case 'Brand': return item['brand']?.toString() == masterItem?['brand']?.toString();
              default: return false;
            }
          });
        }).toList()
          ..sort((a, b) => _number(b['priority']).compareTo(_number(a['priority'])));
        var effective = rate;
        var promotionalCost = 0.0;
        String? ruleTitle;
        for (final rule in matchingRules) {
          final multiple = rule['apply_multiple_pricing_rules'] == 1 || rule['apply_multiple_pricing_rules'] == true;
          if (rule['price_or_product_discount'] == 'Product') {
            final freeCode = (rule['same_item'] == 1 || rule['same_item'] == true)
                ? code : rule['free_item']?.toString() ?? '';
            final freeCost = costByItem[freeCode];
            final freeUnitCost = freeCost == null ? 0.0
                : (freeCost.quantity > 0 ? freeCost.value / freeCost.quantity : freeCost.fallbackRate);
            final threshold = _number(rule['min_qty']) > 0 ? _number(rule['min_qty']) : 1.0;
            final freeQuantity = _number(rule['free_qty']) > 0 ? _number(rule['free_qty']) : 1.0;
            if (freeUnitCost > 0) {
              promotionalCost += freeUnitCost * freeQuantity / threshold;
              ruleTitle ??= rule['scheme_name']?.toString() ?? rule['title']?.toString();
            }
          } else {
            final kind = rule['rate_or_discount']?.toString() ?? '';
            double nextPrice = effective;
            if (kind == 'Rate') {
              nextPrice = _number(rule['rate']);
            } else if (kind == 'Discount Percentage') {
              nextPrice = effective * (1 - _number(rule['discount_percentage']) / 100);
            } else if (kind == 'Discount Amount') {
              nextPrice = effective - _number(rule['discount_amount']);
            }
            if (rule['margin_type']?.toString().isNotEmpty == true) {
              final margin = _number(rule['margin_rate_or_amount']);
              nextPrice = rate + (rule['margin_type'] == 'Amount' ? margin : rate * margin / 100);
            }
            if (nextPrice.isFinite && nextPrice >= 0) {
              effective = nextPrice;
              ruleTitle ??= rule['scheme_name']?.toString() ?? rule['title']?.toString();
            }
          }
          if (!multiple) break;
        }
        effective = effective.clamp(0, double.infinity).toDouble();
        final gross = rate - unitCost;
        final afterDiscount = effective - unitCost;
        rows.add({
          'item_code': code,
          'price': rate,
          'cost': unitCost,
          'gross_profit': gross,
          'gross_margin': gross / rate * 100,
          'discount': rate - effective,
          'effective_price': effective,
          'after_discount_profit': afterDiscount - promotionalCost,
          'after_discount_margin': effective > 0 ? (afterDiscount - promotionalCost) / effective * 100 : 0.0,
          'currency': currency,
          'rule': ruleTitle ?? '',
          'promotion_cost': promotionalCost,
        });
      }
      rows.sort((a, b) => _number(a['after_discount_margin']).compareTo(_number(b['after_discount_margin'])));
      setState(() {
        _companies = companies;
        _company = selectedCompany;
        _rows = rows;
        _currency = effectivePriceCurrency;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rows.where((row) => (row['item_code'] ?? '').toString().toLowerCase().contains(_search.toLowerCase())).toList();
    final selectedCompanyCurrencies = _companies.where((company) => company.name == _company).map((company) => company.defaultCurrency ?? 'غير محددة').toList(growable: false);
    final companyCurrency = selectedCompanyCurrencies.isEmpty ? 'غير محددة' : selectedCompanyCurrencies.first;
    final lowMargin = visible.where((row) => _number(row['after_discount_margin']) < 10).length;
    return Scaffold(
      appBar: AppBar(title: const Text('تحليل هامش الربح'), actions: [
        IconButton(onPressed: _loading ? null : _load, tooltip: 'تحديث التحليل', icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          DropdownButtonFormField<String>(
            initialValue: _company,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الشركة التي تُحسب عليها تكلفة المخزون'),
            items: _companies.map((company) => DropdownMenuItem(value: company.name, child: Text(company.name))).toList(),
            onChanged: _loading ? null : (value) { setState(() => _company = value); _load(); },
          ),
          const SizedBox(height: 8),
          TextField(decoration: const InputDecoration(labelText: 'بحث برمز الصنف', prefixIcon: Icon(Icons.search)), onChanged: (value) => setState(() => _search = value)),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_loading) const LinearProgressIndicator(),
          Row(children: [
            Expanded(child: Text('الأصناف المحللة: ${visible.length}', style: Theme.of(context).textTheme.titleSmall)),
            Text('هامش أقل من 10%: $lowMargin', style: Theme.of(context).textTheme.titleSmall),
          ]),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('التكلفة تقديرية من تقييم مخزون الشركة المختارة، والسعر من قائمة البيع المحددة. يشمل التحليل شرائح المخططات الترويجية القابلة للتطبيق على الصنف، ولا يشمل الضرائب أو مصاريف البيع أو خصومات العميل/المعاملة أو شروط قيمة الفاتورة أو القواعد التراكمية والمختلطة والمقيدة بمستودع محدد. تأكد من تطابق عملة قائمة البيع مع عملة الشركة: $companyCurrency مقابل ${_currency.isEmpty ? 'عملة السعر غير محددة' : _currency}.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
        Expanded(child: visible.isEmpty && !_loading
          ? const Center(child: Text('لا توجد أصناف لها سعر بيع وتكلفة مخزون قابلة للمقارنة في الشركة المحددة.'))
          : ListView.builder(itemCount: visible.length, itemBuilder: (context, index) {
              final row = visible[index];
              final margin = _number(row['after_discount_margin']);
              return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
                title: Text(row['item_code'].toString()),
                subtitle: Text('السعر: ${_number(row['price']).toStringAsFixed(2)} ${row['currency']} • التكلفة: ${_number(row['cost']).toStringAsFixed(2)} • الربح بعد الخصم: ${_number(row['after_discount_profit']).toStringAsFixed(2)}${(row['rule'] as String).isEmpty ? '' : ' • ${row['rule']}'}'),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${margin.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, color: margin < 0 ? Theme.of(context).colorScheme.error : margin < 10 ? Colors.orange : Theme.of(context).colorScheme.primary)),
                  const Text('الهامش بعد الخصم', style: TextStyle(fontSize: 10)),
                ]),
              ));
            })),
      ]),
    );
  }
}
