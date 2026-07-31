import 'package:eureka/theme_v2/home/home_controller.dart';
import 'package:eureka/theme_v2/home/home_layer_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current Home exposes Today only', () {
    expect(HomeLayerState.current.primary, HomeSurface.today);
    expect(HomeLayerState.current.secondary, isNull);
    expect(HomeLayerState.current.hasSecondary, isFalse);
  });

  test('controller toggles Agenda without creating a second layer', () {
    final controller = ThemeV2HomeController();
    addTearDown(controller.dispose);

    expect(controller.presentation, HomePresentation.today);
    controller.openAgenda();
    expect(controller.presentation, HomePresentation.agenda);
    expect(controller.layers.secondary, isNull);
    controller.closeAgenda();
    expect(controller.presentation, HomePresentation.today);
  });
}
