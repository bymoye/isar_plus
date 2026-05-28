import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart' show visibleForTesting;

/// A function type that represents a unit of work to be executed on a worker
/// isolate.
///
/// The computation may return a value of type [T] either synchronously or
/// asynchronously. It is passed to [IsarWorkerPool.run] and executed in
/// isolation from the main isolate.
///
/// Example:
/// ```dart
/// IsarWorkerComputation<int> work = () async {
///   await Future.delayed(Duration(milliseconds: 100));
///   return 42;
/// };
/// final result = await IsarWorkerPool.run(work);
/// ```
typedef IsarWorkerComputation<T> = FutureOr<T> Function();

/// Holds a deferred computation together with the [Completer] used to deliver
/// its result back to the original caller.
///
/// Instances are placed in [IsarWorkerPool._pendingQueue] when all worker
/// isolates are busy and are drained as workers become idle.
class _PendingTask<T> {
  /// Creates a [_PendingTask] with the given [computation] and [completer].
  _PendingTask(this.computation, this.completer);

  /// The unit of work to run on a worker isolate.
  final IsarWorkerComputation<T> computation;

  /// The [Completer] whose future was handed back to the caller. Once the
  /// computation finishes (or throws), this completer is resolved accordingly.
  final Completer<T> completer;
}

/// A static, lazily-initialized pool of Dart [Isolate]s used to offload
/// CPU-intensive work away from the main isolate.
///
/// ## Overview
///
/// [IsarWorkerPool] manages a fixed set of long-lived worker isolates. Work is
/// submitted via [run], which either dispatches to an idle worker immediately
/// or enqueues the task until one becomes available. Tasks are always executed
/// in FIFO order.
///
/// The pool is initialized on the first call to [run] and can be torn down
/// with [dispose]. After disposal the pool can be re-initialized by calling
/// [run] again.
///
/// ## Worker count
///
/// By default the pool creates `(Platform.numberOfProcessors - 1).clamp(2, 8)`
/// workers. This can be overridden before the first [run] call using
/// [configure].
///
/// ## Usage
///
/// ```dart
/// // Optional: customise the pool size before first use.
/// IsarWorkerPool.configure(4);
///
/// // Submit work from any isolate context.
/// final result = await IsarWorkerPool.run<int>(() async {
///   // Heavy computation here …
///   return expensiveCalculation();
/// });
///
/// // Shut down all worker isolates when no longer needed.
/// await IsarWorkerPool.dispose();
/// ```
///
/// ## Thread safety
///
/// All public methods must be called from the **same** isolate (typically the
/// root isolate). The pool is not safe to use concurrently from multiple
/// isolates.
class IsarWorkerPool {
  // Private constructor prevents instantiation – this is a purely static API.
  IsarWorkerPool._();

  /// Overrides the default worker count set by [configure].
  ///
  /// `null` means "use the platform default".
  static int? _customWorkerCount;

  /// All spawned [_WorkerHandle]s, both idle and busy.
  static final List<_WorkerHandle> _allWorkers = [];

  /// Workers that are not currently executing a task and are ready to accept
  /// new work immediately.
  static final Queue<_WorkerHandle> _idleWorkers = Queue();

  /// Tasks waiting for a worker to become free. Drained in FIFO order by
  /// [_onWorkerIdle].
  static final Queue<_PendingTask<dynamic>> _pendingQueue = Queue();

  /// The [Future] that resolves once all worker isolates have been spawned.
  ///
  /// A non-null value indicates that initialization has started (or
  /// completed). It is reset to `null` by [dispose] so the pool can be
  /// reused.
  static Future<void>? _initFuture;

  /// Overrides the number of worker isolates created when the pool is first
  /// initialized.
  ///
  /// [workerCount] is clamped to the range `[1, 16]`.
  ///
  /// Must be called **before** the first [run] (i.e., before the pool is
  /// initialized). Calling it after initialization throws an
  /// [UnsupportedError].
  ///
  /// Throws:
  /// - [UnsupportedError] if the pool has already been initialized.
  ///
  /// Example:
  /// ```dart
  /// IsarWorkerPool.configure(4); // Use exactly 4 workers.
  /// ```
  static void configure(int workerCount) {
    if (_initFuture != null) {
      throw UnsupportedError(
        'IsarWorkerPool is already initialized and cannot be reconfigured.',
      );
    }
    _customWorkerCount = workerCount.clamp(1, 16);
  }

