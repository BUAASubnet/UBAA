import 'package:flutter/material.dart';
import '../common/detail_fields.dart' show DetailField;

class AcademicInfo extends StatelessWidget {
  const AcademicInfo({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class AcademicMore extends StatelessWidget {
  const AcademicMore({required this.fields});
  final List<(String, String)> fields;
  @override
  Widget build(BuildContext context) => fields.isEmpty
      ? const SizedBox.shrink()
      : ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('更多信息'),
          children: [
            for (final (label, value) in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DetailField(label: label, value: value),
              ),
          ],
        );
}
