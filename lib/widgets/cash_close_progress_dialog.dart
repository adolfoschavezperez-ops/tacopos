import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/cash/cash_close_execution.dart';
import '../core/theme/brand_colors.dart';

class CashCloseProgressDialog extends StatelessWidget {
  const CashCloseProgressDialog({super.key, required this.stageListenable});

  final ValueListenable<CashCloseProgressStage> stageListenable;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ValueListenableBuilder<CashCloseProgressStage>(
        valueListenable: stageListenable,
        builder: (context, stage, _) {
          return AlertDialog(
            title: Text(stage.title),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: BrandColors.accentYellow,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    stage.message,
                    style: const TextStyle(
                      color: BrandColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
