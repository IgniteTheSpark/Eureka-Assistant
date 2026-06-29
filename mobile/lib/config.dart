/// App-wide configuration.
///
/// The API base URL is compile-time injected so the same code points at local
/// dev or the deployed backend:
///   flutter run    --dart-define=API_BASE=http://localhost:8000
///   flutter build  --dart-define=API_BASE=https://api.yourdomain.com
class AppConfig {
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:8000',
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
