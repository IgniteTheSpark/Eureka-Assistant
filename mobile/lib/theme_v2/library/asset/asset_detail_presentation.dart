import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../data_revision.dart';
import '../../../render/render_spec.dart';
import 'asset_editor.dart';
import 'asset_editors.dart';

enum AssetDetailPresentationKind { bottomSheet, fullPage }

enum AssetDetailLoadState { loading, ready, error }

/// Asset type never decides its chrome. Every detail enters through the same
/// bottom-sheet surface and may then expand without replacing its state.
AssetDetailPresentationKind initialAssetDetailPresentation(String _) =>
    AssetDetailPresentationKind.bottomSheet;

class AssetDetailController extends ChangeNotifier {
  AssetDetailController({
    ApiClient? api,
    required CardData data,
    required Map<String, dynamic> payload,
    required this.cardType,
    required this.assetId,
    required this.userSkillId,
    required RenderSpec? spec,
    this.sessionId,
  }) : _api = api ?? ApiClient(),
       _ownsApi = api == null,
       _data = data,
       _payload = Map<String, dynamic>.from(payload),
       spec = themeV2AssetEditorSpec(
         cardType,
         spec ?? synthesizeSpec(cardType),
       ),
       presentation = initialAssetDetailPresentation(cardType) {
    draft = AssetEditorDraft(payload: _payload, spec: this.spec);
  }

  final ApiClient _api;
  final bool _ownsApi;
  final String cardType;
  final String? assetId;
  final String? userSkillId;
  final String? sessionId;
  final RenderSpec spec;
  final ScrollController scrollController = ScrollController();

  AssetDetailPresentationKind presentation;
  AssetDetailLoadState loadState = AssetDetailLoadState.loading;
  late AssetEditorDraft draft;
  CardData _data;
  Map<String, dynamic> _payload;
  Future<void>? _hydration;
  bool editing = false;
  bool busy = false;
  bool _disposed = false;
  String? errorMessage;

  CardData get data => _data;
  Map<String, dynamic> get payload => Map.unmodifiable(_payload);
  bool get isDone => todoPayloadIsDone(_payload);
  String? get sourceLabel {
    final explicit =
        _payload['source_label']?.toString().trim() ??
        _payload['source']?.toString().trim() ??
        '';
    if (explicit.isNotEmpty) return explicit;
    final session = sessionId?.trim() ?? '';
    return session.isEmpty ? null : '来自闪念';
  }

  Future<void> hydrate() => _hydration ??= _hydrateOnce();

  Future<void> _hydrateOnce() async {
    final id = assetId;
    if (id == null || id.isEmpty || cardType == 'task') {
      loadState = AssetDetailLoadState.ready;
      _notify();
      return;
    }
    try {
      final response = await _api.getJson(_detailPath(id));
      final raw = switch (cardType) {
        'event' => response is Map ? (response['event'] ?? response) : null,
        'contact' => response is Map ? (response['contact'] ?? response) : null,
        _ => response is Map ? response['asset'] : null,
      };
      final map = raw is Map ? raw.cast<String, dynamic>() : null;
      final hydrated = cardType == 'event' || cardType == 'contact'
          ? map
          : (map?['payload'] as Map?)?.cast<String, dynamic>();
      if (_disposed || hydrated == null) return;
      _payload = Map<String, dynamic>.from(hydrated);
      _data = buildCard(
        payload: _payload,
        spec: spec,
        displayName: cardType,
      ).copyWith(domain: map?['domain'] as String? ?? _data.domain);
      if (!draft.isDirty) {
        draft.dispose();
        draft = AssetEditorDraft(payload: _payload, spec: spec);
      }
      loadState = AssetDetailLoadState.ready;
      errorMessage = null;
    } catch (error) {
      if (_disposed) return;
      loadState = AssetDetailLoadState.error;
      errorMessage = '完整内容暂时无法加载，当前显示缓存内容';
    }
    _notify();
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

  void beginEditing() {
    editing = true;
    _notify();
  }

  void cancelEditing() {
    editing = false;
    _notify();
  }

  Future<void> saveDraft(Map<String, dynamic> next) async {
    final id = assetId;
    if (id == null || busy) return;
    busy = true;
    _notify();
    try {
      switch (cardType) {
        case 'event':
          await _api.putJson('/api/events/$id', next);
        case 'contact':
          await _api.putJson('/api/contacts/$id', next);
        default:
          await _api.putJson('/api/assets/$id', {'payload_patch': next});
      }
      _payload = Map<String, dynamic>.from(next);
      _data = buildCard(
        payload: _payload,
        spec: spec,
        displayName: cardType,
      ).copyWith(domain: _data.domain);
      draft.acceptSaved();
      editing = false;
      bumpData();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> toggleTodo() async {
    final id = assetId;
    if (id == null || busy) return;
    final next = !isDone;
    busy = true;
    _payload = {..._payload, 'status': next ? 'done' : 'pending'};
    _notify();
    try {
      await _api.putJson('/api/assets/$id', {
        'payload_patch': {'status': next ? 'done' : 'pending'},
      });
      bumpData();
    } catch (_) {
      _payload = {..._payload, 'status': next ? 'pending' : 'done'};
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> delete() async {
    final id = assetId;
    if (id == null || busy) return;
    busy = true;
    _notify();
    try {
      await _api.deleteJson(_detailPath(id));
      bumpData();
    } finally {
      busy = false;
      _notify();
    }
  }

  String _detailPath(String id) => switch (cardType) {
    'event' => '/api/events/$id',
    'contact' => '/api/contacts/$id',
    _ => '/api/assets/$id',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    draft.dispose();
    scrollController.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
