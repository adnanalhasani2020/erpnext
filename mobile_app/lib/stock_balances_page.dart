import 'package:flutter/material.dart';

import 'models/erp_models.dart';
import 'widgets/count_card.dart';
import 'widgets/server_search_field.dart';

class StockBalancesPage extends StatelessWidget {
  const StockBalancesPage({super.key,required this.stockBalances,required this.warehouses,required this.items,required this.search,required this.searchController,required this.selectedWarehouse,required this.guest,required this.loading,required this.loadingMore,required this.error,required this.hasMore,required this.onSearch,required this.onOpenStockWorkflow,required this.onSelectWarehouse,required this.onLoadMore,required this.onShowItemDetails});
  final List<ErpStockBalance> stockBalances;
  final List<ErpWarehouse> warehouses;
  final List<ErpItem> items;
  final String search;
  final TextEditingController searchController;
  final String? selectedWarehouse;
  final bool guest,loading,loadingMore,hasMore;
  final String? error;
  final void Function(String,{bool updateWarehouse,String? warehouse}) onSearch;
  final VoidCallback onOpenStockWorkflow;
  final ValueChanged<String?> onSelectWarehouse;
  final VoidCallback onLoadMore;
  final ValueChanged<ErpStockBalance> onShowItemDetails;

  @override
  Widget build(BuildContext context){
    final filtered=stockBalances.where((row)=>(search.isEmpty||row.itemCode.toLowerCase().contains(search.toLowerCase()))&&(selectedWarehouse==null||row.warehouse==selectedWarehouse)).toList(growable:false);
    final loadedWarehouses=filtered.map((row)=>row.warehouse).toSet().length;
    return ListView(padding:const EdgeInsets.all(18),children:[
      if(guest) const Card(child:ListTile(leading:Icon(Icons.science_outlined),title:Text('بيانات تجريبية محلية'),subtitle:Text('هذه سجلات وهمية للاستعراض فقط. لا يوجد اتصال بالخادم ولا يمكن حفظ معاملات.'))),
      Row(children:[const CircleAvatar(child:Icon(Icons.inventory_2_outlined)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('أرصدة المخزون',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),Text('الكميات وقيمة المخزون ومعدل التقييم حسب المستودع',style:Theme.of(context).textTheme.bodySmall)])),IconButton(tooltip:'تحديث البيانات',onPressed:guest||loading?null:onLoadMore,icon:const Icon(Icons.refresh))]),
      const Text('قيمة المخزون ومعدل التقييم من سجل Bin في ERPNext وبعملة الشركة المالكة للمستودع. لا تجمع القيم بين شركات ذات عملات مختلفة.'),const SizedBox(height:16),
      DropdownButtonFormField<String>(initialValue:selectedWarehouse,isExpanded:true,decoration:const InputDecoration(labelText:'تصفية حسب المستودع'),items:[const DropdownMenuItem<String>(value:null,child:Text('كل المستودعات')),...warehouses.map((warehouse)=>DropdownMenuItem<String>(value:warehouse.id,child:Text(warehouse.name,overflow:TextOverflow.ellipsis)))],onChanged:onSelectWarehouse),
      const SizedBox(height:12),FilledButton.icon(onPressed:guest?null:onOpenStockWorkflow,icon:const Icon(Icons.tune),label:const Text('فتح عمليات المخزون المتقدمة')),const SizedBox(height:10),
      ServerSearchField(controller:searchController,label:'ابحث برمز الصنف',onSearch:onSearch,loading:loading,buttonLabel:guest?'بحث محلي':'بحث في الخادم'),const SizedBox(height:8),
      Row(children:[Expanded(child:CountCard(label:'الأرصدة المحمّلة',count:filtered.length,icon:Icons.inventory_outlined)),const SizedBox(width:8),Expanded(child:CountCard(label:'مستودعات ضمن النتائج',count:loadedWarehouses,icon:Icons.warehouse_outlined))]),
      const Text('الأعداد تخص النتائج المحمّلة فقط. لا تُجمع كميات الأصناف مع اختلاف وحدات القياس.'),
      if(loading) const LinearProgressIndicator(),if(error!=null) Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)))),
      if(filtered.isEmpty&&!loading) const Card(child:ListTile(title:Text('لا توجد أرصدة مطابقة لرمز الصنف والمستودع المحددين'))),
      ...filtered.map((balance)=>Card(child:ListTile(title:Text(balance.itemCode),subtitle:Text('${balance.warehouse}\nمحجوز: ${balance.reservedQty} • متوقع: ${balance.projectedQty}\nقيمة المخزون: ${balance.stockValue?.toStringAsFixed(2)??'غير متاحة'} • معدل التقييم: ${balance.valuationRate?.toStringAsFixed(2)??'غير متاح'}'),isThreeLine:true,trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(balance.actualQty.toStringAsFixed(2),style:Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight:FontWeight.bold)),Text('متاح: ${balance.availableQty.toStringAsFixed(2)}',style:Theme.of(context).textTheme.bodySmall),Text(balance.stockUom??'—',style:Theme.of(context).textTheme.bodySmall)]),onTap:()=>onShowItemDetails(balance)))),
      if(hasMore||loadingMore) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:FilledButton.tonal(onPressed:loadingMore?null:onLoadMore,child:Text(loadingMore?'جارٍ تحميل المزيد...':'تحميل المزيد من الأرصدة'))),
    ]);
  }
}
