import 'package:flutter/foundation.dart';

enum RekaInboxSource { pending, recent, offer }

@immutable
class RekaInboxItem {
  const RekaInboxItem({
    required this.id,
    required this.type,
    required this.kind,
    required this.title,
    required this.body,
    required this.ref,
    required this.cta,
    required this.status,
    required this.createdAt,
    required this.sources,
  });

  final String id;
  final String type;
  final String kind;
  final String title;
  final String body;
  final String ref;
  final String cta;
  final String status;
  final DateTime createdAt;
  final Set<RekaInboxSource> sources;

  bool get isUnread => status == 'pending' || status == 'delivered';
  bool get isTerminal =>
      status == 'acted' ||
      status == 'dismissed' ||
      status == 'expired' ||
      status == 'ignored';
  bool get isOffer => sources.contains(RekaInboxSource.offer);

  factory RekaInboxItem.fromJson(
    Map<String, dynamic> json, {
    required RekaInboxSource source,
  }) {
    final id = json['id']?.toString().trim() ?? '';
    final title = json['text']?.toString().trim() ?? '';
    if (id.isEmpty) throw const FormatException('Inbox item id is required');
    if (title.isEmpty) {
      throw const FormatException('Inbox item text is required');
    }
    final createdAt = DateTime.tryParse(
      json['created_at']?.toString() ?? '',
    )?.toLocal();
    return RekaInboxItem(
      id: id,
      type: json['type']?.toString() ?? 'nudge',
      kind: json['kind']?.toString() ?? '',
      title: title,
      body: json['body']?.toString() ?? '',
      ref: json['ref']?.toString() ?? '',
      cta: json['cta']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      sources: Set.unmodifiable({source}),
    );
  }

  RekaInboxItem copyWith({
    String? type,
    String? kind,
    String? title,
    String? body,
    String? ref,
    String? cta,
    String? status,
    DateTime? createdAt,
    Set<RekaInboxSource>? sources,
  }) {
    return RekaInboxItem(
      id: id,
      type: type ?? this.type,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      body: body ?? this.body,
      ref: ref ?? this.ref,
      cta: cta ?? this.cta,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      sources: Set.unmodifiable(sources ?? this.sources),
    );
  }

  RekaInboxItem mergedWith(RekaInboxItem other) {
    assert(id == other.id);
    final preferred = _statusPriority(other.status) > _statusPriority(status)
        ? other
        : this;
    final fallback = identical(preferred, this) ? other : this;
    return preferred.copyWith(
      type: preferred.type.isEmpty ? fallback.type : preferred.type,
      kind: preferred.kind.isEmpty ? fallback.kind : preferred.kind,
      title: preferred.title.isEmpty ? fallback.title : preferred.title,
      body: preferred.body.isEmpty ? fallback.body : preferred.body,
      ref: preferred.ref.isEmpty ? fallback.ref : preferred.ref,
      cta: preferred.cta.isEmpty ? fallback.cta : preferred.cta,
      createdAt: createdAt.isAfter(other.createdAt)
          ? createdAt
          : other.createdAt,
      sources: {...sources, ...other.sources},
    );
  }

  static int _statusPriority(String status) => switch (status) {
    'acted' || 'dismissed' || 'expired' || 'ignored' => 3,
    'seen' => 2,
    'pending' || 'delivered' => 1,
    _ => 0,
  };
}
