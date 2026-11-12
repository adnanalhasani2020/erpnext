import 'package:flutter/material.dart';
import 'api/frappe_api.dart';

class ErpDocTypeDefinition {
  const ErpDocTypeDefinition(this.group, this.label, this.doctype, this.icon);
  final String group, label, doctype;
  final IconData icon;
}

const erpDocTypeDefinitions = <ErpDocTypeDefinition>[
  ErpDocTypeDefinition('المبيعات', 'عروض الأسعار', 'Quotation', Icons.request_quote_outlined),
  ErpDocTypeDefinition('المبيعات', 'أوامر البيع', 'Sales Order', Icons.shopping_cart_outlined),
  ErpDocTypeDefinition('المبيعات', 'أذون التسليم', 'Delivery Note', Icons.local_shipping_outlined),
  ErpDocTypeDefinition('المبيعات', 'فواتير المبيعات', 'Sales Invoice', Icons.receipt_long_outlined),
  ErpDocTypeDefinition('المبيعات', 'نقاط البيع', 'POS Invoice', Icons.point_of_sale_outlined),
  ErpDocTypeDefinition('المبيعات', 'العملاء', 'Customer', Icons.people_outline),
  ErpDocTypeDefinition('المبيعات', 'جهات الاتصال', 'Contact', Icons.contact_phone_outlined),
  ErpDocTypeDefinition('المبيعات', 'الفرص البيعية', 'Opportunity', Icons.trending_up_outlined),
  ErpDocTypeDefinition('المبيعات', 'العملاء المحتملون', 'Lead', Icons.person_search_outlined),
  ErpDocTypeDefinition('المشتريات', 'طلبات المواد', 'Material Request', Icons.playlist_add_outlined),
  ErpDocTypeDefinition('المشتريات', 'طلبات عروض الأسعار', 'Request for Quotation', Icons.request_page_outlined),
  ErpDocTypeDefinition('المشتريات', 'عروض الموردين', 'Supplier Quotation', Icons.price_check_outlined),
  ErpDocTypeDefinition('المشتريات', 'أوامر الشراء', 'Purchase Order', Icons.shopping_bag_outlined),
  ErpDocTypeDefinition('المشتريات', 'إيصالات الشراء', 'Purchase Receipt', Icons.move_to_inbox_outlined),
  ErpDocTypeDefinition('المشتريات', 'فواتير المشتريات', 'Purchase Invoice', Icons.receipt_outlined),
  ErpDocTypeDefinition('المشتريات', 'الموردون', 'Supplier', Icons.local_shipping_outlined),
  ErpDocTypeDefinition('المخزون', 'الأصناف', 'Item', Icons.inventory_2_outlined),
  ErpDocTypeDefinition('المخزون', 'المستودعات', 'Warehouse', Icons.warehouse_outlined),
  ErpDocTypeDefinition('المخزون', 'حركات المخزون', 'Stock Entry', Icons.swap_horiz_outlined),
  ErpDocTypeDefinition('المخزون', 'تسويات المخزون', 'Stock Reconciliation', Icons.fact_check_outlined),
  ErpDocTypeDefinition('المخزون', 'قوائم الالتقاط', 'Pick List', Icons.playlist_add_check_outlined),
  ErpDocTypeDefinition('المخزون', 'الدفعات', 'Batch', Icons.qr_code_2_outlined),
  ErpDocTypeDefinition('المخزون', 'الأرقام التسلسلية', 'Serial No', Icons.numbers_outlined),
  ErpDocTypeDefinition('المخزون', 'فحوصات الجودة', 'Quality Inspection', Icons.verified_outlined),
  ErpDocTypeDefinition('المحاسبة', 'القيود اليومية', 'Journal Entry', Icons.menu_book_outlined),
  ErpDocTypeDefinition('المحاسبة', 'سندات الدفع', 'Payment Entry', Icons.payments_outlined),
  ErpDocTypeDefinition('المحاسبة', 'الحسابات', 'Account', Icons.account_balance_outlined),
  ErpDocTypeDefinition('المحاسبة', 'مراكز التكلفة', 'Cost Center', Icons.account_tree_outlined),
  ErpDocTypeDefinition('المحاسبة', 'حركات البنك', 'Bank Transaction', Icons.account_balance_wallet_outlined),
  ErpDocTypeDefinition('المحاسبة', 'استيراد كشوف البنك', 'Bank Statement Import', Icons.upload_file_outlined),
  ErpDocTypeDefinition('المحاسبة', 'مطابقة المدفوعات', 'Payment Reconciliation', Icons.rule_outlined),
  ErpDocTypeDefinition('المحاسبة', 'التسوية الآلية الجماعية', 'Process Payment Reconciliation', Icons.auto_awesome_motion_outlined),
  ErpDocTypeDefinition('المحاسبة', 'سجل التسوية الآلية', 'Process Payment Reconciliation Log', Icons.receipt_long_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'الموظفون', 'Employee', Icons.badge_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'الحضور', 'Attendance', Icons.fact_check_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'طلبات الإجازة', 'Leave Application', Icons.event_available_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'تخصيص الإجازات', 'Leave Allocation', Icons.calendar_month_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'مطالبات المصروفات', 'Expense Claim', Icons.request_quote_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'مسيرات الرواتب', 'Payroll Entry', Icons.payments_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'قسائم الرواتب', 'Salary Slip', Icons.receipt_long_outlined),
  ErpDocTypeDefinition('الموارد البشرية', 'تسجيلات الحضور', 'Employee Checkin', Icons.login_outlined),
  ErpDocTypeDefinition('المشاريع والدعم', 'المشاريع', 'Project', Icons.work_outline),
  ErpDocTypeDefinition('المشاريع والدعم', 'المهام', 'Task', Icons.task_alt_outlined),
  ErpDocTypeDefinition('المشاريع والدعم', 'سجل الوقت', 'Timesheet', Icons.timer_outlined),
  ErpDocTypeDefinition('المشاريع والدعم', 'التذاكر', 'Issue', Icons.support_agent_outlined),
  ErpDocTypeDefinition('التصنيع', 'قوائم المواد', 'BOM', Icons.schema_outlined),
  ErpDocTypeDefinition('التصنيع', 'أوامر التصنيع', 'Work Order', Icons.precision_manufacturing_outlined),
  ErpDocTypeDefinition('التصنيع', 'بطاقات العمل', 'Job Card', Icons.assignment_outlined),
  ErpDocTypeDefinition('الأصول', 'الأصول الثابتة', 'Asset', Icons.apartment_outlined),
  ErpDocTypeDefinition('الأصول', 'حركة الأصول', 'Asset Movement', Icons.swap_horiz_outlined),
];

