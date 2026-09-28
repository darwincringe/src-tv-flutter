import 'package:flutter/foundation.dart';

/// Native builds have a real navigator stack, so browser history is unused.
void installWebHistoryGuard({
  required Listenable listenable,
  required String Function() currentUri,
}) {}

bool platformCanHistoryBack() => false;

void platformHistoryBack() {}
