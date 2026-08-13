import 'dart:async';

import 'package:flutter/material.dart';

import 'home_repository.dart';
import 'today_dot_field_controller.dart';
import 'today_dot_field_simulation.dart';
import 'today_dot_matrix_painter.dart';
import 'today_dot_matrix_scene.dart';
import 'today_reka_quick_actions.dart';

class TodayDotExperimentPage extends StatefulWidget {
  const TodayDotExperimentPage({
    super.key,
    this.repository,
    this.onCreateAsset,
    this.onCreateReport,
    this.onStartChat,
    this.now,
    this.active = true,
    this.sceneController,
    this.sceneSimulation,
  });

  static const scrollKey = ValueKey<String>('today-dot-experiment-scroll');

  final ThemeV2HomeRepository? repository;
  final VoidCallback? onCreateAsset;
  final VoidCallback? onCreateReport;
  final VoidCallback? onStartChat;
  final DateTime? now;
  final bool active;
  final TodayDotFieldController? sceneController;
  final TodayDotFieldSimulation? sceneSimulation;

  @override
  State<TodayDotExperimentPage> createState() => _TodayDotExperimentPageState();
}

class _TodayDotExperimentPageState extends State<TodayDotExperimentPage>
    with SingleTickerProviderStateMixin {
  late ThemeV2HomeRepository _repository;
  late bool _ownsRepository;
  late final AnimationController _refreshEmphasis = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Future<void>? _inflightRefresh;
  bool _refreshing = false;
  bool _refreshFailed = false;
  bool _menuExpanded = false;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _installRepository(widget.repository);
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

  Future<void> _refresh() {
    final inflight = _inflightRefresh;
    if (inflight != null) return inflight;
    final future = _performRefresh();
    _inflightRefresh = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_inflightRefresh, future)) _inflightRefresh = null;
      }),
    );
    return future;
  }

  Future<void> _performRefresh() async {
    final serial = ++_requestSerial;
    if (mounted) {
      setState(() {
        _refreshing = true;
        _refreshFailed = false;
      });
    }
    try {
      await _repository.load();
      if (!mounted || serial != _requestSerial) return;
      setState(() {
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

  void _handleRefreshStatus(RefreshIndicatorStatus? status) {
    switch (status) {
      case RefreshIndicatorStatus.drag:
      case RefreshIndicatorStatus.armed:
      case RefreshIndicatorStatus.snap:
      case RefreshIndicatorStatus.refresh:
        _refreshEmphasis.animateTo(
          1,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      case RefreshIndicatorStatus.done:
      case RefreshIndicatorStatus.canceled:
      case null:
        _refreshEmphasis.animateBack(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
    }
  }

  Future<void> _openQuickActions(Rect anchor) async {
    setState(() => _menuExpanded = true);
    try {
      await showTodayRekaQuickActions(
        context,
        anchor: anchor,
        onCreateAsset: widget.onCreateAsset,
        onCreateReport: widget.onCreateReport,
        onStartChat: widget.onStartChat,
      );
    } finally {
      if (mounted) setState(() => _menuExpanded = false);
    }
  }

  @override
  void dispose() {
    _requestSerial++;
    _refreshEmphasis.dispose();
    _disposeOwnedRepository();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TodayDotMatrixPalette.light.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => RefreshIndicator.noSpinner(
                onRefresh: _refresh,
                onStatusChange: _handleRefreshStatus,
                child: SingleChildScrollView(
                  key: TodayDotExperimentPage.scrollKey,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: AnimatedBuilder(
                      animation: _refreshEmphasis,
                      builder: (context, _) => TodayDotMatrixScene(
                        refreshEmphasis: _refreshEmphasis.value,
                        menuExpanded: _menuExpanded,
                        now: widget.now,
                        active: widget.active,
                        controller: widget.sceneController,
                        simulation: widget.sceneSimulation,
                        onRekaTap: (anchor) =>
                            unawaited(_openQuickActions(anchor)),
                      ),
                    ),
                  ),
                ),
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
              top: 12,
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
      color: const Color(0xFFF2F5F2),
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
                  color: TodayDotMatrixPalette.light.foreground,
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
