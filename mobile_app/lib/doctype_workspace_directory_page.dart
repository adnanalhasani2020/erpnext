import 'dart:convert';
import 'package:flutter/material.dart';
import 'api/frappe_api.dart';
import 'doctype_workspace_model.dart';
import 'doctype_workspace_editor_page.dart';
import 'workspace_web_page.dart';

const erpDocTypeLabelHints = <ErpDocTypeDefinition>[
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
  List<ErpDocTypeDefinition> _definitions = const [];
  Map<String, List<Map<String, dynamic>>> _workspaceNumberCards = const {};
  bool _loading = true;
  String? _directoryError;

  @override
  void initState() {
    super.initState();
    _loadWorkspaceDirectory();
  }

  Map<String, dynamic> _routeOptions(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  static const _workspaceLinkTypes = {'DocType', 'Report', 'Page', 'URL', 'Dashboard', 'Workspace'};

  Future<void> _loadWorkspaceDirectory() async {
    setState(() { _loading = true; _directoryError = null; });
    try {
      final workspaces = await widget.api.fetchWorkspaceDirectory();
      final definitions = <ErpDocTypeDefinition>[];
      final numberCardsByWorkspace = <String, List<Map<String, dynamic>>>{};
      final seen = <String>{};
      for (final workspace in workspaces) {
        final workspaceTitle = (workspace['title'] ?? workspace['label'] ?? workspace['name'] ?? 'ERPNext').toString();
        final workspaceName = (workspace['name'] ?? workspaceTitle).toString();
        final rawNumberCards = workspace['number_cards'];
        if (rawNumberCards is List) {
          final cards = rawNumberCards
              .whereType<Map>()
              .map((card) => Map<String, dynamic>.from(card))
              .where((card) => (card['number_card_name']?.toString().trim().isNotEmpty ?? false))
              .toList();
          if (cards.isNotEmpty) numberCardsByWorkspace[workspaceName] = cards;
        }
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
        if (workspace['type']?.toString() == 'Link') {
          final linkType = workspace['link_type']?.toString() ?? '';
          final target = workspace['link_to']?.toString().trim() ?? '';
          final supported = _workspaceLinkTypes.contains(linkType);
          final routeOptions = _routeOptions(workspace['route_options']);
          if (supported && target.isNotEmpty &&
              seen.add('${workspaceName}::اختصارات::${linkType}::${target}::${jsonEncode(routeOptions)}')) {
            definitions.add(ErpDocTypeDefinition(
              workspaceLabel,
              workspace['title']?.toString() ?? workspace['label']?.toString() ?? target,
              target,
              _workspaceIcon(workspaceLabel),
              'اختصارات',
              linkType,
              routeOptions,
              workspaceName,
            ));
          }
          continue;
        }
        if (workspace['type']?.toString() == 'URL') {
          final target = (workspace['url'] ?? workspace['link_to'] ?? '').toString().trim();
          if (target.isNotEmpty && seen.add('${workspaceName}::URL::${target}')) {
            definitions.add(ErpDocTypeDefinition(
              workspaceLabel, workspace['label']?.toString() ?? target, target,
              _workspaceIcon(workspaceLabel), 'اختصارات', 'URL', const {}, workspaceName,
            ));
          }
          continue;
        }
        final shortcuts = workspace['shortcuts'];
        if (shortcuts is List) {
          for (final rawShortcut in shortcuts) {
            if (rawShortcut is! Map) continue;
            final shortcut = Map<String, dynamic>.from(rawShortcut);
            final shortcutType = shortcut['type']?.toString() ?? '';
            if (!_workspaceLinkTypes.contains(shortcutType) ||
                (shortcut['hidden'] == 1 || shortcut['hidden'] == true)) continue;
            final doctype = shortcut['link_to']?.toString().trim() ?? '';
            final routeOptions = _routeOptions(shortcut['route_options']);
            if (doctype.isEmpty || !seen.add('${workspaceName}::اختصارات::${shortcutType}::${doctype}::${jsonEncode(routeOptions)}')) continue;
            final label = shortcut['label']?.toString().trim() ?? '';
            definitions.add(ErpDocTypeDefinition(
              workspaceLabel,
              label.isEmpty ? doctype : label,
              doctype,
              _workspaceIcon(workspaceLabel),
              'اختصارات',
              shortcutType,
              routeOptions,
              workspaceName,
            ));
          }
        }
        final workspaceLinks = workspace['links'];
        final sidebarItems = workspace['sidebar_items'];
        // Workspace page cards and the sidebar are two parallel navigation
        // representations. Prefer the page's Card Break grouping when present;
        // use sidebar Section Breaks only for sidebar-only workspaces.
        final links = workspaceLinks is List && workspaceLinks.isNotEmpty
            ? List<dynamic>.from(workspaceLinks)
            : sidebarItems is List ? List<dynamic>.from(sidebarItems) : <dynamic>[];
        var currentSection = 'عام';
        var hiddenCard = false;
        for (final raw in links) {
          if (raw is! Map) continue;
          final link = Map<String, dynamic>.from(raw);
          final workspaceLinkKind = link['type']?.toString() ?? '';
          if (workspaceLinkKind == 'Card Break' || workspaceLinkKind == 'Section Break' || workspaceLinkKind == 'Header') {
            hiddenCard = link['hidden'] == 1 || link['hidden'] == true;
            final heading = link['label']?.toString().trim() ?? '';
            if (!hiddenCard && heading.isNotEmpty) currentSection = heading;
            continue;
          }
          if (hiddenCard) continue;
          final doctype = link['link_to']?.toString().trim() ?? '';
          final linkType = link['link_type']?.toString() ?? '';
          final routeOptions = _routeOptions(link['route_options']);
          if (doctype.isEmpty || !_workspaceLinkTypes.contains(linkType) ||
              (link['hidden'] == 1 || link['hidden'] == true) ||
              !seen.add('${workspaceName}::${currentSection}::${linkType}::${doctype}::${jsonEncode(routeOptions)}')) continue;
          const translatedLabels = <String, String>{
            'Credit Note': 'إشعار دائن',
            'Debit Note': 'إشعار مدين',
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
          final sourceLabel = link['label']?.toString().trim() ?? '';
          var displayLabel = routeOptions.isNotEmpty && sourceLabel.isNotEmpty
              ? (translatedLabels[sourceLabel] ?? sourceLabel)
              : translatedLabels[doctype] ?? (sourceLabel.isNotEmpty ? sourceLabel : doctype);
          if (routeOptions.isEmpty && (sourceLabel.isEmpty || sourceLabel == doctype)) {
            for (final known in erpDocTypeLabelHints) {
              if (known.doctype == doctype) { displayLabel = known.label; break; }
            }
          }
          definitions.add(ErpDocTypeDefinition(
            workspaceLabel,
            displayLabel,
            doctype,
            _workspaceIcon(workspaceLabel),
            currentSection,
            linkType,
            routeOptions,
            workspaceName,
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        _definitions = definitions;
        _workspaceNumberCards = numberCardsByWorkspace;
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
    // Keep separate ERPNext Workspace records separate even when their
    // translated titles happen to be identical (for example, ERPNext and HRMS).
    final groups = <String, List<ErpDocTypeDefinition>>{};
    for (final item in _definitions) {
      final workspaceKey = item.workspaceName.isEmpty ? item.group : item.workspaceName;
      groups.putIfAbsent(workspaceKey, () => []).add(item);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('مساحات العمل'), actions: [IconButton(tooltip: 'مزامنة شاشات ERPNext', onPressed: _loading ? null : _loadWorkspaceDirectory, icon: const Icon(Icons.sync))]),
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
            subtitle: Text('لم يتم تحميل روابط الشاشات من ERPNext؛ لن يعرض التطبيق قائمة افتراضية غير مؤكدة. $_directoryError'),
            trailing: IconButton(onPressed: _loadWorkspaceDirectory, icon: const Icon(Icons.refresh)),
          )),
          if (!_loading && _directoryError == null && _definitions.isEmpty)
            const Card(child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('لا توجد روابط شاشات متاحة'),
              subtitle: Text('لم يُرجع ERPNext أي روابط Workspace مرئية لهذا المستخدم.'),
            )),
          for (final group in groups.entries)
            Builder(builder: (context) {
              final workspaceLabel = group.value.first.group;
              final sections = <String, List<ErpDocTypeDefinition>>{};
              for (final item in group.value) {
                sections.putIfAbsent(item.section, () => []).add(item);
              }
              final numberCards = _workspaceNumberCards[group.key] ?? const <Map<String, dynamic>>[];
              return Card(child: ExpansionTile(
                initiallyExpanded: workspaceLabel == 'المبيعات' || workspaceLabel == 'المشتريات',
                leading: group.value.first.workspaceName.isEmpty
                    ? const Icon(Icons.folder_outlined)
                    : IconButton(
                        tooltip: 'فتح مساحة العمل الأصلية في ERPNext',
                        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                          builder: (_) => WorkspaceWebPage(
                            api: widget.api,
                            title: group.key,
                            linkType: 'Workspace',
                            target: group.value.first.workspaceName,
                          ),
                        )),
                        icon: const Icon(Icons.open_in_browser),
                      ),
                title: Text(workspaceLabel),
                subtitle: Text(group.value.length.toString() + ' شاشة'),
                children: [
                  if (numberCards.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final card in numberCards)
                            _WorkspaceNumberCard(
                              api: widget.api,
                              name: card['number_card_name'].toString(),
                              label: card['label']?.toString() ?? card['number_card_name'].toString(),
                            ),
                        ],
                      ),
                    ),
                  for (final section in sections.entries)
                    ExpansionTile(
                      initiallyExpanded: sections.length == 1,
                      leading: const Icon(Icons.view_agenda_outlined),
                      title: Text(section.key),
                      subtitle: Text(section.value.length.toString() + ' مستند'),
                      children: [
                        for (final item in section.value)
                          ListTile(
                            leading: Icon(item.icon),
                            title: Text(item.label),
                            subtitle: Text(item.linkType == 'Report' ? 'تقرير • ${item.doctype}' : item.doctype, textDirection: TextDirection.ltr),
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
                    ),
                ],
              ));
            }),
        ],
      ),
    );
  }
}


class _WorkspaceNumberCard extends StatefulWidget {
  const _WorkspaceNumberCard({
    required this.api,
    required this.name,
    required this.label,
  });

  final FrappeApi api;
  final String name;
  final String label;

  @override
  State<_WorkspaceNumberCard> createState() => _WorkspaceNumberCardState();
}

class _WorkspaceNumberCardState extends State<_WorkspaceNumberCard> {
  late Future<double?> _value;

  @override
  void initState() {
    super.initState();
    _value = widget.api.fetchWorkspaceNumberCardValue(widget.name);
  }

  @override
  void didUpdateWidget(covariant _WorkspaceNumberCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.name != widget.name) {
      _value = widget.api.fetchWorkspaceNumberCardValue(widget.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double?>(
      future: _value,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data == null) return const SizedBox.shrink();
        return SizedBox(
          width: 156,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(height: 22, child: LinearProgressIndicator())
                  else if (snapshot.hasError)
                    const Icon(Icons.info_outline, size: 20)
                  else
                    Text(
                      snapshot.data?.toString() ?? '—',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
