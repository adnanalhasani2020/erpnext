part of 'frappe_api.dart';

mixin DocTypeWorkspaceApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchWorkspaceDirectory() async {
    // Use permission-filtered Desk boot data on v16 and the dedicated sidebar
    // endpoint on v15. get_workspaces() itself is not a whitelisted v16 method.
    core.Map<String, dynamic>? workspaceMessage;
    Object? lastError;
    for (final method in const [
      'frappe.desk.desktop.get_workspace_sidebar_items',
      'frappe.sessions.get',
    ]) {
      try {
        final uri = Uri.parse('$_baseUrl/api/method/' + method);
        final response = await _sendUri('GET', uri);
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر تحميل مساحات العمل المسموح بها.'));
        }
        final message = data['message'];
        if (message is! core.Map<String, dynamic>) {
          throw const FormatException('استجابة مساحات العمل غير متوقعة.');
        }
        final pages = message['pages'] ?? message['workspace_pages'];
        if (pages is! List) {
          throw const FormatException('قائمة مساحات العمل غير متاحة في استجابة الخادم.');
        }
        workspaceMessage = <String, dynamic>{...message, 'pages': pages};
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (workspaceMessage == null) {
      throw Exception(lastError?.toString() ?? 'تعذر تحميل مساحات العمل.');
    }

    final summaries = (workspaceMessage['pages'] as List)
      .whereType<core.Map<String, dynamic>>()
      .map((row) => core.Map<String, dynamic>.from(row))
      .toList(growable: false);

    Future<core.Map<String, dynamic>> fetchWorkspaceDetail(core.Map<String, dynamic> row) async {
      final name = row['name']?.toString() ?? '';
      final pageType = row['type']?.toString() ?? 'Workspace';
      if (name.isEmpty || pageType == 'Link' || pageType == 'URL') {
        return core.Map<String, dynamic>.from(row);
      }
      try {
        final detailResponse = await _send(
          'GET', '/api/resource/Workspace/' + Uri.encodeComponent(name),
        );
        final detailData = _decode(detailResponse.body);
        if (detailResponse.statusCode < 200 || detailResponse.statusCode >= 300) {
          return core.Map<String, dynamic>.from(row);
        }
        final document = detailData['data'];
        if (document is! core.Map<String, dynamic> ||
            document['doctype'] != 'Workspace' || document['name'] != name) {
          return core.Map<String, dynamic>.from(row);
        }
        return core.Map<String, dynamic>.from(document);
      } catch (_) {
        return core.Map<String, dynamic>.from(row);
      }
    }

    // Preserve Desk ordering while bounding concurrent detail reads.
    final details = <core.Map<String, dynamic>>[];
    for (var offset = 0; offset < summaries.length; offset += 8) {
      final end = (offset + 8 < summaries.length) ? offset + 8 : summaries.length;
      final batch = await Future.wait(summaries.sublist(offset, end).map(fetchWorkspaceDetail));
      details.addAll(batch);
    }
    return details;
  }

  Future<core.Map<String, dynamic>> fetchDocTypeMeta(String doctype) async {
    final uri = Uri.parse('$_baseUrl/api/method/frappe.desk.form.load.getdoctype')
        .replace(queryParameters: {'doctype': doctype.trim(), 'with_parent': '1'});
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تعريف المستند من ERPNext.'));
    }
    final message = data['message'];
    final docs = message is core.Map<String, dynamic> ? message['docs'] : null;
    if (docs is! List) throw const FormatException('تعريف الحقول غير متاح.');
    final meta = docs.whereType<core.Map<String, dynamic>>().firstWhere(
      (row) => row['doctype'] == 'DocType' && row['name'] == doctype,
      orElse: () => <String, dynamic>{},
    );
    if (meta.isEmpty || meta['fields'] is! List) throw FormatException('تعريف DocType غير موجود: ' + doctype);
    return core.Map<String, dynamic>.from(meta);
  }

  Future<List<core.Map<String, dynamic>>> fetchDocTypeRows({
    required String doctype, required List<String> fields,
    String search = '', int start = 0, List<List<dynamic>> filters = const [],
    List<String> searchFields = const [], String orderBy = 'modified desc',
  }) async {
    final selected = <String>{'name', 'docstatus', 'modified', ...fields}.toList();
    final query = search.trim();
    final ors = <List<dynamic>>[];
    if (query.isNotEmpty) {
      ors.add(['name', 'like', '%$query%']);
      for (final field in (searchFields.isEmpty ? fields.where((f) => f != 'name') : searchFields).take(8)) {
        ors.add([field, 'like', '%$query%']);
      }
    }
    final uri = FrappeApi.buildResourcePageUri(
      baseUrl: _baseUrl, resource: doctype, fields: selected,
      filters: filters, orFilters: ors.isEmpty ? null : ors, orderBy: orderBy,
      start: start, pageLength: FrappeApi.pageSize,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل السجلات. تحقق من صلاحية القراءة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة قائمة المستندات غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchDocTypeDocument({
    required String doctype, required String name,
  }) async {
    final response = await _send('GET', '/api/resource/' +
      Uri.encodeComponent(doctype.trim()) + '/' + Uri.encodeComponent(name.trim()));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل المستند.'));
    }
    final doc = data['data'];
    if (doc is! core.Map<String, dynamic> || doc['doctype'] != doctype || doc['name'] != name) {
      throw const FormatException('هوية المستند غير مطابقة.');
    }
    return core.Map<String, dynamic>.from(doc);
  }


  Future<core.Map<String, dynamic>> saveDocTypeDocument({
    required String doctype, String? name,
    required core.Map<String, dynamic> values,
  }) async {
    final editing = name != null && name.trim().isNotEmpty;
    final payload = editing
      ? <String, dynamic>{...await fetchDocTypeDocument(doctype: doctype, name: name.trim()), ...values}
      : <String, dynamic>{'doctype': doctype, ...values};
    if (editing && payload['docstatus'] != 0) {
      throw const FormatException('لا يمكن تعديل مستند مرحّل أو ملغى.');
    }
    final response = await _sendJson('POST',
      editing ? '/api/method/frappe.client.save' : '/api/method/frappe.client.insert',
      {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'رفض ERPNext حفظ المستند. تحقق من الحقول والصلاحيات.'));
    }
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != doctype ||
        saved['name'] is! String || (editing && saved['name'] != name.trim())) {
      throw const FormatException('لم يؤكد ERPNext حفظ المستند.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  Future<List<core.Map<String, dynamic>>> fetchDocTypeWorkflowTransitions({
    required String doctype, required String name,
  }) async {
    final doc = await fetchDocTypeDocument(doctype: doctype, name: name);
    final uri = Uri.parse('$_baseUrl/api/method/frappe.model.workflow.get_transitions')
        .replace(queryParameters: {'doc': jsonEncode(doc)});
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب إجراءات سير العمل من ERPNext.'));
    }
    final rows = data['message'];
    if (rows is! List) throw const FormatException('استجابة إجراءات سير العمل غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>().where((row) =>
      row['action'] is String && (row['action'] as String).trim().isNotEmpty
    ).map((row) => core.Map<String, dynamic>.from(row)).toList();
  }

  Future<core.Map<String, dynamic>> applyDocTypeWorkflowAction({
    required String doctype, required String name, required String action,
  }) async {
    final key = doctype + ':' + name + ':workflow:' + action;
    if (!_inFlightDocumentActions.add(key)) throw const FormatException('الإجراء قيد التنفيذ بالفعل.');
    try {
      final doc = await fetchDocTypeDocument(doctype: doctype, name: name);
      final transitions = await fetchDocTypeWorkflowTransitions(doctype: doctype, name: name);
      if (!transitions.any((row) => row['action']?.toString() == action)) {
        throw const FormatException('الإجراء غير متاح لهذا المستند أو للمستخدم الحالي.');
      }
      final response = await _sendJson(
        'POST', '/api/method/frappe.model.workflow.apply_workflow',
        {'doc': doc, 'action': action},
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'رفض ERPNext تنفيذ إجراء سير العمل.'));
      }
      final updated = data['message'];
      if (updated is! core.Map<String, dynamic> || updated['doctype'] != doctype ||
          updated['name'] != name) {
        throw const FormatException('لم يؤكد ERPNext تنفيذ الإجراء على المستند الصحيح.');
      }
      return core.Map<String, dynamic>.from(updated);
    } finally {
      _inFlightDocumentActions.remove(key);
    }
  }

  Future<core.Map<String, dynamic>> transitionDocTypeDocument({
    required String doctype, required String name, required String action,
  }) async {
    final key = doctype + ':' + name + ':' + action;
    if (!_inFlightDocumentActions.add(key)) throw const FormatException('الإجراء قيد التنفيذ بالفعل.');
    try {
      final doc = await fetchDocTypeDocument(doctype: doctype, name: name);
      final status = (doc['docstatus'] as num?)?.toInt() ?? 0;
      final method = action == 'Submit' && status == 0 ? 'submit'
        : action == 'Cancel' && status == 1 ? 'cancel' : '';
      if (method.isEmpty) throw const FormatException('الإجراء لا يناسب حالة المستند الحالية.');
      final response = await _sendJson('POST', '/api/method/frappe.client.' + method, {'doc': doc});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'رفض ERPNext تنفيذ الإجراء.'));
      }
      final changed = data['message'];
      final expected = action == 'Submit' ? 1 : 2;
      if (changed is! core.Map<String, dynamic> || changed['doctype'] != doctype ||
          changed['name'] != name || (changed['docstatus'] as num?)?.toInt() != expected) {
        throw const FormatException('لم يؤكد ERPNext حالة المستند بعد الإجراء.');
      }
      return core.Map<String, dynamic>.from(changed);
    } finally {
      _inFlightDocumentActions.remove(key);
    }
  }


  Future<double?> fetchWorkspaceNumberCardValue(String numberCardName) async {
    final name = numberCardName.trim();
    if (name.isEmpty) return null;
    final generation = _sessionGeneration;
    final card = await fetchDocTypeDocument(doctype: 'Number Card', name: name);
    if (generation != _sessionGeneration) {
      throw const HttpException('تغيرت جلسة ERPNext أثناء تحميل بطاقة المؤشر.');
    }
    // Custom-method and report cards can execute server-defined behavior;
    // keep those on the original Workspace instead of emulating them.
    final cardType = card['type']?.toString().trim();
    if ((cardType != null && cardType.isNotEmpty && cardType != 'Document Type') ||
        card['document_type'] is! String ||
        card['function'] is! String) {
      return null;
    }
    // Dynamic filters contain server-side JavaScript expressions in Desk.
    // Do not evaluate or silently ignore them in Flutter; leave those cards
    // to the original Workspace WebView instead.
    final rawDynamicFilters = card['dynamic_filters_json'];
    dynamic decodedDynamicFilters = rawDynamicFilters;
    if (rawDynamicFilters is String && rawDynamicFilters.trim().isNotEmpty) {
      try {
        decodedDynamicFilters = jsonDecode(rawDynamicFilters);
      } catch (_) {
        return null;
      }
    }
    final hasDynamicFilters = decodedDynamicFilters is List
        ? decodedDynamicFilters.isNotEmpty
        : decodedDynamicFilters is Map
            ? decodedDynamicFilters.isNotEmpty
            : decodedDynamicFilters != null;
    if (hasDynamicFilters) return null;
    final filters = card['filters_json']?.toString().trim().isNotEmpty == true
        ? card['filters_json']
        : '[]';
    final response = await _sendJson(
      'POST',
      '/api/method/frappe.desk.doctype.number_card.number_card.get_result',
      {'doc': card, 'filters': filters},
    );
    if (generation != _sessionGeneration) {
      throw const HttpException('تغيرت جلسة ERPNext أثناء حساب بطاقة المؤشر.');
    }
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل بطاقة المؤشر من ERPNext.'));
    }
    final raw = data['message'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  Future<core.Map<String, List<core.Map<String, dynamic>>>> fetchDocTypeActivity({
    required String doctype,
    required String name,
  }) async {
    final generation = _sessionGeneration;
    final reference = <List<dynamic>>[
      ['reference_doctype', '=', doctype],
      ['reference_name', '=', name],
    ];
    Future<List<core.Map<String, dynamic>>> loadRelated(
      String relatedDoctype,
      List<String> fields,
      List<List<dynamic>> filters,
    ) async {
      try {
        final rows = <core.Map<String, dynamic>>[];
        var start = 0;
        while (true) {
          final page = await fetchDocTypeRows(
            doctype: relatedDoctype,
            fields: fields,
            filters: filters,
            orderBy: 'creation desc',
            start: start,
          );
          rows.addAll(page);
          if (page.length < FrappeApi.pageSize) break;
          start += page.length;
        }
        return rows;
      } catch (_) {
        // Some roles can read the document but not every timeline DocType.
        // Keep the other activity sections available under ERPNext permissions.
        return <core.Map<String, dynamic>>[];
      }
    }
    final attachments = await loadRelated(
      'File',
      const ['file_name', 'file_url', 'file_size', 'is_private', 'creation'],
      <List<dynamic>>[
        ['attached_to_doctype', '=', doctype],
        ['attached_to_name', '=', name],
      ],
    );
    final comments = await loadRelated(
      'Comment',
      const ['comment_type', 'content', 'comment_by', 'comment_email', 'creation'],
      reference,
    );
    final versions = await loadRelated(
      'Version',
      const ['data', 'owner', 'creation'],
      <List<dynamic>>[
        ['ref_doctype', '=', doctype],
        ['docname', '=', name],
      ],
    );
    if (generation != _sessionGeneration) {
      throw const HttpException('تغيرت جلسة ERPNext أثناء تحميل سجل المستند.');
    }
    return <String, List<core.Map<String, dynamic>>>{
      'attachments': attachments,
      'comments': comments,
      'versions': versions,
    };
  }

  Future<void> addDocTypeComment({
    required String doctype,
    required String name,
    required String content,
  }) async {
    final text = content.trim();
    if (doctype.trim().isEmpty || name.trim().isEmpty || text.isEmpty) {
      throw const FormatException('المستند ونص التعليق مطلوبان.');
    }
    // Frappe v15/v16 requires these two arguments in the method signature;
    // the server derives the authoritative identity from the authenticated session.
    final generation = _sessionGeneration;
    final user = await currentUser();
    if (generation != _sessionGeneration) {
      throw const HttpException('تغيرت جلسة ERPNext قبل إرسال التعليق.');
    }
    final response = await _sendJson(
      'POST',
      '/api/method/frappe.desk.form.utils.add_comment',
      {
        'reference_doctype': doctype,
        'reference_name': name,
        'content': text,
        'comment_email': user,
        'comment_by': user,
      },
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'رفض ERPNext إضافة التعليق.'));
    }
    if (data['message'] == null) {
      throw const FormatException('لم يؤكد ERPNext إضافة التعليق.');
    }
  }

  Future<core.Map<String, dynamic>> uploadDocTypeAttachment({
    required String doctype,
    required String name,
    required String fileName,
    required List<int> bytes,
    bool isPrivate = true,
  }) async {
    if (doctype.trim().isEmpty || name.trim().isEmpty ||
        fileName.trim().isEmpty || bytes.isEmpty) {
      throw const FormatException('المستند والملف ومحتوى الملف مطلوبة.');
    }
    if (_guestMode) {
      throw const FormatException('وضع الضيف للقراءة فقط؛ سجّل الدخول لرفع المرفقات.');
    }
    final generation = _sessionGeneration;
    final boundary = '----FrappeMobile${DateTime.now().microsecondsSinceEpoch}';
    final safeName = fileName
        .replaceAll('"', '_')
        .replaceAll('/', '_')
        .replaceAll(String.fromCharCode(92), '_')
        .replaceAll('\r', '_')
        .replaceAll('\n', '_');
    final request = await _client.postUrl(Uri.parse('$_baseUrl/api/method/upload_file'));
    if (generation != _sessionGeneration) {
      request.abort();
      throw const HttpException('تغيرت جلسة ERPNext قبل بدء رفع الملف.');
    }
    request.followRedirects = false;
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    if (_cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '),
      );
      final csrfToken = _cookies['csrf_token'];
      if (csrfToken != null && csrfToken.isNotEmpty) {
        request.headers.set('X-Frappe-CSRF-Token', csrfToken);
      }
    }
    void field(String key, String value) {
      request.write('--$boundary\r\n');
      request.write('Content-Disposition: form-data; name="$key"\r\n\r\n');
      request.write('$value\r\n');
    }
    field('is_private', isPrivate ? '1' : '0');
    field('doctype', doctype);
    field('docname', name);
    request.write('--$boundary\r\n');
    request.write('Content-Disposition: form-data; name="file"; filename="$safeName"\r\n');
    request.write('Content-Type: application/octet-stream\r\n\r\n');
    request.add(bytes);
    request.write('\r\n--$boundary--\r\n');
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 60));
    if (generation != _sessionGeneration) {
      throw const HttpException('تم تجاهل نتيجة رفع ملف من جلسة سابقة.');
    }
    _captureCookies(response);
    final data = _decode(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر رفع المرفق إلى ERPNext.'));
    }
    final uploaded = data['message'];
    if (uploaded is! core.Map<String, dynamic> ||
        uploaded['attached_to_doctype'] != doctype ||
        uploaded['attached_to_name'] != name) {
      throw const FormatException('لم يؤكد ERPNext ربط الملف بالمستند المطلوب.');
    }
    return core.Map<String, dynamic>.from(uploaded);
  }

}