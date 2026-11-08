import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class SalesInvoiceComposer extends StatefulWidget {
  const SalesInvoiceComposer({
    super.key,
    required this.api,
    required this.customers,
    required this.items,
    required this.warehouses,
    required this.companies,
    required this.onCompleted,
  });

  final FrappeApi api;
  final List<ErpCustomer> customers;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final List<ErpCompany> companies;
  final ValueChanged<bool> onCompleted;

  @override
  State<SalesInvoiceComposer> createState() => _SalesInvoiceComposerState();
}

class _SalesInvoiceLineDraft {
  ErpItem? item;
  ErpWarehouse? warehouse;
  final quantity = TextEditingController(text: '1');
  final rate = TextEditingController(text: '0');

  void dispose() {
    quantity.dispose();
    rate.dispose();
  }

  double get qty => double.tryParse(quantity.text.trim()) ?? 0;
  double get unitRate => double.tryParse(rate.text.trim()) ?? 0;
  double get total => qty * unitRate;
}

class _SalesInvoiceComposerState extends State<SalesInvoiceComposer> {
  final _formKey = GlobalKey<FormState>();
  final List<_SalesInvoiceLineDraft> _lines = [];
  ErpCustomer? _customer;
  ErpCompany? _company;
  bool _updateStock = true;
  bool _saving = false;
  String? _error;
  String? _createdInvoiceId;
  Map<String, dynamic>? _pendingDraft;

