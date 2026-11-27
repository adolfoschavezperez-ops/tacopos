import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';

class SaasCard extends StatelessWidget {
  const SaasCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final hasHeader = title != null || trailing != null;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: tokens.border),
        ],
        Padding(padding: padding, child: child),
      ],
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        hoverColor: tokens.surfaceHover,
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}
