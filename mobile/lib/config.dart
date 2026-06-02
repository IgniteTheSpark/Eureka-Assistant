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
}
