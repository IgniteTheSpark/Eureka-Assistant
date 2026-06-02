import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _queryTools = {
  'tool_query_asset',
  'tool_query_event',
  'tool_query_contact',
  'tool_query_input_turn',
  'tool_query_digest',
};

/// True for tools whose result is not a renderable *created* card (queries +
/// report). Their results render as a one-line chip instead.
bool isQueryTool(String name) =>
    _queryTools.contains(name) || name == 'tool_render_report';

/// Pull created card dicts out of a FastMCP tool_result envelope. Mirrors the
/// web extractCardsFromToolResult: walks top-level / structuredContent /
/// JSON-in-content[0].text, returns tagged card maps.
List<Map<String, dynamic>> extractCards(Map<String, dynamic> response) {
  final candidates = <Map<String, dynamic>>[response];
  final sc = response['structuredContent'];
  if (sc is Map) candidates.add(sc.cast<String, dynamic>());
  final content = response['content'];
  if (content is List && content.isNotEmpty && content.first is Map) {
    final text = (content.first as Map)['text'];
    if (text is String) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map) candidates.add(parsed.cast<String, dynamic>());
      } catch (_) {
        // not JSON — ignore
      }
    }
  }
  for (final c in candidates) {
    for (final key in const ['assets', 'events', 'contacts', 'tasks']) {
      final arr = c[key];
      if (arr is List && arr.isNotEmpty) {
        return arr
            .whereType<Map>()
            .map((e) => _tag(e.cast<String, dynamic>()))
            .whereType<Map<String, dynamic>>()
            .toList();
      }
    }
    final single = _tag(c);
    if (single != null) return [single];
  }
  return [];
}

Map<String, dynamic>? _tag(Map<String, dynamic> d) {
  if (d['task_id'] != null) return {...d, 'card_type': 'task'};
  if (d['asset_id'] != null && d['payload'] != null) return d;
  if (d['event_id'] != null && d['title'] != null) return {...d, 'card_type': 'event'};
  if (d['contact_id'] != null && d['name'] != null) return {...d, 'card_type': 'contact'};
  return null;
}

const _skillIcons = {
  'todo': '✅',
  'event': '📅',
  'contact': '👤',
  'idea': '💡',
  'notes': '📝',
  'expense': '💰',
  'misc': '🗂',
  'external_ref': '🔗',
};

/// A compact in-chat card for a created asset / event / contact / task. The
/// render_spec-faithful card is a later E2 polish; this shows icon + title +
/// subtitle so created items are visible.
class ChatCard extends StatelessWidget {
  final Map<String, dynamic> card;
  const ChatCard(this.card, {super.key});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final (icon, title, subtitle) = _present(card);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: eu.textMid, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, String, String) _present(Map<String, dynamic> c) {
    switch (c['card_type']) {
      case 'event':
        return ('📅', '${c['title'] ?? '事件'}', '${c['location'] ?? ''}');
      case 'contact':
        final meta = [c['title'], c['company']]
            .whereType<String>()
            .where((s) => s.isNotEmpty);
        return ('👤', '${c['name'] ?? '联系人'}', meta.join(' · '));
      case 'task':
        return ('⏳', '${c['title'] ?? c['summary'] ?? '任务'}',
            '${c['external_system'] ?? ''}');
      default:
        final skill = c['user_skill_name'] as String?;
        final payload = (c['payload'] as Map?)?.cast<String, dynamic>() ?? {};
        final icon = _skillIcons[skill] ?? '🗂';
        final title = payload['content'] ??
            payload['title'] ??
            payload['name'] ??
            (payload['amount'] != null ? '¥${payload['amount']}' : null) ??
            (skill ?? '资产');
        final subtitle = payload['description'] ?? payload['due_date'] ?? '';
        return (icon, '$title', '$subtitle');
    }
  }
}
