import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';
import '../core/env/backoffice_env.dart';

class EnvironmentIndicatorPill extends StatelessWidget {
  const EnvironmentIndicatorPill({super.key, required this.config});

  final BackofficeConfig config;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final label = config.isLocal ? 'LOCAL' : 'DEV';
    final Color accent = config.isLocal ? tokens.info : tokens.warning;
    final Color bg = config.isLocal ? tokens.infoSoft : tokens.warningSoft;

    return Tooltip(
      message: config.isLocal
          ? 'Ambiente de pruebas local'
          : 'Ambiente de desarrollo',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5.5,
              height: 5.5,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: accent,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
