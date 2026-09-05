part of '../widgets.dart';

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 88,
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(child: Text(value)),
    ],
  );
}
