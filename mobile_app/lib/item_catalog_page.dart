import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'api/frappe_api.dart';
import 'doctype_workspace_editor_page.dart';
import 'doctype_workspace_model.dart';
import 'workspace_native_destination_page.dart';
import 'master_data_page.dart';
import 'models/erp_models.dart';

class ItemCatalogPage extends StatefulWidget {
  const ItemCatalogPage({super.key, required this.api, this.companies = const []});
  final FrappeApi api;
  final List<ErpCompany> companies;
  @override
  State<ItemCatalogPage> createState() => _ItemCatalogPageState();
}

class _ItemCatalogPageState extends State<ItemCatalogPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<String> _groups = [], _brands = [];
  String? _group, _brand, _status = 'active', _message, _error;
  bool _loading = false, _more = false, _hasMore = false, _grid = true;
  int _offset = 0;

  @override
  void initState() { super.initState(); _loadFilters(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _loadFilters() async {
    List<Map<String, dynamic>> groups = [];
    List<String> brands = [];
    try { groups = await widget.api.fetchMasterDataRows(doctype: 'Item Group'); } catch (_) {}
    try { brands = await widget.api.fetchItemBrands(); } catch (_) {}
    if (!mounted) return;
    setState(() {
      _groups = groups.map((e) => e['name']?.toString() ?? '').where((e) => e.isNotEmpty).toList();
      _brands = brands;
    });
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _more || (more && !_hasMore)) return;
    setState(() { if (more) { _more = true; } else { _loading = true; _error = null; } _message = null; });
    try {
      final page = await widget.api.fetchItemCatalogRows(
        start: more ? _offset : 0, search: _search.text, itemGroup: _group, brand: _brand, status: _status);
      if (!mounted) return;
      setState(() {
        if (more) {
          final ids = _items.map((e) => e['name']?.toString()).toSet();
          _items.addAll(page.where((e) => !ids.contains(e['name']?.toString())));
        } else { _items = page; }
        _offset = more ? _offset + page.length : page.length;
        _hasMore = page.length == FrappeApi.pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() { _loading = false; _more = false; }); }
  }

  String _title(Map<String, dynamic> row) =>
      row['item_name']?.toString().trim().isNotEmpty == true ? row['item_name'].toString() : row['name']?.toString() ?? '';

  String? _imageUrl(dynamic raw) {
    final path = raw?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (widget.api.baseUrl.isEmpty) return null;
    return '${widget.api.baseUrl}/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Widget _image(Map<String, dynamic> row, {double size = 72}) {
    final url = _imageUrl(row['image']);
    return ClipRRect(borderRadius: BorderRadius.circular(9), child: Container(
      width: size, height: size, color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: url == null ? const Icon(Icons.inventory_2_outlined, size: 30)
          : Image.network(url, headers: widget.api.imageRequestHeadersFor(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
    ));
  }

  void _details(String code) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    builder: (_) => ItemCatalogDetailsSheet(api: widget.api, itemCode: code));

  Future<void> _edit([String? code]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (_) => _ItemCatalogEditor(api: widget.api, itemCode: code));
    if (saved == true && mounted) _load();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _BarcodeScannerPage()));
    if (code == null || code.isEmpty || !mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final item = await widget.api.fetchItemByBarcode(code);
      if (!mounted) return;
      if (item == null) { setState(() => _error = 'لا يوجد صنف مرتبط بالباركود $code'); }
      else { _details(item['name'].toString()); }
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<List<Map<String, dynamic>>> _allRows() async {
    final all = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final page = await widget.api.fetchItemCatalogRows(
        start: start, search: _search.text, itemGroup: _group, brand: _brand, status: _status);
      all.addAll(page);
      if (page.length < FrappeApi.pageSize) break;
      start += page.length;
      if (all.length >= 10000) throw const FormatException('حد التصدير 10,000 صنف؛ استخدم فلاتر أضيق.');
    }
    return all;
  }

  Future<void> _export() async {
    setState(() => _message = 'جارٍ تجهيز ملف Excel...');
    try {
      final rows = await _allRows();
      final book = Excel.createExcel();
      final sheet = book['Items'];
      const keys = ['item_code','item_name','item_group','stock_uom','brand','description','image','disabled'];
      sheet.appendRow(keys.map((e) => TextCellValue(e)).toList());
      for (final row in rows) {
        sheet.appendRow(keys.map((key) => TextCellValue(row[key]?.toString() ?? '')).toList());
      }
      final bytes = book.encode();
      if (bytes == null) throw const FormatException('تعذر إنشاء ملف Excel.');
      await Share.shareXFiles([XFile.fromData(Uint8List.fromList(bytes), name: 'erpnext_items.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        text: 'دليل الأصناف من ERPNext: ${rows.length} صنف');
      if (mounted) setState(() => _message = 'تم تجهيز ${rows.length} صنفاً للمشاركة.');
    } catch (e) { if (mounted) setState(() => _message = 'فشل التصدير: ${e.toString()}'); }
  }

  String _str(dynamic v) => v?.toString().trim() ?? '';
  Future<void> _import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw const FormatException('تعذر قراءة الملف.');
      final book = Excel.decodeBytes(bytes);
      if (book.tables.isEmpty) throw const FormatException('ملف Excel فارغ.');
      final sheet = book.tables[book.tables.keys.first]!;
      if (sheet.rows.length < 2) throw const FormatException('لا توجد صفوف للاستيراد.');
      final headers = sheet.rows.first.map((c) => _str(c?.value).toLowerCase()).toList();
      const required = ['item_code','item_name','item_group','stock_uom'];
      for (final key in required) { if (!headers.contains(key)) throw FormatException('العمود $key مطلوب.'); }
      final index = <String,int>{for (var i=0;i<headers.length;i++) if(headers[i].isNotEmpty) headers[i]:i};
      String val(List<Data?> row,String key) { final i=index[key]; return i==null||i>=row.length?'':_str(row[i]?.value); }
      final rows = sheet.rows.skip(1).where((r)=>r.any((c)=>_str(c?.value).isNotEmpty)).toList();
      if (rows.length > 500) throw const FormatException('الحد الأقصى 500 صنف في الدفعة الواحدة.');
      final seenCodes = <String>{};
      final duplicateCodes = <String>{};
      final invalidRows = <int>[];
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final code = val(row, 'item_code');
        final name = val(row, 'item_name');
        final group = val(row, 'item_group');
        final uom = val(row, 'stock_uom');
        if ([code, name, group, uom].any((v) => v.isEmpty)) {
          invalidRows.add(i + 2);
        }
        if (code.isNotEmpty && !seenCodes.add(code)) duplicateCodes.add(code);
      }
      if (invalidRows.isNotEmpty || duplicateCodes.isNotEmpty) {
        final rowText = invalidRows.take(8).join('، ');
        final duplicateText = duplicateCodes.take(8).join('، ');
        throw FormatException([
          if (invalidRows.isNotEmpty) 'بيانات أساسية ناقصة في الصفوف: $rowText${invalidRows.length > 8 ? ' وغيرها' : ''}.',
          if (duplicateCodes.isNotEmpty) 'رموز أصناف مكررة داخل الملف: $duplicateText${duplicateCodes.length > 8 ? ' وغيرها' : ''}.',
          'لم يُحفظ أي صنف. صحح الملف ثم أعد الاستيراد.',
        ].join(' '));
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد استيراد دليل الأصناف'),
          content: Text(
            'سيتم إرسال ${rows.length} صنفاً إلى ERPNext. '
            'الرمز الموجود مسبقاً سيحدّث الصنف الحالي، والرمز الجديد سينشئ صنفاً جديداً. '
            'قد ينجح بعض السجلات ويفشل بعضها بحسب صلاحيات الخادم والبيانات المرجعية. '
            'لن يبدأ الحفظ قبل تأكيدك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ابدأ الاستيراد'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      var ok=0, failed=0; final errors=<String>[];
      for (final row in rows) {
        final code=val(row,'item_code'), name=val(row,'item_name'), group=val(row,'item_group'), uom=val(row,'stock_uom');
        try {
          await widget.api.saveMasterDataDocument(doctype:'Item', name:code, values:{
            'item_code':code,'item_name':name,'item_group':group,'stock_uom':uom,
            if(val(row,'brand').isNotEmpty)'brand':val(row,'brand'),
            if(val(row,'description').isNotEmpty)'description':val(row,'description'),
            if(val(row,'image').isNotEmpty)'image':val(row,'image'),
            'disabled': val(row,'disabled')=='1'||val(row,'disabled').toLowerCase()=='true',
          });
          ok++;
        } catch(e) { failed++; if(errors.length<8) errors.add('$code: ${e.toString().replaceFirst('Exception: ','')}'); }
      }
      if (!mounted) return;
      final suffix = errors.isEmpty ? '' : '\n${errors.join('\n')}';
      final report = 'الاستيراد: $ok ناجح، $failed فشل.$suffix';
      setState(()=>_message=report);
      await _load();
      if (mounted) { setState(() => _message = report); }
    } catch(e) { if(mounted) setState(()=>_message='تعذر الاستيراد: ${e.toString()}'); }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
    appBar: AppBar(title: const Text('دليل الأصناف'), actions: [
      IconButton(tooltip: 'فتح قائمة الجوال', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceNativeDestinationPage(api: widget.api, title: 'Item', linkType: 'DocTypeList', target: 'Item'))), icon: const Icon(Icons.arrow_forward)),
      IconButton(tooltip:'مسح باركود', onPressed:_loading?null:_scan, icon:const Icon(Icons.qr_code_scanner)),
      IconButton(tooltip:'تصدير Excel', onPressed:_loading?null:_export, icon:const Icon(Icons.file_download_outlined)),
      PopupMenuButton<String>(onSelected:(v){
        if(v=='import') { _import(); }
        if(v=='other') {
          Navigator.push(context,MaterialPageRoute<void>(
            builder:(_)=>MasterDataPage(api:widget.api,companies:widget.companies,initialType:'Item Group')));
        }
      },
        itemBuilder:(_)=>const [
          PopupMenuItem(value:'import',child:Text('استيراد Excel')),
          PopupMenuItem(value:'other',child:Text('بيانات أساسية أخرى')),
        ]),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed:_loading?null:()=>_edit(), icon:const Icon(Icons.add), label:const Text('صنف جديد')),
    body: Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,10,12,6),child:TextField(
        controller:_search,textInputAction:TextInputAction.search,onSubmitted:(_)=>_load(),
        decoration:InputDecoration(labelText:'بحث بالرمز أو الاسم أو المجموعة أو العلامة',
          prefixIcon:const Icon(Icons.search),suffixIcon:IconButton(onPressed:_load,icon:const Icon(Icons.search))))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Wrap(spacing:8,runSpacing:8,children:[
        SizedBox(width:165,child:DropdownButtonFormField<String?>(initialValue:_group,isExpanded:true,
          decoration:const InputDecoration(labelText:'المجموعة'),
          items:[const DropdownMenuItem<String?>(value:null,child:Text('كل المجموعات')),
            ..._groups.map((v)=>DropdownMenuItem<String?>(value:v,child:Text(v,overflow:TextOverflow.ellipsis)))],
          onChanged:(v){setState(()=>_group=v);_load();})),
        SizedBox(width:145,child:DropdownButtonFormField<String?>(initialValue:_brand,isExpanded:true,
          decoration:const InputDecoration(labelText:'العلامة التجارية'),
          items:[const DropdownMenuItem<String?>(value:null,child:Text('كل العلامات')),
            ..._brands.map((v)=>DropdownMenuItem<String?>(value:v,child:Text(v,overflow:TextOverflow.ellipsis)))],
          onChanged:(v){setState(()=>_brand=v);_load();})),
        SizedBox(width:125,child:DropdownButtonFormField<String>(initialValue:_status,
          decoration:const InputDecoration(labelText:'الحالة'),
          items:const [DropdownMenuItem(value:'active',child:Text('النشطة')),
            DropdownMenuItem(value:'disabled',child:Text('المعطلة')),DropdownMenuItem(value:'all',child:Text('الكل'))],
          onChanged:(v){setState(()=>_status=v);_load();})),
        IconButton.filledTonal(onPressed:()=>setState(()=>_grid=!_grid),
          tooltip:_grid?'عرض قائمة':'عرض شبكة',icon:Icon(_grid?Icons.view_list:Icons.grid_view)),
        IconButton(onPressed:_load,icon:const Icon(Icons.refresh)),
      ])),
      if(_message!=null) Padding(padding:const EdgeInsets.all(8),child:Card(child:Padding(padding:const EdgeInsets.all(8),child:Text(_message!)))),
      if(_loading) const LinearProgressIndicator(),
      if(_error!=null) ListTile(leading:const Icon(Icons.error_outline),title:const Text('تعذر تحميل الأصناف'),
        subtitle:Text(_error!),trailing:IconButton(onPressed:_load,icon:const Icon(Icons.refresh))),
      Expanded(child:_items.isEmpty&&!_loading?const Center(child:Text('لا توجد أصناف مطابقة.')):
        _grid?GridView.builder(padding:const EdgeInsets.all(12),
          gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:230,mainAxisExtent:210,crossAxisSpacing:10,mainAxisSpacing:10),
          itemCount:_items.length,itemBuilder:(_,i)=>Card(clipBehavior:Clip.antiAlias,child:InkWell(
            onTap:()=>_details(_items[i]['name'].toString()),child:Padding(padding:const EdgeInsets.all(10),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Center(child:_image(_items[i],size:82)),const SizedBox(height:8),
                Text(_title(_items[i]),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold)),
                Text('${_items[i]['name']} • ${_items[i]['stock_uom']??''}',maxLines:1,overflow:TextOverflow.ellipsis),
                Text(_items[i]['item_group']?.toString()??'',maxLines:1,overflow:TextOverflow.ellipsis),
                const Spacer(),Row(children:[Expanded(child:Text(_items[i]['brand']?.toString()??'بدون علامة',maxLines:1,overflow:TextOverflow.ellipsis)),
                  IconButton(onPressed:()=>_edit(_items[i]['name'].toString()),icon:const Icon(Icons.edit_outlined))]),
              ]))))):
        ListView.builder(padding:const EdgeInsets.all(10),itemCount:_items.length,itemBuilder:(_,i)=>Card(child:ListTile(
          leading:_image(_items[i]),title:Text(_title(_items[i])),
          subtitle:Text('${_items[i]['name']} • ${_items[i]['item_group']??''}\n${_items[i]['brand']??''} • ${_items[i]['stock_uom']??''}'),
          isThreeLine:true,onTap:()=>_details(_items[i]['name'].toString()),
          trailing:IconButton(onPressed:()=>_edit(_items[i]['name'].toString()),icon:const Icon(Icons.edit_outlined)))))),
      if(_hasMore||_more) Padding(padding:const EdgeInsets.all(10),child:OutlinedButton.icon(
        onPressed:_more?null:()=>_load(more:true),icon:const Icon(Icons.expand_more),label:Text(_more?'جارٍ التحميل...':'تحميل المزيد'))),
    ]),
  ));
}

