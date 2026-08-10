import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ring_capture_task.dart';

abstract interface class RingCaptureStore {
  Future<List<RingCaptureTask>> load(String userId);

  Future<void> upsert(String userId, RingCaptureTask task);

  Future<void> remove(String userId, String taskId);
}

class SharedPreferencesRingCaptureStore implements RingCaptureStore {
  SharedPreferencesRingCaptureStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'ring_capture_tasks_v1:';

  final Future<SharedPreferences> Function() _preferences;
  final Map<String, Map<String, RingCaptureTask>> _tasksByUser = {};

  @override
  Future<List<RingCaptureTask>> load(String userId) async {
    final normalizedUserId = _normalizeUserId(userId);
    final tasks = await _loadMap(normalizedUserId);
    return List<RingCaptureTask>.unmodifiable(tasks.values);
  }

  @override
  Future<void> upsert(String userId, RingCaptureTask task) async {
    final normalizedUserId = _normalizeUserId(userId);
    if (task.userId.trim() != normalizedUserId) {
      throw ArgumentError.value(
        task.userId,
        'task.userId',
        'must match the authenticated user scope',
      );
    }
    final current = await _loadMap(normalizedUserId);
    final updated = Map<String, RingCaptureTask>.from(current)
      ..[task.id] = task;
    await _persist(normalizedUserId, current: current, updated: updated);
  }

  @override
  Future<void> remove(String userId, String taskId) async {
    final normalizedUserId = _normalizeUserId(userId);
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      throw ArgumentError.value(taskId, 'taskId', 'must not be empty');
    }
    final current = await _loadMap(normalizedUserId);
    final updated = Map<String, RingCaptureTask>.from(current)
      ..remove(normalizedTaskId);
    await _persist(normalizedUserId, current: current, updated: updated);
  }

  Future<Map<String, RingCaptureTask>> _loadMap(String userId) async {
    final cached = _tasksByUser[userId];
    if (cached != null) return cached;

    final preferences = await _preferences();
    final raw = preferences.getString('$_keyPrefix$userId');
    final loaded = <String, RingCaptureTask>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map) continue;
            try {
              final task = RingCaptureTask.fromJson(
                Map<String, dynamic>.from(entry),
              );
              if (task.userId == userId) loaded[task.id] = task;
            } on Object {
              // A malformed entry must not prevent other recoverable tasks from
              // loading. The persisted JSON remains untouched until a write.
            }
          }
        }
      } on Object {
        // Preserve malformed persisted JSON until the next successful write.
      }
    }
    _tasksByUser[userId] = loaded;
    return loaded;
  }

  Future<void> _persist(
    String userId, {
    required Map<String, RingCaptureTask> current,
    required Map<String, RingCaptureTask> updated,
  }) async {
    _tasksByUser[userId] = updated;
    try {
      final preferences = await _preferences();
      final ok = await preferences.setString(
        '$_keyPrefix$userId',
        jsonEncode(updated.values.map((task) => task.toJson()).toList()),
      );
      if (!ok) throw StateError('failed to persist ring capture tasks');
    } on Object {
      _tasksByUser[userId] = current;
      rethrow;
    }
  }
}

String _normalizeUserId(String userId) {
  final normalized = userId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must not be empty');
  }
  return normalized;
}
