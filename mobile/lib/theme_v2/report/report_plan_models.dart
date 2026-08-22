import 'package:flutter/foundation.dart';

String reportTimeBoundaryIso(DateTime value) => value.toUtc().toIso8601String();

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
class ReportPresentationPreferenceView {
  const ReportPresentationPreferenceView({this.family, this.customText = ''});

  final String? family;
  final String customText;

  factory ReportPresentationPreferenceView.fromJson(
    Map<String, dynamic> json,
  ) => ReportPresentationPreferenceView(
    family: json['family']?.toString(),
    customText: json['custom_text']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'family': family,
    'custom_text': customText,
  };
}

@immutable
class ReportAssetSelectionView {
  const ReportAssetSelectionView({
    this.autoReferences = const [],
    this.manualReferences = const [],
    this.excludedReferenceIds = const [],
  });

  final List<EvidenceReferenceView> autoReferences;
  final List<EvidenceReferenceView> manualReferences;
  final List<String> excludedReferenceIds;

  factory ReportAssetSelectionView.fromJson(Map<String, dynamic> json) =>
      ReportAssetSelectionView(
        autoReferences: _referenceList(json['auto_references']),
        manualReferences: _referenceList(json['manual_references']),
        excludedReferenceIds:
            (json['excluded_reference_ids'] as List? ?? const [])
                .map((item) => item.toString())
                .toList(growable: false),
      );

  List<EvidenceReferenceView> get resolvedReferences {
    final excluded = excludedReferenceIds.toSet();
    return <EvidenceReferenceView>{
      ...autoReferences.where((item) => !excluded.contains(item.id)),
      ...manualReferences.where((item) => !excluded.contains(item.id)),
    }.toList(growable: false);
  }

  Map<String, dynamic> toJson() => {
    'auto_references': autoReferences.map((item) => item.toJson()).toList(),
    'manual_references': manualReferences.map((item) => item.toJson()).toList(),
    'excluded_reference_ids': excludedReferenceIds,
  };
}

List<EvidenceReferenceView> _referenceList(dynamic value) =>
    (value as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              EvidenceReferenceView.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);

@immutable
class ReportScopeDraftView {
  const ReportScopeDraftView({
    required this.adapterKind,
    this.primaryReference,
    this.supportingReferences = const [],
    this.skillIds = const [],
    this.timeRange,
    this.attentionFocus = const [],
    this.additionalFocus = '',
    this.presentationPreference = const ReportPresentationPreferenceView(),
    this.missingDimensions = const [],
    this.selection = const ReportAssetSelectionView(),
  });

  final String adapterKind;
  final EvidenceReferenceView? primaryReference;
  final List<EvidenceReferenceView> supportingReferences;
  final List<String> skillIds;
  final Map<String, dynamic>? timeRange;
  final List<String> attentionFocus;
  final String additionalFocus;
  final ReportPresentationPreferenceView presentationPreference;
  final List<String> missingDimensions;
  final ReportAssetSelectionView selection;

  List<EvidenceReferenceView> get references => [
    ?primaryReference,
    ...supportingReferences,
  ];

