import 'package:flutter/foundation.dart';

import 'asset_entity_ref.dart';

enum AssetDetailSourceKind { manual, flash, session, report }

@immutable
class AssetDetailField {
  const AssetDetailField({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    required this.long,
    required this.order,
  });

  factory AssetDetailField.fromJson(Map<String, dynamic> json) =>
      AssetDetailField(
        id: _requiredString(json, 'id'),
        label: _requiredString(json, 'label'),
        type: _requiredString(json, 'type'),
        required: json['required'] == true,
        long: json['long'] == true,
        order: (json['order'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String label;
  final String type;
  final bool required;
  final bool long;
  final int order;
}

@immutable
class AssetDetailSkill {
  const AssetDetailSkill({
    required this.id,
    required this.machineName,
    required this.displayName,
    required this.icon,
  });

  factory AssetDetailSkill.fromJson(Map<String, dynamic> json) =>
      AssetDetailSkill(
        id: _optionalString(json['id']),
        machineName: _requiredString(json, 'machine_name'),
        displayName: _requiredString(json, 'display_name'),
        icon: _requiredString(json, 'icon'),
      );

  final String? id;
  final String machineName;
  final String displayName;
  final String icon;
}

@immutable
class AssetDetailDisplay {
  const AssetDetailDisplay({
    required this.primaryFieldId,
    required this.secondaryFieldIds,
  });

  factory AssetDetailDisplay.fromJson(Map<String, dynamic> json) =>
      AssetDetailDisplay(
        primaryFieldId: _requiredString(json, 'primary_field_id'),
        secondaryFieldIds: List.unmodifiable(
          (json['secondary_field_ids'] as List? ?? const [])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty),
        ),
      );

  final String primaryFieldId;
  final List<String> secondaryFieldIds;
}

@immutable
class AssetDetailSource {
  const AssetDetailSource({
    required this.kind,
    required this.label,
    required this.sessionId,
    required this.inputTurnId,
    required this.reportId,
  });

  factory AssetDetailSource.fromJson(Map<String, dynamic> json) =>
      AssetDetailSource(
        kind: switch (_requiredString(json, 'kind')) {
          'manual' => AssetDetailSourceKind.manual,
          'flash' => AssetDetailSourceKind.flash,
          'session' => AssetDetailSourceKind.session,
          'report' => AssetDetailSourceKind.report,
          final value => throw FormatException(
            'unsupported asset detail source kind: $value',
          ),
        },
        label: _requiredString(json, 'label'),
        sessionId: _optionalString(json['session_id']),
        inputTurnId: _optionalString(json['input_turn_id']),
        reportId: _optionalString(json['report_id']),
      );

  final AssetDetailSourceKind kind;
  final String label;
  final String? sessionId;
  final String? inputTurnId;
  final String? reportId;

  bool get canOpen => switch (kind) {
    AssetDetailSourceKind.manual => false,
    AssetDetailSourceKind.report => reportId != null,
    AssetDetailSourceKind.flash ||
    AssetDetailSourceKind.session => sessionId != null && inputTurnId != null,
  };
}

@immutable
class AssetDetailCapabilities {
  const AssetDetailCapabilities({
    required this.editable,
    required this.deletable,
  });

  factory AssetDetailCapabilities.fromJson(Map<String, dynamic> json) =>
      AssetDetailCapabilities(
        editable: json['editable'] == true,
        deletable: json['deletable'] == true,
      );

  final bool editable;
  final bool deletable;
}

@immutable
class AssetDetailModel {
  const AssetDetailModel({
    required this.ref,
    required this.version,
    required this.skill,
    required this.fields,
    required this.values,
    required this.display,
    required this.source,
    required this.capabilities,
  });

  factory AssetDetailModel.fromJson(Map<String, dynamic> json) {
    final entity = _map(json, 'entity');
    final kind = switch (_requiredString(entity, 'kind')) {
      'asset' => AssetEntityKind.asset,
      'event' => AssetEntityKind.event,
      'contact' => AssetEntityKind.contact,
      final value => throw FormatException(
        'unsupported asset detail entity kind: $value',
      ),
    };
    final fields = <AssetDetailField>[
      for (final value in json['fields'] as List? ?? const [])
        AssetDetailField.fromJson((value as Map).cast<String, dynamic>()),
    ]..sort((a, b) => a.order.compareTo(b.order));

    return AssetDetailModel(
      ref: AssetEntityRef(kind: kind, id: _requiredString(entity, 'id')),
      version: _requiredString(entity, 'version'),
      skill: AssetDetailSkill.fromJson(_map(json, 'skill')),
      fields: List.unmodifiable(fields),
      values: Map.unmodifiable(_map(json, 'values')),
      display: AssetDetailDisplay.fromJson(_map(json, 'display')),
      source: AssetDetailSource.fromJson(_map(json, 'source')),
      capabilities: AssetDetailCapabilities.fromJson(
        _map(json, 'capabilities'),
      ),
    );
  }

  final AssetEntityRef ref;
  final String version;
  final AssetDetailSkill skill;
  final List<AssetDetailField> fields;
  final Map<String, dynamic> values;
  final AssetDetailDisplay display;
  final AssetDetailSource source;
  final AssetDetailCapabilities capabilities;
}

Map<String, dynamic> _map(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! Map) throw FormatException('$key must be an object');
  return value.cast<String, dynamic>();
}

String _requiredString(Map<String, dynamic> source, String key) {
  final value = source[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('$key is required');
  return value;
}

String? _optionalString(dynamic value) {
  final string = value?.toString().trim() ?? '';
  return string.isEmpty ? null : string;
}
