import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../render/render_spec.dart';
import '../../render/skill_card.dart';
import 'capture_session_controller.dart';
import '../session/theme_v2_session_page.dart';

/// Owns the Theme V2 capture-to-session adapter for one notification target.
class CaptureSessionPage extends StatefulWidget {
  const CaptureSessionPage({super.key, required this.recordingId});

  final String recordingId;

  @override
  State<CaptureSessionPage> createState() => _CaptureSessionPageState();
}

class _CaptureSessionPageState extends State<CaptureSessionPage> {
  late final CaptureSessionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CaptureSessionController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        readOnly: true,
        emptyOpener: '正在载入闪念…',
      ),
    );
  }
}
