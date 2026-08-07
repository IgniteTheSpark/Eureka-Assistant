import 'package:flutter/foundation.dart';

@immutable
class EvidenceReferenceView {
  const EvidenceReferenceView({required this.kind, required this.id});

  final String kind;
  final String id;

  factory EvidenceReferenceView.fromJson(Map<String, dynamic> json) =>
      EvidenceReferenceView(
        kind: json['kind']?.toString() ?? 'asset',
        id: json['id']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'kind': kind, 'id': id};

  String get key => '$kind:$id';

  @override
  bool operator ==(Object other) =>
      other is EvidenceReferenceView && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

@immutable
class ResearchEntityView {
  const ResearchEntityView({
    required this.id,
    required this.kind,
    required this.name,
    this.qualifier,
    this.enabled = true,
  });

  final String id;
  final String kind;
  final String name;
  final String? qualifier;
  final bool enabled;

  factory ResearchEntityView.fromJson(Map<String, dynamic> json) =>
      ResearchEntityView(
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'topic',
        name: json['name']?.toString() ?? '',
        qualifier: json['qualifier']?.toString(),
        enabled: json['enabled'] != false,
      );

  ResearchEntityView copyWith({bool? enabled}) => ResearchEntityView(
    id: id,
    kind: kind,
    name: name,
    qualifier: qualifier,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    if (qualifier != null && qualifier!.isNotEmpty) 'qualifier': qualifier,
    'enabled': enabled,
  };
}

@immutable
class PublicResearchBriefView {
  const PublicResearchBriefView({
    this.entities = const [],
    this.questions = const [],
    this.freshness = 'current',
  });

  final List<ResearchEntityView> entities;
  final List<String> questions;
  final String freshness;

  factory PublicResearchBriefView.fromJson(Map<String, dynamic> json) =>
      PublicResearchBriefView(
        entities: (json['entities'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  ResearchEntityView.fromJson(item.cast<String, dynamic>()),
            )
            .toList(growable: false),
        questions: (json['questions'] as List? ?? const [])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        freshness: json['freshness']?.toString() ?? 'current',
      );

  PublicResearchBriefView copyWith({
    List<ResearchEntityView>? entities,
    List<String>? questions,
    String? freshness,
  }) => PublicResearchBriefView(
    entities: entities ?? this.entities,
    questions: questions ?? this.questions,
    freshness: freshness ?? this.freshness,
  );

  Map<String, dynamic> toJson() => {
    'entities': entities.map((item) => item.toJson()).toList(growable: false),
    'questions': questions,
    'freshness': freshness,
  };
}

@immutable
class PlanBlockerView {
  const PlanBlockerView({required this.code, required this.message});

  final String code;
  final String message;

  factory PlanBlockerView.fromJson(Map<String, dynamic> json) =>
      PlanBlockerView(
        code: json['code']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
      );
}

@immutable
class ReportPlanDraftView {
  const ReportPlanDraftView({
    required this.selectedOptionId,
    this.attentionQuestions = const [],
    this.additionalFocus = '',
    this.skillIds = const [],
    this.references = const [],
    this.publicResearch = const PublicResearchBriefView(),
    this.blockers = const [],
    this.timeRange,
  });

  final String selectedOptionId;
  final List<String> attentionQuestions;
  final String additionalFocus;
  final List<String> skillIds;
  final List<EvidenceReferenceView> references;
  final PublicResearchBriefView publicResearch;
  final List<PlanBlockerView> blockers;
  final Map<String, dynamic>? timeRange;

  factory ReportPlanDraftView.fromJson(Map<String, dynamic> json) {
    final evidence =
        (json['evidence_scope'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return ReportPlanDraftView(
      selectedOptionId: json['selected_option_id']?.toString() ?? '',
      attentionQuestions: (json['attention_questions'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      additionalFocus: json['additional_focus']?.toString() ?? '',
      skillIds: (evidence['skill_ids'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      references: (evidence['references'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                EvidenceReferenceView.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
      publicResearch: PublicResearchBriefView.fromJson(
        (json['public_research_scope'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      blockers: (json['blockers'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => PlanBlockerView.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      timeRange: (evidence['time_range'] as Map?)?.cast<String, dynamic>(),
    );
  }

  ReportPlanDraftView copyWith({
    String? selectedOptionId,
    List<String>? attentionQuestions,
    String? additionalFocus,
    List<String>? skillIds,
    List<EvidenceReferenceView>? references,
    PublicResearchBriefView? publicResearch,
    List<PlanBlockerView>? blockers,
    Map<String, dynamic>? timeRange,
  }) => ReportPlanDraftView(
    selectedOptionId: selectedOptionId ?? this.selectedOptionId,
    attentionQuestions: attentionQuestions ?? this.attentionQuestions,
    additionalFocus: additionalFocus ?? this.additionalFocus,
    skillIds: skillIds ?? this.skillIds,
    references: references ?? this.references,
    publicResearch: publicResearch ?? this.publicResearch,
    blockers: blockers ?? this.blockers,
    timeRange: timeRange ?? this.timeRange,
  );

  Map<String, dynamic> toUpdateJson(int revision) => {
    'expected_revision': revision,
    'selected_option_id': selectedOptionId,
    'attention_questions': attentionQuestions,
    'additional_focus': additionalFocus,
    'evidence_scope': {
      'time_range': timeRange,
      'skill_ids': skillIds,
      'references': references.map((item) => item.toJson()).toList(),
    },
    'public_research_scope': publicResearch.toJson(),
  };
}

@immutable
class ReportEvidenceOption {
  const ReportEvidenceOption({
    required this.reference,
    required this.title,
    required this.typeLabel,
    required this.filterId,
    required this.filterLabel,
    required this.icon,
    this.subtitle,
  });

  final EvidenceReferenceView reference;
  final String title;
  final String? subtitle;
  final String typeLabel;
  final String filterId;
  final String filterLabel;
  final String icon;

  factory ReportEvidenceOption.fromJson(Map<String, dynamic> json) =>
      ReportEvidenceOption(
        reference: EvidenceReferenceView.fromJson(
          (json['reference'] as Map).cast<String, dynamic>(),
        ),
        title: json['title']?.toString() ?? '资产',
        subtitle: json['subtitle']?.toString(),
        typeLabel: json['type_label']?.toString() ?? '资产',
        filterId: json['filter_id']?.toString() ?? 'asset',
        filterLabel: json['filter_label']?.toString() ?? '资产',
        icon: json['icon']?.toString() ?? '•',
      );
}

@immutable
class ReportEvidenceOptionPage {
  const ReportEvidenceOptionPage({
    required this.items,
    required this.filters,
    this.nextCursor,
  });

  final List<ReportEvidenceOption> items;
  final List<Map<String, String>> filters;
  final String? nextCursor;

  factory ReportEvidenceOptionPage.fromJson(Map<String, dynamic> json) =>
      ReportEvidenceOptionPage(
        items: (json['items'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  ReportEvidenceOption.fromJson(item.cast<String, dynamic>()),
            )
            .toList(growable: false),
        filters: (json['filters'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => {
                'id': item['id']?.toString() ?? '',
                'label': item['label']?.toString() ?? '',
              },
            )
            .toList(growable: false),
        nextCursor: json['next_cursor']?.toString(),
      );
}
