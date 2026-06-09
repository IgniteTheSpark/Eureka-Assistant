import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// §9 球球 — renders the pet (or its pre-hatch egg) in a transparent WebView by
/// inlining the design engine (`pixel.js` + `mascot.js`) + the genome into
/// `assets/pet_render.html`. Same inline-asset pattern as the report viewer's
/// GSAP. Prop-driven: change [genome]/[state]/[egg] and it re-renders.
///
/// [genome] keys: skin, emblem, emblemColor, head, leftItem, rightItem.
/// [state]: idle | listen | celebrate | sleep.
class PetView extends StatefulWidget {
  final Map<String, dynamic> genome;
  final double scale;
  final String state;
  final bool egg;

  /// Bump this (e.g. on tap / a fresh drop) to fire the celebrate animation
  /// without reloading the canvas. Ignored for eggs.
  final int celebrateSignal;

  const PetView({
    super.key,
    required this.genome,
    this.scale = 6,
    this.state = 'idle',
    this.egg = false,
    this.celebrateSignal = 0,
  });

  @override
  State<PetView> createState() => _PetViewState();
}

class _PetViewState extends State<PetView> {
  late final WebViewController _c;
  static String? _pixel, _mascot, _tmpl;   // cached engine assets (load once)

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));   // transparent — sits over the app
    _load();
  }

  Future<void> _load() async {
    _pixel ??= await rootBundle.loadString('assets/js/pixel.js');
    _mascot ??= await rootBundle.loadString('assets/js/mascot.js');
    _tmpl ??= await rootBundle.loadString('assets/pet_render.html');
    if (!mounted) return;
    await _c.loadHtmlString(_buildHtml());
  }

  String _buildHtml() {
    final g = <String, dynamic>{
      ...widget.genome,
      'scale': widget.scale,
      'state': widget.state,
      if (widget.egg) 'egg': true,
    };
    // NOTE: consume the trailing ` {}` default too — otherwise the injected JSON
    // sits next to it (`= {json} {}`) and that's a SyntaxError that kills the
    // whole bootstrap script (pet renders blank). Unreplaced it stays `= {};`.
    return _tmpl!
        .replaceFirst('/*__PIXEL_JS__*/', _pixel!)
        .replaceFirst('/*__MASCOT_JS__*/', _mascot!)
        .replaceFirst('/*__GENOME_JSON__*/ {}', jsonEncode(g));
  }

  @override
  void didUpdateWidget(covariant PetView old) {
    super.didUpdateWidget(old);
    // Re-render when the genome / state / egg flag changes (e.g. equip a
    // cosmetic, hatch the egg).
    if (old.egg != widget.egg ||
        old.state != widget.state ||
        old.scale != widget.scale ||
        jsonEncode(old.genome) != jsonEncode(widget.genome)) {
      if (_tmpl != null) _c.loadHtmlString(_buildHtml());
    } else if (!widget.egg && old.celebrateSignal != widget.celebrateSignal) {
      // Cheap celebrate — no canvas reload.
      celebrate();
    }
  }

  /// Imperative celebrate (drop / task-complete) without a full reload.
  void celebrate() => _c.runJavaScript('window.celebratePet && window.celebratePet()');

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _c);
  }
}
