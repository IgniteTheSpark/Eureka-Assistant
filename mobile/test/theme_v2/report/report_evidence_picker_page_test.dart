import 'dart:async';

import 'package:eureka/theme_v2/report/report_evidence_picker_page.dart';
import 'package:eureka/theme_v2/report/report_plan_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'full-screen picker wraps type filters and reviews selected assets',
    (tester) async {
      List<EvidenceReferenceView>? result;
      final calls = <String>[];
      Future<ReportEvidenceOptionPage> loader({
        String query = '',
        String type = 'all',
        String? skill,
        String? cursor,
      }) async {
        calls.add('$query|$type|${skill ?? ''}|${cursor ?? ''}');
        return const ReportEvidenceOptionPage(
          items: [
            ReportEvidenceOption(
              reference: EvidenceReferenceView(kind: 'asset', id: 'dance-1'),
              title: 'Urban 编舞',
              subtitle: '网球中心 · 48',
              typeLabel: '跳舞记录',
              filterId: 'dance',
              filterLabel: '跳舞记录',
              icon: '💃',
            ),
          ],
          filters: [
            {'id': 'all', 'label': '全部'},
            {'id': 'dance', 'label': '跳舞'},
            {'id': 'running', 'label': '跑步'},
            {'id': 'water', 'label': '喝水'},
            {'id': 'expense', 'label': '消费'},
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showReportEvidencePickerSheet(
                  context,
                  loadPage: loader,
                  initialSkillId: 'dance',
                  initialSelected: const [
                    EvidenceReferenceView(kind: 'asset', id: 'dance-1'),
                  ],
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(calls.first, '|asset|dance|');
      expect(find.text('Urban 编舞'), findsOneWidget);
      expect(find.text('网球中心 · 48'), findsOneWidget);
      expect(find.text('跳舞记录 · 网球中心 · 48'), findsNothing);
      expect(
        find.byKey(const ValueKey('report-evidence-filter-wrap')),
        findsOneWidget,
      );
      expect(find.text('已选择 1 项'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('完成 1'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('report-evidence-selected-review')),
      );
      await tester.pumpAndSettle();
      expect(find.text('已选资产'), findsOneWidget);
      expect(find.text('Urban 编舞'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey('report-evidence-review-remove-asset:dance-1'),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('report-evidence-review-done')),
      );
      await tester.pumpAndSettle();
      expect(find.text('已选择 0 项'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('report-evidence-confirm')));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
    },
  );

  testWidgets('picker searches filters and returns typed selected references', (
    tester,
  ) async {
    final calls = <String>[];
    List<EvidenceReferenceView>? result;
    Future<ReportEvidenceOptionPage> loader({
      String query = '',
      String type = 'all',
      String? skill,
      String? cursor,
    }) async {
      calls.add('$query|$type|${skill ?? ''}|${cursor ?? ''}');
      return const ReportEvidenceOptionPage(
        items: [
          ReportEvidenceOption(
            reference: EvidenceReferenceView(kind: 'event', id: 'event-1'),
            title: '球队建设讨论',
            typeLabel: '日程',
            filterId: 'event',
            filterLabel: '日程',
            icon: '📅',
          ),
          ReportEvidenceOption(
            reference: EvidenceReferenceView(kind: 'contact', id: 'contact-1'),
            title: 'Kevin',
            typeLabel: '联系人',
            filterId: 'contact',
            filterLabel: '联系人',
            icon: '👤',
          ),
          ReportEvidenceOption(
            reference: EvidenceReferenceView(kind: 'asset', id: 'asset-1'),
            title: '周末长跑',
            typeLabel: '跑步训练',
            filterId: 'skill-running',
            filterLabel: '跑步训练',
            icon: '🏃',
          ),
        ],
        filters: [
          {'id': 'all', 'label': '全部'},
          {'id': 'event', 'label': '日程'},
          {'id': 'contact', 'label': '联系人'},
          {'id': 'skill-running', 'label': '跑步训练'},
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await Navigator.of(context)
                  .push<List<EvidenceReferenceView>>(
                    MaterialPageRoute(
                      builder: (_) => ReportEvidencePickerPage(
                        loadPage: loader,
                        initialSelected: const [
                          EvidenceReferenceView(
                            kind: 'contact',
                            id: 'contact-1',
                          ),
                        ],
                      ),
                    ),
                  );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('日程'), findsWidgets);
    expect(find.text('联系人'), findsWidgets);
    expect(find.text('跑步训练'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('report-evidence-search')),
      'Kevin',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(calls.last, 'Kevin|all||');

    await tester.tap(
      find.byKey(const ValueKey('report-evidence-filter-skill-running')),
    );
    await tester.pump();
    expect(calls.last, 'Kevin|asset|skill-running|');

    await tester.tap(find.byKey(const ValueKey('evidence-event:event-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-evidence-confirm')));
    await tester.pumpAndSettle();

    expect(result, const [
      EvidenceReferenceView(kind: 'contact', id: 'contact-1'),
      EvidenceReferenceView(kind: 'event', id: 'event-1'),
    ]);
  });

  testWidgets('cancelling picker preserves the caller state', (tester) async {
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<List<EvidenceReferenceView>>(
                    MaterialPageRoute(
                      builder: (_) => ReportEvidencePickerPage(
                        loadPage:
                            ({query = '', type = 'all', skill, cursor}) async =>
                                const ReportEvidenceOptionPage(
                                  items: [],
                                  filters: [],
                                ),
                      ),
                    ),
                  );
              returned = result == null;
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-evidence-cancel')));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
  });

  testWidgets('a stale search response cannot replace the latest results', (
    tester,
  ) async {
    final requests = <Completer<ReportEvidenceOptionPage>>[];
    Future<ReportEvidenceOptionPage> loader({
      String query = '',
      String type = 'all',
      String? skill,
      String? cursor,
    }) {
      final request = Completer<ReportEvidenceOptionPage>();
      requests.add(request);
      return request.future;
    }

    await tester.pumpWidget(
      MaterialApp(home: ReportEvidencePickerPage(loadPage: loader)),
    );
    expect(requests, hasLength(1));

    await tester.enterText(
      find.byKey(const ValueKey('report-evidence-search')),
      'latest',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(requests, hasLength(2));

    requests[1].complete(_evidencePage(id: 'new', title: '最新结果'));
    await tester.pump();
    await tester.pump();
    expect(find.text('最新结果'), findsOneWidget);

    requests[0].complete(_evidencePage(id: 'old', title: '过期结果'));
    await tester.pump();
    await tester.pump();
    expect(find.text('最新结果'), findsOneWidget);
    expect(find.text('过期结果'), findsNothing);
  });

  testWidgets('load more admits only one request for the current cursor', (
    tester,
  ) async {
    final loadMore = Completer<ReportEvidenceOptionPage>();
    var calls = 0;
    Future<ReportEvidenceOptionPage> loader({
      String query = '',
      String type = 'all',
      String? skill,
      String? cursor,
    }) {
      calls += 1;
      if (cursor == null) {
        return Future.value(
          _evidencePage(id: 'first', title: '第一页', nextCursor: 'cursor-2'),
        );
      }
      return loadMore.future;
    }

    await tester.pumpWidget(
      MaterialApp(home: ReportEvidencePickerPage(loadPage: loader)),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('report-evidence-load-more'));
    await tester.tap(button);
    await tester.tap(button);
    expect(calls, 2);

    loadMore.complete(_evidencePage(id: 'second', title: '第二页'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);
  });
}

ReportEvidenceOptionPage _evidencePage({
  required String id,
  required String title,
  String? nextCursor,
}) => ReportEvidenceOptionPage(
  items: [
    ReportEvidenceOption(
      reference: EvidenceReferenceView(kind: 'asset', id: id),
      title: title,
      typeLabel: '记录',
      filterId: 'all',
      filterLabel: '全部',
      icon: '•',
    ),
  ],
  filters: const [
    {'id': 'all', 'label': '全部'},
  ],
  nextCursor: nextCursor,
);
