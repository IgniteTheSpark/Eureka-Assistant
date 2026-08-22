import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/reka_terminal.dart';
import 'package:eureka/theme_v2/capture/reka_terminal_models.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live transcript stays at four lines and follows its tail', (
    tester,
  ) async {
    var model = _model(
      phase: RekaTerminalPhase.listening,
      transcript: List.generate(8, (index) => '第 ${index + 1} 行内容').join('\n'),
    );
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return RekaTerminal(model: model, onClose: () {});
          },
        ),
      ),
    );
    await tester.pump();

    final viewport = find.byKey(RekaTerminal.transcriptViewportKey);
    final initialHeight = tester.getSize(viewport).height;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)),
    );
    expect(initialHeight, closeTo(17 * 1.35 * 4, 1));
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);

    update(() {
      model = _model(
        phase: RekaTerminalPhase.listening,
        transcript: '${model.transcript}\n最后一行',
      );
    });
    await tester.pump();
    await tester.pump();

    expect(tester.getSize(viewport).height, initialHeight);
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
  });

  testWidgets('hardware terminal uses phase copy without transcript content', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      _host(
        RekaTerminal(
          model: _model(
            source: CaptureActivitySource.ring,
            phase: RekaTerminalPhase.transcribing,
            statusLabel: '正在转写',
            queuedCount: 2,
          ),
          onClose: () => closed += 1,
        ),
      ),
    );

    expect(find.text('REKA://RING'), findsOneWidget);
    expect(find.text('正在转写'), findsOneWidget);
    expect(find.text('另有 2 条'), findsOneWidget);
    expect(find.byKey(RekaTerminal.transcriptViewportKey), findsNothing);
    expect(
      tester.getSize(find.byKey(RekaTerminal.closeKey)).shortestSide,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(RekaTerminal.closeKey));
    expect(closed, 1);
  });

  testWidgets('completed terminal opens detail only when identifiers exist', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        RekaTerminal(
          model: _model(
            phase: RekaTerminalPhase.done,
            statusLabel: '已整理 · 3 项',
            canOpenDetail: true,
          ),
          onClose: () {},
          onOpenDetail: () => opened += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(RekaTerminal.bodyKey));
    expect(opened, 1);
  });

  testWidgets('large text keeps actions reachable without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RekaTerminal(
          model: _model(
            phase: RekaTerminalPhase.listening,
            transcript: List.filled(6, '较长的实时语音内容').join('\n'),
          ),
          onClose: () {},
        ),
        textScaler: const TextScaler.linear(1.5),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(RekaTerminal.closeKey), findsOneWidget);
  });
}

RekaTerminalModel _model({
  CaptureActivitySource source = CaptureActivitySource.app,
  required RekaTerminalPhase phase,
  String statusLabel = '聆听中',
  String transcript = '',
  int queuedCount = 0,
  bool canOpenDetail = false,
}) => RekaTerminalModel(
  identity: 'client:test',
  aliases: const {'client:test'},
  source: source,
  phase: phase,
  statusLabel: statusLabel,
  transcript: transcript,
  queuedCount: queuedCount,
  canOpenDetail: canOpenDetail,
);

Widget _host(Widget child, {TextScaler textScaler = TextScaler.noScaling}) =>
    MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(body: Center(child: child)),
      ),
    );
