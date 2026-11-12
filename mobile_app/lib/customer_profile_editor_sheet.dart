import 'dart:core' as core;

import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class CustomerProfileEditorSheet extends StatefulWidget {
  const CustomerProfileEditorSheet({
    required this.api,
    required this.customer,
    required this.onSaved,
  });

  final FrappeApi api;
  final ErpCustomer customer;
  final VoidCallback onSaved;

  @override
  State<CustomerProfileEditorSheet> createState() =>
      _CustomerProfileEditorSheetState();
}

class _CustomerProfileEditorSheetState
    extends State<CustomerProfileEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _group = TextEditingController();
  final _territory = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _taxId = TextEditingController();
  final _currency = TextEditingController();
  final _priceList = TextEditingController();
  String _type = 'Company';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    _territory.dispose();
    _mobile.dispose();
    _email.dispose();
    _website.dispose();
    _taxId.dispose();
    _currency.dispose();
    _priceList.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final document = await widget.api.fetchCustomerDocument(widget.customer.id);
      if (!mounted) return;
      _name.text = document['customer_name']?.toString() ?? '';
      _group.text = document['customer_group']?.toString() ?? '';
      _territory.text = document['territory']?.toString() ?? '';
      _mobile.text = document['mobile_no']?.toString() ?? '';
      _email.text = document['email_id']?.toString() ?? '';
      _website.text = document['website']?.toString() ?? '';
      _taxId.text = document['tax_id']?.toString() ?? '';
      _currency.text = document['default_currency']?.toString() ?? '';
      _priceList.text = document['default_price_list']?.toString() ?? '';
      _type = document['customer_type']?.toString() == 'Individual'
          ? 'Individual'
          : 'Company';
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateCustomerProfile(
        customerId: widget.customer.id,
        values: {
          'customer_name': _name.text,
          'customer_type': _type,
          'customer_group': _group.text,
          'territory': _territory.text,
          'mobile_no': _mobile.text,
          'email_id': _email.text,
          'website': _website.text,
          'tax_id': _taxId.text,
          'default_currency': _currency.text,
          'default_price_list': _priceList.text,
        },
      );
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث ملف العميل في ERPNext.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
      {bool required = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? 'هذا الحقل مطلوب'
                : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .88,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                children: [
                  Text('تعديل ملف العميل',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(widget.customer.id,
                      style: Theme.of(context).textTheme.bodySmall),
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )),
                      ),
                    ),
                  _field(_name, 'اسم العميل', required: true),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'نوع العميل'),
                    items: const [
                      DropdownMenuItem(value: 'Company', child: Text('شركة')),
                      DropdownMenuItem(value: 'Individual', child: Text('فرد')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _type = value);
                          },
                  ),
                  const SizedBox(height: 10),
                  _field(_group, 'مجموعة العملاء', required: true),
                  _field(_territory, 'المنطقة', required: true),
                  _field(_mobile, 'رقم الهاتف',
                      keyboardType: TextInputType.phone),
                  _field(_email, 'البريد الإلكتروني',
                      keyboardType: TextInputType.emailAddress),
                  _field(_website, 'الموقع الإلكتروني'),
                  _field(_taxId, 'الرقم الضريبي'),
                  _field(_currency, 'العملة الافتراضية'),
                  _field(_priceList, 'قائمة الأسعار الافتراضية'),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات'),
                  ),
                ],
              ),
            ),
    );
  }
}