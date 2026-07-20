import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import 'glass.dart';

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.message = 'Cargando...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ReportLoadingWidget(message: message);
  }
}

class ReportLoadingWidget extends StatefulWidget {
  const ReportLoadingWidget({super.key, this.message = 'Cargando...'});

  final String message;

  @override
  State<ReportLoadingWidget> createState() => _ReportLoadingWidgetState();
}

class _ReportLoadingWidgetState extends State<ReportLoadingWidget> {
  var _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    return Center(
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: BrandColors.accentYellow),
            const SizedBox(height: 14),
            Text(
              widget.message,
              style: const TextStyle(color: BrandColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
