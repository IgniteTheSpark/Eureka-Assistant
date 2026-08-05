import 'dart:async';

export 'session_controller.dart';

import 'package:flutter/material.dart';

import '../../assets/assets.dart';
import '../../chat/chat_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/eureka_colors.dart';
import '../../widgets/asset_picker.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'session_composer.dart';
import 'session_controller.dart';
import 'session_header.dart';
import 'session_history_drawer.dart';
import 'session_transcript.dart';
import 'unified_session_controller.dart';

enum SessionSurfaceState { loaded, analyzing, history, empty, error }

@immutable
class SessionViewState {
  const SessionViewState({
    required this.surface,
    required this.messages,
    required this.streaming,
    required this.error,
  });

  final SessionSurfaceState surface;
  final List<ChatMessage> messages;
  final bool streaming;
  final String? error;

  factory SessionViewState.resolve({
    required List<ChatMessage> messages,
    required bool streaming,
    required String? error,
    required bool historyOpen,
  }) {
    final normalizedError = error?.trim();
    final surface = historyOpen
        ? SessionSurfaceState.history
        : normalizedError != null && normalizedError.isNotEmpty
        ? SessionSurfaceState.error
        : streaming
        ? SessionSurfaceState.analyzing
        : messages.isEmpty
        ? SessionSurfaceState.empty
        : SessionSurfaceState.loaded;
    return SessionViewState(
      surface: surface,
      messages: List.unmodifiable(messages),
      streaming: streaming,
      error: normalizedError,
    );
  }
}

int sessionTurnCount(Iterable<ChatMessage> messages) {
  return messages.where((message) => message.isUser).length;
}

/// Standalone Session route: it deliberately has neither the global top
/// navigation nor the floating dock.
class ThemeV2SessionPage extends StatefulWidget {
  const ThemeV2SessionPage({
    super.key,
    this.controller,
    this.boundSessionId,
    this.subjectType,
    this.subjectId,
    this.subjectLabel,
    this.startBlank = false,
    this.initializeController = true,
    this.initialHistoryOpen = false,
    this.emptyOpener,
    this.emptyStarters = const [],
    this.focusedInputTurnId,
    this.readOnly = false,
    this.onBack,
    this.onNewConversation,
  });

  final ThemeV2SessionController? controller;
  final String? boundSessionId;
  final String? subjectType;
  final String? subjectId;
  final String? subjectLabel;
  final bool startBlank;
  final bool initializeController;
  final bool initialHistoryOpen;
  final String? emptyOpener;
  final List<String> emptyStarters;
  final String? focusedInputTurnId;
  final bool readOnly;
  final VoidCallback? onBack;
  final VoidCallback? onNewConversation;

  @override
  State<ThemeV2SessionPage> createState() => _ThemeV2SessionPageState();
}