class ErpDocTypeDirectoryPage extends StatefulWidget {
  const ErpDocTypeDirectoryPage({super.key, required this.api, this.onOpenDefinition});
  final FrappeApi api;
  final ValueChanged<ErpDocTypeDefinition>? onOpenDefinition;

  @override
  State<ErpDocTypeDirectoryPage> createState() => _ErpDocTypeDirectoryPageState();
}

class _ErpDocTypeDirectoryPageState extends State<ErpDocTypeDirectoryPage> {
  List<ErpDocTypeDefinition> _definitions = erpDocTypeDefinitions;
  bool _loading = true;
  String? _directoryError;

  @override
  void initState() {
    super.initState();
    _loadWorkspaceDirectory();
  }

  Future<void> _loadWorkspaceDirectory() async {
    setState(() { _loading = true; _directoryError = null; });
    try {
      final workspaces = await widget.api.fetchWorkspaceDirectory();
      final definitions = <ErpDocTypeDefinition>[];
      final seen = <String>{};
      for (final workspace in workspaces) {
        final workspaceTitle = (workspace['title'] ?? workspace['label'] ?? workspace['name'] ?? 'ERPNext').toString();
        const workspaceLabels = <String, String>{
          'Accounting': 'المحاسبة',
          'Financial Reports': 'التقارير المالية',
          'Invoicing': 'الفوترة',
          'Payments': 'المدفوعات',
          'Assets': 'الأصول',
          'Buying': 'المشتريات',
          'CRM': 'علاقات العملاء',
          'Manufacturing': 'التصنيع',
          'Projects': 'المشاريع',
          'Quality': 'الجودة',
          'Selling': 'المبيعات',
          'ERPNext Settings': 'إعدادات النظام',
          'Stock': 'المخزون',
          'Support': 'الدعم',
          'Human Resources': 'الموارد البشرية',
          'HR': 'الموارد البشرية',
        };
        final workspaceLabel = workspaceLabels[workspaceTitle] ?? workspaceTitle;
        final links = <dynamic>[
          if (workspace['links'] is List) ...(workspace['links'] as List),
          if (workspace['sidebar_items'] is List) ...(workspace['sidebar_items'] as List),
        ];
        for (final raw in links) {
          if (raw is! Map) continue;
          final link = Map<String, dynamic>.from(raw);
          final doctype = link['link_to']?.toString().trim() ?? '';
          if (doctype.isEmpty || link['link_type']?.toString() != 'DocType' ||
              (link['hidden'] == 1 || link['hidden'] == true) || link['type'] == 'Section Break' || !seen.add('${workspaceTitle}::${doctype}')) continue;
          const translatedLabels = <String, String>{
            'Payment Request': 'طلبات الدفع',
            'Payment Order': 'أوامر الدفع',
            'Bank Account': 'الحسابات البنكية',
            'Currency': 'العملات',
            'Mode of Payment': 'طرق الدفع',
            'Price List': 'قوائم الأسعار',
            'Item Price': 'أسعار الأصناف',
            'Customer Group': 'مجموعات العملاء',
            'Supplier Group': 'مجموعات الموردين',
            'Territory': 'المناطق البيعية',
            'Campaign': 'الحملات',
            'Sales Person': 'مندوبو المبيعات',
            'Sales Partner': 'شركاء المبيعات',
            'BOM': 'قوائم المواد',
            'Work Order': 'أوامر التصنيع',
            'Job Card': 'بطاقات العمل',
            'Asset Category': 'فئات الأصول',
            'Asset Repair': 'إصلاح الأصول',
            'Quality Action': 'إجراءات الجودة',
            'Non Conformance': 'حالات عدم المطابقة',
          };
          var displayLabel = translatedLabels[doctype] ??
            ((link['label']?.toString().trim().isNotEmpty ?? false) ? link['label'].toString() : doctype);
          for (final known in erpDocTypeDefinitions) {
            if (known.doctype == doctype) { displayLabel = known.label; break; }
          }
          definitions.add(ErpDocTypeDefinition(
            workspaceLabel,
            displayLabel,
            doctype,
            _workspaceIcon(workspaceLabel),
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        if (definitions.isNotEmpty) _definitions = definitions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _directoryError = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  IconData _workspaceIcon(String workspace) {
    final value = workspace.toLowerCase();
    if (value.contains('sell') || value.contains('بيع')) return Icons.sell_outlined;
    if (value.contains('buy') || value.contains('شراء')) return Icons.shopping_bag_outlined;
    if (value.contains('stock') || value.contains('مخزون')) return Icons.inventory_2_outlined;
    if (value.contains('account') || value.contains('حساب')) return Icons.account_balance_outlined;
    if (value.contains('human') || value.contains('hr') || value.contains('موارد')) return Icons.badge_outlined;
    if (value.contains('manufact')) return Icons.precision_manufacturing_outlined;
    if (value.contains('project')) return Icons.work_outline;
    if (value.contains('asset')) return Icons.apartment_outlined;
    return Icons.folder_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ErpDocTypeDefinition>>{};
    for (final item in _definitions) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('شاشات ERPNext المستقلة'), actions: [IconButton(tooltip: 'مزامنة شاشات ERPNext', onPressed: _loading ? null : _loadWorkspaceDirectory, icon: const Icon(Icons.sync))]),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('كل نوع مستند في شاشة مستقلة'),
            subtitle: Text('تُقرأ روابط المستندات من مساحات العمل التي يعرضها خادم ERPNext للمستخدم، وتبقى الصلاحيات والتحققات النهائية للخادم.'),
          )),
          if (_loading) const LinearProgressIndicator(),
          if (_directoryError != null) Card(child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('تعذر مزامنة مساحات العمل'),
            subtitle: Text('يعرض التطبيق الدليل الاحتياطي. $_directoryError'),
            trailing: IconButton(onPressed: _loadWorkspaceDirectory, icon: const Icon(Icons.refresh)),
          )),
          for (final group in groups.entries)
            Card(child: ExpansionTile(
              initiallyExpanded: group.key == 'المبيعات' || group.key == 'المشتريات',
              leading: const Icon(Icons.folder_outlined),
              title: Text(group.key),
              subtitle: Text(group.value.length.toString() + ' شاشة'),
              children: [
                for (final item in group.value)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    subtitle: Text(item.doctype, textDirection: TextDirection.ltr),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () {
                      final open = widget.onOpenDefinition;
                      if (open != null) {
                        open(item);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute<void>(
                        builder: (_) => ErpDocTypeWorkspacePage(api: widget.api, definition: item),
                      ));
                    },
                  ),
              ],
            )),
        ],
      ),
    );
  }
}
