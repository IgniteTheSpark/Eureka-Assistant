import 'package:flutter/material.dart';

import 'notifications_page.dart';
import 'stub_surface.dart';

/// Library surface (asset categories + detail + AddSkillWizard). E1 stub —
/// wired to /api/skills + /api/assets in E2.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubSurface(
      title: '资产库',
      subtitle: '类目 / 资产 / 技能（E2 接入 /api/skills · /api/assets）',
      icon: Icons.grid_view_outlined,
      actions: [NotificationsBell()],
    );
  }
}
