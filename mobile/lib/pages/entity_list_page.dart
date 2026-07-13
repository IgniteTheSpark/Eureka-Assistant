import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../widgets/skeleton_loader.dart';

/// A simple list of one first-class entity type (events / contacts / files),
/// fetched from [endpoint] and rendered as SkillCards. Opened by tapping a
/// 常驻 tile in the Library. Each card opens its detail sheet on tap.
class EntityListPage extends StatefulWidget {
  final String title;
  final String endpoint;
  final String listKey;
  final Map<String, dynamic> Function(Map<String, dynamic>) toCard;
  const EntityListPage({
    super.key,
    required this.title,
    required this.endpoint,
    required this.listKey,
    required this.toCard,
  });

  @override
  State<EntityListPage> createState() => _EntityListPageState();
}

class _EntityListPageState extends State<EntityListPage> {
  final _api = ApiClient();
  // Revision-keyed fetch (see LibraryPage) — re-fetches on any data change and
  // survives hot-reload (driven from build, not an initState listener).
  int _loadedRev = -1;
  Future<List<Map<String, dynamic>>>? _future;

  Future<List<Map<String, dynamic>>> _futureFor(int rev) {
    if (rev != _loadedRev || _future == null) {
      _loadedRev = rev;
      _future = _load();
    }
    return _future!;
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await _api.getJson(widget.endpoint);
    final list = (res is Map ? res[widget.listKey] : null) as List? ?? const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
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
        title: Text(
          widget.title,
          style: TextStyle(
            color: eu.textHi,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: dataRevision,
        builder: (context, rev, _) => FutureBuilder<List<Map<String, dynamic>>>(
          future: _futureFor(rev),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const USkeletonList(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                count: 7,
              );
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '加载失败：${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: eu.accentRed),
                  ),
                ),
              );
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return Center(
                child: Text('还没有内容', style: TextStyle(color: eu.textMid)),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              itemBuilder: (_, i) => SkillCard(
                widget.toCard(items[i]),
                layoutOverride: 'horizontal',
              ),
            );
          },
        ),
      ),
    );
  }
}
