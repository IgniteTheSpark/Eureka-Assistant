import 'package:flutter/widgets.dart';

/// Global mutation counter. Any write (create/edit/delete) bumps it; list
/// surfaces listen and re-fetch so a change refreshes the lists behind it (the
/// Flutter analog of the web's SWR cache invalidation).
final dataRevision = ValueNotifier<int>(0);

void bumpData() => dataRevision.value++;

/// Refreshes data whenever the user returns to a screen — i.e. any route is
/// popped (chat / detail page) or any bottom sheet / dialog closes. This is the
/// general safety net: even if a specific create/edit path forgets to call
/// [bumpData], coming back to a list always shows fresh data. Registered on the
/// root navigator (see main.dart `navigatorObservers`).
class DataRefreshObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    bumpData();
  }
}