class ItemCatalogDetailsSheet extends StatefulWidget {
  const ItemCatalogDetailsSheet({super.key,required this.api,required this.itemCode});
  final FrappeApi api; final String itemCode;
  @override
  State<ItemCatalogDetailsSheet> createState()=>_ItemCatalogDetailsSheetState();
}
class _ItemCatalogDetailsSheetState extends State<ItemCatalogDetailsSheet> {
  late Future<Map<String,dynamic>> _doc;
  List<Map<String,dynamic>> _prices=[],_bins=[];
  bool _loading=true; String? _error;
  @override
  void initState(){super.initState();_doc=widget.api.fetchItemCatalogDocument(widget.itemCode);_related();}
  Future<void> _related() async {
    try {
      final prices=await widget.api.fetchItemCatalogPrices(widget.itemCode);
      final bins=<Map<String,dynamic>>[]; var start=0;
      while(true){
        final page=await widget.api.fetchStockBalances(start:start,search:widget.itemCode);
        bins.addAll(page.where((e)=>e.itemCode==widget.itemCode).map((e)=>{
          'warehouse':e.warehouse,'actual_qty':e.actualQty,'reserved_qty':e.reservedQty,
          'projected_qty':e.projectedQty,'stock_uom':e.stockUom,'stock_value':e.stockValue}));
        if(page.length<FrappeApi.pageSize||start>=10000)break; start+=page.length;
      }
      if(mounted)setState(()=>_prices=prices..sort((a,b)=>(a['price_list']??'').toString().compareTo((b['price_list']??'').toString())));
      if(mounted)setState(()=>_bins=bins);
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  String _img(String p)=>p.startsWith('http')?p:'${widget.api.baseUrl}/${p.replaceFirst(RegExp(r'^/+'),'')}';
  @override
  Widget build(BuildContext context)=>SizedBox(height:MediaQuery.of(context).size.height*.92,
    child:FutureBuilder<Map<String,dynamic>>(future:_doc,builder:(context,s){
      if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(s.hasError)return Center(child:Text(s.error.toString()));
      final d=s.data!; final image=d['image']?.toString()??'';
      const labels={
        'رمز الصنف':'item_code','الاسم':'item_name','المجموعة':'item_group','العلامة التجارية':'brand',
        'الوصف':'description','وحدة المخزون':'stock_uom','بلد المنشأ':'country_of_origin',
        'المصنع الافتراضي':'default_item_manufacturer','رقم القطعة':'default_manufacturer_part_no','وزن الوحدة':'weight_per_unit',
        'وحدة الوزن':'weight_uom','نهاية الصلاحية':'end_of_life','مدة الصلاحية':'shelf_life_in_days',
        'نوع طلب المواد الافتراضي':'default_material_request_type',
        'طريقة التقييم':'valuation_method','السعر القياسي':'standard_rate','صنف مخزني':'is_stock_item',
        'صنف بيع':'is_sales_item','صنف شراء':'is_purchase_item','تتبع تسلسلي':'has_serial_no',
        'تتبع دفعات':'has_batch_no','يتطلب انتهاء':'has_expiry_date','معطل':'disabled',
      };
      final barcodes=d['barcodes'] is List?d['barcodes'] as List:const [];
      return ListView(padding:const EdgeInsets.all(16),children:[
        Row(children:[
          image.isEmpty?const SizedBox(width:100,height:100,child:Icon(Icons.inventory_2_outlined,size:48)):
            ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.network(_img(image),headers:widget.api.imageRequestHeadersFor(_img(image)),width:100,height:100,fit:BoxFit.cover,
              errorBuilder:(_,__,___)=>const SizedBox(width:100,height:100,child:Icon(Icons.broken_image_outlined)))),
          const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(d['item_name']?.toString()??widget.itemCode,style:Theme.of(context).textTheme.titleLarge),
            Text(widget.itemCode),Text(d['brand']?.toString()??'بدون علامة'),
          ])),
        ]),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ErpDocTypeWorkspacePage(
              api: widget.api,
              definition: const ErpDocTypeDefinition('المخزون', 'الأصناف', 'Item', Icons.inventory_2_outlined),
              initialDocumentName: widget.itemCode,
            ),
          )),
          icon: const Icon(Icons.edit_note),
          label: const Text('تحرير نموذج الصنف الكامل'),
        ),
        const Divider(height:28),Text('التفاصيل الكاملة',style:Theme.of(context).textTheme.titleMedium),
        ...labels.entries.where((e)=>d[e.value]!=null&&d[e.value].toString().isNotEmpty)
          .map((e)=>ListTile(dense:true,title:Text(e.key),subtitle:Text(d[e.value].toString()))),
        if(barcodes.isNotEmpty)...[const Divider(),Text('الباركود',style:Theme.of(context).textTheme.titleMedium),
          ...barcodes.whereType<Map>().map((e)=>ListTile(leading:const Icon(Icons.qr_code_2),title:Text(e['barcode']?.toString()??''),subtitle:Text(e['barcode_type']?.toString()??'')))],
        ExpansionTile(title:const Text('عرض جميع حقول سجل ERPNext'),
          children:d.entries.where((e)=>!labels.values.contains(e.key)&&e.key!='doctype'&&e.key!='name')
            .map((e)=>ListTile(dense:true,title:Text(e.key),subtitle:Text(e.value is Map||e.value is List
              ?const JsonEncoder.withIndent('  ').convert(e.value):e.value.toString()))).toList()),
        const Divider(),Text('أسعار البيع والشراء',style:Theme.of(context).textTheme.titleMedium),
        if(_loading)const LinearProgressIndicator(),
        if(_prices.isEmpty&&!_loading)const Text('لا توجد أسعار مسجلة لهذا الصنف.'),
        ..._prices.map((p)=>ListTile(
          leading:Icon(p['selling']==1||p['selling']==true?Icons.sell_outlined:Icons.shopping_cart_outlined),
          title:Text('${p['price_list']??''} • ${p['price_list_rate']??'—'} ${p['currency']??''}'),
          subtitle:Text('${p['selling']==1||p['selling']==true?'بيع':'شراء'} • ${p['uom']??'الوحدة الأساسية'} • ${p['valid_from']??'دون بداية'} إلى ${p['valid_upto']??'مفتوح'}'))),
        const Divider(),Text('الأرصدة في جميع المستودعات',style:Theme.of(context).textTheme.titleMedium),
        if(_bins.isEmpty&&!_loading)const Text('لا توجد أرصدة ظاهرة.'),
        ..._bins.map((b)=>Card(child:ListTile(title:Text(b['warehouse'].toString()),
          subtitle:Text('محجوز ${b['reserved_qty']} • متوقع ${b['projected_qty']} ${b['stock_uom']??''}'),
          trailing:Text(b['actual_qty'].toString(),style:const TextStyle(fontWeight:FontWeight.bold))))),
        if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      ]);
    }));
}

