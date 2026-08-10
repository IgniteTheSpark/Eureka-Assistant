import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data_revision.dart';
import '../../today/today_data.dart';
import '../foundation/theme_v2_motion.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../reka/reka_signal_actions.dart';
import '../reka/reka_signal_repository.dart';
import '../shell/theme_v2_async_state.dart';
import '../shell/theme_v2_page_title.dart';
import 'home_agenda_panel.dart';
import 'home_controller.dart';
import 'home_repository.dart';
import 'home_today_panel.dart';

class ThemeV2HomePage extends StatefulWidget {
  const ThemeV2HomePage({
    super.key,
    this.controller,
    this.repository,
    this.now,
    this.active = true,
    this.onOpenReka,
    this.rekaSignals,
    this.onRekaAction,
    this.onOpenRekaTarget,
    this.onOpenReports,
    this.onCreateReport,
  });

  static const panelKey = ValueKey<String>('theme-v2-home-panel');

  final ThemeV2HomeController? controller;
  final ThemeV2HomeRepository? repository;
  final bool active;
  final VoidCallback? onOpenReka;
  final RekaSignalRepository? rekaSignals;
  final RekaSignalMutationCallback? onRekaAction;
  final RekaSignalTargetCallback? onOpenRekaTarget;
  final VoidCallback? onOpenReports;
  final VoidCallback? onCreateReport;

  /// Deterministic clock seam for visual tests. Production uses local time.
  final DateTime? now;

  @override
  State<ThemeV2HomePage> createState() => _ThemeV2HomePageState();
}

class _ThemeV2HomePageState extends State<ThemeV2HomePage> {
  late ThemeV2HomeController _controller;
  late bool _ownsController;
  late ThemeV2HomeRepository _repository;
  late bool _ownsRepository;

  TodayData? _data;
  bool _loading = true;
  bool _refreshing = false;
  bool _refreshFailed = false;
  int _requestSerial = 0;
  final Set<String> _rekaMutations = <String>{};

