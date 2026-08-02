import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../data_revision.dart';
import '../../render/skill_card.dart';
import '../../timeline/timeline.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../asset_detail/asset_detail_repository.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'asset/asset_list_page.dart';
import 'container_index.dart';
import 'create_skill_action.dart';
import 'library_components.dart';
import 'library_controller.dart';
import 'library_hub.dart';
import 'library_models.dart';
import 'library_navigation.dart';
import 'library_repository.dart';
import 'library_states.dart';
import 'pinned_configuration.dart';

class ThemeV2LibraryPage extends ConsumerStatefulWidget {
  const ThemeV2LibraryPage({
    super.key,
    this.controller,
    this.autoLoad = true,
    this.onOpenContainer,
    this.onOpenRecent,
    this.onCreateSkill,
    this.navigation,
  });

  final LibraryController? controller;
  final bool autoLoad;
  final LibraryContainerCallback? onOpenContainer;
  final ValueChanged<LibraryRecentAsset>? onOpenRecent;
  final VoidCallback? onCreateSkill;
  final LibraryNavigationController? navigation;

  @override
  ConsumerState<ThemeV2LibraryPage> createState() => _ThemeV2LibraryPageState();
}

class _ThemeV2LibraryPageState extends ConsumerState<ThemeV2LibraryPage> {
  ApiClient? _ownedApi;
  final ApiClient _detailApi = ApiClient();
  late final LibraryController _controller;
  late final bool _ownsController;
  late final LibraryNavigationController _navigation;
  late final bool _ownsNavigation;
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  LibraryContainerSummary? _selectedContainer;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    if (_ownsController) {
      final api = ApiClient();
      _ownedApi = api;
      _controller = LibraryController(
        repository: ApiLibraryRepository(api, coreRecordsOnly: true),
      );
    } else {
      _controller = widget.controller!;
    }
    _ownsNavigation = widget.navigation == null;
    _navigation = widget.navigation ?? LibraryNavigationController();
    if (widget.autoLoad) {
      dataRevision.addListener(_refresh);
      if (_controller.status == LibraryStatus.idle) {
        _controller.load();
      }
    }
  }

  @override
  void dispose() {
    if (widget.autoLoad) dataRevision.removeListener(_refresh);
    if (_ownsController) {
      _controller.dispose();
      _ownedApi?.close();
    }
    if (_ownsNavigation) _navigation.dispose();
    _detailApi.close();
    super.dispose();
  }

  void _refresh() => _controller.load();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _navigation]),
      builder: (context, _) {
        final status = _controller.status;
        final hasOverview = _controller.overview != null;
        if (status == LibraryStatus.loading && !hasOverview) {
          return PopScope(
            canPop: !_navigation.canPop,
            onPopInvokedWithResult: _handlePop,
            child: const ColoredBox(
              color: Colors.transparent,
              child: LibraryStateView.loading(),
            ),
          );
        }
        if (status == LibraryStatus.offline || status == LibraryStatus.error) {
          return PopScope(
            canPop: !_navigation.canPop,
            onPopInvokedWithResult: _handlePop,
            child: ColoredBox(
              color: context.themeV2.background,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 112),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: LibraryStateView.error(
                    offline: status == LibraryStatus.offline,
                    message: _controller.errorMessage,
                    onRetry: _controller.retry,
                  ),
                ),
              ),
            ),
          );
        }

        return PopScope(
          canPop: !_navigation.canPop,
          onPopInvokedWithResult: _handlePop,
          child: PageStorage(
            bucket: _pageStorageBucket,
            child: Stack(
              children: [
                Positioned.fill(child: _activeSurface()),
                if (status == LibraryStatus.loading)
                  const Positioned(
                    top: ThemeV2Spacing.sm,
                    left: ThemeV2Spacing.xl,
                    right: ThemeV2Spacing.xl,
                    child: _LibraryRefreshIndicator(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _activeSurface() => switch (_navigation.surface) {
    LibrarySurface.hub => LibraryHub(
      controller: _controller,
      onOpenContainer: widget.onOpenContainer ?? _openContainer,
      onOpenContainerIndex: () =>
          _navigation.open(LibrarySurface.containerIndex),
      onOpenAllContainers: () => _navigation.open(LibrarySurface.allContainers),
      onConfigurePinned: () =>
          _navigation.open(LibrarySurface.pinnedConfiguration),
      onCreateSkill: widget.onCreateSkill ?? _openCreateSkill,
      onOpenRecent: widget.onOpenRecent ?? _openRecent,
    ),
    LibrarySurface.containerIndex => ContainerIndex(
      controller: _controller,
      onBack: _navigation.back,
      onOpenContainer: widget.onOpenContainer ?? _openContainer,
      onOpenAllContainers: () => _navigation.open(LibrarySurface.allContainers),
      onCreateSkill: widget.onCreateSkill ?? _openCreateSkill,
    ),
    LibrarySurface.allContainers => AllContainers(
      controller: _controller,
      onBack: _navigation.back,
      onOpenContainer: widget.onOpenContainer ?? _openContainer,
      onCreateSkill: widget.onCreateSkill ?? _openCreateSkill,
    ),
    LibrarySurface.pinnedConfiguration => PinnedConfiguration(
      controller: _controller,
      onDone: _navigation.back,
      onCreateSkill: widget.onCreateSkill ?? _openCreateSkill,
    ),
    LibrarySurface.assetContainer => _assetContainerSurface(),
  };

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) _navigation.back();
  }

  void _openCreateSkill() {
    showThemeV2CreateSkillLaunch(context);
  }

  Future<void> _openRecent(LibraryRecentAsset item) async {
    await openAssetDetail(
      context,
      AssetEntityRef(kind: AssetEntityKind.asset, id: item.id),
      repository: ApiAssetDetailRepository(_detailApi, coreRecordsOnly: true),
    );
  }

  void _openContainer(LibraryContainerSummary container) {
    _selectedContainer = container;
    _navigation.open(LibrarySurface.assetContainer);
  }

  Widget _assetContainerSurface() {
    final container = _selectedContainer;
    if (container == null) {
      return const SizedBox.shrink();
    }
    switch (container.type) {
      case LibraryContainerType.event:
        return ThemeV2AssetListPage.entities(
          title: '事件档案',
          cardType: 'event',
          initialEntities: const [],
          api: _detailApi,
          coreRecordsOnly: true,
          onBack: _navigation.back,
          contentBottomPadding: ThemeV2Spacing.lg,
        );
      case LibraryContainerType.contact:
        return ThemeV2AssetListPage.entities(
          title: '人物索引',
          cardType: 'contact',
          initialEntities: const [],
          api: _detailApi,
          coreRecordsOnly: true,
          onBack: _navigation.back,
          contentBottomPadding: ThemeV2Spacing.lg,
        );
      case LibraryContainerType.todo:
      case LibraryContainerType.notes:
      case LibraryContainerType.custom:
        final meta = SkillMeta(
          container.mark,
          container.label,
          'gray',
          container.userSkillId,
        );
        return ThemeV2AssetListPage.assets(
          meta: meta,
          skillName: container.id,
          initialAssets: const [],
          specs: ref.read(renderSpecsProvider).valueOrNull ?? const {},
          api: _detailApi,
          coreRecordsOnly: true,
          onBack: _navigation.back,
          contentBottomPadding: ThemeV2Spacing.lg,
          onConfigureCard:
              container.type == LibraryContainerType.custom &&
                  container.userSkillId != null
              ? () => showThemeV2SkillConfigurationLaunch(
                  context,
                  userSkillId: container.userSkillId!,
                )
              : null,
        );
    }
  }
}

class _LibraryRefreshIndicator extends StatelessWidget {
  const _LibraryRefreshIndicator();

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '正在刷新资产库',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.surface,
          elevation: 2,
          shadowColor: tokens.foreground.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeV2Spacing.md,
              vertical: ThemeV2Spacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: ThemeV2Spacing.sm),
                Text(
                  '正在刷新资产库…',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
