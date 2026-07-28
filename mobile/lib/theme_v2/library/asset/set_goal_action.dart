import 'package:flutter/material.dart';

import '../../foundation/theme_v2_semantics.dart';
import '../../foundation/theme_v2_theme.dart';

@immutable
class SetGoalIntent {
  const SetGoalIntent._(this.routeName, this.arguments);

  factory SetGoalIntent.forSkill(String userSkillId) =>
      SetGoalIntent._('/theme-v2/goals/new', {'user_skill_id': userSkillId});

  final String routeName;
  final Map<String, String> arguments;
}

@immutable
class SetGoalActionState {
  const SetGoalActionState({required this.userSkillId});

  final String? userSkillId;

  bool get enabled => userSkillId != null && userSkillId!.trim().isNotEmpty;
  String get disabledReason => enabled ? '' : '这个内容没有可关联的 Skill';
  SetGoalIntent? get intent =>
      enabled ? SetGoalIntent.forSkill(userSkillId!) : null;
}

class SetGoalAction extends StatelessWidget {
  const SetGoalAction({super.key, required this.state, required this.onIntent});

  final SetGoalActionState state;
  final ValueChanged<SetGoalIntent> onIntent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Tooltip(
      message: state.disabledReason,
      child: ThemeV2HitTarget(
        child: OutlinedButton.icon(
          onPressed: state.enabled ? () => onIntent(state.intent!) : null,
          icon: Icon(Icons.flag_outlined, color: tokens.accent),
          label: const Text('设定目标'),
        ),
      ),
    );
  }
}
