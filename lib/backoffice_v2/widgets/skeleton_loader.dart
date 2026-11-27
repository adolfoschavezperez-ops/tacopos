import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.borderRadius = 6,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final color = Color.lerp(
          tokens.skeletonBase,
          tokens.skeletonHighlight,
          _controller.value,
        );
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 960
                ? 4
                : constraints.maxWidth >= 580
                ? 2
                : 1;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.3,
              children: List.generate(
                4,
                (_) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(
                      BackofficeSpacing.radiusLg,
                    ),
                    border: Border.all(color: tokens.border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SkeletonBox(width: 90, height: 11),
                      SizedBox(height: 12),
                      SkeletonBox(width: 140, height: 22),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          height: 240,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
            border: Border.all(color: tokens.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 14),
              SizedBox(height: 18),
              Expanded(child: SkeletonBox(height: double.infinity)),
            ],
          ),
        ),
      ],
    );
  }
}

class TableSkeleton extends StatelessWidget {
  const TableSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: List.generate(
          rows,
          (index) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: index == rows - 1
                  ? null
                  : Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: SkeletonBox(height: 12)),
                SizedBox(width: 16),
                Expanded(flex: 2, child: SkeletonBox(height: 12)),
                SizedBox(width: 16),
                Expanded(flex: 1, child: SkeletonBox(height: 12)),
                SizedBox(width: 16),
                Expanded(flex: 1, child: SkeletonBox(height: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
