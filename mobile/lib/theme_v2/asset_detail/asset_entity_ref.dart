import 'package:flutter/foundation.dart';

enum AssetEntityKind { asset, event, contact }

@immutable
class AssetEntityRef {
  const AssetEntityRef({required this.kind, required this.id});

  final AssetEntityKind kind;
  final String id;

  String get pathSegment => kind.name;

  @override
  bool operator ==(Object other) =>
      other is AssetEntityRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}
