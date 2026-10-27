import 'dart:async';

Future<T> runWithTransactionWriteLock<T>(Future<T> Function() operation) async {
  final previous = _tail;
  final release = Completer<void>();
  _tail = release.future;
  await previous;
  try {
    return await operation();
  } finally {
    release.complete();
  }
}

Future<void> _tail = Future<void>.value();
