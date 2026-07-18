import 'package:flutter/material.dart';

import '../theme.dart';

/// Circular headcount ring: "41/56 Present".
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.total,
    this.label = 'Present',
    this.size = 148,
  });

  final int value;
  final int total;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final theme = Theme.of(context);
    final progress = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    final complete = total > 0 && value >= total;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              color: complete ? c.success : theme.colorScheme.primary,
              backgroundColor: c.surfaceAlt,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$value',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: complete ? c.success : theme.colorScheme.primary,
                      ),
                    ),
                    TextSpan(
                      text: '/$total',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: .55),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
