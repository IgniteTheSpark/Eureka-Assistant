import 'package:flutter/widgets.dart';

/// Legacy aggregate refresh counter. Navigation and lifecycle refreshes use
/// this signal so established consumers continue to re-fetch as before.
final dataRevision = ValueNotifier<int>(0);

/// Confirmed-write counter. Theme V2 Library surfaces use this narrower signal
/// so navigating back to them does not invalidate already loaded content.
final dataMutationRevision = ValueNotifier<int>(0);

/// Requests a broad refresh without claiming that local data was mutated.
void requestDataRefresh() => dataRevision.value++;

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