class _ThemeV2SessionPageState extends State<ThemeV2SessionPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  late final ThemeV2SessionController _controller;
  UnifiedSessionController? _ownedController;
  late bool _historyOpen = widget.initialHistoryOpen;
  late String? _subjectLabel = widget.subjectLabel;
  final List<({String id, String label})> _contexts = [];
  var _sessionSelectionRevision = 0;

  @override
  void initState() {
    super.initState();
    final supplied = widget.controller;
    if (supplied is FlashSessionWorkflow) {
      _ownedController = UnifiedSessionController(
        flashController: supplied,
        ownsFlashController: false,
        initialSource: UnifiedSessionSource.flash,
      );
      _controller = _ownedController!;
    } else if (supplied != null) {
      _controller = supplied;
    } else {
      _ownedController = UnifiedSessionController();
      _controller = _ownedController!;
    }
    _contexts.addAll(_controller.contextAssets);
    _controller.addListener(_onControllerChanged);
    if (widget.initializeController) _initialize();
    if (widget.initialHistoryOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scaffoldKey.currentState?.openDrawer();
      });
    }
  }

  void _initialize() {
    if (widget.startBlank) return;
    final sessionId = widget.boundSessionId;
    if (sessionId != null && sessionId.isNotEmpty) {
      _ignoreErrors(_controller.loadSession(sessionId));
      return;
    }
    final subjectType = widget.subjectType;
    final subjectId = widget.subjectId;
    if (subjectType != null && subjectId != null) {
      _ignoreErrors(_controller.bindSubject(subjectType, subjectId));
      return;
    }
    _ignoreErrors(_controller.resumeLast());
  }

  void _ignoreErrors(Future<void> future) {
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final restored = _controller.contextAssets;
    _contexts
      ..clear()
      ..addAll(restored);
    setState(() {});
  }

  Future<void> _addContext() async {
    final taken = _contexts.map((context) => context.id).toSet();
    final picked = await showModalBottomSheet<List<AssetItem>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.themeV2.surface,
      builder: (_) => AssetPickerPanel(excludeIds: taken),
    );
    if (picked == null || picked.isEmpty) return;
    final ok = await _controller.attachContexts(
      picked.map((asset) => asset.id).toList(),
      labels: {for (final asset in picked) asset.id: asset.title},
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加资产失败，请重试')));
    }
  }

  Future<void> _precipitate(ChatMessage message, String skill) {
    final text = message.parts
        .whereType<TextPart>()
        .map((part) => part.text)
        .join();
    return _controller.precipitate(text, skill);
  }

  void _newConversation() {
    _sessionSelectionRevision++;
    _contexts.clear();
    _subjectLabel = null;
    final callback = widget.onNewConversation;
    if (callback != null) {
      callback();
    } else {
      _controller.reset();
    }
    if (mounted) setState(() {});
    if (_historyOpen) Navigator.of(context).maybePop();
  }

  Future<void> _selectSession(SessionInfo session) async {
    final revision = ++_sessionSelectionRevision;
    try {
      await _controller.loadSession(session.id, title: session.title);
    } catch (_) {
      if (mounted && revision == _sessionSelectionRevision) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('会话加载失败，请重试')));
      }
      return;
    }
    if (!mounted || revision != _sessionSelectionRevision) return;
    _subjectLabel = null;
    if (_historyOpen) Navigator.of(context).pop();
  }

  void _back() {
    final callback = widget.onBack;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _ownedController?.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambient = Theme.of(context);
    var theme = buildThemeV2Theme(ambient.brightness);
    final fallbackPalette = ambient.brightness == Brightness.dark
        ? EurekaColors.dark
        : EurekaColors.light;
    final legacy =
        ambient.extension<EurekaTheme>() ?? EurekaTheme(fallbackPalette);
    theme = theme.copyWith(extensions: [...theme.extensions.values, legacy]);
    return Theme(
      data: theme,
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final state = SessionViewState.resolve(
      messages: _controller.messages,
      streaming: _controller.streaming,
      error: _controller.error,
      historyOpen: _historyOpen,
    );
    final title = _subjectLabel?.trim().isNotEmpty == true
        ? _subjectLabel!.trim()
        : _controller.displayTitle;
    final activeController = _controller;
    final turnCount = activeController is SessionTurnCountSource
        ? (activeController as SessionTurnCountSource).sessionTurnCount
        : sessionTurnCount(state.messages);
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: context.themeV2.background,
      onDrawerChanged: (open) {
        if (_historyOpen != open) setState(() => _historyOpen = open);
      },
      drawer: widget.readOnly
          ? null
          : SessionHistoryDrawer(
              activeSessionId: _controller.sessionId,
              loadSessions: _controller.listSessions,
              deleteSession: _controller.deleteSession,
              onSelectSession: _selectSession,
              onNewSession: _newConversation,
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SessionHeader(
              title: title,
              turnCount: turnCount,
              onBack: _back,
              onNewSession: widget.readOnly ? null : _newConversation,
              onOpenHistory: widget.readOnly
                  ? null
                  : () => _scaffoldKey.currentState?.openDrawer(),
            ),
            if (_subjectLabel != null || _contexts.isNotEmpty)
              _SessionContextRail(
                subjectLabel: _subjectLabel,
                contexts: _contexts,
              ),
            Expanded(
              child: SessionTranscript(
                messages: state.messages,
                turnCount: turnCount,
                analyzing: state.surface == SessionSurfaceState.analyzing,
                error: state.error,
                onRetry: () => unawaited(_controller.retryLastFailedTurn()),
                onKeepDraft: _inputFocusNode.requestFocus,
                onPrecipitate: _precipitate,
                onStarter: (text) => unawaited(_controller.send(text)),
                emptyOpener: widget.emptyOpener,
                emptyStarters: widget.emptyStarters,
                focusedInputTurnId: widget.focusedInputTurnId,
              ),
            ),
            if (!widget.readOnly)
              SessionComposer(
                controller: _inputController,
                focusNode: _inputFocusNode,
                streaming: state.streaming,
                onAddContext: () => unawaited(_addContext()),
                onSend: _controller.send,
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionContextRail extends StatelessWidget {
  const _SessionContextRail({
    required this.subjectLabel,
    required this.contexts,
  });

  final String? subjectLabel;
  final List<({String id, String label})> contexts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          if (subjectLabel != null)
            _ContextChip(label: subjectLabel!, accent: true),
          for (final item in contexts) _ContextChip(label: item.label),
        ],
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent ? tokens.accentSoft : tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
        border: Border.all(color: accent ? tokens.accent : tokens.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent ? tokens.foreground : tokens.muted,
          fontSize: 11,
        ),
      ),
    );
  }
}
