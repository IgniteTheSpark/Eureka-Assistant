import 'package:flutter/material.dart';

import '../../pages/create_asset.dart';
import '../../render/asset_detail_sheet.dart';
import 'calendar_manual_record_picker.dart';

Widget calendarEditorPageForSkill(
  CalendarSkillOption option,
  DateTime effectiveDate,
) {
  switch (option.kind) {
    case CalendarSkillKind.event:
      return EventForm(presetDate: effectiveDate);
    case CalendarSkillKind.contact:
      return const ContactForm();
    case CalendarSkillKind.asset:
      final definition = SkillDef(
        option.name,
        option.displayName,
        option.icon,
        option.accentColor,
        option.payloadSchema,
      );
      return AssetEditPage(
        payload: const {},
        cardType: option.name,
        title: '',
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
