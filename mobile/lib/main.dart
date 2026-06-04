import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_events.dart';
import 'app_shell.dart';
import 'auth/auth_controller.dart';
import 'data_revision.dart';
import 'pages/login_page.dart';
import 'pages/session_detail_page.dart';
import 'theme/app_theme.dart';
import 'theme/eureka_colors.dart';
import 'theme/theme_controller.dart';
import 'widgets/listening_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // START_THEME=light|dark lets a build boot into a theme for screenshot parity
  // (the runtime toggle can't be driven headless).
  const startTheme = String.fromEnvironment('START_THEME');
  if (startTheme == 'light') themeModeNotifier.value = ThemeMode.light;
  if (startTheme == 'dark') themeModeNotifier.value = ThemeMode.dark;
  // Resolve the persisted login token before the first frame; the gate shows
  // login vs. app shell once loaded. (AppEvents/SSE need the token, so they
  // start only once authed — see _AuthGate.)
  AuthController.instance.load();
  runApp(const ProviderScope(child: EurekaApp()));
}

class EurekaApp extends StatelessWidget {
  const EurekaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Eureka',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          // General refresh: returning to any screen (pop / sheet close) re-fetches.
          navigatorObservers: [DataRefreshObserver()],
          theme: buildEurekaTheme(EurekaColors.light),
          darkTheme: buildEurekaTheme(EurekaColors.dark),
          themeMode: mode,
          // The app is phone-shaped (iOS target). On a wide desktop window,
          // clamp content to a phone width centered on a dark gutter so cards,
          // sheets and layouts read at their designed size everywhere.
          builder: (context, child) {
            final bg = (mode == ThemeMode.light ? EurekaColors.light : EurekaColors.dark).bg;
            return ColoredBox(
              color: mode == ThemeMode.light
                  ? const Color(0xFFE7E4DC)
                  : const Color(0xFF05070D),
              child: Center(
                child: ClipRect(
                  child: ColoredBox(
                    color: bg,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      // Stack so the global listening overlay covers ALL routes
                      // (driven by the hardware SSE `listening` event).
                      child: Stack(
                        children: [
                          child ?? const SizedBox.shrink(),
                          ValueListenableBuilder<bool>(
                            valueListenable: listeningNotifier,
                            builder: (_, on, child) => on
                                ? const Positioned.fill(child: GlobalListeningOverlay())
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          home: const _AuthGate(),
        );
      },
    );
  }
}

/// Gates the app behind login. Shows a loading screen until the persisted token
/// is resolved, then either the login page or the app shell. Starts the SSE
/// bridge only once authed (the stream requires the bearer token).
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  static const _startSession = String.fromEnvironment('START_SESSION');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthController.instance,
      builder: (context, _) {
        final auth = AuthController.instance;
        if (!auth.loaded) {
          return const ColoredBox(
            color: Colors.transparent,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!auth.isAuthed) return const LoginPage();
        // Authed: open the hardware/notifications SSE bridge (idempotent).
        AppEvents.instance.start();
        return _startSession.isEmpty
            ? const AppShell()
            : SessionDetailPage(sessionId: _startSession, title: '会话详情');
      },
    );
  }
}
