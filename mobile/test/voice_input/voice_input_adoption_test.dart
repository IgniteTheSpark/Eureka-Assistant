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

  test('ordinary authoring surfaces never own a voice service or lease', () {
    const sources = [
      'lib/pages/chat_page.dart',
      'lib/pages/session_detail_page.dart',
      'lib/theme_v2/session/theme_v2_session_page.dart',
      'lib/theme_v2/report/report_create_sheet.dart',
      'lib/theme_v2/report/report_run_page.dart',
      'lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart',
      'lib/flash/flash_sheet.dart',
    ];

    for (final path in sources) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('VoiceInputScope.sharedService')),
        reason: path,
      );
      expect(source, isNot(contains('VoiceInputLease')), reason: path);
      expect(source, isNot(contains('VoiceInputService(')), reason: path);
    }
  });

  test('the App root is the only real voice service owner', () {
    final main = File('lib/main.dart').readAsStringSync();
    final scope = File(
      'lib/voice_input/voice_input_scope.dart',
    ).readAsStringSync();
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(main, contains('VoiceInputHost('));
    expect(scope, contains('_service = widget.service ?? VoiceInputService()'));
    expect(scope, contains('VoiceInputCoordinator(service: _service)'));
    expect('VoiceInputService()'.allMatches(production), hasLength(1));
    expect(production, isNot(contains('VoiceInputLease')));
    expect(production, isNot(contains('VoiceInputScope.sharedService')));
    expect(production, isNot(contains('另一个输入框正在使用麦克风')));
  });
}
