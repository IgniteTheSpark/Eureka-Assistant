import '../../render/render_spec.dart';
import 'package:flutter/foundation.dart';

@immutable
class CardDisplayConfig {
  CardDisplayConfig({
    required String primaryFieldId,
    Iterable<String> secondaryFieldIds = const [],
  }) : primaryFieldId = primaryFieldId.trim(),
       secondaryFieldIds = List.unmodifiable(
         _normalizeSecondary(primaryFieldId, secondaryFieldIds),
       ) {
    if (this.primaryFieldId.isEmpty) {
      throw ArgumentError.value(primaryFieldId, 'primaryFieldId');
    }
  }

  factory CardDisplayConfig.fromRenderSpec(Map<String, dynamic> source) {
    final canonical = source['card_display'];
    if (canonical is Map) {
      final primary = canonical['primary_field_id']?.toString().trim() ?? '';
      if (primary.isNotEmpty) {
        return CardDisplayConfig(
          primaryFieldId: primary,
          secondaryFieldIds:
              (canonical['secondary_field_ids'] as List? ?? const []).map(
                (value) => value.toString(),
              ),
        );
      }
    }
    final primary = source['primary_field']?.toString().trim() ?? '';
    if (primary.isEmpty) {
      throw const FormatException('render_spec requires a primary field');
    }
    return CardDisplayConfig(
      primaryFieldId: primary,
      secondaryFieldIds: [
        if (source['secondary_field'] != null)
          source['secondary_field'].toString(),
        for (final meta
            in (source['meta_fields'] as List? ?? const []).whereType<Map>())
          if (meta['field'] != null) meta['field'].toString(),
      ],
    );
  }

  final String primaryFieldId;
  final List<String> secondaryFieldIds;

  Map<String, dynamic> applyToRenderSpec(Map<String, dynamic> source) {
    final output = Map<String, dynamic>.from(source);
    final formats = _fieldFormats(source);
    output['card_display'] = {
      'primary_field_id': primaryFieldId,
      'secondary_field_ids': List<String>.from(secondaryFieldIds),
    };
    output['primary_field'] = primaryFieldId;
    _writeFormat(output, 'primary_format', formats[primaryFieldId]);

    if (secondaryFieldIds.isEmpty) {
      output.remove('secondary_field');
      output.remove('secondary_format');
    } else {
      final first = secondaryFieldIds.first;
      output['secondary_field'] = first;
      _writeFormat(output, 'secondary_format', formats[first]);
    }
    output['meta_fields'] = [
      for (final field in secondaryFieldIds.skip(1))
        {
          'field': field,
          if (formats[field] case final format?) 'format': format,
        },
    ];
    return output;
  }

  static List<String> _normalizeSecondary(
    String primaryFieldId,
    Iterable<String> candidates,
  ) {
    final primary = primaryFieldId.trim();
    final normalized = <String>[];
    for (final candidate in candidates) {
      final field = candidate.trim();
      if (field.isEmpty || field == primary || normalized.contains(field)) {
        continue;
      }
      normalized.add(field);
      if (normalized.length == 3) break;
    }
    return normalized;
  }

  static Map<String, String> _fieldFormats(Map<String, dynamic> source) {
    final formats = <String, String>{};

    void collect(dynamic fieldValue, dynamic formatValue) {
      final field = fieldValue?.toString().trim() ?? '';
      final format = formatValue?.toString().trim() ?? '';
      if (field.isNotEmpty && format.isNotEmpty) formats[field] = format;
    }

    collect(source['primary_field'], source['primary_format']);
    collect(source['secondary_field'], source['secondary_format']);
    for (final meta
        in (source['meta_fields'] as List? ?? const []).whereType<Map>()) {
      collect(meta['field'], meta['format']);
    }
    return formats;
  }

  static void _writeFormat(
    Map<String, dynamic> target,
    String key,
    String? format,
  ) {
    if (format == null) {
      target.remove(key);
    } else {
      target[key] = format;
    }
  }
}

@immutable
class AssetCardViewData {
  const AssetCardViewData({
    required this.mark,
    required this.skillLabel,
    required this.primaryValue,
    this.secondaryValues = const [],
    this.timeLabel,
  });

  factory AssetCardViewData.fromPayload({
    required Map<String, dynamic> payload,
    required CardDisplayConfig display,
    required RenderSpec? spec,
    required String skillLabel,
    String? timeLabel,
  }) {
    String formatted(String field) =>
        applyFormat(payload[field], spec?.formatForField(field)).trim();

    final primary = formatted(display.primaryFieldId);
    final normalizedSkillLabel = skillLabel.trim();
    final icon = spec?.icon.trim();
    final normalizedTime = timeLabel?.trim();
    return AssetCardViewData(
      mark: icon == null || icon.isEmpty ? '•' : icon,
      skillLabel: normalizedSkillLabel,
      primaryValue: primary.isEmpty ? normalizedSkillLabel : primary,
      secondaryValues: List.unmodifiable([
        for (final field in display.secondaryFieldIds)
          if (formatted(field) case final value when value.isNotEmpty) value,
      ]),
      timeLabel: normalizedTime == null || normalizedTime.isEmpty
          ? null
          : normalizedTime,
    );
  }

  final String mark;
  final String skillLabel;
  final String primaryValue;
  final List<String> secondaryValues;
  final String? timeLabel;
}