class _ItemCatalogEditor extends StatefulWidget {
  const _ItemCatalogEditor({required this.api,this.itemCode});
  final FrappeApi api; final String? itemCode;
  @override
  State<_ItemCatalogEditor> createState()=>_ItemCatalogEditorState();
}
class _ItemCatalogEditorState extends State<_ItemCatalogEditor> {
  final _form=GlobalKey<FormState>();
  final Map<String,TextEditingController> _c={};
  final _barcodeController=TextEditingController();
  bool _loading=false,_saving=false,_stock=true,_serial=false,_batch=false,_expiry=false,_disabled=false;
  String? _error;
  bool get _editing=>widget.itemCode!=null;
  static const fields={
    'item_code':'رمز الصنف','item_name':'اسم الصنف','item_group':'مجموعة الأصناف','stock_uom':'وحدة المخزون',
    'brand':'العلامة التجارية','description':'الوصف','image':'رابط/مسار الصورة','country_of_origin':'بلد المنشأ',
    'default_item_manufacturer':'المصنع الافتراضي','default_manufacturer_part_no':'رقم قطعة المصنع','weight_per_unit':'وزن الوحدة',
    'weight_uom':'وحدة الوزن','end_of_life':'تاريخ نهاية الصلاحية','shelf_life_in_days':'مدة الصلاحية بالأيام',
    'default_material_request_type':'نوع طلب المواد الافتراضي','valuation_method':'طريقة التقييم',
    'standard_rate':'السعر القياسي',
  };
  @override
  void initState(){super.initState();for(final k in fields.keys){_c[k]=TextEditingController();}if(_editing)_load();}
  @override
  void dispose(){for(final c in _c.values){c.dispose();}_barcodeController.dispose();super.dispose();}
  Future<void> _load() async {
    setState(()=>_loading=true);
    try{
      final d=await widget.api.fetchItemCatalogDocument(widget.itemCode!);
      if(!mounted)return;
      for(final e in _c.entries){e.value.text=d[e.key]?.toString()??'';}
      final codes=d['barcodes'];
      if(codes is List){_barcodeController.text=codes.whereType<Map>().map((e)=>e['barcode']?.toString()??'').where((e)=>e.isNotEmpty).join('\n');}
      setState((){
        _stock=d['is_stock_item']==1||d['is_stock_item']==true;
        _serial=d['has_serial_no']==1||d['has_serial_no']==true;
        _batch=d['has_batch_no']==1||d['has_batch_no']==true;
        _expiry=d['has_expiry_date']==1||d['has_expiry_date']==true;
        _disabled=d['disabled']==1||d['disabled']==true;
      });
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _chooseReference(String key, String label, String doctype) async {
    final search=TextEditingController();
    var rows=<Map<String,dynamic>>[];
    BuildContext? sheetContext;
    var busy=false, started=false;
    String? error;
    Future<void> load(StateSetter refresh) async {
      refresh(() { busy=true; error=null; });
      try {
        final result=await widget.api.fetchMasterDataRows(doctype:doctype,search:search.text);
        if(sheetContext?.mounted != true)return;
        refresh(() {
          rows=result.where((row) {
            if(row['disabled']==1||row['disabled']==true)return false;
            if(doctype=='UOM'&&(row['enabled']==0||row['enabled']==false))return false;
            if(doctype=='Item Group'&&(row['is_group']==1||row['is_group']==true))return false;
            if(doctype=='Warehouse'&&(row['is_group']==1||row['is_group']==true))return false;
            return true;
          }).toList();
        });
      } catch(e) { if(sheetContext?.mounted == true)refresh(()=>error=e.toString().replaceFirst('Exception: ','')); }
      finally { if(sheetContext?.mounted == true)refresh(()=>busy=false); }
    }
    final selected=await showModalBottomSheet<String>(context:context,isScrollControlled:true,useSafeArea:true,
      builder:(sheetCtx){ sheetContext=sheetCtx; return StatefulBuilder(builder:(context,refresh) {
        if(!started){started=true;WidgetsBinding.instance.addPostFrameCallback((_) { if(sheetCtx.mounted)load(refresh); });}
        return Padding(padding:EdgeInsets.fromLTRB(16,12,16,MediaQuery.of(context).viewInsets.bottom+16),
          child:SizedBox(height:MediaQuery.of(context).size.height*.7,child:Column(children:[
            Text('اختيار $label',style:Theme.of(context).textTheme.titleLarge),
            TextField(controller:search,textInputAction:TextInputAction.search,onSubmitted:(_)=>load(refresh),
              decoration:InputDecoration(labelText:'بحث $label',suffixIcon:IconButton(onPressed:()=>load(refresh),icon:const Icon(Icons.search)))),
            if(busy)const LinearProgressIndicator(),
            if(error!=null)Text(error!),
            Expanded(child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i){
              final row=rows[i]; final id=row['name']?.toString()??'';
              final title=(row['item_group_name']??row['uom_name']??row['warehouse_name']??row['supplier_name']??id).toString();
              return ListTile(title:Text(title),subtitle:Text(id),onTap:()=>Navigator.pop(sheetCtx,id));
            })),
          ])));
      }); });
    search.dispose();
    if(selected!=null&&mounted)setState(()=>_c[key]!.text=selected);
  }

