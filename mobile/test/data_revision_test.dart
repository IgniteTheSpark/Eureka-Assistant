import 'package:eureka/app_shell.dart';
import 'package:eureka/data_revision.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation refresh does not publish a mutation revision', () {
    final dataBefore = dataRevision.value;
    final mutationBefore = dataMutationRevision.value;
    addTearDown(() {
      dataRevision.value = dataBefore;
      dataMutationRevision.value = mutationBefore;
    });

    requestDataRefresh();

    expect(dataRevision.value, dataBefore + 1);
    expect(dataMutationRevision.value, mutationBefore);
  });

  test('confirmed mutation publishes both revisions', () {
    final dataBefore = dataRevision.value;
    final mutationBefore = dataMutationRevision.value;
    addTearDown(() {
      dataRevision.value = dataBefore;
      dataMutationRevision.value = mutationBefore;
    });

    bumpData();

    expect(dataRevision.value, dataBefore + 1);
    expect(dataMutationRevision.value, mutationBefore + 1);
  });

  testWidgets('DataRefreshObserver route pop requests only a legacy refresh', (
    tester,
  ) async {
    final dataBefore = dataRevision.value;
    final mutationBefore = dataMutationRevision.value;
    addTearDown(() {
      dataRevision.value = dataBefore;
      dataMutationRevision.value = mutationBefore;
    });
    final observer = DataRefreshObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('close'),
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    expect(dataRevision.value, dataBefore + 1);
    expect(dataMutationRevision.value, mutationBefore);
  });

  testWidgets('legacy shell resume requests only a legacy refresh', (
    tester,
  ) async {
    final dataBefore = dataRevision.value;
    final mutationBefore = dataMutationRevision.value;
    addTearDown(() {
      dataRevision.value = dataBefore;
      dataMutationRevision.value = mutationBefore;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const AppShell(),
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(dataRevision.value, dataBefore + 1);
    expect(dataMutationRevision.value, mutationBefore);
  });

  testWidgets('Theme V2 shell resume requests only a legacy refresh', (
    tester,
  ) async {
    final dataBefore = dataRevision.value;
    final mutationBefore = dataMutationRevision.value;
    addTearDown(() {
      dataRevision.value = dataBefore;
      dataMutationRevision.value = mutationBefore;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          pages: const [
            ThemeV2PageScaffold(body: SizedBox.shrink()),
            ThemeV2PageScaffold(body: SizedBox.shrink()),
            ThemeV2PageScaffold(body: SizedBox.shrink()),
          ],
        ),
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(dataRevision.value, dataBefore + 1);
    expect(dataMutationRevision.value, mutationBefore);
  });
}
