import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'history_policy.dart';

Uri _current = Uri.parse('/');
var _skips = 0;

/// Keeps browser Back aligned with the screens the user actually opened.
///
/// Episode changes must not become extra Back steps, and a second copy of the
/// same URL must not swallow a Back press. Registered in the capture phase so
/// it sees the page being left before Flutter applies the new route.
void installWebHistoryGuard({
  required Listenable listenable,
  required String Function() currentUri,
}) {
  _current = Uri.parse(currentUri());
  listenable.addListener(() {
    _current = Uri.parse(currentUri());
  });
  web.window.addEventListener('popstate', ((web.Event _) => _onPop()).toJS, true.toJS);
}

void _onPop() {
  final landed = Uri.parse(web.window.location.href);
  final left = _current;
  if (_skips < 12 &&
      shouldSkipHistoryEntry(left, landed) &&
      platformCanHistoryBack()) {
    _skips++;
    platformHistoryBack();
    return;
  }
  _skips = 0;
}

/// True when Back stays inside this visit. The engine stores that depth on the
/// current history entry; the first entry is 0, so Back would leave the site.
bool platformCanHistoryBack() {
  final raw = web.window.history.state;
  if (raw == null || !raw.typeofEquals('object')) return false;
  final serial = (raw as JSObject).getProperty<JSAny?>('serialCount'.toJS);
  if (serial == null || serial.isUndefinedOrNull || !serial.typeofEquals('number')) {
    return false;
  }
  return (serial as JSNumber).toDartDouble > 0;
}

void platformHistoryBack() {
  web.window.history.back();
}
