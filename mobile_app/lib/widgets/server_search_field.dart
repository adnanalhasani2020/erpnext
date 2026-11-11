import 'package:material_ui/material_ui.dart';

class ServerSearchField extends StatelessWidget {
  const ServerSearchField({
    required this.controller,
    required this.label,
    required this.onSearch,
    this.loading = false,
    this.buttonLabel = 'بحث في الخادم',
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onSearch;
  final bool loading;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) => TextField(
            controller: controller,
            enabled: !loading,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: loading ? null : () {
                        controller.clear();
                        onSearch('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onSubmitted: onSearch,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: loading ? null : () => onSearch(controller.text),
            icon: loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: Text(loading ? 'جارٍ البحث...' : buttonLabel),
          ),
        ),
      ],
    );
  }
}
