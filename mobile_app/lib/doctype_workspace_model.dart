import 'package:flutter/material.dart';

class ErpDocTypeDefinition {
  const ErpDocTypeDefinition(
    this.group,
    this.label,
    this.doctype,
    this.icon, [
    this.section = 'عام',
  ]);

  final String group, label, doctype, section;
  final IconData icon;
}
