import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/toast.dart';

/// 设置 → 已连接应用 (§4.0.6 / §1.7.1). Two sections:
/// - **已连接**: this user's connections (status chip · 测试 · 断开).
/// - **可连接**: the connector catalog; tapping one opens a connect form whose
///   fields come from the connector spec (secret fields are masked).
///
/// Credentials are write-only: they're only ever sent up (POST), never shown.
/// [focusConnector] optionally deep-links from a failed external sync straight
/// to that connector's connect form (§4.4.2/§4.4.3).
class ConnectedAppsPage extends StatefulWidget {
  final String? focusConnector;
  const ConnectedAppsPage({super.key, this.focusConnector});

  @override
  State<ConnectedAppsPage> createState() => _ConnectedAppsPageState();
}

class _ConnectedAppsPageState extends State<ConnectedAppsPage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _connectors = const [];
  List<Map<String, dynamic>> _connected = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final r = await Future.wait([
        _api.getJson('/api/connectors'),
        _api.getJson('/api/connected-apps'),
      ]);
      final cons = ((r[0] as Map?)?['connectors'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final conn = ((r[1] as Map?)?['connected'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _connectors = cons;
        _connected = conn;
        _loading = false;
      });
      // Deep-link: auto-open the requested connector's form on first load.
      if (initial && widget.focusConnector != null) {
        final spec = cons.firstWhere(
          (c) => c['connector_id'] == widget.focusConnector,
          orElse: () => {},
        );
        if (spec.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _openConnectForm(spec),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showToast(context, '加载失败：$e', error: true);
      }
    }
  }

  Map<String, dynamic>? _connectionFor(String connectorId) {
    for (final c in _connected) {
      if (c['connector_id'] == connectorId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: const Text('已连接应用'),
      ),
      body: _loading
          ? const USkeletonList(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
              count: 6,
              cardHeight: 76,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (_connected.isNotEmpty) ...[
                  _label(eu, '已连接'),
                  const SizedBox(height: 8),
                  for (final c in _connected) _connectedRow(eu, c),
                  const SizedBox(height: 22),
                ],
                _label(eu, '可连接'),
                const SizedBox(height: 8),
                for (final spec in _connectors) _catalogRow(eu, spec),
                const SizedBox(height: 16),
                Text(
                  '你的密钥只存在服务端、加密保存，绝不回传或展示。',
                  style: TextStyle(
                    color: eu.textLo,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _label(EurekaColors eu, String t) => Text(
    t,
    style: euMono(fontSize: 10.5, letterSpacing: 2.2, color: eu.textMid),
  );

  ({String text, Color color}) _statusMeta(EurekaColors eu, String? status) {
    switch (status) {
      case 'connected':
        return (text: '已连接', color: eu.accentGreen);
      case 'needs_reauth':
        return (text: '需重新授权', color: eu.accentAmber);
      case 'error':
        return (text: '连接出错', color: eu.accentRed);
      default:
        return (text: '已断开', color: eu.textLo);
    }
  }

  Widget _connectedRow(EurekaColors eu, Map<String, dynamic> c) {
    final spec = _connectors.firstWhere(
      (s) => s['connector_id'] == c['connector_id'],
      orElse: () => {},
    );
    final icon = (spec['icon'] as String?) ?? '🔌';
    final meta = _statusMeta(eu, c['status'] as String?);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        children: [
          _connectorLogo(eu, c['connector_id'] as String? ?? '', icon),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (c['display_name'] as String?) ??
                      (c['connector_id'] as String? ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: eu.textHi,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: meta.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      meta.text,
                      style: TextStyle(color: meta.color, fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _miniBtn(eu, '测试', () => _test(c)),
          const SizedBox(width: 6),
          _miniBtn(eu, '断开', () => _disconnect(c), danger: true),
        ],
      ),
    );
  }

  /// Branded logo tile for a connector. Real product marks (DingTalk / Notion)
  /// render as their brand-tinted SVG in a white "app tile"; unknown connectors
  /// fall back to the catalog emoji on a themed tile. Bundled SVGs use
  /// `currentColor`, so a single asset tints to the brand color via colorFilter.
  Widget _connectorLogo(
    EurekaColors eu,
    String connectorId,
    String fallbackEmoji, {
    double box = 36,
  }) {
    String? asset;
    Color glyph;
    if (connectorId.startsWith('dingtalk')) {
      asset = 'assets/logo/dingtalk.svg';
      glyph = const Color(0xFF1677FF); // DingTalk blue
    } else if (connectorId == 'notion') {
      asset = 'assets/logo/notion.svg';
      glyph = const Color(0xFF111111); // Notion mono N
    } else {
      return Container(
        width: box,
        height: box,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: eu.surface,
          borderRadius: BorderRadius.circular(box * 0.26),
          border: Border.all(color: eu.border),
        ),
        child: Text(fallbackEmoji, style: TextStyle(fontSize: box * 0.5)),
      );
    }
    return Container(
      width: box,
      height: box,
      padding: EdgeInsets.all(box * 0.2),
      decoration: BoxDecoration(
        color:
            Colors.white, // brand logos read against white, like real app icons
        borderRadius: BorderRadius.circular(box * 0.26),
        border: Border.all(color: eu.border),
      ),
      child: SvgPicture.asset(
        asset,
        colorFilter: ColorFilter.mode(glyph, BlendMode.srcIn),
      ),
    );
  }

  Widget _miniBtn(
    EurekaColors eu,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? eu.accentRed : eu.textMid;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }

  Widget _catalogRow(EurekaColors eu, Map<String, dynamic> spec) {
    final connected =
        _connectionFor(spec['connector_id'] as String? ?? '') != null;
    return GestureDetector(
      onTap: () => _openConnectForm(spec),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          children: [
            _connectorLogo(
              eu,
              spec['connector_id'] as String? ?? '',
              (spec['icon'] as String?) ?? '🔌',
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (spec['name'] as String?) ?? '',
                    style: TextStyle(
                      color: eu.textHi,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (spec['description'] as String?) ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: eu.textLo,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (connected)
              Icon(Icons.check_circle, size: 18, color: eu.accentGreen)
            else
              Text(
                '连接',
                style: TextStyle(
                  color: eu.brand,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openConnectForm(Map<String, dynamic> spec) {
    final eu = context.eu;
    final fields = (spec['fields'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final controllers = {
      for (final f in fields) (f['key'] as String): TextEditingController(),
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: eu.surfaceRaised,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _connectorLogo(
                      eu,
                      spec['connector_id'] as String? ?? '',
                      (spec['icon'] as String?) ?? '🔌',
                      box: 40,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '连接 ${spec['name']}',
                      style: TextStyle(
                        color: eu.textHi,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  (spec['description'] as String?) ?? '',
                  style: TextStyle(
                    color: eu.textMid,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                for (final f in fields) ...[
                  Text(
                    (f['label'] as String?) ?? (f['key'] as String? ?? ''),
                    style: TextStyle(color: eu.textMid, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: eu.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: eu.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: controllers[f['key'] as String],
                      obscureText: f['secret'] == true,
                      style: TextStyle(color: eu.textHi, fontSize: 14),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: (f['placeholder'] as String?) ?? '',
                        hintStyle: TextStyle(color: eu.textLo, fontSize: 12.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: submitting
                        ? null
                        : () async {
                            final creds = {
                              for (final e in controllers.entries)
                                e.key: e.value.text.trim(),
                            };
                            if (creds.values.any((v) => v.isEmpty)) {
                              showToast(sheetCtx, '请填完所有字段', error: true);
                              return;
                            }
                            setSheet(() => submitting = true);
                            try {
                              await _api.postJson('/api/connected-apps', {
                                'connector_id': spec['connector_id'],
                                'credentials': creds,
                              });
                              if (sheetCtx.mounted) {
                                Navigator.of(sheetCtx).pop();
                              }
                              if (mounted) {
                                showToast(context, '已连接 ${spec['name']}');
                                _load();
                              }
                            } catch (e) {
                              if (!sheetCtx.mounted) return;
                              setSheet(() => submitting = false);
                              showToast(sheetCtx, '连接失败：$e', error: true);
                            }
                          },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: eu.brand,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '连接',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _test(Map<String, dynamic> c) async {
    try {
      final res = await _api.postJson(
        '/api/connected-apps/${c['id']}/test',
        {},
      );
      final status = (res is Map ? res['status'] : null) as String?;
      if (mounted) {
        showToast(
          context,
          status == 'connected' ? '连接正常' : '连接异常：$status',
          error: status != 'connected',
        );
        _load();
      }
    } catch (e) {
      if (mounted) showToast(context, '测试失败：$e', error: true);
    }
  }

  Future<void> _disconnect(Map<String, dynamic> c) async {
    final eu = context.eu;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: eu.surfaceRaised,
        title: Text(
          '断开 ${c['display_name']}？',
          style: TextStyle(color: eu.textHi),
        ),
        content: Text(
          '会删除你存的凭据，需要时可重新连接。',
          style: TextStyle(color: eu.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: eu.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '断开',
              style: TextStyle(
                color: eu.accentRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteJson('/api/connected-apps/${c['id']}');
      if (mounted) {
        showToast(context, '已断开');
        _load();
      }
    } catch (e) {
      if (mounted) showToast(context, '断开失败：$e', error: true);
    }
  }
}
