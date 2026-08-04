import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';

enum VisitSurveyAnswer {
  firstTime('first_time', true),
  returning('returning', false);

  const VisitSurveyAnswer(this.firestoreValue, this.isFirstVisit);

  final String firestoreValue;
  final bool isFirstVisit;
}

Future<VisitSurveyAnswer?> showVisitSurveyDialog(BuildContext context) {
  return showGeneralDialog<VisitSurveyAnswer>(
    context: context,
    barrierColor: BrandColors.backgroundPrimary.withAlpha(245),
    barrierDismissible: false,
    barrierLabel: 'Cliente nuevo',
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, _, _) => const VisitSurveyDialog(),
  );
}

class VisitSurveyDialog extends StatefulWidget {
  const VisitSurveyDialog({super.key});

  @override
  State<VisitSurveyDialog> createState() => _VisitSurveyDialogState();
}

class _VisitSurveyDialogState extends State<VisitSurveyDialog> {
  bool _answered = false;

  void _answer(VisitSurveyAnswer answer) {
    if (_answered) return;
    setState(() => _answered = true);
    Navigator.of(context).pop(answer);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortestSide = media.size.shortestSide;
    final titleSize = shortestSide < 600 ? 34.0 : 44.0;
    final buttonTextSize = shortestSide < 600 ? 28.0 : 34.0;
    final buttonHeight = shortestSide < 600 ? 96.0 : 112.0;

    return Material(
      color: BrandColors.backgroundPrimary,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.clamp(320.0, 760.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '¿ES CLIENTE NUEVO?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: BrandColors.textPrimary,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 48),
                      _VisitSurveyButton(
                        label: 'Sí',
                        height: buttonHeight,
                        fontSize: buttonTextSize,
                        enabled: !_answered,
                        filled: true,
                        onPressed: () => _answer(VisitSurveyAnswer.firstTime),
                      ),
                      const SizedBox(height: 28),
                      _VisitSurveyButton(
                        label: 'No',
                        height: buttonHeight,
                        fontSize: buttonTextSize,
                        enabled: !_answered,
                        filled: false,
                        onPressed: () => _answer(VisitSurveyAnswer.returning),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VisitSurveyButton extends StatelessWidget {
  const _VisitSurveyButton({
    required this.label,
    required this.height,
    required this.fontSize,
    required this.enabled,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final double height;
  final double fontSize;
  final bool enabled;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final background = filled ? BrandColors.accentYellow : BrandColors.surface;
    final foreground = filled
        ? BrandColors.backgroundPrimary
        : BrandColors.textPrimary;
    final borderColor = filled
        ? BrandColors.accentYellow
        : BrandColors.glassBorder;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withAlpha(150),
          disabledForegroundColor: foreground.withAlpha(180),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderColor, width: 1.4),
          ),
          textStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
