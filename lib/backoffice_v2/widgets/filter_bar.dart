import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';

enum DatePreset { today, last7Days, last30Days, last90Days, monthToDate, custom }

class SaasFilterBar extends StatelessWidget {
  const SaasFilterBar({
    super.key,
    required this.activePreset,
    required this.startDateLabel,
    required this.endDateLabel,
    required this.onPresetSelected,
    required this.onPickCustomRange,
    this.searchController,
    this.searchHint = 'Buscar por folio, mesa o cliente...',
    this.onSearchSubmitted,
    this.trailingActions = const [],
  });

  final DatePreset activePreset;
  final String startDateLabel;
  final String endDateLabel;
  final ValueChanged<DatePreset> onPresetSelected;
  final VoidCallback onPickCustomRange;
  final TextEditingController? searchController;
  final String searchHint;
  final ValueChanged<String>? onSearchSubmitted;
  final List<Widget> trailingActions;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        border: Border.all(color: tokens.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _PresetGroup(
            activePreset: activePreset,
            onPresetSelected: onPresetSelected,
          ),
          OutlinedButton.icon(
            onPressed: onPickCustomRange,
            icon: const Icon(Icons.calendar_today_outlined, size: 14),
            label: Text('$startDateLabel — $endDateLabel'),
          ),
          if (searchController != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
              child: TextField(
                controller: searchController,
                onSubmitted: onSearchSubmitted,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: searchHint,
                  prefixIcon: const Icon(Icons.search, size: 16),
                ),
              ),
            ),
          ...trailingActions,
        ],
      ),
    );
  }
}

class _PresetGroup extends StatelessWidget {
  const _PresetGroup({
    required this.activePreset,
    required this.onPresetSelected,
  });

  final DatePreset activePreset;
  final ValueChanged<DatePreset> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final items = [
      (DatePreset.today, 'Hoy'),
      (DatePreset.last7Days, '7 días'),
      (DatePreset.last30Days, '30 días'),
      (DatePreset.last90Days, '90 días'),
      (DatePreset.monthToDate, 'Mes'),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((entry) {
          final selected = activePreset == entry.$1;
          return InkWell(
            onTap: () => onPresetSelected(entry.$1),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? tokens.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: selected ? Border.all(color: tokens.border) : null,
              ),
              child: Text(
                entry.$2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? tokens.textPrimary : tokens.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
