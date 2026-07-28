import 'package:flutter/material.dart';

import 'asset_detail_presentation.dart';
import 'asset_detail_sheet.dart';

/// Full-page chrome for an already-hydrated detail controller.
///
/// The controller is supplied by the sheet transition, so this page never owns
/// or re-fetches asset state.
class ThemeV2AssetDetailPage extends StatefulWidget {
  const ThemeV2AssetDetailPage({super.key, required this.controller});

  final AssetDetailController controller;

  @override
  State<ThemeV2AssetDetailPage> createState() => _ThemeV2AssetDetailPageState();
}

class _ThemeV2AssetDetailPageState extends State<ThemeV2AssetDetailPage> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.presentation !=
        AssetDetailPresentationKind.fullPage) {
      widget.controller.expand();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeV2AssetDetailSurface(widget.controller);
  }
}
