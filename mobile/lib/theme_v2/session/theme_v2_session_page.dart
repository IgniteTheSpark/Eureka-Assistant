import 'dart:async';

import 'package:flutter/material.dart';

import '../../assets/assets.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/eureka_colors.dart';
import '../../widgets/asset_picker.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'session_composer.dart';
import 'session_header.dart';
import 'session_history_drawer.dart';
import 'session_transcript.dart';

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

/// Testable contract between the Theme V2 view and the mature chat engine.
///
/// Production uses [ChatControllerSessionAdapter]; tests can provide an
/// in-memory implementation without replacing any streaming or API rules.
abstract interface class ThemeV2SessionController implements Listenable {
  List<ChatMessage> get messages;
  bool get streaming;
  String? get error;
  String? get sessionId;
  String get displayTitle;
  List<({String id, String label})> get contextAssets;

  Future<void> resumeLast();
  Future<void> bindSubject(String type, String id);
  Future<void> loadSession(String id, {String? title});
  Future<List<SessionInfo>> listSessions();
  Future<bool> deleteSession(String id);
  Future<void> send(String text);
  Future<void> retryLastFailedTurn();
  Future<void> precipitate(String text, String skill);
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels,
  });
  void reset();
}

class ChatControllerSessionAdapter extends ChangeNotifier
    implements ThemeV2SessionController {
  ChatControllerSessionAdapter(this.chat, {this.ownsChat = false}) {
    chat.addListener(_forward);
  }

  final ChatController chat;
  final bool ownsChat;
  var _disposed = false;

  void _forward() {
    if (!_disposed) notifyListeners();
  }

  @override
  List<ChatMessage> get messages => chat.messages;

  @override
  bool get streaming => chat.streaming;

  @override
  String? get error => chat.error;

  @override
  String? get sessionId => chat.sessionId;

  @override
  String get displayTitle => chat.displayTitle;

  @override
  List<({String id, String label})> get contextAssets => chat.contextAssets;

  @override
  Future<bool> attachContexts(
    List<String> assetIds, {
    Map<String, String> labels = const {},
  }) => chat.attachContexts(assetIds, labels: labels);

  @override
  Future<void> bindSubject(String type, String id) =>
      chat.bindSubject(type, id);

  @override
  Future<bool> deleteSession(String id) => chat.deleteSession(id);

  @override
  Future<void> loadSession(String id, {String? title}) =>
      chat.loadSession(id, title: title);

  @override
  Future<List<SessionInfo>> listSessions() => chat.listSessions();

  @override
  Future<void> precipitate(String text, String skill) =>
      chat.precipitate(text, skill);

  @override
  void reset() => chat.reset();

  @override
  Future<void> resumeLast() => chat.resumeLast();

  @override
  Future<void> retryLastFailedTurn() => chat.retryLastFailedTurn();

  @override
  Future<void> send(String text) => chat.send(text);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    chat.removeListener(_forward);
    if (ownsChat) chat.dispose();
    super.dispose();
  }
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
  ChatControllerSessionAdapter? _ownedAdapter;
  late bool _historyOpen = widget.initialHistoryOpen;
  late String? _subjectLabel = widget.subjectLabel;
  final List<({String id, String label})> _contexts = [];
  var _sessionSelectionRevision = 0;

  @override
  void initState() {
    super.initState();
    final supplied = widget.controller;
    if (supplied != null) {
      _controller = supplied;
    } else {
      _ownedAdapter = ChatControllerSessionAdapter(
        ChatController(),
        ownsChat: true,
      );
      _controller = _ownedAdapter!;
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
    _ownedAdapter?.dispose();
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
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: context.themeV2.background,
      onDrawerChanged: (open) {
        if (_historyOpen != open) setState(() => _historyOpen = open);
      },
      drawer: SessionHistoryDrawer(
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
              messageCount: state.messages.length,
              onBack: _back,
              onNewSession: _newConversation,
              onOpenHistory: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            if (_subjectLabel != null || _contexts.isNotEmpty)
              _SessionContextRail(
                subjectLabel: _subjectLabel,
                contexts: _contexts,
              ),
            Expanded(
              child: SessionTranscript(
                messages: state.messages,
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
