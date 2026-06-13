import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/flash/flash.dart';
import 'package:eureka/pet/pet_controller.dart';

void main() {
  test('FlashResult parses session metadata and success cards', () {
    final result = FlashResult.fromJson({
      'ok': true,
      'session_id': 'session-1',
      'input_turn_id': 'turn-1',
      'summary': '已记录 1 项内容。',
      'cards': [
        {'card_type': 'todo', 'asset_id': 'asset-1', 'title': '提交报告'},
      ],
    });

    expect(result.ok, isTrue);
    expect(result.sessionId, 'session-1');
    expect(result.inputTurnId, 'turn-1');
    expect(result.cards.single['asset_id'], 'asset-1');
  });

  test('Pet parses onboarding completion independently from spawned', () {
    final pet = Pet.fromJson({
      'spawned': true,
      'onboarding_completed': false,
      'name': 'Reka',
      'seed': 'seed',
      'skin': 'aurora',
      'emblem': 'star',
      'emblem_color': 'gold',
      'equipped': const {},
      'unlocked': const {},
      'milestones': const {},
    });

    expect(pet.spawned, isTrue);
    expect(pet.onboardingCompleted, isFalse);
  });
}
