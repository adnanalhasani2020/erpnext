import 'package:flutter/material.dart';

class ServerSearchField extends StatelessWidget {
  const ServerSearchField({
    required this.controller,
    required this.label,
    required this.onSearch,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) => TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: () {
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
            onPressed: () => onSearch(controller.text),
            icon: const Icon(Icons.search),
            label: const Text('بحث في الخادم'),
          ),
        ),
      ],
    );
  }
}
