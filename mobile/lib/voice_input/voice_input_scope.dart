import 'package:flutter/widgets.dart';

import 'voice_input_controller.dart';
import 'voice_input_service.dart';

final class VoiceInputScope extends InheritedWidget {
  VoiceInputScope({
    super.key,
    required super.child,
    VoiceInputServiceClient? service,
    VoiceInputLease? lease,
  }) : service = service ?? sharedService,
       lease = lease ?? VoiceInputLease.shared;

  static final VoiceInputServiceClient sharedService = VoiceInputService();

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

  @override
  bool updateShouldNotify(VoiceInputScope oldWidget) {
    return service != oldWidget.service || lease != oldWidget.lease;
  }
}
