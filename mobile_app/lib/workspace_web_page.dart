import 'dart:async';
import 'dart:io' show Cookie;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cookie_manager_flutter/webview_cookie_manager_flutter.dart';

import 'api/frappe_api.dart';

class WorkspaceWebPage extends StatefulWidget {
  const WorkspaceWebPage({
    super.key,
    required this.api,
    required this.title,
    required this.linkType,
    required this.target,
  });

  final FrappeApi api;
  final String title;
  final String linkType;
  final String target;

  @override
  State<WorkspaceWebPage> createState() => _WorkspaceWebPageState();
}

class _WorkspaceWebPageState extends State<WorkspaceWebPage> {
  late final WebViewController _controller;
  final WebviewCookieManager _cookieManager = WebviewCookieManager();
  bool _loading = true;
  String? _error;
  int _progress = 0;

  String _workspaceSlug(String value) {
    var slug = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    while (slug.startsWith('-')) {
      slug = slug.substring(1);
    }
    while (slug.endsWith('-')) {
      slug = slug.substring(0, slug.length - 1);
    }
    return slug;
  }

  Uri _resolveTarget() {
    final baseText = widget.api.baseUrl.trim();
    final base = Uri.parse(baseText.endsWith('/') ? baseText : baseText + '/');
    final target = widget.target.trim();
    if (widget.linkType == 'URL') {
      final parsed = Uri.tryParse(target);
      return parsed != null && parsed.hasScheme ? parsed : base.resolve(target);
    }
    if (widget.linkType == 'DocTypeList') {
      final doctype = _workspaceSlug(target);
      if (doctype.isEmpty) throw const FormatException('وجهة قائمة ERPNext غير صالحة.');
      return base.resolve('app/$doctype');
    }
    if (widget.linkType == 'DocTypeDocument') {
      final separator = target.indexOf('|');
      if (separator <= 0 || separator == target.length - 1) {
        throw const FormatException('وجهة مستند ERPNext غير صالحة.');
      }
      final doctype = _workspaceSlug(target.substring(0, separator));
      final documentName = target.substring(separator + 1);
      if (doctype.isEmpty || documentName.trim().isEmpty) {
        throw const FormatException('وجهة مستند ERPNext غير صالحة.');
      }
      return base.resolve('app/$doctype/${Uri.encodeComponent(documentName)}');
    }
    final route = switch (widget.linkType) {
      'Dashboard' => 'app/dashboard-view/',
      'Workspace' => 'app/',
      'Report' => 'app/query-report/',
      _ => 'app/',
    };
    final routeName = widget.linkType == 'Workspace' ? _workspaceSlug(target) : target;
    return base.resolve(route + Uri.encodeComponent(routeName));
  }

  bool _sameOrigin(Uri left, Uri right) =>
      left.scheme == right.scheme &&
      left.host == right.host &&
      left.port == right.port;

  Future<void> _initialize() async {
    try {
      await _cookieManager.clearCookies();
      final target = _resolveTarget();
      final base = Uri.parse(widget.api.baseUrl);
      if (!const {'http', 'https'}.contains(target.scheme) ||
          (target.scheme == 'http' &&
              (base.scheme != 'http' || !_sameOrigin(target, base)))) {
        throw const FormatException('عنوان صفحة الويب غير آمن أو غير مدعوم.');
      }
      if (_sameOrigin(target, base)) {
        final cookieHeader = widget.api.imageRequestHeaders['Cookie'] ?? '';
        final cookies = <Cookie>[];
        for (final part in cookieHeader.split(';')) {
          final separator = part.indexOf('=');
          if (separator <= 0) continue;
          final name = part.substring(0, separator).trim();
          final value = part.substring(separator + 1).trim();
          if (name.isEmpty) continue;
          cookies.add(Cookie(name, value)
            ..domain = base.host
            ..path = '/'
            ..secure = base.scheme == 'https'
            ..httpOnly = name == 'sid' || name == 'session_id');
        }
        await _cookieManager.setCookies(cookies, origin: base.origin);
      }
      await _controller.loadRequest(target);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageStarted: (_) {
          if (mounted) setState(() {
            _loading = true;
            _error = null;
          });
        },
        onPageFinished: (_) {
          if (mounted) setState(() {
            _loading = false;
            _progress = 100;
          });
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() {
              _loading = false;
              _error = error.description;
            });
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
            return NavigationDecision.prevent;
          }
          final base = Uri.tryParse(widget.api.baseUrl);
          if (uri.scheme == 'http' &&
              (base == null || base.scheme != 'http' || !_sameOrigin(uri, base))) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));
    _initialize();
  }

  @override
  void dispose() {
    unawaited(_cookieManager.clearCookies().then((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'إعادة تحميل صفحة ERPNext',
            onPressed: () {
              setState(() {
                _error = null;
                _loading = true;
                _progress = 0;
              });
              _controller.reload();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
          if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 36),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _initialize,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
