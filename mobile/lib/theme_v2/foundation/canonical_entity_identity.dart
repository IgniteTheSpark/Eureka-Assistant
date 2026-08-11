const canonicalTodoAssetIcon = '📋';
const canonicalEventAssetIcon = '📅';
const canonicalContactAssetIcon = '👤';
const canonicalNotesAssetIcon = '✍️';
const canonicalExpenseAssetIcon = '💳';

const canonicalEntityIcons = <String, String>{
  'todo': canonicalTodoAssetIcon,
  'event': canonicalEventAssetIcon,
  'contact': canonicalContactAssetIcon,
  'notes': canonicalNotesAssetIcon,
  'expense': canonicalExpenseAssetIcon,
};

const canonicalEntityLabels = <String, String>{
  'todo': '待办',
  'event': '日程',
  'contact': '联系人',
  'notes': '随记',
  'expense': '消费',
};

String canonicalEntityKey(String key) => switch (key.trim().toLowerCase()) {
  'calendar' => 'event',
  'note' || 'idea' || 'misc' || 'other' => 'notes',
  final normalized => normalized,
};

String resolveEntityLabel(
  String key, {
  String? configuredLabel,
  String fallback = '资产',
}) {
  final pinned = canonicalEntityLabels[canonicalEntityKey(key)];
  if (pinned != null) return pinned;
  final configured = configuredLabel?.trim() ?? '';
  if (configured.isNotEmpty) return configured;
  return fallback;
}

String resolveEntityIcon(
  String key, {
  String? configuredIcon,
  String fallback = '•',
}) {
  final pinned = canonicalEntityIcons[canonicalEntityKey(key)];
  if (pinned != null) return pinned;
  final configured = configuredIcon?.trim() ?? '';
  return configured.isEmpty ? fallback : configured;
}
