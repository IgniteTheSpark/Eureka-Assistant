import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/eureka_colors.dart';
import '../foundation/theme_v2_theme.dart';
import '../library/asset/asset_detail_presentation.dart';
import '../library/asset/asset_detail_sheet.dart';
import 'asset_detail_repository.dart';
import 'asset_entity_ref.dart';

Future<void> openAssetDetail(
  BuildContext context,
  AssetEntityRef ref, {
  AssetDetailRepository? repository,
  bool coreRecordsOnly = false,
  RekaOverdueReminderContext? overdueReminder,
}) async {
  ApiClient? ownedApi;
  final resolvedRepository =
      repository ??
      ApiAssetDetailRepository(
        ownedApi = ApiClient(),
        coreRecordsOnly: coreRecordsOnly,
      );
  final controller = AssetDetailController(
    repository: resolvedRepository,
    ref: ref,
  );
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final routeTheme = buildThemeV2Theme(Theme.of(sheetContext).brightness);
        final legacyColors = routeTheme.brightness == Brightness.dark
            ? EurekaColors.dark
            : EurekaColors.light;
        return Theme(
          data: routeTheme.copyWith(
            extensions: [
              ...routeTheme.extensions.values,
              EurekaTheme(legacyColors),
            ],
          ),
          child: ThemeV2AssetDetailSurface(
            controller,
            api: ownedApi,
            overdueReminder: overdueReminder,
          ),
        );
      },
    );
  } finally {
    controller.dispose();
    ownedApi?.close();
  }
}
