import 'package:eureka/render/render_spec.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/session/session_card_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> card({
    required String kind,
    required String id,
    String? skill,
    required Map<String, dynamic> entity,
  }) => {
    'entity_kind': kind,
    'entity_id': id,
    'skill_machine_name': ?skill,
    'entity': entity,
    'source': {
      'session_id': 'session-1',
      'input_turn_id': 'turn-1',
      'kind': 'chat',
    },
  };

  test('canonical todo renders local readable deadline and asset route', () {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 18);
    final todo = card(
      kind: 'asset',
      id: 'todo-1',
      skill: 'todo',
      entity: {
        'asset_id': 'todo-1',
        'domain': '工作',
        'payload': {
          'title': '提交方案',
          'due_date': tomorrow.toIso8601String(),
          'status': 'pending',
        },
      },
    );

    expect(isCanonicalSessionEntityCard(todo), isTrue);
    final data = resolveSkillCardData(todo, {'todo': synthesizeSpec('todo')});
    expect(data.title, '提交方案');
    expect(data.subtitle, '明天 18:00');
    expect(data.icon, '📋');
    expect(
      skillCardEntityRef(todo),
      const AssetEntityRef(kind: AssetEntityKind.asset, id: 'todo-1'),
    );
  });

  test('event and contact use their raw entities and canonical routes', () {
    final event = card(
      kind: 'event',
      id: 'event-1',
      entity: {
        'event_id': 'event-1',
        'title': '设计评审',
        'start_at': '2026-08-09T15:00:00+08:00',
        'end_at': '2026-08-09T16:00:00+08:00',
      },
    );
    final contact = card(
      kind: 'contact',
      id: 'contact-1',
      entity: {'contact_id': 'contact-1', 'name': '冯总', 'company': '远景科技'},
    );

    expect(resolveSkillCardData(event, const {}).subtitle, '15:00–16:00');
    expect(resolveSkillCardData(contact, const {}).title, '冯总');
    expect(
      skillCardEntityRef(event),
      const AssetEntityRef(kind: AssetEntityKind.event, id: 'event-1'),
    );
    expect(
      skillCardEntityRef(contact),
      const AssetEntityRef(kind: AssetEntityKind.contact, id: 'contact-1'),
    );
  });

  test('session shape rejects old and incomplete card protocols', () {
    expect(
      isCanonicalSessionEntityCard({
        'card_type': 'todo',
        'asset_id': 'todo-1',
        'payload': {'title': '旧卡片'},
      }),
      isFalse,
    );
    expect(
      isCanonicalSessionEntityCard(
        card(kind: 'asset', id: 'asset-1', entity: const {'payload': {}}),
      ),
      isFalse,
    );
    expect(
      isCanonicalSessionEntityCard({
        ...card(kind: 'event', id: 'event-1', entity: const {'title': '缺来源'}),
        'source': const {},
      }),
      isFalse,
    );
  });

  test(
    'message filtering preserves only canonical entities and pending action',
    () {
      final entity = card(
        kind: 'contact',
        id: 'contact-1',
        entity: const {'name': 'Alex'},
      );
      final pending = {
        'kind': 'pending_contact',
        'card_type': 'pending_contact',
        'pending_action_id': 'pending-1',
        'candidates': const [
          {'contact_id': 'contact-1', 'name': 'Alex'},
        ],
      };

      expect(
        sessionMessageCards([
          entity,
          pending,
          const {'asset_id': 'old'},
        ]),
        [entity, pending],
      );
    },
  );
}
