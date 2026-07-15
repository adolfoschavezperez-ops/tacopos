import 'package:flutter/material.dart';

enum AppSnackBarType { info, success, warning, error }

void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackBarType type = AppSnackBarType.info,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: _durationFor(type),
      action: action,
    ),
  );
}

Duration _durationFor(AppSnackBarType type) {
  return switch (type) {
    AppSnackBarType.error => const Duration(seconds: 6),
    AppSnackBarType.success => const Duration(seconds: 4),
    AppSnackBarType.warning => const Duration(seconds: 4),
    AppSnackBarType.info => const Duration(seconds: 4),
  };
}
