import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/library_controller.dart';
import 'package:eureka/theme_v2/library/library_hub.dart';
import 'package:eureka/theme_v2/library/library_models.dart';
import 'package:eureka/theme_v2/library/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('library hub always exposes the user custom skills', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = LibraryController(
      repository: _Repository(),
      pinnedStore: _PinnedStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: LibraryHub(
            controller: controller,
            onOpenContainer: (_) {},
            onOpenContainerIndex: () {},
            onOpenAllContainers: () {},
            onConfigurePinned: () {},
            onCreateSkill: () {},
          ),
        ),
      ),
    );

    expect(find.text('我的技能'), findsOneWidget);
    expect(find.text('每日喝水量'), findsOneWidget);
    expect(find.text('跑步训练记录'), findsOneWidget);
  });
}

class _Repository implements LibraryRepository {
  @override
  Future<LibraryOverview> loadOverview() async => LibraryOverview(
    systemContainers: const [
      LibraryContainerSummary(
        id: 'todo',
        label: '待办',
        mark: '📋',
        type: LibraryContainerType.todo,
        totalCount: 1,
        isSystem: true,
      ),
    ],
    customContainers: const [
      LibraryContainerSummary(
        id: 'daily_water_intake',
        label: '每日喝水量',
        mark: '💧',
        type: LibraryContainerType.custom,
        totalCount: 5,
        isSystem: false,
      ),
      LibraryContainerSummary(
        id: 'running_training_log',
        label: '跑步训练记录',
        mark: '🏃',
        type: LibraryContainerType.custom,
        totalCount: 1,
        isSystem: false,
      ),
    ],
  );
}

class _PinnedStore implements LibraryPinnedStore {
  @override
  Future<List<String>?> load() async => const ['todo'];

  @override
  Future<void> save(List<String> ids) async {}
}
