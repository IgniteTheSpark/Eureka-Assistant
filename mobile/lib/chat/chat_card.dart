import 'dart:convert';

/// Card extraction helpers shared by chat + flash. Card *rendering* now lives in
/// render/skill_card.dart (the render_spec-driven SkillCard).

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
