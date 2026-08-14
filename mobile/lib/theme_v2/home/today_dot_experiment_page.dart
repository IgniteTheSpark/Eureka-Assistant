import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data_revision.dart';
import '../../today/today_data.dart';
import '../foundation/theme_v2_motion.dart';
import '../foundation/theme_v2_theme.dart';
import '../shell/theme_v2_floating_dock.dart';
import '../shell/theme_v2_global_top_nav.dart';
import '../reka/reka_signal_actions.dart';
import 'home_agenda_panel.dart';
import 'home_repository.dart';
import 'today_dithered_reka_config.dart';
import 'today_output_coordinator.dart';
import 'today_reka_motion_controller.dart';
import 'today_reka_quick_actions.dart';
import 'today_reka_scene.dart';
import 'today_living_surface.dart';

class TodayDotExperimentPage extends StatefulWidget {
  const TodayDotExperimentPage({
    super.key,
    this.repository,
    this.onManualRecord,
    this.onCreateReport,
    this.onStartChat,
    this.onOpenReka,
    this.onOpenAssetLibrary,
    this.clock,
    this.now,
    this.active = true,
    this.rekaController,
    this.rekaConfig = const TodayDitheredRekaConfig(),
    this.rekaBuilder,
    this.extendUnderChrome = false,
  });

  static const scrollKey = ValueKey<String>('today-dot-experiment-scroll');

  final ThemeV2HomeRepository? repository;
  final VoidCallback? onManualRecord;
  final VoidCallback? onCreateReport;
  final VoidCallback? onStartChat;
  final VoidCallback? onOpenReka;
  final VoidCallback? onOpenAssetLibrary;
  final ValueListenable<DateTime>? clock;
  final DateTime? now;
  final bool active;
  final TodayRekaMotionController? rekaController;
  final TodayDitheredRekaConfig rekaConfig;
  final TodayRekaBuilder? rekaBuilder;
  final bool extendUnderChrome;

  @override
  State<TodayDotExperimentPage> createState() => _TodayDotExperimentPageState();
}

