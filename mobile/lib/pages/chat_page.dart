import 'package:flutter/material.dart';

import 'stub_surface.dart';

/// Agent chat surface (SSE streaming, cards, precipitate). E1 stub — wired to
/// the SSE /api/chat stream in E2.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubSurface(
      title: 'Agent',
      subtitle: '对话 · SSE 流式（E2 接入 /api/chat）',
      icon: Icons.auto_awesome_outlined,
    );
  }
}
