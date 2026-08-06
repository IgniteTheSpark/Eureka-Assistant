import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../pet/floating_mascot.dart'
    show mascotSuppressed, releaseMascotSuppress;
import '../../timeline/timeline.dart' show eventAssetIcon;
import '../foundation/theme_v2_motion.dart';
import '../foundation/canonical_entity_identity.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';

enum CalendarSkillKind { event, contact, asset }

@immutable
class CalendarSkillOption {
  const CalendarSkillOption.event()
    : kind = CalendarSkillKind.event,
      name = 'event',
      displayName = '日程',
      icon = eventAssetIcon,
      accentColor = 'purple',
      userSkillId = null,
      payloadSchema = const {},
      renderSpecData = const {};

  const CalendarSkillOption.contact({
    required this.displayName,
    required this.icon,
    required this.userSkillId,
    this.accentColor = 'neutral',
    this.payloadSchema = const {},
    this.renderSpecData = const {},
  }) : kind = CalendarSkillKind.contact,
       name = 'contact';

  const CalendarSkillOption.asset({
    required this.name,
    required this.displayName,
    required this.icon,
    required this.userSkillId,
    this.accentColor = 'gray',
    this.payloadSchema = const {},
    this.renderSpecData = const {},
  }) : kind = CalendarSkillKind.asset;

  final CalendarSkillKind kind;
  final String name;
  final String displayName;
  final String icon;
  final String accentColor;
  final String? userSkillId;
  final Map<String, dynamic> payloadSchema;
  final Map<String, dynamic> renderSpecData;
}

@immutable
class CalendarSkillCatalog {
  const CalendarSkillCatalog({
    required this.options,
    this.recentNames = const [],
    this.recentUnavailable = false,
  });

  final List<CalendarSkillOption> options;
  final List<String> recentNames;
  final bool recentUnavailable;
}

typedef CalendarSkillLoader = Future<CalendarSkillCatalog> Function();