class _TodayDotExperimentPageState extends State<TodayDotExperimentPage> {
  late ThemeV2HomeRepository _repository;
  late bool _ownsRepository;
  Future<void>? _inflightRefresh;
  bool _refreshing = false;
  bool _refreshFailed = false;
  bool _menuExpanded = false;
  bool _agendaOpen = false;
  int _refreshSignal = 0;
  int _requestSerial = 0;
  TodayData? _data;
  bool _suppressProduction = true;
  late final TodayRekaMotionController _sceneRekaController =
      widget.rekaController ??
      TodayRekaMotionController(config: widget.rekaConfig);
  late final bool _ownsSceneRekaController = widget.rekaController == null;
  late final TodayOutputCoordinator _outputCoordinator =
      TodayOutputCoordinator();
  bool _outputRebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _installRepository(widget.repository);
    _outputCoordinator.addListener(_onOutputChanged);
    dataRevision.addListener(_onDataRevision);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(covariant TodayDotExperimentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _requestSerial++;
      _disposeOwnedRepository();
      _installRepository(widget.repository);
      _inflightRefresh = null;
      _refreshing = false;
      _refreshFailed = false;
      _data = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh());
      });
    }
  }

  void _installRepository(ThemeV2HomeRepository? repository) {
    _repository = repository ?? ApiThemeV2HomeRepository();
    _ownsRepository = repository == null;
  }

  void _disposeOwnedRepository() {
    if (_ownsRepository && _repository is ApiThemeV2HomeRepository) {
      (_repository as ApiThemeV2HomeRepository).dispose();
    }
  }

  void _onDataRevision() => unawaited(_refresh(suppressProduction: false));

  void _onOutputChanged() {
    if (_outputRebuildScheduled) return;
    _outputRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _outputRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh({bool suppressProduction = true}) {
    final inflight = _inflightRefresh;
    if (inflight != null) return inflight;
    final future = _performRefresh(suppressProduction: suppressProduction);
    _inflightRefresh = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_inflightRefresh, future)) _inflightRefresh = null;
      }),
    );
    return future;
  }

  Future<void> _performRefresh({required bool suppressProduction}) async {
    final serial = ++_requestSerial;
    if (mounted) {
      setState(() {
        _refreshing = true;
        _refreshFailed = false;
        _refreshSignal++;
      });
    }
    try {
      final loaded = await _repository.load();
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _data = loaded;
        _suppressProduction = suppressProduction;
        _refreshing = false;
        _refreshFailed = false;
      });
    } catch (_) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _refreshing = false;
        _refreshFailed = true;
      });
    }
  }

  Future<void> _openRekaSignal(TodayRekaItem item) async {
    await openRekaSignalTarget(
      context,
      item,
      repository: _repository is ApiThemeV2HomeRepository
          ? (_repository as ApiThemeV2HomeRepository).rekaSignals
          : null,
    );
    if (mounted) await _refresh();
  }

  Future<void> _openQuickActions(Rect anchor) async {
    setState(() => _menuExpanded = true);
    try {
      await showTodayRekaQuickActions(
        context,
        anchor: anchor,
        onManualRecord: widget.onManualRecord,
        onCreateReport: widget.onCreateReport,
        onStartChat: widget.onStartChat,
      );
    } finally {
      if (mounted) setState(() => _menuExpanded = false);
    }
  }

  void _openAgenda() => setState(() => _agendaOpen = true);

  void _closeAgenda() => setState(() => _agendaOpen = false);

  Widget _livingPresentation({
    required double topChromeInset,
    required double bottomChromeInset,
  }) {
    return LayoutBuilder(
      key: const ValueKey('today-living-presentation'),
      builder: (context, constraints) => TodayRekaScene(
        config: widget.rekaConfig,
        topChromeInset: topChromeInset,
        bottomChromeInset: bottomChromeInset,
        refreshSignal: _refreshSignal,
        menuExpanded: _menuExpanded,
        now: widget.now,
        active: widget.active,
        cue: _outputCoordinator.cue,
        controller: _sceneRekaController,
        rekaBuilder: widget.rekaBuilder,
        content: RefreshIndicator.noSpinner(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            key: TodayDotExperimentPage.scrollKey,
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Padding(
                padding: EdgeInsets.only(
                  top: topChromeInset,
                  bottom: bottomChromeInset,
                ),
                child: AnimatedBuilder(
                  animation: _sceneRekaController,
                  builder: (context, _) => TodayLivingSurface(
                    data: _data ?? TodayData.empty,
                    now: widget.now ?? DateTime.now(),
                    active: widget.active,
                    rekaCenter:
                        _sceneRekaController.rekaCenter -
                        Offset(0, topChromeInset),
                    suppressProduction: _suppressProduction,
                    outputCoordinator: _outputCoordinator,
                    onOpenSignal: _openRekaSignal,
                    onOpenReka: widget.onOpenReka,
                    onOpenAssetLibrary: widget.onOpenAssetLibrary,
                    onOpenAgenda: _openAgenda,
                    clock: widget.clock,
                  ),
                ),
              ),
            ),
          ),
        ),
        onRekaTap: (anchor) => unawaited(_openQuickActions(anchor)),
      ),
    );
  }

  Widget _agendaPresentation({
    required double topChromeInset,
    required double bottomChromeInset,
  }) {
    return LayoutBuilder(
      key: const ValueKey('today-agenda-presentation'),
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.only(
          top: topChromeInset,
          bottom: bottomChromeInset,
        ),
        child: SizedBox(
          width: constraints.maxWidth,
          height: 720,
          child: HomeAgendaPanel(
            data: _data ?? TodayData.empty,
            date: widget.now,
            onCloseAgenda: _closeAgenda,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestSerial++;
    dataRevision.removeListener(_onDataRevision);
    _disposeOwnedRepository();
    if (_ownsSceneRekaController) _sceneRekaController.dispose();
    _outputCoordinator.removeListener(_onOutputChanged);
    _outputCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final topChromeInset = widget.extendUnderChrome
        ? ThemeV2GlobalTopNav.floatingExtent
        : 0.0;
    final bottomChromeInset = widget.extendUnderChrome
        ? ThemeV2FloatingDock.contentClearance + bottomPadding
        : 0.0;
    return ColoredBox(
      color: context.themeV2.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
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
              child: _agendaOpen
                  ? _agendaPresentation(
                      topChromeInset: topChromeInset,
                      bottomChromeInset: bottomChromeInset,
                    )
                  : _livingPresentation(
                      topChromeInset: topChromeInset,
                      bottomChromeInset: bottomChromeInset,
                    ),
            ),
          ),
          if (_refreshing)
            Positioned(
              top: 0,
              left: 0,
              child: Semantics(
                label: '正在刷新今日',
                liveRegion: true,
                child: SizedBox.square(dimension: 1),
              ),
            ),
          if (_refreshFailed)
            Positioned(
              top: topChromeInset + 12,
              left: 18,
              right: 18,
              child: _RefreshFailure(onRetry: () => unawaited(_refresh())),
            ),
        ],
      ),
    );
  }
}

class _RefreshFailure extends StatelessWidget {
  const _RefreshFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.themeV2.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '刷新失败，已保留当前场景',
                style: TextStyle(
                  color: context.themeV2.foreground,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
