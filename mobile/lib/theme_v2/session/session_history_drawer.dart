import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';

class SessionHistoryDrawer extends StatefulWidget {
  const SessionHistoryDrawer({
    super.key,
    required this.activeSessionId,
    required this.loadSessions,
    required this.deleteSession,
    required this.onSelectSession,
    required this.onNewSession,
  });

  final String? activeSessionId;
  final Future<List<SessionInfo>> Function() loadSessions;
  final Future<bool> Function(String id) deleteSession;
  final Future<void> Function(SessionInfo session) onSelectSession;
  final VoidCallback onNewSession;

  @override
  State<SessionHistoryDrawer> createState() => _SessionHistoryDrawerState();
}

class _SessionHistoryDrawerState extends State<SessionHistoryDrawer> {
  List<SessionInfo>? _sessions;
  Object? _error;
  var _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _sessions = null;
      _error = null;
    });
    try {
      final sessions = await widget.loadSessions();
      if (!mounted || revision != _revision) return;
      setState(() => _sessions = sessions);
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() => _error = error);
    }
  }

  Future<void> _delete(SessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话？'),
        content: Text('「${session.title}」将被删除，其中产生的资产会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await widget.deleteSession(session.id);
    if (!mounted) return;
    if (ok) {
      setState(() => _sessions?.removeWhere((item) => item.id == session.id));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      await _load();
    }
  }

  @override
  void dispose() {
    _revision++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final availableWidth = MediaQuery.sizeOf(context).width;
    final width = math.min(304.0, math.max(0.0, availableWidth - 40));
    return Drawer(
      width: width,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SESSION ARCHIVE',
                          style: ThemeV2Typography.mono(
                            color: tokens.accent,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '历史会话',
                          style: TextStyle(
                            color: tokens.foreground,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ThemeV2IconButton(
                    semanticLabel: '关闭历史会话',
                    icon: Icons.close_rounded,
                    color: tokens.muted,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildBody(tokens)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: ThemeV2Sizes.minTouchTarget,
                child: FilledButton.icon(
                  onPressed: widget.onNewSession,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新会话'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeV2Tokens tokens) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('历史会话加载失败', style: TextStyle(color: tokens.muted)),
            const SizedBox(height: 8),
            SizedBox(
              height: ThemeV2Sizes.minTouchTarget,
              child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ),
          ],
        ),
      );
    }
    final sessions = _sessions;
    if (sessions == null) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
      );
    }
    if (sessions.isEmpty) {
      return Center(
        child: Text('暂无会话', style: TextStyle(color: tokens.muted)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final active = session.id == widget.activeSessionId;
        return Semantics(
          button: true,
          selected: active,
          label: '${session.title}，打开会话',
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            decoration: BoxDecoration(
              color: active ? tokens.accentSoft : Colors.transparent,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onSelectSession(session),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.foreground,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${session.createdAt.month}月'
                            '${session.createdAt.day}日 · '
                            '${session.createdAt.hour.toString().padLeft(2, '0')}:'
                            '${session.createdAt.minute.toString().padLeft(2, '0')}',
                            style: ThemeV2Typography.mono(
                              color: tokens.muted,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ThemeV2IconButton(
                  semanticLabel: '删除 ${session.title}',
                  icon: Icons.delete_outline_rounded,
                  color: tokens.muted,
                  onPressed: () => _delete(session),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
