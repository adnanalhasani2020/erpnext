import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() => runApp(const ErpNextMobileApp());

class ErpNextMobileApp extends StatelessWidget {
  const ErpNextMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERPNext Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF24936E)),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: MobileHomePage(),
      ),
    );
  }
}

class FrappeApi {
  final HttpClient _client = HttpClient();
  final Map<String, String> _cookies = {};
  String _baseUrl = '';

  void configure(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                (uri.host == 'localhost' || uri.host == '10.0.2.2')))) {
      throw const FormatException('أدخل رابطاً صحيحاً يبدأ بـ https://');
    }
    _baseUrl = normalized;
  }

  Future<String> login(String username, String password) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl/api/method/login'));
    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    request.write(Uri(queryParameters: {'usr': username.trim(), 'pwd': password}).query);
    final response = await request.close();
    _captureCookies(response);
    final data = _decode(await utf8.decoder.bind(response).join());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تسجيل الدخول (${response.statusCode})'));
    }
    if (_cookies.isEmpty) {
      throw Exception(_message(data, 'لم يستلم التطبيق جلسة دخول من الخادم. تحقق من إعدادات ERPNext.'));
    }
    return currentUser();
  }

  Future<String> currentUser() async {
    final response = await _send('GET', '/api/method/frappe.auth.get_logged_user');
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'انتهت جلسة الدخول أو تعذر التحقق منها.'));
    }
    final message = data['message'];
    if (message is! String || message.isEmpty || message == 'Guest') {
      throw Exception('لم يتم التحقق من المستخدم المسجل.');
    }
    return message;
  }

  Future<void> logout() async {
    if (_cookies.isNotEmpty) {
      try {
        await _send('POST', '/api/method/logout');
      } catch (_) {}
    }
    _cookies.clear();
  }

  Future<_ApiResponse> _send(String method, String path) async {
    final request = await _client.openUrl(method, Uri.parse('$_baseUrl$path'));
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
    final response = await request.close();
    _captureCookies(response);
    return _ApiResponse(response.statusCode, await utf8.decoder.bind(response).join());
  }

  void _captureCookies(HttpClientResponse response) {
    for (final header in response.headers[HttpHeaders.setCookieHeader] ?? []) {
      final pair = header.split(';').first.split('=');
      if (pair.length >= 2) {
        _cookies[pair.first.trim()] = pair.sublist(1).join('=').trim();
      }
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }

  String _message(Map<String, dynamic> data, String fallback) {
    final message = data['message'];
    return message is String && message.isNotEmpty ? message : fallback;
  }

  void dispose() => _client.close(force: true);
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class MobileHomePage extends StatefulWidget {
  const MobileHomePage({super.key});

  @override
  State<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends State<MobileHomePage> {
  final _api = FrappeApi();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _user;

  @override
  void dispose() {
    _api.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      _api.configure(_urlController.text);
      final user = await _api.login(_userController.text, _passwordController.text);
      if (!mounted) return;
      setState(() { _user = user; _passwordController.clear(); });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    await _api.logout();
    if (!mounted) return;
    setState(() { _user = null; _busy = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _user == null ? _buildLogin() : _buildDashboard(),
        ),
      ),
    );
  }

  Widget _buildLogin() {
    return Center(
      key: const ValueKey('login'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 68),
              const SizedBox(height: 18),
              Text('ERPNext للجوال',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('اتصل بنظام ERPNext الخاص بك',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رابط الخادم',
                  hintText: 'https://erp.example.com',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _userController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم أو البريد',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) { if (!_busy) _login(); },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: Text(_busy ? 'جارٍ الاتصال...' : 'تسجيل الدخول'),
              ),
              const SizedBox(height: 18),
              Text(
                'نسخة تأسيسية: يلزم تشغيل خادم ERPNext وإدخال رابطه قبل تسجيل الدخول.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
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
              Text(_user ?? ''),
            ],
          )),
          IconButton(tooltip: 'تسجيل الخروج', onPressed: _busy ? null : _logout, icon: const Icon(Icons.logout)),
        ]),
        const SizedBox(height: 24),
        Card(
          color: scheme.primaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cloud_done_outlined, size: 30),
              SizedBox(height: 10),
              Text('تم الاتصال بخادم ERPNext', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              SizedBox(height: 5),
              Text('تسجيل الدخول والتحقق من الجلسة يعملان عبر واجهة Frappe API.'),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Text('الوحدات القادمة',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const _ModuleTile(icon: Icons.point_of_sale_outlined, title: 'المبيعات', subtitle: 'الفواتير والعملاء'),
        const _ModuleTile(icon: Icons.inventory_2_outlined, title: 'المخزون', subtitle: 'الأصناف والمستودعات وحركات المخزون'),
        const _ModuleTile(icon: Icons.shopping_cart_outlined, title: 'المشتريات', subtitle: 'الموردون وأوامر الشراء'),
        const _ModuleTile(icon: Icons.account_balance_wallet_outlined, title: 'الحسابات', subtitle: 'القيود والمدفوعات والتقارير'),
        const SizedBox(height: 12),
        Text('هذه الوحدات واجهات تمهيدية وليست شاشات تشغيل مكتملة بعد.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.lock_outline),
      ),
    );
  }
}
