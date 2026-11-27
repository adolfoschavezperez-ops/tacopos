import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';
import 'status_pill.dart';

class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaPositive,
    this.subtitle,
    this.icon,
  });

  final String label;
  final String value;
  final String? delta;
  final bool? deltaPositive;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tokens.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null)
                Icon(icon, size: 16, color: tokens.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 8),
                StatusPill(
                  label: delta!,
                  tone: switch (deltaPositive) {
                    true => StatusTone.success,
                    false => StatusTone.danger,
                    null => StatusTone.neutral,
                  },
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11.5, color: tokens.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
