import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../data_revision.dart';
import '../../render/render_spec.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../library/asset/asset_detail_presentation.dart';
import '../library/asset/asset_editor.dart';
import '../library/asset/asset_editors.dart';
import 'asset_detail_model.dart';
import 'asset_detail_repository.dart';
import 'asset_entity_ref.dart';

enum AssetEditMode { create, update }

class ThemeV2AssetEditPage extends StatefulWidget {
  const ThemeV2AssetEditPage({
    super.key,
    required this.reference,
    required this.initialValues,
    required this.mode,
    required this.skillName,
    required this.displayName,
    this.spec,
    this.presetDate,
    this.initialDomain,
    this.api,
    this.repository,
  });

  final AssetEntityRef reference;
  final Map<String, dynamic> initialValues;
  final AssetEditMode mode;
  final String skillName;
  final String displayName;
  final RenderSpec? spec;
  final DateTime? presetDate;
  final String? initialDomain;
  final ApiClient? api;
  final AssetDetailRepository? repository;

  @override
  State<ThemeV2AssetEditPage> createState() => _ThemeV2AssetEditPageState();
}

class _ThemeV2AssetEditPageState extends State<ThemeV2AssetEditPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final bool _ownsApi = widget.api == null;
  late final AssetDetailRepository _repository =
      widget.repository ?? ApiAssetDetailRepository(_api);
  late final Future<void> _initialization = _initialize();
  final _scrollController = ScrollController();

  AssetDetailModel? _model;
  AssetEditorDraft? _draft;
  String? _error;
  var _busy = false;

  Future<void> _initialize() async {
    if (widget.mode == AssetEditMode.update) {
      final model = await _repository.load(widget.reference);
      _model = model;
      _draft = AssetEditorDraft(
        payload: model.values,
        spec: renderSpecFromAssetDetailModel(model),
      );
      return;
    }
    final spec = widget.spec ?? await _loadCreateSpec();
    _draft = AssetEditorDraft(
      payload: _presetValues(widget.initialValues, spec),
      spec: spec,
    );
  }

  Future<RenderSpec> _loadCreateSpec() async {
    final response = await _api.getJson('/api/skills');
    final skills =
        (response is Map ? response['skills'] : null) as List? ?? const [];
    final raw = skills.whereType<Map>().cast<Map>().firstWhere(
      (skill) => skill['name'] == widget.skillName,
      orElse: () => const {},
    );
    if (raw.isEmpty) {
      throw StateError('Skill schema unavailable: ${widget.skillName}');
    }
    final render =
        (raw['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
    final schema =
        (raw['payload_schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RenderSpec(
      cardLayout: render['card_layout'] as String? ?? 'horizontal',
      icon: render['icon'] as String? ?? '•',
      accentColor: render['accent_color'] as String? ?? 'gray',
    ).withSchema(schema);
  }

  Map<String, dynamic> _presetValues(
    Map<String, dynamic> values,
    RenderSpec spec,
  ) {
    final result = Map<String, dynamic>.from(values);
    final preset = widget.presetDate;
    if (preset == null) return result;
    for (final field in spec.schemaFields) {
      if (result[field] != null && '${result[field]}'.isNotEmpty) continue;
      switch (spec.fieldTypes[field]) {
        case 'date':
          result[field] = _isoBeijing(preset, dateOnly: true);
        case 'datetime':
          result[field] = _isoBeijing(preset);
      }
    }
    return result;
  }

  static String _isoBeijing(DateTime value, {bool dateOnly = false}) {
    String two(int number) => number.toString().padLeft(2, '0');
    final date = '${value.year}-${two(value.month)}-${two(value.day)}';
    if (dateOnly) return date;
    return '$date'
        'T${two(value.hour)}:${two(value.minute)}:00+08:00';
  }

  Future<void> _save(Map<String, dynamic> values) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.mode == AssetEditMode.create) {
        final payload = <String, dynamic>{
          for (final entry in values.entries)
            if (_hasCreateValue(entry.value)) entry.key: entry.value,
        };
        await _api.postJson('/api/assets', {
          'user_skill_name': widget.skillName,
          'payload': payload,
          'domain': widget.initialDomain ?? '',
        });
        bumpData();
        _draft?.acceptSaved();
        if (!mounted) return;
        Navigator.of(context).pop(<String, dynamic>{
          'user_skill_name': widget.skillName,
          'display_name': widget.displayName,
          'icon': _draft?.spec.icon ?? '•',
          'payload': payload,
        });
        return;
      }

      final model = _model;
      if (model == null) throw StateError('Asset detail is not loaded');
      _model = await _repository.save(model, values);
      bumpData();
      _draft?.acceptSaved();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '保存失败：$error';
      });
    }
  }

  bool _hasCreateValue(dynamic value) =>
      value != null &&
      (value is! String || value.trim().isNotEmpty) &&
      (value is! Iterable || value.isNotEmpty);

  @override
  void dispose() {
    _draft?.dispose();
    _scrollController.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = buildThemeV2Theme(Theme.of(context).brightness);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.themeV2.background,
          appBar: AppBar(
            title: Text(
              widget.mode == AssetEditMode.create
                  ? '创建${widget.displayName}'
                  : '编辑${widget.displayName}',
            ),
          ),
          body: FutureBuilder<void>(
            future: _initialization,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(ThemeV2Spacing.xl),
                    child: Text('无法加载编辑结构：${snapshot.error}'),
                  ),
                );
              }
              final draft = _draft;
              if (snapshot.connectionState != ConnectionState.done ||
                  draft == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: [
                  if (_error case final error?)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ThemeV2Spacing.xl,
                        ThemeV2Spacing.sm,
                        ThemeV2Spacing.xl,
                        0,
                      ),
                      child: Text(
                        error,
                        style: TextStyle(color: context.themeV2.critical),
                      ),
                    ),
                  Expanded(
                    child: IgnorePointer(
                      ignoring: _busy,
                      child: AssetEditorRouter(
                        cardType: widget.skillName,
                        draft: draft,
                        scrollController: _scrollController,
                        onSave: _save,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
