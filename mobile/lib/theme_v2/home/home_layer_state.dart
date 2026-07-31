enum HomeSurface { today }

class HomeLayerState {
  const HomeLayerState({
    this.primary = HomeSurface.today,
    this.secondary,
  });

  final HomeSurface primary;
  final HomeSurface? secondary;

  bool get hasSecondary => secondary != null;

  static const current = HomeLayerState();
}
