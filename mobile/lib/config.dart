/// App-wide configuration.
///
/// The API base URL is compile-time injected so the same code points at local
/// dev or the deployed backend:
///   flutter run    --dart-define=API_BASE=http://localhost:8000
///   flutter build  --dart-define=API_BASE=https://api.ureka.chat
class AppConfig {
  /// Selects the Theme V2 shell at application startup.
  ///
  /// Theme V2 is the product default. The legacy shell is retained only for an
  /// explicit diagnostic build:
  ///   flutter run --dart-define=THEME_V2=false
  static const themeV2 = bool.fromEnvironment('THEME_V2', defaultValue: true);

  /// Enables the reversible Light Today dithered-Reka evaluation surface.
  ///
  /// The environment name stays unchanged for build and rollout compatibility.
  static const todayDotExperiment = bool.fromEnvironment(
    'TODAY_DOT_EXPERIMENT',
    defaultValue: false,
  );

  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://api.ureka.chat',
  );

  static const tencentAsrBase = String.fromEnvironment(
    'TENCENT_ASR_BASE',
    defaultValue: 'https://pre.card.biz',
  );

  /// Hidden by default so end-user debug/demo builds don't expose ring internals.
  /// Enable only when actively debugging ring hardware:
  ///   --dart-define=SHOW_RING_DEBUG=true
  static const showRingDebug = bool.fromEnvironment(
    'SHOW_RING_DEBUG',
    defaultValue: false,
  );
}
