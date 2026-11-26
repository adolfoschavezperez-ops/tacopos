import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded, local-only diagnostics for an administrator to inspect on-device.
/// It never stores order IDs, employee IDs, PINs, tokens, exception messages,
/// or document paths, and it never writes diagnostics to Firebase.
class OperationalDiagnosticsService with WidgetsBindingObserver {
  OperationalDiagnosticsService._();

  static final instance = OperationalDiagnosticsService._();

  static const int maxFileBytes = 128 * 1024;
  static const int maxEventsInMemory = 200;
  static const Set<String> _allowedFields = {
    'durationMs',
    'documents',
    'convertedDocuments',
    'results',
    'listeners',
    'queueDepth',
    'generation',
    'fromCache',
    'pendingWrites',
    'errorCode',
    'stage',
    'frames',
    'slowFrames',
    'maxFrameMs',
    'rssMb',
    'employeeTag',
    'deviceTag',
    'branchTag',
    'source',
    'versionCode',
    'cpuPercent',
    'pssMb',
    'rxBytesDelta',
    'txBytesDelta',
  };

  File? _file;
  Future<void> _writeTail = Future<void>.value();
  Timer? _flushTimer;
  final List<Map<String, Object?>> _pending = [];
  final List<Map<String, Object?>> _recent = [];
  int _slowFrames = 0;
  double _maxFrameMs = 0;
  int _frameCount = 0;
  DateTime? _lastFrameSummaryAt;
  final MethodChannel _diagnosticsChannel = const MethodChannel(
    'tacopos/device_diagnostics',
  );
  Timer? _resourceTimer;
  int? _previousCpuTimeMs;
  DateTime? _previousCpuSampleAt;
  int? _previousRxBytes;
  int? _previousTxBytes;
  bool _started = false;
  int _activeListeners = 0;

  int get activeListeners => _activeListeners;

  void listenerAttached(String source) {
    _activeListeners++;
    record(
      'listener',
      'attach',
      fields: {'listeners': _activeListeners, 'source': source},
    );
  }

  void listenerCancelled(String source) {
    if (_activeListeners > 0) _activeListeners--;
    record(
      'listener',
      'cancel',
      fields: {'listeners': _activeListeners, 'source': source},
    );
  }

  Future<void> initialize() async {
    if (_started || kIsWeb) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _startResourceSampling();
    try {
      final directory = await getApplicationSupportDirectory();
      _file = File(
        '${directory.path}${Platform.pathSeparator}operational-diagnostics.jsonl',
      );
      record('app', 'diagnostics_started');
    } catch (error) {
      developer.log(
        'local diagnostic store unavailable',
        name: 'OperationalDiagnostics',
        error: error.runtimeType.toString(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    record('lifecycle', state.name);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _resourceTimer?.cancel();
      _resourceTimer = null;
      _previousCpuTimeMs = null;
      _previousCpuSampleAt = null;
      _previousRxBytes = null;
      _previousTxBytes = null;
      _flush();
    } else if (state == AppLifecycleState.resumed) {
      _startResourceSampling();
    }
  }

  void _startResourceSampling() {
    if (_resourceTimer?.isActive == true || kIsWeb) return;
    unawaited(_sampleResources());
    _resourceTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_sampleResources()),
    );
  }

  Future<void> _sampleResources() async {
    try {
      final metrics = await _diagnosticsChannel.invokeMapMethod<String, num>(
        'processMetrics',
      );
      if (metrics == null) return;
      final cpuTimeMs = metrics['cpuTimeMs']?.toInt();
      final pssBytes = metrics['pssBytes']?.toInt();
      final rxBytes = metrics['rxBytes']?.toInt();
      final txBytes = metrics['txBytes']?.toInt();
      final now = DateTime.now();
      final previousCpuTime = _previousCpuTimeMs;
      final previousAt = _previousCpuSampleAt;
      final cpuPercent =
          cpuTimeMs != null &&
              previousCpuTime != null &&
              previousAt != null &&
              now.isAfter(previousAt)
          ? 100 *
                (cpuTimeMs - previousCpuTime) /
                now.difference(previousAt).inMilliseconds
          : null;
      _previousCpuTimeMs = cpuTimeMs;
      _previousCpuSampleAt = now;
      final rxBytesDelta = rxBytes != null && _previousRxBytes != null
          ? rxBytes - _previousRxBytes!
          : null;
      final txBytesDelta = txBytes != null && _previousTxBytes != null
          ? txBytes - _previousTxBytes!
          : null;
      _previousRxBytes = rxBytes != null && rxBytes >= 0 ? rxBytes : null;
      _previousTxBytes = txBytes != null && txBytes >= 0 ? txBytes : null;
      record(
        'device',
        'resource_sample',
        fields: {
          ...?cpuPercent == null ? null : {'cpuPercent': cpuPercent},
          if (pssBytes != null) 'pssMb': (pssBytes / (1024 * 1024)).round(),
          if (rxBytesDelta != null && rxBytesDelta >= 0)
            'rxBytesDelta': rxBytesDelta,
          if (txBytesDelta != null && txBytesDelta >= 0)
            'txBytesDelta': txBytesDelta,
        },
      );
    } on PlatformException catch (error) {
      record('device', 'resource_sample', result: error.code);
    } catch (error) {
      record('device', 'resource_sample', result: error.runtimeType.toString());
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameCount++;
      final durationMs = timing.totalSpan.inMicroseconds / 1000;
      if (durationMs >= 32) {
        _slowFrames++;
        if (durationMs > _maxFrameMs) _maxFrameMs = durationMs;
      }
    }
    final now = DateTime.now();
    if (_slowFrames == 0 ||
        (_lastFrameSummaryAt != null &&
            now.difference(_lastFrameSummaryAt!) <
                const Duration(minutes: 1))) {
      return;
    }
    _lastFrameSummaryAt = now;
    record(
      'ui',
      'frame_summary',
      fields: {
        'frames': _frameCount,
        'slowFrames': _slowFrames,
        'maxFrameMs': _maxFrameMs.round(),
      },
    );
    _slowFrames = 0;
    _maxFrameMs = 0;
    _frameCount = 0;
  }

