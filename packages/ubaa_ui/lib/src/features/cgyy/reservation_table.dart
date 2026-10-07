import 'package:flutter/material.dart';

class CgyyTableHeader extends SliverPersistentHeaderDelegate {
  CgyyTableHeader({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(covariant CgyyTableHeader old) =>
      old.height != height || old.child != child;
}
