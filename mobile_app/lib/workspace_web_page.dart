import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  bool _loading = true;
  String? _error;
  int _progress = 0;

  Uri _resolveTarget() {
    final baseText = widget.api.baseUrl.trim();
    final base = Uri.parse(baseText.endsWith('/') ? baseText : '$baseText/');
    final target = widget.target.trim();
    if (widget.linkType == 'URL') {
      final parsed = Uri.tryParse(target);
      return parsed != null && parsed.hasScheme ? parsed : base.resolve(target);
    }
    final route = switch (widget.linkType) {
      'Dashboard' => 'app/dashboard-view/',
      'Workspace' => 'app/',
      _ => 'app/',
    };
    return base.resolve(route + Uri.encodeComponent(target));
  }

  bool _sameOrigin(Uri left, Uri right) =>
      left.scheme == right.scheme &&
      left.host == right.host &&
      left.port == right.port;

  Future<void> _initialize() async {
    try {
      // The app keeps its Frappe session in memory. Start with a clean WebView
      // cookie store, then pass the current same-origin session cookie once.
      await _cookieManager.clearCookies();
      final target = _resolveTarget();
      final base = Uri.parse(widget.api.baseUrl);
      final headers = _sameOrigin(target, base)
          ? widget.api.imageRequestHeaders
          : const <String, String>{};
      await _controller.loadRequest(target, headers: headers);
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
          return NavigationDecision.navigate;
        },
      ));
    _initialize();
  }

  @override
  void dispose() {
    // Do not retain an authenticated Desk session after leaving this screen.
    unawaited(_cookieManager.clearCookies());
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
          if (_loading) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
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
