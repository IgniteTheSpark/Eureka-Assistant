/// Process-wide holder for the current auth bearer token, so low-level code
/// (ApiClient, the SSE client) can attach `Authorization` without DI. Set only
/// by AuthController. [onUnauthorized] fires when a request 401s *while a token
/// was present* (expired/invalid) so the app can bounce back to login.
class AuthStore {
  static String? token;
  static void Function()? onUnauthorized;
}
