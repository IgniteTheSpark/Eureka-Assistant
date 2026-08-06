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

String canonicalEntityKey(String key) => switch (key.trim().toLowerCase()) {
  'calendar' => 'event',
  'note' || 'idea' || 'misc' || 'other' => 'notes',
  final normalized => normalized,
};

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
