import 'package:flutter/foundation.dart';

@immutable
class RingFileRef {
  const RingFileRef({
    required this.name,
    required this.id,
    required this.sizeBytes,
  });

  final String name;
  final List<int> id;
  final int sizeBytes;

  String get identityMaterial => '$name:$sizeBytes:${id.join('-')}';
}

sealed class RingFileEvent {
  const RingFileEvent(this.operationId);

  final String operationId;

  factory RingFileEvent.fromMap(Map<Object?, Object?> raw) {
    final operationId = raw['operationId']?.toString() ?? '';
    return switch (raw['kind']?.toString()) {
      'item' => RingFileItemEvent(
        operationId,
        RingFileRef(
          name: raw['name']?.toString() ?? '',
          id: List<int>.from(raw['id'] as List? ?? const []),
          sizeBytes: (raw['size'] as num?)?.toInt() ?? 0,
        ),
        count: (raw['count'] as num?)?.toInt() ?? 0,
        index: (raw['index'] as num?)?.toInt() ?? 0,
      ),
      'audio' => RingFileAudioEvent(
        operationId,
        Uint8List.fromList(List<int>.from(raw['pcm'] as List? ?? const [])),
      ),
      'done' => RingFileDoneEvent(operationId),
      'deleted' => RingFileDeletedEvent(operationId, raw['ok'] == true),
      'memoryInfo' => RingMemoryInfoEvent(
        operationId,
        Uint8List.fromList(List<int>.from(raw['raw'] as List? ?? const [])),
      ),
      'memory' => RingMemoryStateEvent(
        operationId,
        (raw['state'] as num?)?.toInt() ?? -1,
      ),
      'memoryFull' => RingMemoryFullEvent(
        operationId,
        first: (raw['a'] as num?)?.toInt(),
        second: (raw['b'] as num?)?.toInt(),
        third: (raw['c'] as num?)?.toInt(),
      ),
      'recordingAck' => RingRecordingAckEvent(
        operationId,
        active: raw['active'] == true,
        ok: raw['ok'] == true,
      ),
      'empty' => RingFileEmptyEvent(operationId),
      final kind => RingUnknownFileEvent(
        operationId,
        kind: kind ?? '',
        raw: Map<Object?, Object?>.unmodifiable(raw),
      ),
    };
  }
}

final class RingFileItemEvent extends RingFileEvent {
  const RingFileItemEvent(
    super.operationId,
    this.file, {
    required this.count,
    required this.index,
  });

  final RingFileRef file;
  final int count;
  final int index;
}

final class RingFileAudioEvent extends RingFileEvent {
  const RingFileAudioEvent(super.operationId, this.pcm);

  final Uint8List pcm;
}

final class RingFileDoneEvent extends RingFileEvent {
  const RingFileDoneEvent(super.operationId);
}

final class RingFileDeletedEvent extends RingFileEvent {
  const RingFileDeletedEvent(super.operationId, this.ok);

  final bool ok;
}

final class RingMemoryInfoEvent extends RingFileEvent {
  const RingMemoryInfoEvent(super.operationId, this.raw);

  final Uint8List raw;
}

final class RingMemoryStateEvent extends RingFileEvent {
  const RingMemoryStateEvent(super.operationId, this.state);

  final int state;
}

final class RingMemoryFullEvent extends RingFileEvent {
  const RingMemoryFullEvent(
    super.operationId, {
    required this.first,
    required this.second,
    required this.third,
  });

  final int? first;
  final int? second;
  final int? third;
}

final class RingRecordingAckEvent extends RingFileEvent {
  const RingRecordingAckEvent(
    super.operationId, {
    required this.active,
    required this.ok,
  });

  final bool active;
  final bool ok;
}

final class RingFileEmptyEvent extends RingFileEvent {
  const RingFileEmptyEvent(super.operationId);
}

final class RingUnknownFileEvent extends RingFileEvent {
  const RingUnknownFileEvent(
    super.operationId, {
    required this.kind,
    required this.raw,
  });

  final String kind;
  final Map<Object?, Object?> raw;
}
