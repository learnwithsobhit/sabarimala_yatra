import 'package:flutter/material.dart';

import '../theme.dart';

/// The signature "digital yatra pass": dark card with a thin gold
/// gradient border, member identity, and travel assignment rows.
class PassCard extends StatelessWidget {
  const PassCard({
    super.key,
    required this.memberName,
    this.role,
    this.nextStopTitle,
    this.nextStopPlace,
    this.rows = const [],
  });

  final String memberName;
  final String? role;
  final String? nextStopTitle;
  final String? nextStopPlace;
  final List<PassRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;

    return Semantics(
      container: true,
      label: _semanticSummary(),
      child: ExcludeSemantics(child: _buildCard(context, c)),
    );
  }

  String _semanticSummary() {
    final parts = <String>['Digital yatra pass for $memberName'];
    if (role != null) parts.add('role $role');
    if (nextStopTitle != null) {
      parts.add(
        'next stop $nextStopTitle${nextStopPlace != null ? ' at $nextStopPlace' : ''}',
      );
    }
    for (final row in rows) {
      parts.add('${row.label} ${row.value}');
    }
    return parts.join(', ');
  }

  Widget _buildCard(BuildContext context, SharanamColors c) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.gold.withValues(alpha: .9),
            c.gold.withValues(alpha: .25),
            c.gold.withValues(alpha: .9),
          ],
        ),
      ),
      padding: const EdgeInsets.all(1.4),
      child: Container(
        decoration: BoxDecoration(
          color: c.passCard,
          borderRadius: BorderRadius.circular(21),
        ),
        padding: const EdgeInsets.all(20),
        child: DefaultTextStyle(
          style: TextStyle(color: c.onPassCard, fontSize: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'DIGITAL YATRA PASS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: c.gold,
                    ),
                  ),
                  const Spacer(),
                  if (role != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.gold.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: c.gold.withValues(alpha: .5),
                        ),
                      ),
                      child: Text(
                        role!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.gold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                memberName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: c.onPassCard,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (nextStopTitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  'NEXT STOP',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: c.onPassCardMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  nextStopTitle!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (nextStopPlace != null)
                  Text(
                    nextStopPlace!,
                    style: TextStyle(fontSize: 14, color: c.onPassCardMuted),
                  ),
              ],
              if (rows.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Divider(
                    height: 1,
                    color: c.onPassCardMuted.withValues(alpha: .3),
                  ),
                ),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(row.icon, size: 19, color: c.gold),
                        const SizedBox(width: 12),
                        Text(
                          row.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: c.onPassCardMuted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          row.value,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PassRow {
  const PassRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;
}
