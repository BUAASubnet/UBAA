import 'package:flutter/material.dart';
import '../../shared/scroll_gutters.dart' show ScrollGutters;

Widget uiShellContent({
  required double maxWidth,
  required bool wide,
  required Widget? header,
  required Widget body,
}) => Expanded(
  key: const ValueKey<String>('feature-pages'),
  child: Column(
    children: [
      if (header != null)
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: header,
          ),
        ),
      Expanded(
        child: ScrollGutters(
          maxWidth: maxWidth,
          child: SafeArea(top: false, bottom: wide, child: body),
        ),
      ),
    ],
  ),
);
