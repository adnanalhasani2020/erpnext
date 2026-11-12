import 'package:flutter/material.dart';

import '../api/frappe_api.dart';

/// A small native equivalent of ERPNext's Link field.
/// Suggestions are read through Frappe's permission-filtered DocType list API.
class ServerLinkField extends StatelessWidget {
  const ServerLinkField({
    super.key,
    required this.api,
    required this.doctype,
    required this.label,
    required this.controller,
    this.searchFields = const [],
    this.filters = const [],
    this.icon = Icons.search,
    this.onSelected,
  });

  final FrappeApi api;
  final String doctype;
  final String label;
  final TextEditingController controller;
  final List<String> searchFields;
  final List<List<dynamic>> filters;
  final IconData icon;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) => Autocomplete<String>(
    initialValue: TextEditingValue(text: controller.text),
    displayStringForOption: (value) => value,
    optionsBuilder: (value) async {
      final query = value.text.trim();
      if (query.isEmpty) return const Iterable<String>.empty();
      try {
        final rows = await api.fetchDocTypeRows(
          doctype: doctype,
          fields: searchFields,
          search: query,
          searchFields: searchFields,
          filters: filters,
          orderBy: 'name asc',
        );
        return rows.map((row) => row['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .take(8)
            .toSet();
      } catch (_) {
        return const Iterable<String>.empty();
      }
    },
    onSelected: (value) {
      controller.text = value;
      onSelected?.call(value);
    },
    fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
      if (textController.text != controller.text && controller.text.isNotEmpty) {
        textController.value = TextEditingValue(
          text: controller.text,
          selection: TextSelection.collapsed(offset: controller.text.length),
        );
      }
      return TextField(
        controller: textController,
        focusNode: focusNode,
        onChanged: (value) => controller.text = value,
        onSubmitted: (_) => onFieldSubmitted(),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: textController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    textController.clear();
                    controller.clear();
                    onSelected?.call('');
                  },
                ),
        ),
      );
    },
  );
}
