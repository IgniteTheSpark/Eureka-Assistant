import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../pages/chat_page.dart';
import '../../render/render_spec.dart';
import '../../render/skill_card.dart';
import '../session/theme_v2_session_page.dart';
import 'capture_session_controller.dart';

/// Owns the Theme V2 capture-to-session adapter for one notification target.
class CaptureSessionPage extends StatefulWidget {
  const CaptureSessionPage({
    super.key,
    required this.recordingId,
    this.focusedInputTurnId,
    this.controller,
    this.newConversationBuilder,
  });

  final String recordingId;
  final String? focusedInputTurnId;
  final ThemeV2SessionController? controller;
  final WidgetBuilder? newConversationBuilder;

  @override
  State<CaptureSessionPage> createState() => _CaptureSessionPageState();
}

class _CaptureSessionPageState extends State<CaptureSessionPage> {
  late final ThemeV2SessionController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? CaptureSessionController();
  }

  @override
  void dispose() {
    if (_ownsController && _controller is ChangeNotifier) {
      (_controller as ChangeNotifier).dispose();
    }
    super.dispose();
  }

  void _newConversation() {
    final destination = widget.newConversationBuilder;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder:
            destination ??
            (_) => const ChatPage(startBlank: true, themeV2Override: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        renderSpecsProvider.overrideWith((ref) async {
          final api = ApiClient();
          try {
            return await fetchRenderSpecs(api, coreRecordsOnly: true);
          } finally {
            api.close();
          }
        }),
      ],
      child: ThemeV2SessionPage(
        controller: _controller,
        boundSessionId: widget.recordingId,
        focusedInputTurnId: widget.focusedInputTurnId,
        readOnly: false,
        emptyOpener: '正在载入闪念…',
        onNewConversation: _newConversation,
      ),
    );
  }
}
