import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small themed toast that slides down from the **top** — matches the app's
/// notification toast position and the design system (dark/light). Use this for
/// transient confirmations/errors instead of the default Material SnackBar
/// (which pops from the bottom over the dock and ignores our theme).
void showToast(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      error: error,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String message;
  final bool error;
  final VoidCallback onDone;
  const _Toast({required this.message, required this.error, required this.onDone});

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 2000), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final accent = widget.error ? eu.accentRed : eu.brand;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -0.5), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _c,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: eu.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.40)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Text(widget.message,
                    style: TextStyle(
                        color: eu.textHi, fontSize: 13.5, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
