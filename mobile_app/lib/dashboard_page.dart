import 'package:flutter/material.dart';

import 'models/erp_models.dart';
import 'widgets/count_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.user, required this.isGuest, required this.busy, required this.onLogout, required this.companies, required this.companiesLoading, required this.companyError, required this.onRefreshCompanies, required this.inventoryLoading, required this.inventoryError, required this.onRefreshInventory, required this.items, required this.warehouses, required this.stockBalances, required this.onOpenDocTypeDirectory, required this.onOpenTransactions});

  final String? user;
  final bool isGuest;
  final bool busy;
  final VoidCallback onLogout;
  final List<ErpCompany> companies;
  final bool companiesLoading;
  final String? companyError;
  final VoidCallback onRefreshCompanies;
  final bool inventoryLoading;
  final String? inventoryError;
  final VoidCallback onRefreshInventory;
  final List<ErpItem> items;
  final List<ErpWarehouse> warehouses;
  final List<ErpStockBalance> stockBalances;
  final VoidCallback onOpenDocTypeDirectory;
  final VoidCallback onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('dashboard'),
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          const CircleAvatar(child: Icon(Icons.business)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('لوحة التحكم', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              Text(user ?? ''),
            ],
          )),
          IconButton(tooltip: 'تسجيل الخروج', onPressed: busy ? null : onLogout, icon: const Icon(Icons.logout)),
        ]),
        const SizedBox(height: 24),
        if (isGuest)
          Card(
            color: scheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(Icons.visibility_outlined),
              title: Text('وضع الضيف المحلي — بيانات تجريبية فقط'),
              subtitle: Text('أنت داخل التطبيق دون خادم أو حساب. الأسماء والأرصدة والفواتير المعروضة عينات وهمية للتجربة فقط؛ لا تحفظ عملياتك ولا تتصل ببيانات حقيقية.'),
            ),
          ),
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.cloud_done_outlined, size: 30),
              const SizedBox(height: 10),
              Text(isGuest ? 'تم فتح وضع الضيف' : 'تم الاتصال بخادم ERPNext', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 5),
              Text(isGuest ? 'تم الدخول محلياً دون إرسال أي طلب إلى خادم. كل الأرقام والسجلات المعروضة بيانات توضيحية وليست حقيقية.' : 'تسجيل الدخول والتحقق من الجلسة يعملان عبر واجهة Frappe API.'),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text(isGuest ? 'الشركة التجريبية' : 'شركات النظام', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'تحديث الشركات', onPressed: isGuest || companiesLoading ? null : onRefreshCompanies, icon: const Icon(Icons.refresh)),
        ]),
        if (companiesLoading)
          const LinearProgressIndicator()
        else if (companyError != null)
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(companyError!, style: TextStyle(color: scheme.error))))
        else if (companies.isEmpty)
          const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('لا توجد شركات ظاهرة لهذا المستخدم'), subtitle: Text('قد لا توجد شركات أو قد تكون صلاحية القراءة محدودة.')))
        else ...[
          Text('تم جلب ${companies.length} شركة من الخادم.'),
          ...companies.map((company) => Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.business_outlined)),
            title: Text(company.name),
            subtitle: company.abbr == null ? null : Text('الاختصار: ${company.abbr}'),
          ))),
        ],

        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('بيانات المخزون', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'تحديث بيانات المخزون', onPressed: isGuest || inventoryLoading ? null : onRefreshInventory, icon: const Icon(Icons.refresh)),
        ]),
        if (inventoryLoading)
          const LinearProgressIndicator(),
        if (inventoryError != null)
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(inventoryError!, style: TextStyle(color: scheme.error)))),
        ...[
          Row(children: [
            Expanded(child: CountCard(label: 'الأصناف', count: items.length, icon: Icons.inventory_2_outlined)),
            const SizedBox(width: 10),
            Expanded(child: CountCard(label: 'المستودعات', count: warehouses.length, icon: Icons.warehouse_outlined)),
          ]),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('أحدث الأصناف', style: Theme.of(context).textTheme.titleSmall),
            ...items.take(8).map((item) => ListTile(
              dense: true,
              leading: const Icon(Icons.sell_outlined),
              title: Text(item.name),
              subtitle: Text([item.code, if (item.group != null) item.group!, if (item.stockUom != null) item.stockUom!].join(' • ')),
            )),
          ],

          if (stockBalances.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('أرصدة الأصناف حسب المستودع', style: Theme.of(context).textTheme.titleSmall),
            ...stockBalances.take(30).map((balance) => ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_outlined),
              title: Text(balance.itemCode),
              subtitle: Text(balance.warehouse),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(balance.actualQty.toStringAsFixed(2), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(balance.stockUom ?? '—', style: Theme.of(context).textTheme.bodySmall),
              ]),
            )),
            if (stockBalances.length > 30) Text('يُعرض أول 30 رصيداً من أصل ${stockBalances.length}.'),
          ] else ...[
            const SizedBox(height: 8),
            const Text('لا توجد أرصدة فعلية غير صفرية ظاهرة للمستخدم.'),
          ],

          if (warehouses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('المستودعات', style: Theme.of(context).textTheme.titleSmall),
            ...warehouses.take(8).map((warehouse) => ListTile(
              dense: true,
              leading: const Icon(Icons.warehouse_outlined),
              title: Text(warehouse.name),
              subtitle: warehouse.company == null ? null : Text(warehouse.company!),
            )),
          ],
        ],
        const SizedBox(height: 18),
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.dashboard_customize_outlined)),
          title: const Text('شاشات ERPNext المستقلة'),
          subtitle: const Text('كل نوع مستند في شاشة جوال مستقلة'),
          trailing: const Icon(Icons.chevron_left),
          onTap: isGuest ? null : onOpenDocTypeDirectory,
        )),
        const SizedBox(height: 10),
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
          title: const Text('المعاملات'),
          subtitle: const Text('عرض فواتير المبيعات والمشتريات والعملاء والموردين'),
          trailing: const Icon(Icons.chevron_left),
          onTap: onOpenTransactions,
        )),
        const SizedBox(height: 10),
        Text(isGuest ? 'في وضع الضيف يمكنك استعراض العينات والبحث فيها فقط. سجّل الدخول إلى ERPNext لتفعيل إنشاء المستندات والترحيل والدفعات والتقارير.' : 'يمكنك إنشاء فواتير المبيعات وترحيلها وتسجيل دفعات العملاء وإعداد مسودات المرتجعات من شاشة المعاملات.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