  /// Returns the number of workers that will be (or have been) spawned.
  ///
  /// When a custom value has been set via [configure] that value is returned.
  /// Otherwise the count is derived from [Platform.numberOfProcessors]:
  /// `(processors - 1).clamp(2, 8)`.
  static int get _workerCount {
    if (_customWorkerCount != null) return _customWorkerCount!;
    return (Platform.numberOfProcessors - 1).clamp(2, 8);
  }

  /// Explicitly starts the worker isolates in the background.
  ///
  /// This can be called to "warm up" the pool so that the first call to [run]
  /// doesn't experience the latency of spawning isolates.
  ///
  /// The pool is automatically warmed up when an Isar instance is opened.
  static Future<void> warmUp() => _ensureInitialized();

  /// Ensures the pool is initialized, spawning worker isolates if needed.
  ///
  /// Returns the cached [_initFuture] if initialization is already in
  /// progress or complete, or kicks off [_initialize] on the first call.
  static Future<void> _ensureInitialized() {
    return _initFuture ??= _initialize();
  }

  /// Spawns [_workerCount] worker isolates concurrently and registers them
  /// with [_allWorkers] and [_idleWorkers].
  static Future<void> _initialize() async {
    final count = _workerCount;
    final futures = List.generate(
      count,
      (i) => _WorkerHandle.spawn('Isar Worker ${i + 1}'),
    );

    final List<_WorkerHandle> workers;
    try {
      workers = await Future.wait(futures);
    } catch (_) {
      for (final future in futures) {
        future.then((w) => w.dispose(), onError: (_) {});
      }
      _initFuture = null;
      rethrow;
    }

    _allWorkers.addAll(workers);
    _idleWorkers.addAll(workers);
  }

  /// Submits [computation] to be executed on a worker isolate and returns a
  /// [Future] that completes with the result (or an error) once the work is
  /// done.
  ///
  /// If a worker is available the computation is dispatched immediately.
  /// Otherwise it is added to an internal FIFO queue and will be executed
  /// once a worker becomes free.
  ///
  /// The pool is lazily initialized on the first call to [run].
  ///
  /// Example:
  /// ```dart
  /// final sum = await IsarWorkerPool.run<int>(() {
  ///   return List.generate(1000000, (i) => i).reduce((a, b) => a + b);
  /// });
  /// ```
  ///
  /// Throws any error thrown by [computation], preserving the original stack
  /// trace.
  static Future<T> run<T>(IsarWorkerComputation<T> computation) async {
    await _ensureInitialized();

    if (_idleWorkers.isNotEmpty) {
      return _idleWorkers.removeFirst().execute<T>(computation, _onWorkerIdle);
    }

    final taskCompleter = Completer<T>();
    _pendingQueue.add(_PendingTask<T>(computation, taskCompleter));
    return taskCompleter.future;
  }

  /// Shuts down all worker isolates and resets the pool to its uninitialized
  /// state.
  ///
  /// Waits for ongoing initialization to complete before killing isolates.
  /// Any tasks still in the pending queue are silently discarded — callers
  /// whose [Future]s have not yet resolved will never receive a value or an
  /// error after [dispose] is called. Ensure that all in-flight work has
  /// completed before disposing if result delivery is required.
  ///
  /// After [dispose] the pool can be re-initialized by calling [run] or
  /// [configure] again.
  ///
  /// Example:
  /// ```dart
  /// await IsarWorkerPool.dispose();
  /// ```
  static Future<void> dispose() async {
    await _initFuture?.catchError((_) {});
    for (final worker in _allWorkers) {
      worker.dispose();
    }
    _allWorkers.clear();
    _idleWorkers.clear();
    _pendingQueue.clear();
    _initFuture = null;
    // Intentionally preserve _customWorkerCount so that a re-initialized pool
    // reuses the caller's configured worker count.
  }

  /// Called by a [_WorkerHandle] after it finishes executing a task.
  ///
  /// Attempts to immediately assign the next pending task to [worker]. If the
  /// queue is empty the worker is returned to [_idleWorkers].
  static int _generation = 0;

  static void _onWorkerIdle(_WorkerHandle worker, int generation) {
    if (generation != _generation || !_allWorkers.contains(worker)) return;
    while (_pendingQueue.isNotEmpty) {
      final task = _pendingQueue.removeFirst();
      worker
          .execute(task.computation, _onWorkerIdle)
          .then(task.completer.complete, onError: task.completer.completeError);
      return;
    }
    _idleWorkers.addLast(worker);
  }

  /// The number of tasks currently waiting for a free worker.
  ///
  /// Exposed for testing only.
  @visibleForTesting
  static int get pendingTaskCount => _pendingQueue.length;

  /// The number of worker isolates that are currently idle (not executing any
  /// task).
  ///
  /// Exposed for testing only.
  @visibleForTesting
  static int get idleWorkerCount => _idleWorkers.length;
}

