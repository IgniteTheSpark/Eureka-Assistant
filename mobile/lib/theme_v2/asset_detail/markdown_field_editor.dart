import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../markdown/theme_v2_markdown_text.dart';

class MarkdownFieldEditor extends StatefulWidget {
  const MarkdownFieldEditor({
    super.key,
    required this.label,
    required this.controller,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;

  @override
  State<MarkdownFieldEditor> createState() => _MarkdownFieldEditorState();
}

class _MarkdownFieldEditorState extends State<MarkdownFieldEditor> {
  bool _preview = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.label} · Markdown',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: tokens.muted),
              ),
            ),
            _ModeButton(
              label: '编辑',
              selected: !_preview,
              onPressed: () => setState(() => _preview = false),
            ),
            const SizedBox(width: ThemeV2Spacing.xs),
            _ModeButton(
              label: '预览',
              selected: _preview,
              onPressed: () => setState(() => _preview = true),
            ),
          ],
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        Container(
          constraints: const BoxConstraints(minHeight: 220),
          width: double.infinity,
          padding: const EdgeInsets.all(ThemeV2Spacing.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            border: Border.all(
              color: widget.errorText == null ? tokens.border : tokens.critical,
            ),
          ),
          child: _preview
              ? KeyedSubtree(
                  key: const ValueKey('markdown-editor-preview'),
                  child: widget.controller.text.trim().isEmpty
                      ? Text('（无内容）', style: TextStyle(color: tokens.muted))
                      : ThemeV2MarkdownText(
                          widget.controller.text,
                          baseStyle: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.55),
                        ),
                )
              : TextField(
                  key: const ValueKey('markdown-editor-input'),
                  controller: widget.controller,
                  minLines: 9,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration.collapsed(
                    hintText: '支持 Markdown：# 标题、**加粗**、*斜体*、- 列表、> 引用…',
                  ),
                ),
        ),
        if (widget.errorText case final error?)
          Padding(
            padding: const EdgeInsets.only(top: ThemeV2Spacing.xs),
            child: Text(
              error,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.critical),
            ),
          ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 36),
        padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.sm),
        backgroundColor: selected ? tokens.accentSoft : Colors.transparent,
        foregroundColor: selected ? tokens.accent : tokens.muted,
      ),
      child: Text(label),
    );
  }
}
