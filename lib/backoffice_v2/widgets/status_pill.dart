import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';

enum StatusTone { neutral, success, warning, danger, info }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final (Color fg, Color bg) = switch (tone) {
      StatusTone.neutral => (tokens.textSecondary, tokens.surfaceSubtle),
      StatusTone.success => (tokens.success, tokens.successSoft),
      StatusTone.warning => (tokens.warning, tokens.warningSoft),
      StatusTone.danger => (tokens.danger, tokens.dangerSoft),
      StatusTone.info => (tokens.info, tokens.infoSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
