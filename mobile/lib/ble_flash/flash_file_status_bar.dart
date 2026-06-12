import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'flash_file_status_controller.dart';

class FlashFileStatusBar extends StatelessWidget {
  const FlashFileStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return ValueListenableBuilder<FlashFileStatus>(
      valueListenable: FlashFileStatusController.instance.status,
      builder: (context, status, _) {
        if (!status.visible) return const SizedBox.shrink();
        final bg = status.isError
            ? eu.accentRed.withValues(alpha: 0.92)
            : eu.text.withValues(alpha: 0.88);
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    status.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: eu.bg,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
