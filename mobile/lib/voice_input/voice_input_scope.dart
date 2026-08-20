import 'dart:async';

import 'package:flutter/widgets.dart';

import 'voice_input_coordinator.dart';
import 'voice_input_models.dart';
import 'voice_input_service.dart';

typedef VoiceInputSessionIdentity = Object? Function();

final class VoiceInputHost extends StatefulWidget {
  const VoiceInputHost({
    super.key,
    required this.child,
    this.service,
    this.sessionListenable,
    this.sessionIdentity,
  });

  final Widget child;
  final VoiceInputServiceClient? service;
  final Listenable? sessionListenable;
  final VoiceInputSessionIdentity? sessionIdentity;

  @override
  State<VoiceInputHost> createState() => _VoiceInputHostState();
}

final class _VoiceInputHostState extends State<VoiceInputHost>
    with WidgetsBindingObserver {
  late VoiceInputServiceClient _service;
  late VoiceInputCoordinator _coordinator;
  Object? _sessionIdentity;

  @override
  void initState() {
    super.initState();
    _createCoordinator();
    _sessionIdentity = widget.sessionIdentity?.call();
    widget.sessionListenable?.addListener(_handleSessionChange);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(VoiceInputHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionListenable != widget.sessionListenable) {
      oldWidget.sessionListenable?.removeListener(_handleSessionChange);
      widget.sessionListenable?.addListener(_handleSessionChange);
    }
    if (!identical(oldWidget.service, widget.service)) {
      final oldCoordinator = _coordinator;
      _createCoordinator();
      unawaited(oldCoordinator.dispose());
    }
    _sessionIdentity = widget.sessionIdentity?.call();
  }

  void _createCoordinator() {
    _service = widget.service ?? VoiceInputService();
    _coordinator = VoiceInputCoordinator(service: _service);
  }

  void _handleSessionChange() {
    final next = widget.sessionIdentity?.call();
    if (next == _sessionIdentity) return;
    _sessionIdentity = next;
    unawaited(_coordinator.cancelActive(VoiceInputCancelReason.authentication));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    unawaited(_coordinator.cancelActive(VoiceInputCancelReason.appLifecycle));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.sessionListenable?.removeListener(_handleSessionChange);
    unawaited(_coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VoiceInputScope(coordinator: _coordinator, child: widget.child);
  }
}

final class VoiceInputScope extends InheritedWidget {
  const VoiceInputScope({
    super.key,
    required super.child,
    required this.coordinator,
  });

  // Widget tests that mount an individual surface without the real App root
  // receive a fail-closed coordinator. Production always uses VoiceInputHost.
  @visibleForTesting
  static final VoiceInputCoordinator testFallbackCoordinator =
      VoiceInputCoordinator(service: const _MissingVoiceInputHostService());

  final VoiceInputCoordinator coordinator;

  static VoiceInputScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<VoiceInputScope>();
  }

  static VoiceInputScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'VoiceInputScope is missing above this context');
    return scope!;
  }

  static VoiceInputCoordinator coordinatorOf(BuildContext context) {
    return maybeOf(context)?.coordinator ?? testFallbackCoordinator;
  }

  @override
  bool updateShouldNotify(VoiceInputScope oldWidget) {
    return coordinator != oldWidget.coordinator;
  }
}

final class _MissingVoiceInputHostService implements VoiceInputServiceClient {
  const _MissingVoiceInputHostService();

  @override
  Future<VoiceInputSessionHandle> start(VoiceInputMode mode) {
    throw const VoiceInputException(VoiceInputErrorCode.serviceUnavailable);
  }
}
