import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<T> runWithTransactionWriteLock<T>(Future<T> Function() operation) async {
  T? result;
  Object? operationError;
  StackTrace? operationStack;
  var operationFailed = false;
  JSAny? callback(web.Lock? _) {
    return Future<T>.sync(operation)
        .then<JSAny?>(
          (value) {
            result = value;
            return null;
          },
          onError: (Object error, StackTrace stackTrace) {
            // Do not reject the JS promise produced by `toJS`: converting that
            // rejection back with `toDart` replaces the original exception
            // with a generic "Dart exception thrown from converted Future".
            // Let the lock request resolve, then rethrow the original Dart
            // error on this side of the interop boundary.
            operationFailed = true;
            operationError = error;
            operationStack = stackTrace;
            return null;
          },
        )
        .toJS;
  }

  await web.window.navigator.locks
      .request('accountable-google-sheets-write', callback.toJS)
      .toDart;
  if (operationFailed) {
    Error.throwWithStackTrace(operationError!, operationStack!);
  }
  return result as T;
}
