import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<T> runWithTransactionWriteLock<T>(Future<T> Function() operation) async {
  T? result;
  JSAny? callback(web.Lock? _) {
    return operation().then<JSAny?>((value) {
      result = value;
      return null;
    }).toJS;
  }

  await web.window.navigator.locks
      .request('accountable-google-sheets-write', callback.toJS)
      .toDart;
  return result as T;
}
