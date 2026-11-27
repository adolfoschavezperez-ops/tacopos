import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';
import '../core/env/backoffice_env.dart';

class EnvironmentIndicatorPill extends StatelessWidget {
  const EnvironmentIndicatorPill({super.key, required this.config});

  final BackofficeConfig config;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final Color accent = config.isLocal ? tokens.info : tokens.warning;
    final Color bg = config.isLocal ? tokens.infoSoft : tokens.warningSoft;

    return Tooltip(
      message: config.isLocal
          ? 'Conectado exclusivamente a Firebase Emulator Suite (${config.emulatorHost})'
          : 'Ambiente de desarrollo aislado: ${config.projectId}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              config.badgeLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
