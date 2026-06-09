import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../render/render_spec.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart' show SkillMeta, fetchSkills;

/// Shared multi-select asset picker — ONE interaction/display used by both the
/// chat session (关联 context, hosted in a bottom sheet) and 洞察 manual-select
/// (hosted in a centered modal). Only the host + a couple labels differ.
///
/// - [excludeIds]: assets to HIDE (already attached) — session use.
/// - [initialSelected]: assets to PRE-CHECK (editable) — 洞察 use.
/// - pops `List<AssetItem>` (with readable titles) on confirm, null on cancel.
class AssetPickerPanel extends StatefulWidget {
  final Set<String> excludeIds;
  final Set<String> initialSelected;
  final String title; // '添加资产' / '挑要洞察的资产'
  final String confirmVerb; // '添加' / '用这'
  final String unit; // '项' / '条'
  final Color? tint; // accent (洞察 = REKA aura); defaults to brand
  final double heightFactor;
  const AssetPickerPanel({
    super.key,
    this.excludeIds = const {},
    this.initialSelected = const {},
    this.title = '添加资产',
    this.confirmVerb = '添加',
    this.unit = '项',
    this.tint,
    this.heightFactor = 0.62,
  });

  @override
  State<AssetPickerPanel> createState() => _AssetPickerPanelState();
}

class _PickerData {
  final List<AssetItem> assets;
  final Map<String, SkillMeta> skills;
  final Map<String, RenderSpec> specs;
  _PickerData(this.assets, this.skills, this.specs);
}

class _AssetPickerPanelState extends State<AssetPickerPanel> {
  final _api = ApiClient();
  late final Future<_PickerData> _future = _load();
  String _filter = '__all__';
  late final Set<String> _selected = {...widget.initialSelected};
  final Map<String, AssetItem> _byId = {};

  Future<_PickerData> _load() async {
    // Pull the full set (not the default 50) so EVERY skill with assets shows as
    // a tab + is selectable — else older types (随记/读书/…) vanish behind a wall
    // of recent records (e.g. 100+ expenses). 500 = backend max; paginate if ever
    // a user exceeds it.
    final r = await Future.wait(
        [fetchAssets(_api, limit: 500), fetchSkills(_api), fetchRenderSpecs(_api)]);
    return _PickerData(
      r[0] as List<AssetItem>,
      r[1] as Map<String, SkillMeta>,
      r[2] as Map<String, RenderSpec>,
    );
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Color _accent(EurekaColors eu) => widget.tint ?? eu.brand;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final h = MediaQuery.of(context).size.height * widget.heightFactor;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: h,
        child: FutureBuilder<_PickerData>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snap.data;
            final all = (data?.assets ?? const <AssetItem>[])
                .where((a) => !widget.excludeIds.contains(a.id))
                .toList();
            final present = <String>[];
            for (final a in all) {
              if (!present.contains(a.skillName)) present.add(a.skillName);
            }
            String labelOf(String s) => data?.skills[s]?.label ?? s;
            final shown =
                _filter == '__all__' ? all : all.where((a) => a.skillName == _filter).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(widget.title,
                            style: TextStyle(
                                color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      // Explicit dismiss (pops null) — works in BOTH hosts (the
                      // 洞察 centered modal had no other way to close).
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: eu.textMid, size: 22),
                        tooltip: '关闭',
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                if (present.length > 1)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _filterChip(eu, '全部', '__all__'),
                        for (final s in present) _filterChip(eu, labelOf(s), s),
                      ],
                    ),
                  ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(child: Text('没有可选的资产', style: TextStyle(color: eu.textMid)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final a = shown[i];
                            final title = readableTitle(a.payload, data?.specs[a.skillName],
                                fallback: labelOf(a.skillName));
                            _byId[a.id] = a.copyWithTitle(title);
                            final icon = data?.skills[a.skillName]?.icon ?? '•';
                            final checked = _selected.contains(a.id);
                            return ListTile(
                              leading: Text(icon, style: const TextStyle(fontSize: 18)),
                              title: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: eu.textHi, fontSize: 14)),
                              subtitle: Text(labelOf(a.skillName),
                                  style: TextStyle(color: eu.textLo, fontSize: 11)),
                              trailing: Icon(
                                checked ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: checked ? _accent(eu) : eu.textLo,
                                size: 22,
                              ),
                              onTap: () => setState(() {
                                if (checked) {
                                  _selected.remove(a.id);
                                } else {
                                  _selected.add(a.id);
                                }
                              }),
                            );
                          },
                        ),
                ),
                if (_selected.isNotEmpty) _selectedRow(eu),
                _confirmBar(eu),
              ],
            );
          },
        ),
      ),
    );
  }

  // Selected assets as removable chips — deselect without hunting in the list.
  Widget _selectedRow(EurekaColors eu) {
    final accent = _accent(eu);
    return Container(
      height: 44,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: eu.border))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final id in _selected)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selected.remove(id)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(_byId[id]?.title ?? '资产',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: eu.textHi, fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 13, color: eu.textMid),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _confirmBar(EurekaColors eu) {
    final n = _selected.length;
    final accent = _accent(eu);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: eu.border))),
      child: Row(
        children: [
          Expanded(
            child: Text(n == 0 ? '未选择' : '已选 $n ${widget.unit}',
                style: TextStyle(color: n == 0 ? eu.textLo : eu.textMid, fontSize: 13)),
          ),
          GestureDetector(
            onTap: n == 0
                ? null
                : () => Navigator.of(context).pop([for (final id in _selected) _byId[id]!]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: n == 0 ? eu.surface : accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(n == 0 ? widget.confirmVerb : '${widget.confirmVerb} $n ${widget.unit}',
                  style: TextStyle(
                      color: n == 0 ? eu.textLo : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(EurekaColors eu, String label, String value) {
    final active = _filter == value;
    final accent = _accent(eu);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.18) : eu.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? accent.withValues(alpha: 0.45) : eu.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? eu.textHi : eu.textMid,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }
}
