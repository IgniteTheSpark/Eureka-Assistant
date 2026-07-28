import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/asset/asset_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'required schema fields block save and unknown types stay editable',
    (tester) async {
      Map<String, dynamic>? saved;
      final draft = AssetEditorDraft(
        payload: const {'mystery': 'kept'},
        spec: const RenderSpec(
          cardLayout: 'horizontal',
          icon: '•',
          accentColor: 'gray',
          schemaFields: ['title', 'mystery'],
          fieldLabels: {'title': '标题', 'mystery': '未知字段'},
          fieldTypes: {'title': 'string', 'mystery': 'vector3'},
          requiredFields: {'title'},
        ),
      );
      addTearDown(draft.dispose);
      expect(draft.isDirty, isFalse);

      await tester.pumpWidget(
        _host(
          ThemeV2AssetEditor(
            draft: draft,
            onSave: (payload) async => saved = payload,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('asset-editor-mystery')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
      await tester.pump();
      expect(find.text('请填写标题'), findsOneWidget);
      expect(saved, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('asset-editor-title')),
        '新标题',
      );
      expect(draft.isDirty, isTrue);
      await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
      await tester.pump();

      expect(saved?['title'], '新标题');
      expect(saved?['mystery'], 'kept');
    },
  );

  testWidgets('editor clears keyboard inset and supports large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = AssetEditorDraft(
      payload: const {'body': '长文本'},
      spec: const RenderSpec(
        cardLayout: 'horizontal',
        icon: '✍️',
        accentColor: 'amber',
        schemaFields: ['body'],
        fieldLabels: {'body': '正文'},
        longFields: {'body'},
      ),
    );
    addTearDown(draft.dispose);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetEditor(draft: draft, onSave: (_) async {}),
        mediaQueryData: const MediaQueryData(
          size: Size(360, 720),
          viewInsets: EdgeInsets.only(bottom: 280),
          textScaler: TextScaler.linear(1.5),
        ),
      ),
    );

    final padding = tester.widget<AnimatedPadding>(
      find.byKey(const ValueKey('asset-editor-keyboard-padding')),
    );
    expect((padding.padding as EdgeInsets).bottom, greaterThanOrEqualTo(280));
    expect(find.byKey(const ValueKey('asset-editor-body')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child, {MediaQueryData? mediaQueryData}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Builder(
    builder: (context) => MediaQuery(
      data: mediaQueryData ?? MediaQuery.of(context),
      child: Material(child: child),
    ),
  ),
);
