import 'dart:async';

import 'package:flutter/widgets.dart';

import 'voice_input_controller.dart';
import 'voice_input_coordinator.dart';
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
    _service = widget.service ?? VoiceInputScope.sharedService;
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
    return VoiceInputScope(
      coordinator: _coordinator,
      service: _service,
      child: widget.child,
    );
  }
}

final class VoiceInputScope extends InheritedWidget {
  VoiceInputScope({
    super.key,
    required super.child,
    VoiceInputCoordinator? coordinator,
    VoiceInputServiceClient? service,
    VoiceInputLease? lease,
  }) : service = service ?? sharedService,
       coordinator =
           coordinator ??
           VoiceInputCoordinator(service: service ?? sharedService),
       lease = lease ?? VoiceInputLease.shared;

  // Transitional compatibility for existing voice adopters. Task 4-6 migrate
  // every surface to [coordinator], after which this static access is removed.
  static final VoiceInputServiceClient sharedService = VoiceInputService();
  static final VoiceInputCoordinator _fallbackCoordinator =
      VoiceInputCoordinator(service: sharedService);

  final VoiceInputCoordinator coordinator;
  final VoiceInputServiceClient service;
  final VoiceInputLease lease;

  static VoiceInputScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<VoiceInputScope>();
  }

  static VoiceInputScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'VoiceInputScope is missing above this context');
    return scope!;
  }

  static VoiceInputCoordinator coordinatorOf(BuildContext context) {
    return maybeOf(context)?.coordinator ?? _fallbackCoordinator;
  }

  @override
  bool updateShouldNotify(VoiceInputScope oldWidget) {
    return coordinator != oldWidget.coordinator ||
        service != oldWidget.service ||
        lease != oldWidget.lease;
  }
}
