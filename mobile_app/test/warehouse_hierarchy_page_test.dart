import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/warehouse_hierarchy_page.dart';

class _WarehouseTestApi extends FrappeApi {
  @override
  Future<List<ErpCompany>> fetchCompanies() async => const [
        ErpCompany(name: 'Company A', abbr: 'AC', defaultCurrency: 'YER'),
      ];

  @override
  Future<List<Map<String, dynamic>>> fetchMasterDataRows({
    required String doctype,
    int start = 0,
    String? search,
  }) async {
    if (doctype != 'Warehouse' || start > 0) return const [];
    final rows = <Map<String, dynamic>>[
      {
        'name': 'Main - AC',
        'warehouse_name': 'Main',
        'company': 'Company A',
        'parent_warehouse': null,
        'is_group': 1,
        'disabled': 0,
      },
      {
        'name': 'Stores - AC',
        'warehouse_name': 'Stores',
        'company': 'Company A',
        'parent_warehouse': 'Main - AC',
        'is_group': 0,
        'disabled': 0,
      },
    ];
    final query = search?.trim().toLowerCase() ?? '';
    return rows
        .where((row) =>
            query.isEmpty ||
            row['name'].toString().toLowerCase().contains(query) ||
            row['warehouse_name'].toString().toLowerCase().contains(query))
        .toList();
  }
}

void main() {
  testWidgets('warehouse hierarchy groups can be collapsed and expanded', (tester) async {
    final api = _WarehouseTestApi();
    await tester.pumpWidget(MaterialApp(home: WarehouseHierarchyPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Stores'), findsOneWidget);
    await tester.tap(find.byTooltip('طي المجموعة'));
    await tester.pumpAndSettle();
    expect(find.text('Stores'), findsNothing);

    await tester.tap(find.byTooltip('توسيع المجموعة'));
    await tester.pumpAndSettle();
    expect(find.text('Stores'), findsOneWidget);

    api.dispose();
  });

  testWidgets('warehouse hierarchy renders parent and child warehouses', (tester) async {
    final api = _WarehouseTestApi();
    await tester.pumpWidget(MaterialApp(home: WarehouseHierarchyPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Stores'), findsOneWidget);
    expect(find.textContaining('Main - AC'), findsOneWidget);
    expect(find.textContaining('Stores - AC'), findsOneWidget);

    api.dispose();
  });
}
