import 'package:flutter/foundation.dart';

enum LibraryContainerType { todo, notes, event, contact, report, custom }

@immutable
class LibraryContainerSummary {
  const LibraryContainerSummary({
    required this.id,
    required this.label,
    required this.mark,
    required this.type,
    required this.totalCount,
    required this.isSystem,
    this.activityLabel,
    this.userSkillId,
  });

  final String id;
  final String label;
  final String mark;
  final LibraryContainerType type;
  final int totalCount;
  final bool isSystem;
  final String? activityLabel;
  final String? userSkillId;
}

@immutable
class LibraryRecentAsset {
  const LibraryRecentAsset({
    required this.id,
    required this.skillName,
    required this.skillLabel,
    required this.mark,
    required this.primaryValue,
    required this.createdAt,
    required this.detailCard,
  });

  final String id;
  final String skillName;
  final String skillLabel;
  final String mark;
  final String primaryValue;
  final DateTime createdAt;
  final Map<String, dynamic> detailCard;
}

@immutable
class LibrarySourceFailure {
  const LibrarySourceFailure({required this.source, required this.isOffline});

  final String source;
  final bool isOffline;
}

@immutable
class LibraryOverview {
  LibraryOverview({
    List<LibraryContainerSummary> systemContainers = const [],
    List<LibraryContainerSummary> customContainers = const [],
    List<LibraryRecentAsset> recentAssets = const [],
    this.totalAssetCount = 0,
    List<LibrarySourceFailure> failedSources = const [],
  }) : systemContainers = List.unmodifiable(systemContainers),
       customContainers = List.unmodifiable(customContainers),
       recentAssets = List.unmodifiable(recentAssets),
       failedSources = List.unmodifiable(failedSources);

  final List<LibraryContainerSummary> systemContainers;
  final List<LibraryContainerSummary> customContainers;
  final List<LibraryRecentAsset> recentAssets;
  final int totalAssetCount;
  final List<LibrarySourceFailure> failedSources;

  List<LibraryContainerSummary> get containers =>
      List.unmodifiable([...systemContainers, ...customContainers]);

  int get containerCount => systemContainers.length + customContainers.length;
  int get customContainerCount => customContainers.length;
}

class LibraryLoadFailure implements Exception {
  const LibraryLoadFailure(this.message, {this.isOffline = false});

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}
