bool isCanonicalSessionEntityCard(Map<String, dynamic> card) {
  final kind = card['entity_kind']?.toString() ?? '';
  if (!const {'asset', 'event', 'contact'}.contains(kind)) return false;
  if ((card['entity_id']?.toString().trim() ?? '').isEmpty) return false;
  if (card['entity'] is! Map) return false;
  if (kind == 'asset' &&
      (card['skill_machine_name']?.toString().trim() ?? '').isEmpty) {
    return false;
  }
  final source = card['source'];
  if (source is! Map) return false;
  if ((source['session_id']?.toString().trim() ?? '').isEmpty ||
      (source['input_turn_id']?.toString().trim() ?? '').isEmpty) {
    return false;
  }
  return const {
    'capture',
    'chat',
    'report',
  }.contains(source['kind']?.toString());
}

List<Map<String, dynamic>> canonicalSessionEntityCards(Iterable<dynamic> raw) =>
    raw
        .whereType<Map>()
        .map((card) => card.cast<String, dynamic>())
        .where(isCanonicalSessionEntityCard)
        .toList(growable: false);

bool isSessionPendingActionCard(Map<String, dynamic> card) =>
    card['kind'] == 'pending_contact' &&
    card['card_type'] == 'pending_contact' &&
    (card['pending_action_id']?.toString().trim() ?? '').isNotEmpty &&
    card['candidates'] is List;

List<Map<String, dynamic>> sessionMessageCards(Iterable<dynamic> raw) => raw
    .whereType<Map>()
    .map((card) => card.cast<String, dynamic>())
    .where(
      (card) =>
          isCanonicalSessionEntityCard(card) ||
          isSessionPendingActionCard(card),
    )
    .toList(growable: false);
