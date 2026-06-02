import 'package:flutter/material.dart';

import '../assets/assets.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline.dart';

/// Assets of one skill category. Tap a row to inspect its payload.
class CategoryDetailPage extends StatelessWidget {
  final SkillMeta meta;
  final List<AssetItem> assets;
  const CategoryDetailPage({super.key, required this.meta, required this.assets});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final sorted = [...assets]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: Text('${meta.icon} ${meta.label}'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final a = sorted[i];
          return GestureDetector(
            onTap: () => _showSheet(context, a),
            child: SkillCard({
              'user_skill_name': a.skillName,
              'payload': a.payload,
              'asset_id': a.id,
            }),
          );
        },
      ),
    );
  }

  void _showSheet(BuildContext context, AssetItem a) {
    final eu = context.eu;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: eu.surface,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${meta.icon} ${meta.label}',
                  style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final e in a.payload.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(e.key,
                            style: TextStyle(color: eu.textLo, fontSize: 13)),
                      ),
                      Expanded(
                        child: Text('${e.value}',
                            style: TextStyle(color: eu.text, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
