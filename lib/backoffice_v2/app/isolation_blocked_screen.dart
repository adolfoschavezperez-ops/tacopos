import 'package:flutter/material.dart';

import '../core/design/backoffice_theme.dart';
import '../core/design/design_tokens.dart';
import '../core/env/backoffice_env.dart';

class IsolationBlockedApp extends StatelessWidget {
  const IsolationBlockedApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final code = error is EnvironmentGuardException
        ? (error as EnvironmentGuardException).code
        : 'CONFIG_ERROR';
    final message = error is EnvironmentGuardException
        ? (error as EnvironmentGuardException).message
        : error.toString();

    return MaterialApp(
      title: 'TacoPOS Backoffice 2.0 — Bloqueado',
      debugShowCheckedModeBanner: false,
      theme: BackofficeTheme.light(),
      home: Builder(
        builder: (context) {
          final tokens = BackofficeTokens.of(context);
          return Scaffold(
            backgroundColor: tokens.canvas,
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(
                      BackofficeSpacing.radiusLg,
                    ),
                    border: Border.all(
                      color: tokens.danger.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: tokens.dangerSoft,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.gpp_bad_outlined,
                              color: tokens.danger,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Inicio bloqueado por protección de ambiente',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  'Código: $code',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.surfaceSubtle,
                          borderRadius: BorderRadius.circular(
                            BackofficeSpacing.radiusMd,
                          ),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          'Por seguridad, Backoffice 2.0 nunca realiza fallback automático a producción. Ejecuta con --dart-define=ENV=local o --dart-define=ENV=dev.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
