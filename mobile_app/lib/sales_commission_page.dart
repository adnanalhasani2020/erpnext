import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'workspace_native_destination_page.dart';

class SalesCommissionPage extends StatefulWidget {
  const SalesCommissionPage({super.key, required this.api});

  final FrappeApi api;

  @override
  State<SalesCommissionPage> createState() => _SalesCommissionPageState();
}

class _SalesCommissionPageState extends State<SalesCommissionPage> {
  final _searchController = TextEditingController();
  List<core.Map<String, dynamic>> _people = const [];
  bool _loading = false;
  bool _saving = false;
  bool _hasMore = false;
  String? _error;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || (more && !_hasMore)) return;
    setState(() {
      _loading = true;
      if (!more) _error = null;
    });
    try {
      final page = await widget.api.fetchSalesPersons(
        start: more ? _offset : 0,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _people = more ? [..._people, ...page] : page;
        _offset = _people.length;
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

  Future<void> _editCommission(core.Map<String, dynamic> person) async {
    if (_saving) return;
    final id = person['name']?.toString() ?? '';
    final name = person['sales_person_name']?.toString() ?? id;
    final controller = TextEditingController(
      text: person['commission_rate']?.toString() ?? '0',
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل نسبة العمولة'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'نسبة العمولة %',
                  helperText: 'القيمة من 0 إلى 100',
                ),
                validator: (value) {
                  final rate = double.tryParse(value?.trim() ?? '');
                  if (rate == null || !rate.isFinite || rate < 0 || rate > 100) {
                    return 'أدخل نسبة صحيحة من 0 إلى 100';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(dialogContext, double.parse(controller.text.trim()));
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || id.isEmpty || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateSalesPersonCommission(
        salesPersonId: id,
        commissionRate: result,
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث نسبة العمولة في ERPNext.')),
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
                  child: Text('إدارة مندوبي المبيعات والعمولات',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'فتح قائمة الجوال',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => WorkspaceNativeDestinationPage(api: widget.api, title: 'Sales Person', linkType: 'DocTypeList', target: 'Sales Person'),
                  )),
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loading || _saving ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'تعديل نسبة العمولة الأساسية لكل مندوب. تعتمد عمولات المستند الفعلية على توزيع Sales Team داخل ERPNext.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              enabled: !_loading && !_saving,
              decoration: InputDecoration(
                labelText: 'بحث باسم المندوب',
                suffixIcon: IconButton(
                  onPressed: _loading || _saving ? null : () => _load(),
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              ),
            if (_loading || _saving) const LinearProgressIndicator(),
            Expanded(
              child: _people.isEmpty
                  ? Center(
                      child: Text(_loading
                          ? 'جارٍ تحميل مندوبي المبيعات...'
                          : 'لا توجد سجلات مندوبي مبيعات ظاهرة.'),
                    )
                  : ListView.builder(
                      itemCount: _people.length,
                      itemBuilder: (context, index) {
                        final person = _people[index];
                        final id = person['name']?.toString() ?? '';
                        final name =
                            person['sales_person_name']?.toString() ?? id;
                        final rate = double.tryParse(
                                person['commission_rate']?.toString() ?? '') ??
                            0;
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(name),
                            subtitle: Text([
                              id,
                              if (person['employee'] != null)
                                'الموظف: ${person["employee"]}',
                              if (person['parent_sales_person'] != null)
                                'الرئيسي: ${person["parent_sales_person"]}',
                            ].join(' • ')),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${rate.toStringAsFixed(2)}%',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const Text('عمولة أساسية'),
                              ],
                            ),
                            onTap: _saving
                                ? null
                                : () => _editCommission(person),
                          ),
                        );
                      },
                    ),
            ),
            if (_hasMore || (_loading && _people.isNotEmpty))
              OutlinedButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: const Text('تحميل المزيد'),
              ),
            const SizedBox(height: 4),
            const Text(
              'تقارير ملخص العمولات ومعاملات المندوبين متاحة من تبويب التقارير. لا يغيّر هذا الإجراء نسب توزيع Sales Team في الفواتير المرحلة.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
