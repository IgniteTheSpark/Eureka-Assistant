import 'package:eureka/assets/assets.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme_v2/library/asset/asset_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AssetRecordAdapter', () {
    test('custom record derives a shared card from display configuration', () {
      final record = AssetRecordAdapter.custom(
        asset: AssetItem(
          id: 'trip-1',
          skillName: 'travel',
          payload: const {'title': '关西旅行', 'city': '大阪'},
          createdAt: DateTime(2026, 7, 29, 9),
          userSkillId: 'skill-travel',
          sessionId: 'session-1',
          domain: '生活',
        ),
        skillLabel: '旅行',
        renderSpec: const {
          'icon': '✦',
          'primary_field': 'title',
          'secondary_field': 'city',
        },
        payloadSchema: const {
          'title': {'label': '标题', 'type': 'string', 'required': true},
          'city': {'label': '城市', 'type': 'string'},
        },
      );

      expect(record.kind, AssetRecordKind.custom);
      expect(record.card.mark, '✦');
      expect(record.card.primaryValue, '关西旅行');
      expect(record.card.secondaryValues, ['大阪']);
      expect(record.fields.map((field) => field.label), ['标题', '城市']);
      expect(record.userSkillId, 'skill-travel');
      expect(record.sessionId, 'session-1');
      expect(record.domain, '生活');
    });

    test('event and contact adapters normalize typed entities', () {
      final event = AssetRecordAdapter.event(
        entity: const {
          'event_id': 'event-1',
          'title': '设计评审',
          'start_at': '2026-07-29T14:00:00+08:00',
          'end_at': '2026-07-29T15:00:00+08:00',
          'location': '会议室 A',
        },
      );
      final contact = AssetRecordAdapter.contact(
        entity: const {
          'contact_id': 'contact-1',
          'name': '林知夏',
          'company': 'Eureka',
          'title': 'Designer',
        },
      );

      expect(event.kind, AssetRecordKind.event);
      expect(event.card.primaryValue, '设计评审');
      expect(event.card.secondaryValues.single, contains('14:00'));
      expect(event.fields.map((field) => field.id), contains('location'));
      expect(contact.kind, AssetRecordKind.contact);
      expect(contact.card.primaryValue, '林知夏');
      expect(contact.card.secondaryValues, ['Eureka', 'Designer']);
    });

    test('todo adapter recognizes legacy completion and due timestamps', () {
      final record = AssetRecordAdapter.asset(
        asset: AssetItem(
          id: 'todo-1',
          skillName: 'todo',
          payload: const {
            'title': '提交方案',
            'completed': true,
            'due_at': '2026-07-29T18:30:00+08:00',
          },
          createdAt: DateTime(2026, 7, 28),
        ),
        skillLabel: '待办',
        spec: const RenderSpec(
          cardLayout: 'horizontal',
          icon: '✓',
          accentColor: 'neutral',
          primaryField: 'title',
          schemaFields: ['title', 'due_at', 'completed'],
          fieldLabels: {'title': '标题', 'due_at': '截止时间'},
        ),
      );

      expect(record.kind, AssetRecordKind.todo);
      expect(record.completed, isTrue);
      expect(record.dueAt, DateTime.parse('2026-07-29T18:30:00+08:00'));
    });
  });

  group('Todo record classification', () {
    final today = DateTime(2026, 7, 29, 12);

    test('unscheduled records sort after scheduled records', () {
      final records = [
        _todo('open', dueAt: null),
        _todo('evening', dueAt: DateTime(2026, 7, 29, 18)),
        _todo('morning', dueAt: DateTime(2026, 7, 29, 9)),
      ];

      expect(sortTodoRecords(records).map((record) => record.id), [
        'morning',
        'evening',
        'open',
      ]);
    });

    test('filters today completed and unscheduled without overlap errors', () {
      final todayOpen = _todo('today', dueAt: DateTime(2026, 7, 29, 18));
      final done = _todo(
        'done',
        dueAt: DateTime(2026, 7, 28, 18),
        completed: true,
      );
      final open = _todo('open', dueAt: null);

      expect(
        matchesTodoFilter(todayOpen, TodoAssetFilter.today, today),
        isTrue,
      );
      expect(matchesTodoFilter(done, TodoAssetFilter.completed, today), isTrue);
      expect(
        matchesTodoFilter(open, TodoAssetFilter.unscheduled, today),
        isTrue,
      );
      expect(
        matchesTodoFilter(done, TodoAssetFilter.unscheduled, today),
        isFalse,
      );
    });
  });
}

AssetRecordViewModel _todo(
  String id, {
  required DateTime? dueAt,
  bool completed = false,
}) {
  return AssetRecordViewModel(
    id: id,
    containerId: 'todo',
    kind: AssetRecordKind.todo,
    card: const AssetRecordCard(
      mark: '✓',
      skillLabel: '待办',
      primaryValue: '待办',
    ),
    fields: const [],
    payload: const {},
    createdAt: DateTime(2026, 7, 28),
    dueAt: dueAt,
    completed: completed,
  );
}
