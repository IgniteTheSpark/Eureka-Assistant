List<int> normalizeReminderOffsets(
  Object? raw, {
  bool missingUsesDefault = true,
}) {
  if (raw == null) return missingUsesDefault ? const [15] : const [];
  if (raw is! Iterable) return missingUsesDefault ? const [15] : const [];
  final values = raw.whereType<int>().where((value) => value >= 0).toSet();
  return values.toList(growable: false)..sort();
}

String formatReminderSummary(Iterable<int> offsets) {
  final normalized = normalizeReminderOffsets(
    offsets.toList(growable: false),
    missingUsesDefault: false,
  );
  if (normalized.isEmpty) return '不提醒';
  return normalized.map(_offsetLabel).join('、');
}

String reminderOffsetLabel(int minutes) => _offsetLabel(minutes);

String _offsetLabel(int minutes) {
  if (minutes == 0) return '开始时';
  if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
  if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
  return '提前 $minutes 分钟';
}
