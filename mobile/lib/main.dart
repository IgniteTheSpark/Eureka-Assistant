import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'app_events.dart';
import 'app_shell.dart';
import 'auth/auth_controller.dart';
import 'ble_flash/ble_flash_manager.dart';
import 'ble_flash/ble_flash_overlay.dart';
import 'ble_flash/flash_file_workflow.dart';
import 'ring/ring_capture_service.dart';
import 'ring/ring_connection.dart';
import 'data_revision.dart';
import 'device/device_controller.dart';
import 'pages/login_page.dart';
import 'pages/pet_spawn_page.dart';
import 'pet/floating_mascot.dart';
import 'pet/pet_controller.dart';
import 'pet/reka_notifications.dart';
import 'pages/session_detail_page.dart';
import 'render/sprite_factory.dart';
import 'theme/app_theme.dart';
import 'theme/eureka_colors.dart';
import 'theme/theme_controller.dart';
import 'widgets/listening_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  WidgetsBinding.instance.addObserver(_FlashFileLifecycleObserver());
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

class _FlashFileLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FlashFileWorkflow.instance.scanOfflineIfConnected();
    }
  }
}

class EurekaApp extends StatelessWidget {
  const EurekaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'UReka',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          // General refresh: returning to any screen (pop / sheet close) re-fetches.
          // shellRouteObserver lets the shell reset the calendar to 流·今天 when a
          // pushed page is popped back to it.
          navigatorObservers: [DataRefreshObserver(), shellRouteObserver],
          theme: buildEurekaTheme(EurekaColors.light),
          darkTheme: buildEurekaTheme(EurekaColors.dark),
          themeMode: mode,
          // The app is phone-shaped (iOS target). On a wide desktop window,
          // clamp content to a phone width centered on a dark gutter so cards,
          // sheets and layouts read at their designed size everywhere.
          builder: (context, child) {
            final bg =
                (mode == ThemeMode.light
                        ? EurekaColors.light
                        : EurekaColors.dark)
                    .bg;
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
                          // §9.4 sprite-factory host — a 1×1 hidden engine WebView mounted
                          // app-wide so pixel-exact sprite previews (pet board milestones,
                          // the full-screen 换装 page's cells) work regardless of which
                          // route is on top (an offstage board host wouldn't render).
                          const Positioned(
                            left: -50,
                            top: -50,
                            width: 1,
                            height: 1,
                            child: SpriteFactoryHost(),
                          ),
                          // §9.2 全局浮动球球 REKA — above every route (navigates via
                          // navigatorKey). Sits below the hardware listening overlay.
                          const Positioned.fill(child: FloatingMascot()),
                          ValueListenableBuilder<bool>(
                            valueListenable: listeningNotifier,
                            builder: (_, on, child) => on
                                ? const Positioned.fill(
                                    child: GlobalListeningOverlay(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                BleFlashManager.instance.isFlashing,
                            builder: (_, on, child) => on
                                ? const Positioned.fill(
                                    child: BleFlashOverlay(),
                                  )
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
        // §C: restore the 14-day notification history so the REKA feed isn't
        // empty on relaunch (server is the source of truth; SSE adds live ones).
        unawaited(RekaNotifications.instance.loadFromServer());
        BleFlashManager.instance.start();
        unawaited(FlashFileWorkflow.instance.start(auth.userId!));
        // 戒指实时录音 → 闪念(里程碑2)。幂等;仅在戒指连接后双击才生效。
        startRingCapture(ApiClient());
        RingConnection.instance.ensureStarted(); // 全局戒指连接态(头部图标用)
        return _startSession.isEmpty
            ? KeyedSubtree(
                key: ValueKey(auth.sessionEpoch),
                child: const _PostAuthGate(),
              )
            : SessionDetailPage(sessionId: _startSession, title: '会话详情');
      },
    );
  }
}

/// §9.2.2 首屏三级 gating — chooses 孵化 onboarding vs the app shell once the pet
/// has loaded. Tier ① here: `!spawned`(从没孵化的全新用户)→ 全屏孵化 onboarding,
/// 不是晨报、不是 shell。Tiers ②/③(晨报 vs 直接进 app)由 shell 的
/// `maybeShowMorningBriefing` 接手(只在已孵化时跑)。
class _PostAuthGate extends StatefulWidget {
  const _PostAuthGate();

  @override
  State<_PostAuthGate> createState() => _PostAuthGateState();
}

class _PostAuthGateState extends State<_PostAuthGate> {
  final _pet = PetController.instance;
  // Latched the first time the pet resolves: did THIS user need onboarding?
  // null = undecided. Deciding ONCE (not re-reading `spawned` every rebuild) is
  // essential — onboarding's own spawn() flips spawned→true mid-flow, and a
  // live re-read would swap the onboarding page out for the shell the instant
  // the egg hatched (before 现身/起名/首捕 played out).
  bool? _needsOnboarding;
  // Set when onboarding's arc finishes (onDone) → swap to the shell.
  bool _onboardingDone = false;

  @override
  void initState() {
    super.initState();
    // load 球球 (provisions the egg + arms completion-drop toasts). refresh()
    // notifies SYNCHRONOUSLY (loading flag) — calling inside build marks the
    // floating ball dirty mid-build ("setState() during build"); defer a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pet.ensureLoaded();
      DeviceController.instance.refreshBoundDevice();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pet,
      builder: (context, _) {
        if (!_pet.loaded) {
          // Pet still resolving — hold on a neutral background (no spinner flash;
          // the fetch is ~一次往返). Painting the shell here then yanking it would
          // flash for new users.
          return const ColoredBox(color: Colors.transparent);
        }
        // Decide once, the first time the pet is loaded. Onboarding is complete
        // only after the first capture produces a real card; spawned only means
        // the egg has hatched. A null pet means /api/pet failed — don't drag a
        // returning user into 孵化 over a transient blip; fall through to shell.
        _needsOnboarding ??= _pet.pet != null && !_pet.onboardingCompleted;
        if (_needsOnboarding! && !_onboardingDone) {
          return PetSpawnPage(
            onDone: () => setState(() => _onboardingDone = true),
          );
        }
        return const AppShell();
      },
    );
  }
}