  Future<void> _save() async {
    if(_saving||!(_form.currentState?.validate()??false))return;
    if(_serial&&_batch){setState(()=>_error='لا يمكن تفعيل التتبع التسلسلي والدفعات معاً.');return;}
    setState(()=>_saving=true);
    try{
      await widget.api.saveMasterDataDocument(doctype:'Item',name:widget.itemCode,values:{
        for(final e in _c.entries)e.key:e.value.text.trim(),
        'is_stock_item':_stock,'has_serial_no':_serial,'has_batch_no':_batch,
        'has_expiry_date':_expiry,'disabled':_disabled,
        'barcodes':_barcodeController.text.split(RegExp(r'[\r\n,;]+')).map((v)=>v.trim()).where((v)=>v.isNotEmpty).map((v)=>{'barcode':v}).toList(),
      });
      if(mounted)Navigator.pop(context,true);
    }catch(e){if(mounted)setState(()=>_error=e.toString().replaceFirst('Exception: ',''));}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  @override
  Widget build(BuildContext context)=>SizedBox(height:MediaQuery.of(context).size.height*.92,
    child:_loading?const Center(child:CircularProgressIndicator()):Form(key:_form,child:ListView(
      padding:EdgeInsets.fromLTRB(16,8,16,MediaQuery.of(context).viewInsets.bottom+20),
      children:[
        Text(_editing?'تعديل الصنف':'إضافة صنف',style:Theme.of(context).textTheme.titleLarge),
        if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        ...fields.entries.map((e)=>Padding(padding:const EdgeInsets.only(bottom:9),child:TextFormField(
          controller:_c[e.key],readOnly:(_editing&&e.key=='item_code')||const {'item_group','stock_uom','weight_uom'}.contains(e.key),
          onTap:const {'item_group','stock_uom','weight_uom'}.contains(e.key)?(){
            final refs={'item_group':('مجموعة الأصناف','Item Group'),'stock_uom':('وحدة المخزون','UOM'),
              'weight_uom':('وحدة الوزن','UOM')};
            final ref=refs[e.key]!;
            _chooseReference(e.key,ref.$1,ref.$2);
          }:null,
          maxLines:e.key=='description'?3:1,
          decoration:InputDecoration(labelText:e.value,suffixIcon:const {'item_group','stock_uom','weight_uom'}.contains(e.key)?const Icon(Icons.search):null),
          validator:const {'item_code','item_name','item_group','stock_uom'}.contains(e.key)
            ?(v)=>v==null||v.trim().isEmpty?'هذا الحقل مطلوب':null:null))),
        Padding(padding:const EdgeInsets.only(bottom:9),child:TextFormField(controller:_barcodeController,maxLines:3,decoration:const InputDecoration(labelText:'الباركود (باركود في كل سطر)'))),
        const Divider(),
        SwitchListTile(title:const Text('صنف مخزني'),value:_stock,onChanged:(v)=>setState(()=>_stock=v)),
        SwitchListTile(title:const Text('تتبع تسلسلي'),value:_serial,onChanged:(v){setState(() {_serial=v;if(v)_batch=false;});}),
        SwitchListTile(title:const Text('تتبع بالدفعات'),value:_batch,onChanged:(v){setState(() {_batch=v;if(v)_serial=false;});}),
        SwitchListTile(title:const Text('تاريخ انتهاء'),value:_expiry,onChanged:(v)=>setState(()=>_expiry=v)),
        SwitchListTile(title:const Text('تعطيل الصنف'),value:_disabled,onChanged:(v)=>setState(()=>_disabled=v)),
        FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.save),label:Text(_saving?'جارٍ الحفظ...':'حفظ في ERPNext')),
      ])));
}

class _BarcodeScannerPage extends StatefulWidget {
  const _BarcodeScannerPage();
  @override
  State<_BarcodeScannerPage> createState()=>_BarcodeScannerPageState();
}
class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  bool _handled=false;
  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('مسح باركود الصنف')),
    body:MobileScanner(onDetect:(capture){
      if(_handled)return;
      for(final code in capture.barcodes){
        final value=code.rawValue?.trim()??'';
        if(value.isNotEmpty){_handled=true;Navigator.pop(context,value);break;}
      }
    },errorBuilder:(context,error)=>Center(child:Text('تعذر تشغيل الكاميرا: ${error.errorCode.name}')))));
}
