import 'package:flutter/material.dart';

import 'models/erp_models.dart';

class ItemListPage extends StatelessWidget {
  const ItemListPage({super.key, required this.items, required this.search, required this.searchController, required this.guest, required this.loading, required this.loadingMore, required this.error, required this.hasMore, required this.onSearch, required this.onLoadMore, required this.onShowDetails,required this.onRefresh});
  final List<ErpItem> items;
  final String search;
  final TextEditingController searchController;
  final bool guest, loading, loadingMore, hasMore;
  final String? error;
  final ValueChanged<String> onSearch;
  final VoidCallback onLoadMore;
  final ValueChanged<ErpItem> onShowDetails;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final query=search.trim().toLowerCase();
    final filtered=items.where((item)=>item.code.toLowerCase().contains(query)||item.name.toLowerCase().contains(query)||(item.group??'').toLowerCase().contains(query)).toList(growable:false);
    return ListView(padding:const EdgeInsets.all(18),children:[
      if(guest) const Card(child:ListTile(leading:Icon(Icons.science_outlined),title:Text('بيانات تجريبية محلية'),subtitle:Text('هذه سجلات وهمية للاستعراض فقط. لا يوجد اتصال بالخادم ولا يمكن حفظ معاملات.'))),
      Row(children:[const CircleAvatar(child:Icon(Icons.sell_outlined)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('الأصناف',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),Text('بحث في الأصناف المحمّلة من ERPNext',style:Theme.of(context).textTheme.bodySmall)])),IconButton(tooltip:'تحديث البيانات',onPressed:guest||loading?null:onRefresh,icon:const Icon(Icons.refresh))]),
      const SizedBox(height:16),
      TextField(controller:searchController,enabled:!loading,textInputAction:TextInputAction.search,decoration:InputDecoration(labelText:'ابحث بالاسم أو الرمز',prefixIcon:const Icon(Icons.search),suffixIcon:searchController.text.isEmpty?null:IconButton(tooltip:'مسح البحث',onPressed:(){searchController.clear();onSearch('');},icon:const Icon(Icons.clear))),onSubmitted:onSearch),
      const SizedBox(height:8),
      FilledButton.tonalIcon(onPressed:loading||loadingMore?null:()=>onSearch(searchController.text),icon:const Icon(Icons.search),label:Text(guest?'بحث محلي':'بحث في جميع الأصناف بالخادم')),
      const SizedBox(height:10),Text('المعروض ${filtered.length} من ${items.length} صنف في نتيجة البحث الحالية'),
      if(loading) const LinearProgressIndicator(),
      if(error!=null) Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)))),
      if(filtered.isEmpty&&!loading) const Card(child:ListTile(leading:Icon(Icons.search_off),title:Text('لا توجد أصناف مطابقة'))),
      ...filtered.map((item)=>Card(child:ListTile(leading:CircleAvatar(child:Icon(item.isStockItem?Icons.inventory_2_outlined:Icons.miscellaneous_services_outlined)),title:Text(item.name),subtitle:Text([item.code,if(item.group!=null)item.group!,if(item.stockUom!=null)item.stockUom!].join(' • ')),trailing:const Icon(Icons.chevron_left),onTap:()=>onShowDetails(item)))),
      if(hasMore||loadingMore) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:FilledButton.tonal(onPressed:loadingMore?null:onLoadMore,child:Text(loadingMore?'جارٍ تحميل المزيد...':'تحميل المزيد من الأصناف'))),
    ]);
  }
}
