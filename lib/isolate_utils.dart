import 'dart:async';
import 'dart:isolate';

class IsolateUtils {
  static Future<List<R>> runIsolate<T, R>({
    required List<T> data,
    required int numberOfIsolates,
    required FutureOr<void> Function(List<T>, SendPort) isolateEntryPoint,
    required void Function(double, int, int, Duration) progressCallback,
    required void Function(List<R>) completionCallback,
  }) async {
    final receivePort = ReceivePort();
    final startTime = DateTime.now();
    final int totalItems = data.length;
    final int batchSize = (totalItems / numberOfIsolates).ceil();
    final List<R> results = [];
    int processedItems = 0;

    for (var i = 0; i < numberOfIsolates; i++) {
      final start = i * batchSize;
      final end = (i + 1) * batchSize > totalItems ? totalItems : (i + 1) * batchSize;
      final batch = data.sublist(start, end);

      if (batch.isEmpty) continue;

      Isolate.spawn(
        _isolateWrapper<T, R>,
        _IsolateParams<T, R>(batch, receivePort.sendPort, isolateEntryPoint),
      );
    }

    await for (var message in receivePort) {
      if (message is _ProgressMessage) {
        final elapsed = DateTime.now().difference(startTime);
        final estimatedTotalTime = elapsed * (1 / message.progress);
        final remainingTime = estimatedTotalTime - elapsed;
        progressCallback(message.progress, message.processed, totalItems, remainingTime);
      } else if (message is List<R>) {
        results.addAll(message);
        processedItems += message.length;
        if (processedItems == totalItems) {
          completionCallback(results);
          receivePort.close();
          return results;
        }
      }
    }
    return results;
  }

  static void _isolateWrapper<T, R>(_IsolateParams<T, R> params) async {
    params.isolateEntryPoint(params.data, params.sendPort);
  }
}

class _IsolateParams<T, R> {
  final List<T> data;
  final SendPort sendPort;
  final FutureOr<void> Function(List<T>, SendPort) isolateEntryPoint;

  _IsolateParams(this.data, this.sendPort, this.isolateEntryPoint);
}

class _ProgressMessage {
  final double progress;
  final int processed;

  _ProgressMessage(this.progress, this.processed);
}
