import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary authoring surfaces adopt the shared voice input field', () {
    final expected = {
      'lib/theme_v2/session/session_composer.dart':
          "ValueKey('session-composer-voice')",
      'lib/theme_v2/report/report_create_sheet.dart':
          "ValueKey('report-create-voice')",
      'lib/theme_v2/report/report_run_page.dart':
          "ValueKey('report-additional-focus-voice')",
      'lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart':
          "ValueKey('skill-description-voice')",
      'lib/flash/flash_sheet.dart': "ValueKey('flash-input-voice')",
    };

    for (final entry in expected.entries) {
      final source = File(entry.key).readAsStringSync();
      expect(source, contains('VoiceInputField('), reason: entry.key);
      expect(source, contains(entry.value), reason: entry.key);
    }
  });

  test('manual Flash no longer uses the platform speech recognizer', () {
    final source = File('lib/flash/flash_sheet.dart').readAsStringSync();
    expect(source, isNot(contains('speech_to_text')));
    expect(source, isNot(contains('SpeechToText')));
    expect(source, isNot(contains('_ListeningOverlay')));
  });
}
