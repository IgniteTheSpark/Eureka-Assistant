import 'package:eureka/theme_v2/report/report_evidence_picker_page.dart';
import 'package:eureka/theme_v2/report/report_plan_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
