import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';

class SaasColumn<T> {
  const SaasColumn({
    required this.label,
    required this.cellBuilder,
    this.flex = 1,
    this.alignRight = false,
  });

  final String label;
  final Widget Function(T item) cellBuilder;
  final int flex;
  final bool alignRight;
}

class DataTablePro<T> extends StatelessWidget {
  const DataTablePro({
    super.key,
    required this.columns,
    required this.items,
    this.onRowTap,
    this.footerSummary,
    this.hasPrevious = false,
    this.hasNext = false,
    this.onPrevious,
    this.onNext,
    this.pageLabel,
  });

  final List<SaasColumn<T>> columns;
  final List<T> items;
  final ValueChanged<T>? onRowTap;
  final String? footerSummary;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? pageLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final minWidth = (columns.length * 130).toDouble();
              final tableWidth = constraints.maxWidth > minWidth
                  ? constraints.maxWidth
                  : minWidth;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceSubtle,
                          border: Border(
                            bottom: BorderSide(color: tokens.border),
                          ),
                        ),
                        child: Row(
                          children: columns
                              .map(
                                (col) => Expanded(
                                  flex: col.flex,
                                  child: Align(
                                    alignment: col.alignRight
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Text(
                                      col.label.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.4,
                                        color: tokens.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      ...items.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final isLast = index == items.length - 1;
                        return InkWell(
                          onTap: onRowTap == null ? null : () => onRowTap!(item),
                          hoverColor: tokens.surfaceHover,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              border: isLast
                                  ? null
                                  : Border(
                                      bottom: BorderSide(color: tokens.border),
                                    ),
                            ),
                            child: Row(
                              children: columns
                                  .map(
                                    (col) => Expanded(
                                      flex: col.flex,
                                      child: Align(
                                        alignment: col.alignRight
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: col.cellBuilder(item),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
          if (footerSummary != null || hasPrevious || hasNext || pageLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: tokens.surfaceSubtle,
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    footerSummary ?? '',
                    style: TextStyle(fontSize: 12, color: tokens.textMuted),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pageLabel != null) ...[
                        Text(
                          pageLabel!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: hasPrevious ? onPrevious : null,
                        icon: const Icon(Icons.chevron_left, size: 16),
                        label: const Text('Anterior'),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: hasNext ? onNext : null,
                        icon: const Icon(Icons.chevron_right, size: 16),
                        label: const Text('Siguiente'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
