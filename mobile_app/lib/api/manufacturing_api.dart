part of 'frappe_api.dart';

mixin ManufacturingApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchPlantFloorWorkstations({
    required String plantFloor,
    String? workstationType,
    String? workstation,
    String? workstationStatus,
  }) async {
    final floor = plantFloor.trim();
    if (floor.isEmpty) throw const FormatException('حدد أرضية المصنع أولاً.');
    final generation = _sessionGeneration;
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.manufacturing.doctype.workstation.workstation.get_workstations')
        .replace(queryParameters: {
      'plant_floor': floor,
      if (workstationType?.trim().isNotEmpty == true) 'workstation_type': workstationType!.trim(),
      if (workstation?.trim().isNotEmpty == true) 'workstation': workstation!.trim(),
      if (workstationStatus?.trim().isNotEmpty == true) 'workstation_status': workstationStatus!.trim(),
    });
    final response = await _sendUri('GET', uri);
    if (generation != _sessionGeneration) {
      throw const HttpException('تغيرت جلسة ERPNext أثناء تحميل محطات العمل.');
    }
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل محطات العمل من أرضية المصنع.'));
    }
    final rows = data['message'];
    if (rows is! List) throw const FormatException('استجابة محطات العمل غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }
}
