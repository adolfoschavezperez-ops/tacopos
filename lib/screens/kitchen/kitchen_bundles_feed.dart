import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/app_session.dart';
import '../../services/operational_diagnostics_service.dart';
import '../../services/taco_pos_repository.dart';

/// Owned by one kitchen route; consumers share state, never the upstream stream.
class KitchenBundlesFeed
    extends ValueNotifier<AsyncSnapshot<List<KitchenOrderBundle>>> {
  KitchenBundlesFeed(Stream<List<KitchenOrderBundle>> Function() watch)
    : this.synchronized(() => watch().map(KitchenBundlesState.confirmed));

  KitchenBundlesFeed.synchronized(this._watch)
    : super(const AsyncSnapshot.waiting()) {
    _scope = _currentScope;
    AppSession.instance.addListener(_onSessionChanged);
  }

  final Stream<KitchenBundlesState> Function() _watch;
  StreamSubscription<KitchenBundlesState>? _subscription;
  KitchenBundlesState syncState = const KitchenBundlesState();
  Future<void> _cancellation = Future<void>.value();
  late String _scope;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  String get scope => _scope;
  String get _currentScope =>
      '${AppSession.instance.currentRestaurantId}/${AppSession.instance.currentBranchId}';

  void start() {
    if (_started || _disposed) return;
    _started = true;
    OperationalDiagnosticsService.instance.listenerAttached('kitchen.feed');
    _listen(_generation);
  }

  void _listen(int generation) {
    try {
      _subscription = _watch().listen(
        (state) {
          if (_disposed || generation != _generation) return;
          _setState(state);
        },
        onError: (Object error, StackTrace stack) {
          if (_disposed || generation != _generation) return;
          _setState(
            syncState.withIssue(KitchenSyncIssue(error, recoverable: false)),
          );
        },
      );
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _setState(
          syncState.withIssue(KitchenSyncIssue(error, recoverable: false)),
        );
      }
    }
  }

  void _setState(KitchenBundlesState state) {
    syncState = state;
    OperationalDiagnosticsService.instance.record(
      'kitchen',
      'feed_state',
      result: state.issues.isNotEmpty
          ? 'error'
          : state.isConfirmed
          ? 'confirmed'
          : 'provisional',
      fields: {
        'results': state.bundles.length,
        'documents': state.activeOrderIds.length,
        'fromCache': state.ordersFromCache,
        'pendingWrites': state.ordersPendingWrites,
        'queueDepth': state.loadingItemOrderIds.length,
      },
      branchId: AppSession.instance.currentBranchId,
    );
    final previous = value;
    if (state.hasData) {
      value = AsyncSnapshot.withData(ConnectionState.active, state.bundles);
    } else if (state.issues.isNotEmpty) {
      value = AsyncSnapshot.withError(
        ConnectionState.active,
        state.issues.first.error,
      );
    } else {
      value = const AsyncSnapshot.waiting();
    }
    if (previous == value) notifyListeners();
  }

  void _onSessionChanged() {
    if (_scope == _currentScope) return;
    _scope = _currentScope;
    OperationalDiagnosticsService.instance.record(
      'kitchen',
      'feed_scope_changed',
      result: 'restarting',
      fields: {'generation': _generation + 1},
      branchId: AppSession.instance.currentBranchId,
    );
    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    _cancellation = _cancellation.then((_) => previous?.cancel());
    _setState(const KitchenBundlesState());
    unawaited(_restart(_cancellation, generation));
  }

  Future<void> _restart(Future<void> cancellation, int generation) async {
    await cancellation;
    if (!_disposed && _started && generation == _generation) {
      _listen(generation);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    AppSession.instance.removeListener(_onSessionChanged);
    unawaited(_subscription?.cancel());
    if (_started) {
      OperationalDiagnosticsService.instance.listenerCancelled('kitchen.feed');
    }
    super.dispose();
  }
}
