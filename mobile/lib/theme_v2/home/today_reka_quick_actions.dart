import 'package:flutter/material.dart';

enum TodayRekaAction {
  manualRecord('手动记录'),
  createReport('创建报告'),
  startChat('开始新聊天');

  const TodayRekaAction(this.label);

  final String label;
}

Future<void> showTodayRekaQuickActions(
  BuildContext context, {
  required Rect anchor,
  required VoidCallback? onManualRecord,
  required VoidCallback? onCreateReport,
  required VoidCallback? onStartChat,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final selected = await showMenu<TodayRekaAction>(
    context: context,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    items: [
      _item(
        TodayRekaAction.manualRecord,
        Icons.add_circle_outline_rounded,
        enabled: onManualRecord != null,
      ),
      _item(
        TodayRekaAction.createReport,
        Icons.article_outlined,
        enabled: onCreateReport != null,
      ),
      _item(
        TodayRekaAction.startChat,
        Icons.chat_bubble_outline_rounded,
        enabled: onStartChat != null,
      ),
    ],
  );

  switch (selected) {
    case TodayRekaAction.manualRecord:
      onManualRecord?.call();
    case TodayRekaAction.createReport:
      onCreateReport?.call();
    case TodayRekaAction.startChat:
      onStartChat?.call();
    case null:
      return;
  }
}

PopupMenuItem<TodayRekaAction> _item(
  TodayRekaAction action,
  IconData icon, {
  required bool enabled,
}) {
  return PopupMenuItem<TodayRekaAction>(
    key: ValueKey('today-reka-action-${action.name}'),
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Text(action.label),
      ],
    ),
  );
}
