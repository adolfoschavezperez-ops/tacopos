import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';

/// Owned by one kitchen route; consumers share state, never the upstream stream.
class KitchenBundlesFeed
    extends ValueNotifier<AsyncSnapshot<List<KitchenOrderBundle>>> {
  KitchenBundlesFeed(this._watch) : super(const AsyncSnapshot.waiting()) {
    _scope = _currentScope;
    AppSession.instance.addListener(_onSessionChanged);
  }

  final Stream<List<KitchenOrderBundle>> Function() _watch;
  StreamSubscription<List<KitchenOrderBundle>>? _subscription;
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
    _listen(_generation);
  }

  void _listen(int generation) {
    try {
      _subscription = _watch().listen(
        (bundles) {
          if (_disposed || generation != _generation) return;
          value = AsyncSnapshot.withData(ConnectionState.active, bundles);
        },
        onError: (Object error, StackTrace stack) {
          if (_disposed || generation != _generation) return;
          value = AsyncSnapshot.withError(ConnectionState.active, error, stack);
        },
      );
    } catch (error, stack) {
      if (!_disposed && generation == _generation) {
        value = AsyncSnapshot.withError(ConnectionState.active, error, stack);
      }
    }
  }

  void _onSessionChanged() {
    if (_scope == _currentScope) return;
    _scope = _currentScope;
    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    _cancellation = _cancellation.then((_) => previous?.cancel());
    value = const AsyncSnapshot.waiting();
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
    super.dispose();
  }
}
