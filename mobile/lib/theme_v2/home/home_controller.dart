import 'package:flutter/foundation.dart';

import 'home_layer_state.dart';

enum HomePresentation { today, agenda }

class ThemeV2HomeController extends ChangeNotifier {
  ThemeV2HomeController({
    this.layers = HomeLayerState.current,
    HomePresentation initialPresentation = HomePresentation.today,
  }) : _presentation = initialPresentation;

  final HomeLayerState layers;
  HomePresentation _presentation;

  HomePresentation get presentation => _presentation;

  void openAgenda() => _setPresentation(HomePresentation.agenda);
  void closeAgenda() => _setPresentation(HomePresentation.today);

  void _setPresentation(HomePresentation value) {
    if (_presentation == value) return;
    _presentation = value;
    notifyListeners();
  }
}
