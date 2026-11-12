import 'package:flutter/material.dart';

class ErpDocTypeDefinition {
  const ErpDocTypeDefinition(
    this.group,
    this.label,
    this.doctype,
    this.icon, [
    this.section = 'عام',
    this.linkType = 'DocType',
  ]);

  final String group, label, doctype, section, linkType;
  final IconData icon;
}
