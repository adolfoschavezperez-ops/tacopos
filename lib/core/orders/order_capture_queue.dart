import 'dart:async';

import '../../models/order_item.dart';

/// Keeps remote items as a baseline and overlays only local, unconfirmed edits.
class OrderCaptureState {
  List<OrderItem> _baseline = const [];
  final Map<String, OrderItem> _pending = {};

  List<OrderItem> get effectiveItems {
    final baselineIds = _baseline.map((item) => item.id).toSet();
    return [
      ..._baseline.map((item) => _pending[item.id] ?? item),
      ..._pending.values.where((item) => !baselineIds.contains(item.id)),
    ];
  }

  String get effectiveSignature => effectiveItems
      .map(
        (item) =>
            '${item.id}|${item.productId}|${item.personNumber}|${item.qty}|${item.unitPrice}|${item.total}|${item.notes}|${item.kitchenStatus}|${item.paymentStatus}|${item.status}|${item.cancelStatus}',
      )
      .join(';;');

  void apply(OrderItem item) => _pending[item.id] = item;

  void reconcile(List<OrderItem> snapshot) {
    _baseline = List<OrderItem>.of(snapshot);
    final byId = {for (final item in snapshot) item.id: item};
    _pending.removeWhere((id, pending) {
      final remote = byId[id];
      return remote != null &&
          remote.qty == pending.qty &&
          (remote.total - pending.total).abs() < 0.005;
    });
  }

  void fail(String itemId) => _pending.remove(itemId);

  void clear() {
    _baseline = const [];
    _pending.clear();
  }
}

/// Serializes edits for one order and recalculates only after its queue drains.
class OrderCaptureQueue {
  OrderCaptureQueue({this.onStage, this.onEvent});

  final void Function(String stage, String orderId, String? operationId)?
  onStage;
  final void Function(
    String event,
    String orderId,
    int queueDepth,
    int generation,
    int burstId,
    String? operationId,
  )?
  onEvent;
  final Map<String, _OrderQueueState> _states = {};

  Future<void> enqueue(
    String orderId,
    Future<void> Function() mutation, {
    required Future<void> Function() recalculate,
    String? operationId,
  }) {
    final state = _states.putIfAbsent(orderId, _OrderQueueState.new);
    final result = state.enqueue(
      mutation,
      () {
        onStage?.call('T3', orderId, operationId);
        onEvent?.call(
          'WRITE_START',
          orderId,
          state.queueDepth,
          state.generation,
          state.burstId,
          operationId,
        );
      },
      () {
        onEvent?.call(
          'WRITE_END',
          orderId,
          state.queueDepth,
          state.generation,
          state.burstId,
          operationId,
        );
        if (state.queueDepth == 0) {
          onEvent?.call(
            'QUEUE_EMPTY',
            orderId,
            0,
            state.generation,
            state.burstId,
            operationId,
          );
          state.drainRecalculate(
            recalculate,
            onStage: () => onStage?.call('T5', orderId, operationId),
            onComplete: () => onStage?.call('T6', orderId, operationId),
            onEvent: (event, generation) => onEvent?.call(
              event,
              orderId,
              state.queueDepth,
              generation,
              state.burstId,
              operationId,
            ),
          );
        }
      },
    );
    onStage?.call('T2', orderId, operationId);
    onEvent?.call(
      'MUTATION_ENQUEUED',
      orderId,
      state.queueDepth,
      state.generation,
      state.burstId,
      operationId,
    );
    state.requestRecalculate();
    onEvent?.call(
      'RECALC_REQUESTED',
      orderId,
      state.queueDepth,
      state.generation,
      state.burstId,
      operationId,
    );
    return result;
  }

  Future<void> flush(
    String orderId, {
    required Future<void> Function() recalculate,
  }) async {
    final state = _states.putIfAbsent(orderId, _OrderQueueState.new);
    state.requestRecalculate();
    await state._tail;
    state.drainRecalculate(
      recalculate,
      onStage: () {},
      onComplete: () {},
      onEvent: (_, _) {},
    );
    final running = state.recalculateInFlight;
    if (running != null) await running;
  }

  void dispose() => _states.clear();
}

class _OrderQueueState {
  Future<void> _tail = Future<void>.value();
  Future<void>? recalculateInFlight;
  bool _recalculateAgain = false;
  bool _recalculateRequested = false;
  int queueDepth = 0;
  int generation = 0;
  int burstId = 0;
  bool _burstOpen = false;
  Future<void> Function()? _recalculate;
  void Function()? _onRecalculateStage;
  void Function()? _onRecalculateComplete;
  void Function(String event, int generation)? _onRecalculateEvent;

  Future<void> enqueue(
    Future<void> Function() mutation,
    void Function() onStart,
    void Function() onComplete,
  ) {
    if (queueDepth == 0 && !_burstOpen) {
      burstId++;
      _burstOpen = true;
    }
    queueDepth++;
    generation++;
    final result = _tail.then((_) {
      onStart();
      return mutation().whenComplete(() {
        queueDepth--;
        if (queueDepth == 0) _burstOpen = false;
        onComplete();
      });
    });
    _tail = result.catchError((_) {});
    return result;
  }

  void requestRecalculate() {
    _recalculateRequested = true;
    if (recalculateInFlight != null) _recalculateAgain = true;
  }

  void drainRecalculate(
    Future<void> Function() recalculate, {
    required void Function() onStage,
    required void Function() onComplete,
    required void Function(String event, int generation) onEvent,
  }) {
    _recalculate = recalculate;
    _onRecalculateStage = onStage;
    _onRecalculateComplete = onComplete;
    _onRecalculateEvent = onEvent;
    if (queueDepth != 0 || !_recalculateRequested) return;
    if (recalculateInFlight != null) {
      _recalculateAgain = true;
      onEvent('RECALC_AGAIN', generation);
      return;
    }
    final operation = () async {
      do {
        _recalculateAgain = false;
        final recalcGeneration = generation;
        onEvent('RECALC_START', recalcGeneration);
        onStage();
        await recalculate();
        onComplete();
        onEvent('RECALC_END', recalcGeneration);
        if (queueDepth > 0) return;
      } while (_recalculateAgain);
      _recalculateRequested = false;
    }();
    recalculateInFlight = operation;
    unawaited(
      operation.then(
        (_) => _finishRecalculate(),
        onError: (Object error, StackTrace stackTrace) {
          _finishRecalculate();
          Error.throwWithStackTrace(error, stackTrace);
        },
      ),
    );
  }

  void _finishRecalculate() {
    recalculateInFlight = null;
    if (queueDepth == 0 && _recalculateRequested && _recalculate != null) {
      scheduleMicrotask(
        () => drainRecalculate(
          _recalculate!,
          onStage: _onRecalculateStage ?? () {},
          onComplete: _onRecalculateComplete ?? () {},
          onEvent: _onRecalculateEvent ?? (_, _) {},
        ),
      );
    }
  }
}
