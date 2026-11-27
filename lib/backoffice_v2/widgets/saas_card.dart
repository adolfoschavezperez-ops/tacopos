import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';

class SaasCard extends StatefulWidget {
  const SaasCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  State<SaasCard> createState() => _SaasCardState();
}

class _SaasCardState extends State<SaasCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final hasHeader = widget.title != null || widget.trailing != null;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.title != null)
                        Text(
                          widget.title!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                ?widget.trailing,
              ],
            ),
          ),
          Divider(height: 1, color: tokens.border),
        ],
        Padding(padding: widget.padding, child: widget.child),
      ],
    );

    if (widget.onTap != null) {
      content = InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        hoverColor: tokens.surfaceHover,
        child: content,
      );
    }

    return MouseRegion(
      onEnter: (_) {
        if (widget.onTap != null) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (widget.onTap != null) setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: widget.elevated ? tokens.surfaceElevated : tokens.surface,
          borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
          border: Border.all(
            color: _hovered ? tokens.borderStrong : tokens.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: tokens.isDark ? 0.24 : (_hovered ? 0.06 : 0.03),
              ),
              blurRadius: _hovered ? 18 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}