  void record(
    String category,
    String event, {
    String result = 'ok',
    Duration? duration,
    Map<String, Object?> fields = const {},
    String? employeeId,
    String? branchId,
  }) {
    if (kIsWeb) return;
    final deviceTag = _currentDeviceTag;
    final rss = _currentRssMb;
    final row = <String, Object?>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'category': _safeLabel(category),
      'event': _safeLabel(event),
      'result': _safeLabel(result),
      if (duration != null) 'durationMs': duration.inMilliseconds,
      if (employeeId != null) 'employeeTag': _tag(employeeId),
      if (branchId != null) 'branchTag': _tag(branchId),
      ...?deviceTag == null ? null : {'deviceTag': deviceTag},
      ...?rss == null ? null : {'rssMb': rss},
      ..._safeFields(fields),
    };
    _recent.add(row);
    if (_recent.length > maxEventsInMemory) {
      _recent.removeRange(0, _recent.length - maxEventsInMemory);
    }
    _pending.add(row);
    if (_pending.length > maxEventsInMemory) {
      _pending.removeRange(0, _pending.length - maxEventsInMemory);
    }
    // Widget/unit tests may record lifecycle events without initializing the
    // platform store. Keep those events in memory; production initializes the
    // service before starting periodic file flushes.
    if (_started) {
      _flushTimer ??= Timer(const Duration(seconds: 3), _flush);
    }
  }

  int? get _currentRssMb {
    try {
      return (ProcessInfo.currentRss / (1024 * 1024)).round();
    } catch (_) {
      return null;
    }
  }

  String? get _currentDeviceTag {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      return uid == null ? null : _tag(uid);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _safeFields(Map<String, Object?> input) {
    final output = <String, Object?>{};
    for (final entry in input.entries) {
      if (!_allowedFields.contains(entry.key)) continue;
      final value = entry.value;
      if (value is bool || value is int || value is double) {
        output[entry.key] = value;
      } else if (value is String && entry.key == 'source') {
        output[entry.key] = _safeLabel(value);
      } else if (value is String && entry.key == 'errorCode') {
        output[entry.key] = _safeLabel(value);
      } else if (value is String && entry.key == 'stage') {
        output[entry.key] = _safeLabel(value);
      }
    }
    return output;
  }

  String _safeLabel(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_.-]'),
      '_',
    );
    return normalized.substring(0, normalized.length.clamp(0, 48));
  }

  String _tag(String value) => sha256
      .convert(utf8.encode('tacopos-diagnostics-v1:$value'))
      .toString()
      .substring(0, 12);

  Future<List<Map<String, Object?>>> readRecent({int limit = 100}) async {
    _flush();
    await _writeTail;
    final file = _file;
    if (file == null || !await file.exists()) {
      return List.unmodifiable(_recent.reversed.take(limit));
    }
    try {
      final lines = await file.readAsLines();
      final rows = <Map<String, Object?>>[];
      for (final line in lines.reversed) {
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          rows.add(Map<String, Object?>.from(decoded));
          if (rows.length >= limit) break;
        }
      }
      return List.unmodifiable(rows);
    } catch (error) {
      developer.log(
        'local diagnostic read failed',
        name: 'OperationalDiagnostics',
        error: error.runtimeType.toString(),
      );
      return List.unmodifiable(_recent.reversed.take(limit));
    }
  }

  Future<String> exportRecent({int limit = 200}) async {
    final rows = await readRecent(limit: limit);
    return rows.map(jsonEncode).join('\n');
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final file = _file;
    if (file == null || _pending.isEmpty) return;
    final batch = List<Map<String, Object?>>.of(_pending);
    _pending.clear();
    _writeTail = _writeTail.then((_) async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '${batch.map(jsonEncode).join('\n')}\n',
          mode: FileMode.append,
          flush: false,
        );
        final length = await file.length();
        if (length > maxFileBytes) {
          final content = await file.readAsString();
          final tail = content.substring(content.length - (maxFileBytes ~/ 2));
          final firstNewline = tail.indexOf('\n');
          await file.writeAsString(
            firstNewline < 0 ? tail : tail.substring(firstNewline + 1),
            flush: true,
          );
        }
      } catch (error) {
        developer.log(
          'local diagnostic write failed',
          name: 'OperationalDiagnostics',
          error: error.runtimeType.toString(),
        );
      }
    });
  }

  @visibleForTesting
  Future<void> configureForTesting(File file) async {
    _file = file;
    _recent.clear();
    _pending.clear();
    _flushTimer?.cancel();
    _writeTail = Future<void>.value();
  }

  @visibleForTesting
  Future<void> flushForTesting() async {
    _flush();
    await _writeTail;
  }
}
