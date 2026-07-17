import 'dart:async';

import 'package:flutter/material.dart';

enum AppSnackBarType { info, success, warning, error }

enum AppSnackBarPosition { bottom, top }

OverlayEntry? _topSnackEntry;
Timer? _topSnackTimer;

void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackBarType type = AppSnackBarType.info,
  SnackBarAction? action,
  AppSnackBarPosition position = AppSnackBarPosition.bottom,
  Duration duration = const Duration(seconds: 3),
}) {
  final safeDuration = _capDuration(duration);
  if (position == AppSnackBarPosition.top) {
    _showTopSnackBar(context, message, type: type, duration: safeDuration);
    return;
  }
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: safeDuration,
      behavior: SnackBarBehavior.floating,
      action: action,
    ),
  );
}

void _showTopSnackBar(
  BuildContext context,
  String message, {
  required AppSnackBarType type,
  required Duration duration,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  _topSnackTimer?.cancel();
  _topSnackEntry?.remove();
  _topSnackEntry = OverlayEntry(
    builder: (context) {
      final topInset = MediaQuery.viewPaddingOf(context).top;
      final color = _colorFor(type);
      return Positioned(
        top: topInset + 12,
        left: 14,
        right: 14,
        child: SafeArea(
          bottom: false,
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(_topSnackEntry!);
  _topSnackTimer = Timer(duration, () {
    _topSnackEntry?.remove();
    _topSnackEntry = null;
  });
}

Duration _capDuration(Duration duration) {
  const maxDuration = Duration(seconds: 3);
  if (duration <= Duration.zero || duration > maxDuration) {
    return maxDuration;
  }
  return duration;
}

Color _colorFor(AppSnackBarType type) {
  return switch (type) {
    AppSnackBarType.success => const Color(0xFF178A5A),
    AppSnackBarType.warning => const Color(0xFFC28416),
    AppSnackBarType.error => const Color(0xFFB8324A),
    AppSnackBarType.info => const Color(0xFF202A36),
  };
}
