import 'package:flutter/material.dart';

class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton(this.loading, this.label, this.onPressed, {super.key});

  final bool loading;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: FilledButton.tonal(
        onPressed: loading ? null : onPressed,
        child: Text(loading ? 'جارٍ التحميل...' : label),
      ),
    );
  }
}
