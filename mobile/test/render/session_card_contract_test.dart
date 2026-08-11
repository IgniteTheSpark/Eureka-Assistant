import 'package:eureka/render/render_spec.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/session/session_card_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

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

  test('custom session card falls back to the skill display name', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'skills': [
              {
                'name': 'water_intake_log',
                'display_name': '喝水记录',
                'payload_schema': {
                  'amount_ml': {'type': 'number', 'label': '饮水量'},
                },
                'render_spec': {'icon': '💧', 'primary_field': 'amount_ml'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);
    final specs = await fetchRenderSpecs(api);
    final custom = card(
      kind: 'asset',
      id: 'water-1',
      skill: 'water_intake_log',
      entity: const {'asset_id': 'water-1', 'payload': <String, dynamic>{}},
    );

    expect(resolveSkillCardData(custom, specs).title, '喝水记录');
    expect(resolveSkillCardData(custom, const {}).title, '自定义记录');
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

  test(
    'timezone-less canonical event timestamps are treated as legacy UTC',
    () {
      final event = card(
        kind: 'event',
        id: 'event-legacy-utc',
        entity: {
          'event_id': 'event-legacy-utc',
          'title': '周会',
          'start_at': '2026-08-11T08:00:00',
          'end_at': '2026-08-11T10:00:00',
        },
      );

      expect(resolveSkillCardData(event, const {}).subtitle, '16:00–18:00');
    },
  );

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
