import 'package:flutter/material.dart';

import '../theme.dart';

enum StatusBannerKind { offline, urgent, danger, success, info }

/// One consistent banner for offline / urgent / error states,
/// replacing the ad-hoc colored Cards scattered across screens.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.kind,
    required this.message,
    this.title,
    this.onDismiss,
  });

  final StatusBannerKind kind;
  final String message;
  final String? title;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final (bg, fg, icon) = switch (kind) {
      StatusBannerKind.offline => (
          c.offlineContainer,
          Theme.of(context).colorScheme.onSurface,
          Icons.cloud_off_outlined,
        ),
      StatusBannerKind.urgent => (
          c.urgentContainer,
          c.onUrgentContainer,
          Icons.campaign_outlined,
        ),
      StatusBannerKind.danger => (
          c.dangerContainer,
          c.danger,
          Icons.error_outline,
        ),
      StatusBannerKind.success => (
          c.successContainer,
          c.onSuccessContainer,
          Icons.check_circle_outline,
        ),
      StatusBannerKind.info => (
          Theme.of(context).colorScheme.primaryContainer,
          Theme.of(context).colorScheme.onPrimaryContainer,
          Icons.info_outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      title!,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                Text(message, style: TextStyle(color: fg, fontSize: 14)),
              ],
            ),
          ),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, color: fg, size: 18),
            ),
        ],
      ),
    );
  }
}
