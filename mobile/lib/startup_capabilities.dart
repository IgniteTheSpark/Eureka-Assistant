import 'package:flutter/foundation.dart';

/// Compile-time product-service policy applied after authentication.
///
/// Theme V2 retains the mature hardware capture and notification transports,
/// while services that do not exist in the isolated V2 backend stay dormant.
@immutable
class StartupCapabilities {
  const StartupCapabilities.themeV2()
    : hardwareCapture = true,
      notifications = true,
      pet = false,
      nudges = false,
      offers = false,
      legacyTimeline = false,
      legacyContacts = false,
      legacySkills = false;

  const StartupCapabilities.legacy()
    : hardwareCapture = true,
      notifications = true,
      pet = true,
      nudges = true,
      offers = true,
      legacyTimeline = true,
      legacyContacts = true,
      legacySkills = true;

  final bool hardwareCapture;
  final bool notifications;
  final bool pet;
  final bool nudges;
  final bool offers;
  final bool legacyTimeline;
  final bool legacyContacts;
  final bool legacySkills;
}
