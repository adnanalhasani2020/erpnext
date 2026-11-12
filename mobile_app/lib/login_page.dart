import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.formKey, required this.urlController, required this.userController, required this.passwordController, required this.busy, required this.showPassword, required this.error, required this.onLogin, required this.onContinueAsGuest, required this.onTogglePassword});

  final GlobalKey<FormState> formKey;
  final TextEditingController urlController;
  final TextEditingController userController;
  final TextEditingController passwordController;
  final bool busy;
  final bool showPassword;
  final String? error;
  final VoidCallback onLogin;
  final VoidCallback onContinueAsGuest;
  final VoidCallback onTogglePassword;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('login'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.inventory_2_outlined, size: 42, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                Text(
                  'ERPNext للجوال',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'سجّل الدخول لبيانات شركتك، أو ادخل كضيف لاستكشاف التطبيق دون خادم أو حساب.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: urlController,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'رابط خادم ERPNext',
                    hintText: 'https://erp.example.com',
                    prefixIcon: Icon(Icons.link),
                    helperText: 'استخدم رابط HTTPS الخاص بنظامك.',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'أدخل رابط خادم ERPNext.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: userController,
                  enabled: !busy,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم أو البريد',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'أدخل اسم المستخدم أو البريد الإلكتروني.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: passwordController,
                  enabled: !busy,
                  obscureText: !showPassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
                      onPressed: busy ? null : () => onTogglePassword(),
                      icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? 'أدخل كلمة المرور.'
                      : null,
                  onFieldSubmitted: (_) { if (!busy) onLogin(); },
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: scheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(child: Text(error!, style: TextStyle(color: scheme.onErrorContainer))),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: busy ? null : onLogin,
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(busy ? 'جارٍ الاتصال بالخادم...' : 'تسجيل الدخول'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy ? null : onContinueAsGuest,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('الدخول كضيف دون خادم أو حساب'),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'تُرسل بيانات الدخول إلى خادمك مباشرة. لا يحفظ التطبيق كلمة المرور أو ملفات الجلسة على الجهاز؛ تنتهي الجلسة عند تسجيل الخروج أو إغلاق التطبيق.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
