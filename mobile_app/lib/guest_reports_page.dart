import 'package:flutter/material.dart';

class GuestReportsPage extends StatelessWidget {
  const GuestReportsPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: const [
      GuestDemoBanner(),
      _GuestReportsHeader(),
      SizedBox(height: 12),
      Card(child: ListTile(
        leading: Icon(Icons.account_balance_wallet_outlined),
        title: Text('ذمم العملاء التجريبية'),
        subtitle: Text('25,000 ر.ي — مبلغ متبقٍ على فواتير عينة'),
      )),
      Card(child: ListTile(
        leading: Icon(Icons.local_shipping_outlined),
        title: Text('ذمم الموردين التجريبية'),
        subtitle: Text('150,000 ر.ي — مبلغ متبقٍ على فواتير عينة'),
      )),
      Card(child: ListTile(
        leading: Icon(Icons.bar_chart_outlined),
        title: Text('تقرير الأرباح والخسائر'),
        subtitle: Text('عرض توضيحي فقط؛ لا يمثل بيانات محاسبية حقيقية.'),
      )),
      Card(child: ListTile(
        leading: Icon(Icons.inventory_2_outlined),
        title: Text('تقييم المخزون'),
        subtitle: Text('القيم المعروضة عينات افتراضية بعملة الريال اليمني.'),
      )),
    ],
  );
}

class GuestDemoBanner extends StatelessWidget {
  const GuestDemoBanner({super.key});

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: const ListTile(
      dense: true,
      leading: Icon(Icons.science_outlined),
      title: Text('بيانات تجريبية محلية'),
      subtitle: Text('هذه سجلات وهمية للاستعراض فقط. لا يوجد اتصال بالخادم ولا يمكن حفظ معاملات حقيقية.'),
    ),
  );
}

class _GuestReportsHeader extends StatelessWidget {
  const _GuestReportsHeader();

  @override
  Widget build(BuildContext context) => Row(children: [
    CircleAvatar(child: Icon(Icons.assessment_outlined)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('التقارير', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      Text('ملخصات مالية تجريبية محلية', style: Theme.of(context).textTheme.bodySmall),
    ])),
  ]);
}
