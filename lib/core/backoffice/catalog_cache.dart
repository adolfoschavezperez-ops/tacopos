import 'dart:async';

import '../../services/app_session.dart';

/// Shares one catalog listener between backoffice widgets while retaining the
/// last snapshot for the next subscriber.
class BackofficeCatalogCache {
  BackofficeCatalogCache._();

  static final instance = BackofficeCatalogCache._();

  final Map<String, _CatalogEntry<dynamic>> _entries = {};

  Stream<List<T>> watch<T>({
    required String catalog,
    required Stream<List<T>> Function() source,
  }) {
    final key = '${AppSession.instance.currentRestaurantId}:$catalog';
    final entry = _entries.putIfAbsent(key, () => _CatalogEntry<T>(source));
    if (entry is! _CatalogEntry<T>) {
      throw StateError('Catalog cache key reused with a different type.');
    }
    return entry.stream;
  }

  void invalidate(String catalog) {
    final prefix = '${AppSession.instance.currentRestaurantId}:$catalog';
    final keys = _entries.keys.where((key) => key == prefix).toList();
    for (final key in keys) {
      final entry = _entries[key];
      if (entry == null) continue;
      if (entry.hasListeners) {
        entry.invalidateSnapshot();
      } else {
        _entries.remove(key)?.dispose();
      }
    }
  }

  void clear() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }
}

class _CatalogEntry<T> {
  _CatalogEntry(this._source) {
    _controller
      ..onListen = _onListen
      ..onCancel = _onCancel;
  }

  final Stream<List<T>> Function() _source;
  final _controller = StreamController<List<T>>.broadcast();
  StreamSubscription<List<T>>? _subscription;
  List<T>? _lastValue;
  bool hasListeners = false;

  Stream<List<T>> get stream => _controller.stream;

  void _onListen() {
    hasListeners = true;
    final cached = _lastValue;
    if (cached != null) _controller.add(cached);
    _subscription ??= _source().listen((value) {
      _lastValue = List<T>.unmodifiable(value);
      _controller.add(_lastValue!);
    }, onError: _controller.addError);
  }

  Future<void> _onCancel() async {
    hasListeners = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  void invalidateSnapshot() {
    _lastValue = null;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
