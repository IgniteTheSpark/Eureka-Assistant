import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// §9 Reka sprite factory — ONE hidden WebView that has the pixel engine
/// (`pixel.js` + `mascot.js`) loaded and renders any cosmetic preview to a PNG
/// via `canvas.toDataURL`. Lets the wardrobe show pixel-exact previews (the real
/// engine output, identical to the live pet) without spinning up one WebView per
/// grid cell. Results are cached by (opts) so re-renders are instant.
///
/// Mount [SpriteFactoryHost] once in the tree that needs previews (the dressup
/// board); preview widgets then call `SpriteFactory.instance.sprite(...)` /
/// `.part(...)`.
class SpriteFactory {
  SpriteFactory._();
  static final SpriteFactory instance = SpriteFactory._();

  /// The host widget binds the platform view to this so JS actually executes
  /// (a WKWebView only runs once it's realized in the tree).
  final ValueNotifier<WebViewController?> controller = ValueNotifier(null);

  Completer<void>? _ready;
  bool _attaching = false;
  final Map<String, Uint8List> _cache = {};

  /// Boot the engine WebView (idempotent) and resolve once `Mascot` is live.
  Future<void> ensureReady() {
    if (_ready != null) return _ready!.future;
    final c = Completer<void>();
    _ready = c;
    _boot(c);
    return c.future;
  }

  Future<void> _boot(Completer<void> done) async {
    if (!_attaching && controller.value == null) {
      _attaching = true;
      try {
        final pixel = await rootBundle.loadString('assets/js/pixel.js');
        final mascot = await rootBundle.loadString('assets/js/mascot.js');
        final ctrl = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0x00000000));
        await ctrl.loadHtmlString(_html(pixel, mascot));
        controller.value = ctrl; // host rebuilds → mounts the platform view
      } catch (_) {
        if (!done.isCompleted) done.complete();
        return;
      }
    }
    // Poll until the engine + render hooks are live (host must mount the view).
    final ctrl = controller.value;
    for (var i = 0; i < 60; i++) {
      if (ctrl != null) {
        try {
          final r = await ctrl.runJavaScriptReturningResult(
              'String(!!(window.__factoryReady && window.Mascot))');
          if (r.toString().contains('true')) break;
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (!done.isCompleted) done.complete();
  }

  String _html(String pixel, String mascot) => '''
<!doctype html><html><head><meta charset="utf-8"></head>
<body style="margin:0;background:transparent">
<script>$pixel</script>
<script>$mascot</script>
<script>
  window.renderSprite = function(json){
    try { var o = JSON.parse(json); return window.Mascot.sprite(o).toDataURL('image/png'); }
    catch(e){ return ''; }
  };
  window.renderPart = function(kind, key, json){
    try { var o = JSON.parse(json||'{}'); return window.Mascot.partSprite(kind, key, o).toDataURL('image/png'); }
    catch(e){ return ''; }
  };
  window.__factoryReady = true;
</script></body></html>''';

  /// Full Reka rendered with [opts] (wardrobe inventory cells use this with a
  /// per-slot preview genome). Returns PNG bytes, or null on failure.
  Future<Uint8List?> sprite(Map<String, dynamic> opts) async {
    final ck = 'sprite:${jsonEncode(opts)}';
    final hit = _cache[ck];
    if (hit != null) return hit;
    await ensureReady();
    final ctrl = controller.value;
    if (ctrl == null) return null;
    try {
      final r = await ctrl
          .runJavaScriptReturningResult('window.renderSprite(${_jsStr(jsonEncode(opts))})');
      return _store(ck, r);
    } catch (_) {
      return null;
    }
  }

  /// A single component in isolation (milestone reward icons use this).
  Future<Uint8List?> part(String kind, String key, [Map<String, dynamic> opts = const {}]) async {
    final ck = 'part:$kind:$key:${jsonEncode(opts)}';
    final hit = _cache[ck];
    if (hit != null) return hit;
    await ensureReady();
    final ctrl = controller.value;
    if (ctrl == null) return null;
    try {
      final r = await ctrl.runJavaScriptReturningResult(
          'window.renderPart(${_jsStr(kind)}, ${_jsStr(key)}, ${_jsStr(jsonEncode(opts))})');
      return _store(ck, r);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _store(String ck, Object r) {
    final bytes = _dataUrlToBytes(_decode(r));
    if (bytes != null) _cache[ck] = bytes;
    return bytes;
  }

  // runJavaScriptReturningResult may hand back the string already-unwrapped (iOS)
  // or as a JSON-quoted/escaped string (other platforms). Normalize both.
  String _decode(Object r) {
    var s = r.toString();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      try {
        return jsonDecode(s) as String;
      } catch (_) {
        s = s.substring(1, s.length - 1).replaceAll(r'\/', '/');
      }
    }
    return s;
  }

  Uint8List? _dataUrlToBytes(String url) {
    final i = url.indexOf(',');
    if (i < 0 || !url.startsWith('data:image')) return null;
    try {
      return base64Decode(url.substring(i + 1));
    } catch (_) {
      return null;
    }
  }

  // JS string literal (so the injected JSON survives as an argument).
  String _jsStr(String s) => jsonEncode(s);
}

/// Mount once where previews are needed. A 1×1 transparent WebView so the
/// platform view is realized (JS won't run on a never-mounted controller) but
/// it's visually nothing.
class SpriteFactoryHost extends StatefulWidget {
  const SpriteFactoryHost({super.key});

  @override
  State<SpriteFactoryHost> createState() => _SpriteFactoryHostState();
}

class _SpriteFactoryHostState extends State<SpriteFactoryHost> {
  @override
  void initState() {
    super.initState();
    SpriteFactory.instance.ensureReady();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebViewController?>(
      valueListenable: SpriteFactory.instance.controller,
      builder: (_, ctrl, _) {
        if (ctrl == null) return const SizedBox(width: 1, height: 1);
        return SizedBox(width: 1, height: 1, child: WebViewWidget(controller: ctrl));
      },
    );
  }
}

/// A pixel-exact cosmetic preview. Shows [fallback] (swatch/emoji) until the
/// factory returns the real sprite, then swaps to it. [cacheBytes] lets callers
/// hold the resolved bytes across rebuilds.
class SpritePreview extends StatefulWidget {
  final Future<Uint8List?> Function() render;
  final double size;
  final Widget fallback;
  /// Identifies *what* this renders. These widgets carry no [key], so when a grid
  /// rebuilds with different contents at the same position (e.g. switching the
  /// wardrobe tab from 身色 to 头部), Flutter reuses this State and `initState`
  /// does NOT re-run — without this the cell would keep the previous tab's stale
  /// sprite (a bare reka). When [cacheKey] differs from the prior build we drop
  /// the old sprite and re-render the new genome.
  final String? cacheKey;
  const SpritePreview(
      {super.key, required this.render, required this.size, required this.fallback, this.cacheKey});

  @override
  State<SpritePreview> createState() => _SpritePreviewState();
}

class _SpritePreviewState extends State<SpritePreview> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _go();
  }

  @override
  void didUpdateWidget(SpritePreview old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey) {
      _bytes = null; // drop the stale sprite (the imminent build shows fallback)
      _go();
    }
  }

  Future<void> _go() async {
    final b = await widget.render();
    if (mounted && b != null) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) return SizedBox(width: widget.size, height: widget.size, child: widget.fallback);
    return Image.memory(
      _bytes!,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none, // crisp pixels
      gaplessPlayback: true,
    );
  }
}
