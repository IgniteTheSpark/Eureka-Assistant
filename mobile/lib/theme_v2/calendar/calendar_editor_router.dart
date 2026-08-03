import 'package:flutter/material.dart';

import '../../pages/create_asset.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/theme_v2_asset_edit_page.dart';
import 'calendar_manual_record_picker.dart';

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