  factory ReportScopeDraftView.fromJson(Map<String, dynamic> json) {
    final supporting = _referenceList(json['supporting_references']);
    final selectionJson = (json['selection'] as Map?)?.cast<String, dynamic>();
    return ReportScopeDraftView(
      adapterKind: json['adapter_kind']?.toString() ?? 'generic',
      primaryReference: json['primary_reference'] is Map
          ? EvidenceReferenceView.fromJson(
              (json['primary_reference'] as Map).cast<String, dynamic>(),
            )
          : null,
      supportingReferences: supporting,
      skillIds: (json['skill_ids'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      timeRange: (json['time_range'] as Map?)?.cast<String, dynamic>(),
      attentionFocus: (json['attention_focus'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      additionalFocus: json['additional_focus']?.toString() ?? '',
      presentationPreference: ReportPresentationPreferenceView.fromJson(
        (json['presentation_preference'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      missingDimensions: (json['missing_dimensions'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      selection: selectionJson == null
          ? ReportAssetSelectionView(autoReferences: supporting)
          : ReportAssetSelectionView.fromJson(selectionJson),
    );
  }

  ReportScopeDraftView copyWith({
    EvidenceReferenceView? primaryReference,
    bool clearPrimaryReference = false,
    List<EvidenceReferenceView>? supportingReferences,
    List<String>? skillIds,
    Map<String, dynamic>? timeRange,
    bool clearTimeRange = false,
    List<String>? attentionFocus,
    String? additionalFocus,
    ReportPresentationPreferenceView? presentationPreference,
    List<String>? missingDimensions,
    ReportAssetSelectionView? selection,
  }) => ReportScopeDraftView(
    adapterKind: adapterKind,
    primaryReference: clearPrimaryReference
        ? null
        : primaryReference ?? this.primaryReference,
    supportingReferences: supportingReferences ?? this.supportingReferences,
    skillIds: skillIds ?? this.skillIds,
    timeRange: clearTimeRange ? null : timeRange ?? this.timeRange,
    attentionFocus: attentionFocus ?? this.attentionFocus,
    additionalFocus: additionalFocus ?? this.additionalFocus,
    presentationPreference:
        presentationPreference ?? this.presentationPreference,
    missingDimensions: missingDimensions ?? this.missingDimensions,
    selection: selection ?? this.selection,
  );

  Map<String, dynamic> toJson() => {
    'adapter_kind': adapterKind,
    'primary_reference': primaryReference?.toJson(),
    'supporting_references': supportingReferences
        .map((item) => item.toJson())
        .toList(growable: false),
    'skill_ids': skillIds,
    'time_range': timeRange,
    'attention_focus': attentionFocus,
    'additional_focus': additionalFocus,
    'presentation_preference': presentationPreference.toJson(),
    'missing_dimensions': missingDimensions,
    'selection': selection.toJson(),
  };
}

@immutable
class ReportScopeEventCandidateView {
  const ReportScopeEventCandidateView({
    required this.reference,
    required this.title,
    required this.localDate,
    required this.localStart,
    required this.localEnd,
    this.location,
    this.notes,
  });

  final EvidenceReferenceView reference;
  final String title;
  final String localDate;
  final String localStart;
  final String localEnd;
  final String? location;
  final String? notes;

  factory ReportScopeEventCandidateView.fromJson(Map<String, dynamic> json) =>
      ReportScopeEventCandidateView(
        reference: EvidenceReferenceView.fromJson(
          (json['reference'] as Map).cast<String, dynamic>(),
        ),
        title: json['title']?.toString() ?? '未命名日程',
        localDate: json['local_date']?.toString() ?? '',
        localStart: json['local_start']?.toString() ?? '',
        localEnd: json['local_end']?.toString() ?? '',
        location: json['location']?.toString(),
        notes: json['notes']?.toString(),
      );
}

@immutable
class ReportScopeRecordCandidateView {
  const ReportScopeRecordCandidateView({
    required this.reference,
    required this.title,
    required this.effectiveAt,
    this.preview = const {},
  });

  final EvidenceReferenceView reference;
  final String title;
  final DateTime? effectiveAt;
  final Map<String, dynamic> preview;

  factory ReportScopeRecordCandidateView.fromJson(Map<String, dynamic> json) =>
      ReportScopeRecordCandidateView(
        reference: EvidenceReferenceView.fromJson(
          (json['reference'] as Map).cast<String, dynamic>(),
        ),
        title: json['title']?.toString() ?? '记录',
        effectiveAt: DateTime.tryParse(json['effective_at']?.toString() ?? ''),
        preview: (json['preview'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

@immutable
class ReportScopeRecordGroupView {
  const ReportScopeRecordGroupView({
    required this.skillId,
    required this.label,
    required this.count,
    required this.records,
    this.defaultSelected = true,
  });

  final String skillId;
  final String label;
  final int count;
  final bool defaultSelected;
  final List<ReportScopeRecordCandidateView> records;

  factory ReportScopeRecordGroupView.fromJson(Map<String, dynamic> json) =>
      ReportScopeRecordGroupView(
        skillId: json['skill_id']?.toString() ?? '',
        label: json['label']?.toString() ?? '记录',
        count: (json['count'] as num?)?.toInt() ?? 0,
        defaultSelected: json['default_selected'] != false,
        records: (json['records'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => ReportScopeRecordCandidateView.fromJson(
                item.cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
      );
}

@immutable
class ReportScopeCandidateResponseView {
  const ReportScopeCandidateResponseView({
    required this.adapterKind,
    required this.events,
    required this.recordGroups,
    required this.defaultScope,
    this.timeRangeOptions = const [],
  });

  final String adapterKind;
  final List<ReportScopeEventCandidateView> events;
  final List<ReportScopeRecordGroupView> recordGroups;
  final ReportScopeDraftView defaultScope;
  final List<ReportTimeRangeOptionView> timeRangeOptions;

  factory ReportScopeCandidateResponseView.fromJson(
    Map<String, dynamic> json,
  ) => ReportScopeCandidateResponseView(
    adapterKind: json['adapter_kind']?.toString() ?? 'generic',
    events: (json['events'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ReportScopeEventCandidateView.fromJson(
            item.cast<String, dynamic>(),
          ),
        )
        .toList(growable: false),
    recordGroups: (json['record_groups'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              ReportScopeRecordGroupView.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false),
    defaultScope: ReportScopeDraftView.fromJson(
      (json['default_scope'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    timeRangeOptions: (json['time_range_options'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              ReportTimeRangeOptionView.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false),
  );
}

@immutable
class ReportTimeRangeOptionView {
  const ReportTimeRangeOptionView({
    required this.id,
    required this.label,
    this.timeRange,
  });

  final String id;
  final String label;
  final Map<String, dynamic>? timeRange;

  factory ReportTimeRangeOptionView.fromJson(Map<String, dynamic> json) =>
      ReportTimeRangeOptionView(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        timeRange: (json['time_range'] as Map?)?.cast<String, dynamic>(),
      );
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
