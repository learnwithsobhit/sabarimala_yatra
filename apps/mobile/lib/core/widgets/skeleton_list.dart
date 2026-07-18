import 'package:flutter/material.dart';

import '../theme.dart';

/// Simple pulsing placeholder rows while data loads.
class SkeletonList extends StatefulWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 72,
  });

  final int itemCount;
  final double itemHeight;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = 0.35 + (_controller.value * 0.35);
        return Column(
          children: List.generate(widget.itemCount, (i) {
            return Container(
              height: widget.itemHeight,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: c.surfaceAlt.withValues(alpha: t),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border.withValues(alpha: .6)),
              ),
            );
          }),
        );
      },
    );
  }
}