  @override
  void initState() {
    super.initState();
    _installController(widget.controller);
    _installRepository(widget.repository);
    dataRevision.addListener(_onDataRevision);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ThemeV2HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _controller.removeListener(_onPresentationChanged);
      if (_ownsController) _controller.dispose();
      _installController(widget.controller);
    }
    if (!identical(oldWidget.repository, widget.repository)) {
      _disposeOwnedRepository();
      _installRepository(widget.repository);
      _data = null;
      _loading = true;
      unawaited(_load());
    }
  }

  void _installController(ThemeV2HomeController? controller) {
    _controller = controller ?? ThemeV2HomeController();
    _ownsController = controller == null;
    _controller.addListener(_onPresentationChanged);
  }

  void _installRepository(ThemeV2HomeRepository? repository) {
    _repository = repository ?? ApiThemeV2HomeRepository();
    _ownsRepository = repository == null;
  }

  RekaSignalRepository? get _rekaSignals =>
      widget.rekaSignals ??
      (_repository is ApiThemeV2HomeRepository
          ? (_repository as ApiThemeV2HomeRepository).rekaSignals
          : null);

  Future<void> _mutateReka(TodayRekaItem item, String action) async {
    if (!_rekaMutations.add(item.id)) return;
    try {
      final callback = widget.onRekaAction;
      if (callback != null) {
        await callback(item, action);
      } else {
        final repository = _rekaSignals;
        if (repository == null) return;
        switch (action) {
          case 'complete':
            await repository.completeTodo(item.targetId);
          case 'dismiss':
            await repository.dismiss(item.id);
          default:
            return;
        }
      }
      if (!mounted) return;
      final current = _data;
      if (current != null) {
        setState(() {
          _data = current.withRekaQueue(
            current.rekaQueue
                .where((candidate) => candidate.id != item.id)
                .toList(growable: false),
          );
        });
      }
      if (callback == null) bumpData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
    } finally {
      _rekaMutations.remove(item.id);
    }
  }

  void _disposeOwnedRepository() {
    if (_ownsRepository && _repository is ApiThemeV2HomeRepository) {
      (_repository as ApiThemeV2HomeRepository).dispose();
    }
  }

  void _onPresentationChanged() {
    if (mounted) setState(() {});
  }

  void _onDataRevision() => unawaited(_load());

  Future<void> _load() async {
    final serial = ++_requestSerial;
    if (mounted) {
      setState(() {
        _refreshFailed = false;
        if (_data == null) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    }
    try {
      final result = await _repository.load();
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _data = result;
        _loading = false;
        _refreshing = false;
        _refreshFailed = false;
      });
    } catch (_) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (_data == null) {
          // `_loading == false` selects the initial error state below.
        } else {
          _refreshFailed = true;
        }
      });
    }
  }

  @override
  void dispose() {
    _requestSerial++;
    dataRevision.removeListener(_onDataRevision);
    _controller.removeListener(_onPresentationChanged);
    if (_ownsController) _controller.dispose();
    _disposeOwnedRepository();
    super.dispose();
  }

  Widget _content({required double chamberHeight}) {
    final data = _data;
    if (data == null) {
      return SizedBox(
        height: 340,
        child: _loading
            ? const ThemeV2AsyncState.loading(label: '正在加载今日')
            : ThemeV2AsyncState.error(
                title: '今日加载失败',
                message: '请检查网络后重试',
                onRetry: () => unawaited(_load()),
              ),
      );
    }

    final panel = switch (_controller.presentation) {
      HomePresentation.today => HomeTodayPanel(
        key: const ValueKey(HomePresentation.today),
        data: data,
        date: widget.now,
        active: widget.active,
        chamberHeight: chamberHeight,
        onOpenAgenda: _controller.openAgenda,
        onOpenReka: widget.onOpenReka,
        onRekaAction: _mutateReka,
        onOpenRekaTarget: widget.onOpenRekaTarget,
        onOpenReports: widget.onOpenReports,
        onCreateReport: widget.onCreateReport,
      ),
      HomePresentation.agenda => SizedBox(
        height: 720,
        child: HomeAgendaPanel(
          key: const ValueKey(HomePresentation.agenda),
          data: data,
          date: widget.now,
          onCloseAgenda: _controller.closeAgenda,
        ),
      ),
    };

    return Stack(
      children: [
        AnimatedSwitcher(
          duration: ThemeV2Motion.duration(
            context,
            ThemeV2MotionToken.standard,
          ),
          switchInCurve: ThemeV2Motion.easeFluid,
          switchOutCurve: ThemeV2Motion.easeFluid,
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0, 0.018),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: panel,
        ),
        if (_refreshing)
          const Positioned(
            top: 0,
            left: 18,
            right: 18,
            child: _RefreshIndicator(),
          ),
        if (_refreshFailed)
          Positioned(
            top: 12,
            left: 20,
            right: 20,
            child: _RefreshFailure(onRetry: () => unawaited(_load())),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(0, constraints.maxWidth - 36);
        final columns = math.max(1, (contentWidth / 44).floor());
        final visibleCount = math.min(_data?.pool.length ?? 0, 50);
        final rows = (visibleCount + columns - 1) ~/ columns;
        final chamberHeight = math.max(340.0, rows * 44.0);
        return SingleChildScrollView(
          key: ThemeV2HomePage.panelKey,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ThemeV2PageTitle(
                key: ValueKey('theme-v2-page-title-home'),
                title: '今日',
              ),
              const SizedBox(height: 14),
              _content(chamberHeight: chamberHeight),
            ],
          ),
        );
      },
    );
  }
}

class _RefreshIndicator extends StatelessWidget {
  const _RefreshIndicator();

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '正在刷新今日',
      liveRegion: true,
      child: ExcludeSemantics(
        child: LinearProgressIndicator(
          minHeight: 2,
          color: tokens.accent,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}

class _RefreshFailure extends StatelessWidget {
  const _RefreshFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(ThemeV2Radii.md),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '刷新失败',
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: tokens.critical),
              const SizedBox(width: ThemeV2Spacing.sm),
              const Expanded(child: Text('刷新失败，已保留原有内容')),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