List<CalendarSkillOption> parseCalendarSkillOptions(Object? response) {
  final rawSkills = response is List
      ? response
      : ((response is Map ? response['skills'] : null) as List? ?? const []);
  final options = <CalendarSkillOption>[const CalendarSkillOption.event()];
  for (final raw in rawSkills.whereType<Map>()) {
    final name =
        raw['name']?.toString().trim() ??
        raw['machine_name']?.toString().trim() ??
        '';
    if (name.isEmpty ||
        name == 'qa' ||
        name == 'external_ref' ||
        raw['enabled'] == 0 ||
        raw['enabled'] == false ||
        raw['deprecated'] == true ||
        raw['deprecated'] == 1) {
      continue;
    }
    final renderSpec =
        (raw['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payloadSchema = _calendarPayloadSchema(raw);
    final displayName = raw['display_name']?.toString().trim();
    final userSkillId =
        raw['user_skill_id']?.toString() ?? raw['id']?.toString();
    final icon = resolveEntityIcon(
      name,
      configuredIcon: renderSpec['icon']?.toString(),
    );
    final accent = renderSpec['accent_color']?.toString() ?? 'gray';
    if (name == 'contact') {
      options.add(
        CalendarSkillOption.contact(
          displayName: displayName?.isNotEmpty == true ? displayName! : '联系人',
          icon: icon,
          userSkillId: userSkillId,
          accentColor: accent,
          payloadSchema: payloadSchema,
          renderSpecData: renderSpec,
        ),
      );
    } else {
      options.add(
        CalendarSkillOption.asset(
          name: name,
          displayName: displayName?.isNotEmpty == true ? displayName! : name,
          icon: icon,
          userSkillId: userSkillId,
          accentColor: accent,
          payloadSchema: payloadSchema,
          renderSpecData: renderSpec,
        ),
      );
    }
  }
  return List.unmodifiable(options);
}

Map<String, dynamic> _calendarPayloadSchema(Map raw) {
  final legacy = (raw['payload_schema'] as Map?)?.cast<String, dynamic>();
  if (legacy != null) return legacy;
  final schema = (raw['schema'] as Map?)?.cast<String, dynamic>() ?? const {};
  final properties =
      (schema['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
  final required = (schema['required'] as List? ?? const [])
      .map((value) => value.toString())
      .toSet();
  return {
    for (final entry in properties.entries)
      entry.key: _calendarFieldMetadata(entry.key, entry.value, required),
  };
}

Map<String, dynamic> _calendarFieldMetadata(
  String key,
  dynamic raw,
  Set<String> required,
) {
  final metadata = (raw as Map?)?.cast<String, dynamic>() ?? const {};
  return {
    ...metadata,
    'type': switch (metadata['format']?.toString()) {
      'date' => 'date',
      'date-time' => 'datetime',
      'uuid' => 'uuid',
      _ => metadata['type']?.toString() ?? 'string',
    },
    'label': metadata['title']?.toString() ?? key,
    'required': required.contains(key),
    'long': metadata['x-long'] == true,
  };
}

List<String> parseRecentManualSkillNames(Object? response) {
  final rawNames =
      (response is Map ? response['skill_names'] : null) as List? ?? const [];
  final names = <String>[];
  final seen = <String>{};
  for (final raw in rawNames) {
    final name = raw?.toString().trim() ?? '';
    if (name.isEmpty || !seen.add(name)) continue;
    names.add(name);
    if (names.length == 4) break;
  }
  return List.unmodifiable(names);
}

List<CalendarSkillOption> _recentSkillOptions(CalendarSkillCatalog catalog) {
  final byName = {for (final option in catalog.options) option.name: option};
  final recent = <CalendarSkillOption>[];
  final seen = <String>{};
  for (final name in catalog.recentNames.take(4)) {
    if (!seen.add(name)) continue;
    final option = byName[name];
    if (option != null) recent.add(option);
  }
  return List.unmodifiable(recent);
}

Future<CalendarSkillCatalog> fetchCalendarSkillCatalog(ApiClient api) async {
  final options = parseCalendarSkillOptions(
    await api.getJson('/api/user-skills'),
  );
  try {
    return CalendarSkillCatalog(
      options: options,
      recentNames: parseRecentManualSkillNames(
        await api.getJson('/api/user-skills/recent-manual'),
      ),
    );
  } catch (_) {
    return CalendarSkillCatalog(options: options, recentUnavailable: true);
  }
}

Future<CalendarSkillOption?> showCalendarManualRecordPicker(
  BuildContext context, {
  required DateTime effectiveDate,
  required CalendarSkillLoader loader,
}) async {
  final duration = ThemeV2Motion.duration(context, ThemeV2MotionToken.standard);
  mascotSuppressed.value++;
  try {
    return await showGeneralDialog<CalendarSkillOption>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '手动记录',
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      pageBuilder: (dialogContext, _, _) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: CalendarManualRecordPicker(
                  effectiveDate: effectiveDate,
                  loader: loader,
                  onSelected: (option) =>
                      Navigator.of(dialogContext).pop(option),
                  onClose: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: ThemeV2Motion.easeFluid,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    releaseMascotSuppress();
  }
}

class CalendarManualRecordPicker extends StatefulWidget {
  const CalendarManualRecordPicker({
    super.key,
    required this.effectiveDate,
    required this.loader,
    required this.onSelected,
    required this.onClose,
  });

  final DateTime effectiveDate;
  final CalendarSkillLoader loader;
  final ValueChanged<CalendarSkillOption> onSelected;
  final VoidCallback onClose;

  @override
  State<CalendarManualRecordPicker> createState() =>
      _CalendarManualRecordPickerState();
}

class _CalendarManualRecordPickerState
    extends State<CalendarManualRecordPicker> {
  late Future<CalendarSkillCatalog> _future = widget.loader();
  final FocusNode _titleFocus = FocusNode(debugLabel: 'Manual record title');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  void _retry() {
    final nextLoad = widget.loader();
    setState(() {
      _future = nextLoad;
    });
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final height = math.min(630.0, MediaQuery.sizeOf(context).height);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: '手动记录',
      child: Container(
        key: const ValueKey('calendar-manual-record-picker'),
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: tokens.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeV2Spacing.lg,
              ThemeV2Spacing.sm,
              ThemeV2Spacing.lg,
              ThemeV2Spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.border,
                      borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    ),
                  ),
                ),
                const SizedBox(height: ThemeV2Spacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Focus(
                        focusNode: _titleFocus,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '手动记录',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: tokens.foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(
                              '选择要记录的 Skill',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tokens.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ThemeV2IconButton(
                      semanticLabel: '关闭手动记录',
                      icon: Icons.close,
                      color: tokens.foreground,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                const SizedBox(height: ThemeV2Spacing.md),
                Expanded(
                  child: FutureBuilder<CalendarSkillCatalog>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _PickerError(onRetry: _retry);
                      }
                      if (!snapshot.hasData) {
                        return const _PickerLoading();
                      }
                      return _PickerContent(
                        catalog: snapshot.data!,
                        onSelected: widget.onSelected,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerContent extends StatelessWidget {
  const _PickerContent({required this.catalog, required this.onSelected});

  final CalendarSkillCatalog catalog;
  final ValueChanged<CalendarSkillOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final recent = _recentSkillOptions(catalog);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('最近'),
        const SizedBox(height: ThemeV2Spacing.sm),
        if (catalog.recentUnavailable)
          const _RecentStatus('最近暂不可用')
        else if (recent.isEmpty)
          const _RecentStatus('暂无')
        else
          _RecentSkillRow(options: recent, onSelected: onSelected),
        const SizedBox(height: ThemeV2Spacing.lg),
        const _SectionLabel('全部 Skills'),
        const SizedBox(height: ThemeV2Spacing.sm),
        Expanded(
          child: Semantics(
            label: '全部 Skills，可滚动',
            container: true,
            child: _SkillGrid(
              key: const ValueKey('calendar-skill-all-scroll'),
              options: catalog.options,
              onSelected: onSelected,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentStatus extends StatelessWidget {
  const _RecentStatus(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
        ),
      ),
    );
  }
}

class _RecentSkillRow extends StatelessWidget {
  const _RecentSkillRow({required this.options, required this.onSelected});

  final List<CalendarSkillOption> options;
  final ValueChanged<CalendarSkillOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = ThemeV2Spacing.sm;
        final tileWidth = (constraints.maxWidth - gap * 3) / 4;
        return SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var index = 0; index < options.length; index++) ...[
                if (index > 0) const SizedBox(width: gap),
                SizedBox(
                  width: tileWidth,
                  child: _RecentSkillTile(
                    option: options[index],
                    onTap: () => onSelected(options[index]),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecentSkillTile extends StatelessWidget {
  const _RecentSkillTile({required this.option, required this.onTap});

  final CalendarSkillOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '手动记录：${option.displayName}',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
          child: InkWell(
            key: ValueKey('calendar-skill-recent-${option.name}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.xs,
                vertical: ThemeV2Spacing.xs,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(option.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 2),
                  Text(
                    option.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: ThemeV2Typography.mono(
        fontSize: 10,
        color: context.themeV2.muted,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _SkillGrid extends StatelessWidget {
  const _SkillGrid({
    super.key,
    required this.options,
    required this.onSelected,
  });

  final List<CalendarSkillOption> options;
  final ValueChanged<CalendarSkillOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 64,
        crossAxisSpacing: ThemeV2Spacing.sm,
        mainAxisSpacing: ThemeV2Spacing.sm,
      ),
      itemCount: options.length,
      itemBuilder: (context, index) => _SkillTile(
        option: options[index],
        onTap: () => onSelected(options[index]),
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({required this.option, required this.onTap});

  final CalendarSkillOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '手动记录：${option.displayName}',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
          child: InkWell(
            key: ValueKey('calendar-skill-${option.name}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: ThemeV2Sizes.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.md,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
              ),
              child: Row(
                children: [
                  Text(option.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: ThemeV2Spacing.md),
                  Expanded(
                    child: Text(
                      option.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.foreground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 64,
        crossAxisSpacing: ThemeV2Spacing.sm,
        mainAxisSpacing: ThemeV2Spacing.sm,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
          border: Border.all(color: tokens.border),
        ),
      ),
    );
  }
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Skill 加载失败',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: tokens.foreground),
          ),
          const SizedBox(height: ThemeV2Spacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