/// A handle to a single long-lived worker [Isolate].
///
/// Each handle owns one isolate and communicates with it over a private
/// [SendPort]/[ReceivePort] channel. Work is submitted via [execute], and the
/// isolate is terminated by calling [dispose].
///
/// [_WorkerHandle] instances are created exclusively by the static factory
/// [spawn] and are managed by [IsarWorkerPool].
class _WorkerHandle {
  /// Creates a handle that wraps [_isolate] and communicates via [_sendPort].
  _WorkerHandle(this._isolate, this._sendPort);

  /// The underlying Dart [Isolate].
  final Isolate _isolate;

  /// The [SendPort] used to send computation messages to the worker isolate.
  final SendPort _sendPort;

  /// Spawns a new worker isolate with the given [debugName] and returns a
  /// [_WorkerHandle] connected to it.
  ///
  /// The isolate runs [_workerEntry] and signals readiness by sending back its
  /// own [SendPort] on [receivePort].
  ///
  /// The spawned isolate is configured with `errorsAreFatal: false` so that
  /// uncaught errors in the isolate do not kill the entire process; errors are
  /// instead forwarded as [_WorkerError] objects through the task response
  /// channel.
  static Future<_WorkerHandle> spawn(String debugName) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerEntry,
      receivePort.sendPort,
      debugName: debugName,
      errorsAreFatal: false,
    );
    final sendPort = await receivePort.first as SendPort;
    receivePort.close();
    return _WorkerHandle(isolate, sendPort);
  }

  /// Sends [computation] to the worker isolate and returns a [Future] that
  /// resolves with the result once the isolate replies.
  ///
  /// A single-use [ReceivePort] is opened for each task so that responses are
  /// isolated and never cross-wired.
  ///
  /// After the response is received (whether successful or an error), the
  /// response port is closed and [onIdle] is invoked so the pool can schedule
  /// the next task.
  ///
  /// - If the isolate replies with a [_WorkerError] the original error and
  ///   stack trace are re-thrown in the calling isolate via
  ///   [Error.throwWithStackTrace].
  /// - Otherwise the reply is cast to [T] and returned.
  Future<T> execute<T>(
    IsarWorkerComputation<T> computation,
    void Function(_WorkerHandle) onIdle,
  ) async {
    final responsePort = ReceivePort();
    try {
      _sendPort.send([computation, responsePort.sendPort]);
      final response = await responsePort.first;
      if (response is _WorkerError) {
        Error.throwWithStackTrace(response.error, response.stackTrace);
      }
      return response as T;
    } finally {
      responsePort.close();
      onIdle(this);
    }
  }

  /// Terminates the underlying isolate immediately.
  ///
  /// Any pending work assigned to this isolate will not complete. This method
  /// is called by [IsarWorkerPool.dispose].
  void dispose() => _isolate.kill();
}

/// The entry point function executed inside each worker isolate.
///
/// Sends its own [SendPort] back to the pool via [mainSendPort] to establish
/// bidirectional communication, then listens for incoming
/// `[IsarWorkerComputation, SendPort]` messages.
///
/// For each message:
/// - The computation is awaited.
/// - On success the return value is sent back on the provided reply port.
/// - On failure a [_WorkerError] wrapping the error and its stack trace is
///   sent instead, so the error can be faithfully re-thrown in the main
///   isolate.
void _workerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is! List || message.length != 2) return;

    final computation = message[0] as IsarWorkerComputation<dynamic>;
    final replyPort = message[1] as SendPort;

    try {
      replyPort.send(await computation());
    } on Object catch (e, st) {
      try {
        replyPort.send(_WorkerError(e, st));
      } on Object catch (_) {
        replyPort.send(
          _WorkerError(
            ArgumentError('Task failed with unsendable error: $e'),
            StackTrace.empty,
          ),
        );
      }
    }
  });
}

/// A simple value object used to tunnel errors and their stack traces across
/// isolate boundaries.
///
/// Because [Isolate] message passing only supports a limited set of types,
/// errors cannot be sent directly. Instead, the worker wraps them in a
/// [_WorkerError] and sends that; the receiving side unwraps it and
/// re-throws with [Error.throwWithStackTrace].
class _WorkerError {
  /// Creates a [_WorkerError] capturing [error] and its associated
  /// [stackTrace].
  _WorkerError(this.error, this.stackTrace);

  /// The original error object thrown by the computation.
  final Object error;

  /// The stack trace captured at the throw site inside the worker isolate.
  final StackTrace stackTrace;
}
