import 'package:flutter/material.dart';

import '../../../data_revision.dart';
import '../../../render/render_spec.dart';
import '../../asset_detail/asset_detail_model.dart';
import '../../asset_detail/asset_detail_repository.dart';
import '../../asset_detail/asset_entity_ref.dart';
import 'asset_editor.dart';

enum AssetDetailPresentationKind { bottomSheet, fullPage }

enum AssetDetailLoadState { loading, ready, error }

AssetDetailPresentationKind initialAssetDetailPresentation([Object? _]) =>
    AssetDetailPresentationKind.bottomSheet;

class AssetDetailController extends ChangeNotifier {
  AssetDetailController({required this.repository, required this.ref})
    : presentation = initialAssetDetailPresentation();

  final AssetDetailRepository repository;
  final AssetEntityRef ref;
  final ScrollController scrollController = ScrollController();

  AssetDetailPresentationKind presentation;
  AssetDetailLoadState loadState = AssetDetailLoadState.loading;
  AssetDetailModel? _detail;
  RenderSpec? _spec;
  CardData? _data;
  AssetEditorDraft? _draft;
  Future<void>? _hydration;
  bool editing = false;
  bool busy = false;
  bool _disposed = false;
  String? errorMessage;

  AssetDetailModel? get detail => _detail;
  String get assetId => ref.id;
  String get cardType => _detail?.skill.machineName ?? ref.kind.name;
  String get skillDisplayName =>
      _detail?.skill.displayName ?? ref.kind.name.toUpperCase();
  String? get userSkillId => _detail?.skill.id;
  String? get sessionId => _detail?.source.sessionId;
  String? get inputTurnId => _detail?.source.inputTurnId;
  AssetDetailSourceKind? get sourceKind => _detail?.source.kind;
  String? get sourceLabel => _detail?.source.label;
  bool get sourceCanOpen => _detail?.source.canOpen ?? false;
  bool get canEdit =>
      loadState == AssetDetailLoadState.ready &&
      (_detail?.capabilities.editable ?? false);
  bool get canDelete =>
      loadState == AssetDetailLoadState.ready &&
      (_detail?.capabilities.deletable ?? false);

  RenderSpec get spec => _spec ?? synthesizeSpec(cardType);
  AssetEditorDraft get draft => _draft!;
  Map<String, dynamic> get payload =>
      Map.unmodifiable(_detail?.values ?? const {});
  CardData get data =>
      _data ??
      CardData(
        layout: 'horizontal',
        icon: '•',
        accentColor: 'gray',
        title: skillDisplayName,
        subtitle: '',
        metaFields: const [],
      );
  bool get isDone => todoPayloadIsDone(payload);

  Future<void> hydrate() => _hydration ??= _hydrateOnce();

  Future<void> retry() {
    _hydration = null;
    loadState = AssetDetailLoadState.loading;
    errorMessage = null;
    _notify();
    return hydrate();
  }

  Future<void> _hydrateOnce() async {
    try {
      final loaded = await repository.load(ref);
      if (_disposed) return;
      _applyModel(loaded, replaceDraft: true);
      loadState = AssetDetailLoadState.ready;
      errorMessage = null;
    } catch (_) {
      if (_disposed) return;
      loadState = AssetDetailLoadState.error;
      errorMessage = '完整内容暂时无法加载';
    }
    _notify();
  }

  void _applyModel(AssetDetailModel model, {required bool replaceDraft}) {
    _detail = model;
    _spec = renderSpecFromAssetDetailModel(model);
    _data = buildCard(
      payload: model.values,
      spec: _spec,
      displayName: model.skill.machineName,
    );
    if (replaceDraft) {
      _draft?.dispose();
      _draft = AssetEditorDraft(payload: model.values, spec: _spec!);
    }
  }

  void expand() {
    if (presentation == AssetDetailPresentationKind.fullPage) return;
    final offset = scrollController.hasClients ? scrollController.offset : 0.0;
    presentation = AssetDetailPresentationKind.fullPage;
    _notify();
    _restoreScrollOffset(offset);
  }

  void collapse() {
    if (presentation == AssetDetailPresentationKind.bottomSheet) return;
    final offset = scrollController.hasClients ? scrollController.offset : 0.0;
    presentation = AssetDetailPresentationKind.bottomSheet;
    _notify();
    _restoreScrollOffset(offset);
  }

  void _restoreScrollOffset(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !scrollController.hasClients) return;
      final position = scrollController.position;
      scrollController.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  void restoreScrollOffset(double offset) => _restoreScrollOffset(offset);

  void beginEditing() {
    if (!canEdit || _draft == null) return;
    editing = true;
    _notify();
  }

  void cancelEditing() {
    editing = false;
    _draft?.dispose();
    final current = _detail;
    if (current != null) {
      _draft = AssetEditorDraft(payload: current.values, spec: spec);
    }
    _notify();
  }

  Future<void> saveDraft(Map<String, dynamic> next) async {
    final current = _detail;
    if (current == null || busy) return;
    busy = true;
    _notify();
    try {
      final saved = await repository.save(current, next);
      if (_disposed) return;
      _applyModel(saved, replaceDraft: true);
      editing = false;
      bumpData();
    } catch (error) {
      errorMessage = error.toString();
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> toggleTodo() async {
    final current = _detail;
    if (current == null || busy) return;
    busy = true;
    _notify();
    try {
      final saved = await repository.save(current, {
        'status': isDone ? 'pending' : 'done',
      });
      if (_disposed) return;
      _applyModel(saved, replaceDraft: true);
      bumpData();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> delete() async {
    if (busy || !canDelete) return;
    busy = true;
    _notify();
    try {
      await repository.delete(ref);
      bumpData();
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _draft?.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

RenderSpec renderSpecFromAssetDetailModel(AssetDetailModel model) {
  final secondary = model.display.secondaryFieldIds;
  return RenderSpec(
    cardLayout: model.fields.any((field) => field.long)
        ? 'stacked'
        : 'horizontal',
    icon: model.skill.icon,
    accentColor: switch (model.ref.kind) {
      AssetEntityKind.event => 'purple',
      AssetEntityKind.contact => 'neutral',
      AssetEntityKind.asset =>
        model.skill.machineName == 'todo' ? 'blue' : 'gray',
    },
    primaryField: model.display.primaryFieldId,
    primaryFormat:
        model.skill.machineName == 'expense' &&
            model.display.primaryFieldId == 'amount'
        ? 'currency'
        : null,
    secondaryField: secondary.firstOrNull,
    metaFields: [
      for (final field in secondary.skip(1)) MetaFieldSpec(field, null),
    ],
    actions: [
      if (model.skill.machineName == 'todo') 'check',
      if (model.capabilities.editable) 'edit',
      if (model.capabilities.deletable) 'delete',
    ],
    fieldLabels: {for (final field in model.fields) field.id: field.label},
    schemaFields: [for (final field in model.fields) field.id],
    longFields: {
      for (final field in model.fields)
        if (field.long) field.id,
    },
    fieldTypes: {for (final field in model.fields) field.id: field.type},
    requiredFields: {
      for (final field in model.fields)
        if (field.required) field.id,
    },
  );
}
