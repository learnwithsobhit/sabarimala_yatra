import 'package:flutter/material.dart';

import '../theme.dart';

/// Themed card wrapper used across list screens.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: c.border),
    );

    final body = Padding(padding: padding, child: child);

    return Padding(
      padding: margin,
      child: Material(
        color: color ?? theme.colorScheme.surfaceContainerLowest,
        shape: shape,
        child: onTap == null
            ? body
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: body,
              ),
      ),
    );
  }
}

/// Standard list row inside a [SectionCard]-style surface.
class ListRowCard extends StatelessWidget {
  const ListRowCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      margin: margin,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        leading: leading,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing,
      ),
    );
  }
}
