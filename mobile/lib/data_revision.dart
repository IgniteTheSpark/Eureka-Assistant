import 'dart:async';

import 'package:flutter/widgets.dart';

/// Legacy aggregate refresh counter. Navigation and lifecycle refreshes use
/// this signal so established consumers continue to re-fetch as before.
final dataRevision = ValueNotifier<int>(0);

/// Confirmed-write counter. Theme V2 Library surfaces use this narrower signal
/// so navigating back to them does not invalidate already loaded content.
final dataMutationRevision = ValueNotifier<int>(0);

/// Reconciliation-only counter for cached Theme V2 Library surfaces. Resume
/// and a successfully re-established SSE subscription use this signal to
/// catch up writes that may have completed while the client was disconnected,
/// without claiming that the triggering lifecycle/network event is a write.
final dataLibraryCatchUpRevision = ValueNotifier<int>(0);

bool _libraryCatchUpScheduled = false;

/// Requests a broad refresh without claiming that local data was mutated.
void requestDataRefresh() => dataRevision.value++;

/// Coalesces catch-up requests raised in the same event-loop turn so resume and
/// reconnect hooks cannot fan out a duplicate Library refresh storm.
void requestLibraryCatchUp() {
  if (_libraryCatchUpScheduled) return;
  _libraryCatchUpScheduled = true;
  scheduleMicrotask(() {
    _libraryCatchUpScheduled = false;
    dataLibraryCatchUpRevision.value++;
  });
}

/// Publishes a confirmed create, edit, or delete to both legacy and mutation
/// consumers.
void bumpData() {
  dataRevision.value++;
  dataMutationRevision.value++;
}

/// Refreshes data whenever the user returns to a screen — i.e. any route is
/// popped (chat / detail page) or any bottom sheet / dialog closes. This is the
/// general safety net: even if a specific create/edit path forgets to call
/// [bumpData], coming back to a list always shows fresh data. Registered on the
/// root navigator (see main.dart `navigatorObservers`).
class DataRefreshObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    requestDataRefresh();
  }
}
