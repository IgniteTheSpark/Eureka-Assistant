import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../pages/create_asset.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/theme_v2_asset_edit_page.dart';
import 'calendar_manual_record_picker.dart';

typedef CalendarSkillEditorOpener =
    Future<void> Function(
      BuildContext context,
      CalendarSkillOption option,
      DateTime effectiveDate,
    );

Widget calendarEditorPageForSkill(
  CalendarSkillOption option,
  DateTime effectiveDate,
) {
  switch (option.kind) {
    case CalendarSkillKind.event:
      return EventForm(presetDate: effectiveDate, coreRecordsOnly: true);
    case CalendarSkillKind.contact:
      final definition = SkillDef(
        option.name,
        option.displayName,
        option.icon,
        option.accentColor,
        option.payloadSchema,
      );
      return ThemeV2AssetEditPage(
        reference: const AssetEntityRef(
          kind: AssetEntityKind.asset,
          id: 'new:contact',
        ),
        initialValues: const {},
        mode: AssetEditMode.create,
        skillName: option.name,
        userSkillId: option.userSkillId,
        spec: renderSpecForSkill(definition),
        displayName: option.displayName,
        presetDate: effectiveDate,
      );
    case CalendarSkillKind.asset:
      final definition = SkillDef(
        option.name,
        option.displayName,
        option.icon,
        option.accentColor,
        option.payloadSchema,
      );
      return ThemeV2AssetEditPage(
        reference: AssetEntityRef(
          kind: AssetEntityKind.asset,
          id: 'new:${option.name}',
        ),
        initialValues: const {},
        mode: AssetEditMode.create,
        skillName: option.name,
        userSkillId: option.userSkillId,
        spec: renderSpecForSkill(definition),
        displayName: option.displayName,
        presetDate: effectiveDate,
      );
  }
}

Future<void> openCalendarSkillEditor(
  BuildContext context,
  CalendarSkillOption option,
  DateTime effectiveDate,
) async {
  await Navigator.of(context).push<dynamic>(
    MaterialPageRoute<dynamic>(
      builder: (_) => calendarEditorPageForSkill(option, effectiveDate),
    ),
  );
}

Future<void> openCalendarManualRecordFlow(
  BuildContext context, {
  DateTime? effectiveDate,
  CalendarSkillLoader? loader,
  CalendarSkillEditorOpener? openEditor,
}) async {
  ApiClient? ownedApi;
  final effectiveLoader =
      loader ??
      () {
        ownedApi ??= ApiClient();
        return fetchCalendarSkillCatalog(ownedApi!);
      };
  final day = effectiveDate ?? DateTime.now();
  try {
    final option = await showCalendarManualRecordPicker(
      context,
      effectiveDate: day,
      loader: effectiveLoader,
    );
    if (option != null && context.mounted) {
      await (openEditor ?? openCalendarSkillEditor)(context, option, day);
    }
  } finally {
    ownedApi?.close();
  }
}