  @override
  void initState() {
    super.initState();
    if (widget.customers.length == 1) _customer = widget.customers.first;
    if (widget.companies.length == 1) _company = widget.companies.first;
    _lines.add(_SalesInvoiceLineDraft());
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  double get _subtotal => _lines.fold<double>(0, (sum, line) => sum + line.total);

  void _addLine() => setState(() => _lines.add(_SalesInvoiceLineDraft()));

  void _removeLine(int index) {
    if (_lines.length == 1) return;
    setState(() {
      _lines.removeAt(index).dispose();
    });
  }

  String? _validatePositive(String? value, String label) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) return 'أدخل $label أكبر من صفر.';
    return null;
  }

  Future<void> _save({required bool submit}) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_customer == null || _company == null) {
      setState(() => _error = 'اختر العميل والشركة أولاً.');
      return;
    }
    if (_lines.any((line) => line.item == null)) {
      setState(() => _error = 'اختر الصنف لكل بند في الفاتورة.');
      return;
    }
    if (_updateStock && _lines.any((line) => line.item!.isStockItem && line.warehouse == null)) {
      setState(() => _error = 'حدد المستودع لكل صنف مخزني حتى يستطيع ERPNext خصم الكمية عند الترحيل.');
      return;
    }
    if (submit) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد ترحيل الفاتورة'),
          content: const Text('سيتم ترحيل الفاتورة في ERPNext. إذا كان تحديث المخزون مفعلاً، سيعالج ERPNext حركة الصرف وفق إعداداته وصلاحياتك. لا يمكن اعتبار الترحيل مسودة قابلة للتعديل. هل تريد المتابعة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('مراجعة')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد الترحيل')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      if (_pendingDraft == null) {
        final invoice = <String, dynamic>{
          'doctype': 'Sales Invoice',
          'customer': _customer!.id,
          'company': _company!.name,
          'posting_date': _today(),
          'update_stock': _updateStock ? 1 : 0,
          'items': _lines.map((line) {
            final row = <String, dynamic>{
              'item_code': line.item!.code,
              'qty': line.qty,
              'rate': line.unitRate,
            };
            if (line.warehouse != null) row['warehouse'] = line.warehouse!.id;
            return row;
          }).toList(growable: false),
        };
        final created = await widget.api.createSalesInvoice(invoice);
        if (!mounted) return;
        setState(() {
          _pendingDraft = created;
          _createdInvoiceId = created['name'] as String;
        });
      }
      final draft = _pendingDraft!;
      final invoiceId = draft['name'] as String;
      if (!submit) {
        if (!mounted) return;
        widget.onCompleted(false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ مسودة الفاتورة $invoiceId')));
        Navigator.of(context).pop();
        return;
      }
      await widget.api.submitSalesInvoice(draft);
      if (!mounted) return;
      _pendingDraft = null;
      widget.onCompleted(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ترحيل فاتورة المبيعات $invoiceId بنجاح')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة مبيعات جديدة')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('بيانات الفاتورة', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ErpCompany>(
                      value: _company,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'الشركة'),
                      items: widget.companies.map((company) => DropdownMenuItem(value: company, child: Text(company.name, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: _saving || _pendingDraft != null ? null : (value) => setState(() => _company = value),
                      validator: (value) => value == null ? 'اختر الشركة.' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ErpCustomer>(
                      value: _customer,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'العميل'),
                      items: widget.customers.map((customer) => DropdownMenuItem(value: customer, child: Text('${customer.name} • ${customer.id}', overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: _saving || _pendingDraft != null ? null : (value) => setState(() => _customer = value),
                      validator: (value) => value == null ? 'اختر العميل.' : null,
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: const Text('تاريخ الفاتورة'),
                      trailing: Text(_today()),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('أصناف الفاتورة', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(onPressed: _saving || _pendingDraft != null ? null : _addLine, icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
              ]),
              ...List.generate(_lines.length, (index) => _buildLine(index)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _updateStock,
                      onChanged: _saving ? null : (value) => setState(() => _updateStock = value),
                      title: const Text('تحديث المخزون عند الترحيل'),
                      subtitle: const Text('يطلب من ERPNext إنشاء حركة صرف للأصناف المخزنية عند ترحيل الفاتورة.'),
                    ),
                    const Divider(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('إجمالي البنود قبل الضرائب والخصومات'),
                      Text(_subtotal.toStringAsFixed(2), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    const Text('يحسب ERPNext الضرائب والخصومات والإجمالي النهائي وفق إعدادات الشركة وقائمة الأسعار.', style: TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
              if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
              if (_createdInvoiceId != null) Text('رقم المسودة: $_createdInvoiceId'),
              if (_pendingDraft != null) const Text('تم إنشاء المسودة بالفعل. تم قفل تعديل البنود لمنع اختلاف ما تراه عن المستند المحفوظ؛ أعد محاولة الترحيل للمستند نفسه.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving || _pendingDraft != null ? null : () => _save(submit: false),
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                label: const Text('حفظ كمسودة'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : () => _save(submit: true),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_pendingDraft == null ? 'حفظ وترحيل الفاتورة' : 'إعادة محاولة ترحيل $_createdInvoiceId'),
              ),
              const SizedBox(height: 12),
              const Text('ملاحظة: لا يتم تسجيل دفعة مالية تلقائياً. بعد الترحيل تبقى الفاتورة مدينة حتى تسجيل Payment Entry من النظام.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLine(int index) {
    final line = _lines[index];
    return Card(
      key: ValueKey(line),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('البند ${index + 1}', style: Theme.of(context).textTheme.titleSmall)),
            IconButton(tooltip: 'حذف البند', onPressed: _saving || _lines.length == 1 ? null : () => _removeLine(index), icon: const Icon(Icons.delete_outline)),
          ]),
          DropdownButtonFormField<ErpItem>(
            value: line.item,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: widget.items.map((item) => DropdownMenuItem(value: item, child: Text('${item.name} • ${item.code}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: _saving ? null : (value) => setState(() {
              line.item = value;
              if (line.rate.text.trim() == '0') line.rate.text = '0';
              if (!_updateStock || value?.isStockItem != true) line.warehouse = null;
            }),
            validator: (value) => value == null ? 'اختر الصنف.' : null,
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextFormField(
              controller: line.quantity,
              enabled: !_saving && _pendingDraft == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'الكمية'),
              validator: (value) => _validatePositive(value, 'كمية'),
              onChanged: (_) => setState(() {}),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(
              controller: line.rate,
              enabled: !_saving && _pendingDraft == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'سعر الوحدة'),
              validator: (value) => _validatePositive(value, 'سعر'),
              onChanged: (_) => setState(() {}),
            )),
          ]),
          if (_updateStock && line.item?.isStockItem == true) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<ErpWarehouse>(
              value: line.warehouse,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'مستودع الصرف'),
              items: widget.warehouses.map((warehouse) => DropdownMenuItem(value: warehouse, child: Text(warehouse.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _saving ? null : (value) => setState(() => line.warehouse = value),
              validator: (value) => _updateStock && line.item?.isStockItem == true && value == null ? 'اختر مستودع الصرف.' : null,
            ),
          ],
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerEnd, child: Text('الإجمالي: ${line.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }
}
