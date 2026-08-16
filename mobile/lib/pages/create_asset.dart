import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/render_spec.dart' show RenderSpec, normalizeTodoSpec;
import '../render/skill_card.dart' show SkillCard, accentOf;
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../theme_v2/asset/asset_card.dart';
import '../theme_v2/asset/asset_card_display.dart';
import '../theme_v2/asset_detail/asset_entity_ref.dart';
import '../theme_v2/asset_detail/markdown_field_editor.dart';
import '../theme_v2/asset_detail/theme_v2_asset_edit_page.dart';
import '../theme_v2/foundation/canonical_entity_identity.dart';
import '../theme_v2/foundation/theme_v2_theme.dart';
import '../theme_v2/foundation/theme_v2_tokens.dart';
import '../theme_v2/foundation/theme_v2_typography.dart';
import '../theme_v2/reminders/reminder_configuration_sheet.dart';
import '../theme_v2/reminders/reminder_preferences.dart';
import 'event_attendees.dart';

/// Build the field-rendering RenderSpec for a skill from its payload_schema
/// (schemaFields / types / long / required / labels). Lets 快创 reuse the same
/// [ThemeV2AssetEditPage] as 编辑 — create is edit with empty data. (The card preview
/// resolves its own full spec via the provider; this only drives the inputs.)
RenderSpec renderSpecForSkill(SkillDef s) {
  final spec = RenderSpec(
    cardLayout: 'horizontal',
    icon: s.icon,
    accentColor: s.accentColor,
  ).withSchema(s.schema);
  return s.name == 'todo' ? normalizeTodoSpec(spec) : spec;
}

/// Serialize a picked wall-clock [DateTime] as Beijing time (+08:00) — matching
/// the backend's `_LOCAL_TZ` and the agent's ISO convention. `dateOnly` fields
/// emit a bare `YYYY-MM-DD` (no time, no offset) so there is zero timezone
/// ambiguity. Fixes the "picked 6.4 → saved as 6.5" off-by-one that came from
/// `DateTime.toIso8601String()` on a local value (it drops the offset, so the
/// backend re-read it as UTC and shifted the day).
String isoBeijing(DateTime d, {bool dateOnly = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${d.year}-${two(d.month)}-${two(d.day)}';
  if (dateOnly) return date;
  return '${date}T${two(d.hour)}:${two(d.minute)}:00+08:00';
}

/// A creatable skill (name + display + icon/accent + payload_schema), from
/// GET /api/skills. Drives the 快创 menu tiles + the schema-driven form.
class SkillDef {
  final String name;
  final String displayName;
  final String icon;
  final String accentColor;
  final Map<String, dynamic> schema;
  const SkillDef(
    this.name,
    this.displayName,
    this.icon,
    this.accentColor,
    this.schema,
  );
}

Future<List<SkillDef>> fetchSkillDefs(ApiClient api) async {
  final res = await api.getJson('/api/skills');
  final skills = (res is Map ? res['skills'] : null) as List? ?? const [];
  final out = <SkillDef>[];
  for (final s in skills.whereType<Map>()) {
    final name = s['name'] as String?;
    if (name == null ||
        name == 'event' ||
        name == 'qa' ||
        name == 'external_ref') {
      continue;
    }
    final rs = (s['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
    out.add(
      SkillDef(
        name,
        s['display_name'] as String? ?? name,
        resolveEntityIcon(name, configuredIcon: rs['icon'] as String?),
        rs['accent_color'] as String? ?? 'gray',
        (s['payload_schema'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
  return out;
}

/// 快创 — bottom sheet of creatable types (事件 + every skill). Tapping a tile
/// pushes that type's create form. Mirrors the web CreateAssetMenu.
void showCreateMenu(BuildContext context, {DateTime? presetDate}) {
  final eu = context.eu;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: eu.surfaceRaised,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _CreateMenu(presetDate: presetDate),
  );
}

Future<void> openThemeV2SkillCapture(
  BuildContext context, {
  required String skillName,
  required String displayName,
}) async {
  await Navigator.of(context).push<dynamic>(
    MaterialPageRoute<dynamic>(
      builder: (_) => ThemeV2AssetEditPage(
        reference: AssetEntityRef(
          kind: AssetEntityKind.asset,
          id: 'new:$skillName',
        ),
        initialValues: const {},
        mode: AssetEditMode.create,
        skillName: skillName,
        displayName: displayName,
      ),
    ),
  );
}

class _CreateMenu extends StatefulWidget {
  /// When created from an empty calendar day, new date/time fields default to it.
  final DateTime? presetDate;
  const _CreateMenu({this.presetDate});
  @override
  State<_CreateMenu> createState() => _CreateMenuState();
}

class _CreateMenuState extends State<_CreateMenu> {
  final _api = ApiClient();
  late final Future<List<SkillDef>> _future = fetchSkillDefs(_api);

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  void _open(Widget form) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => form));
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '创建',
                style: TextStyle(
                  color: eu.textHi,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<SkillDef>>(
                future: _future,
                builder: (ctx, snap) {
                  final tiles = <Widget>[
                    _tile(
                      eu,
                      '📅',
                      resolveEntityLabel('event'),
                      'purple',
                      () => _open(EventForm(presetDate: widget.presetDate)),
                    ),
                  ];
                  for (final s in snap.data ?? const <SkillDef>[]) {
                    // contact is a 真身 entity → its dedicated form (socials /
                    // email / notes). Every other asset skill uses the SAME
                    // ThemeV2AssetEditPage as 编辑 (create = edit with empty data).
                    final onTap = s.name == 'contact'
                        ? () => _open(const ContactForm())
                        : () => _open(
                            ThemeV2AssetEditPage(
                              reference: AssetEntityRef(
                                kind: AssetEntityKind.asset,
                                id: 'new:${s.name}',
                              ),
                              initialValues: const {},
                              mode: AssetEditMode.create,
                              skillName: s.name,
                              spec: renderSpecForSkill(s),
                              displayName: s.displayName,
                              presetDate: widget.presetDate,
                            ),
                          );
                    tiles.add(
                      _tile(eu, s.icon, s.displayName, s.accentColor, onTap),
                    );
                  }
                  return Wrap(spacing: 10, runSpacing: 10, children: tiles);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    EurekaColors eu,
    String icon,
    String label,
    String accent,
    VoidCallback onTap,
  ) {
    final a = accentOf(accent, eu);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: (MediaQuery.of(context).size.width.clamp(0, 460) - 32 - 10) / 2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: a.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: a.edge),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: eu.textHi,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ── Event create form ────────────────────────────────────────────────────── */

/// Parses both the enriched attendee contract and the legacy
/// `{attendee_id, name}` records still present in older event snapshots.
List<EventAttendeeDraft> eventAttendeeDraftsFromExisting(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((item) {
    final normalized = Map<dynamic, dynamic>.from(item);
    if ('${normalized['id'] ?? ''}'.trim().isEmpty) {
      normalized['id'] = normalized['attendee_id'];
    }
    if ('${normalized['name_raw'] ?? ''}'.trim().isEmpty &&
        '${normalized['name'] ?? ''}'.trim().isNotEmpty) {
      normalized['name_raw'] = normalized['name'];
    }
    if ('${normalized['display_name'] ?? ''}'.trim().isEmpty &&
        '${normalized['name'] ?? ''}'.trim().isNotEmpty) {
      normalized['display_name'] = normalized['name'];
    }
    return EventAttendeeDraft.fromJson(normalized);
  }).toList();
}

String? eventIdFromCreateResponse(dynamic response) {
  if (response is! Map) return null;
  final value = '${response['event_id'] ?? response['id'] ?? ''}'.trim();
  if (value.isNotEmpty) return value;
  return eventIdFromCreateResponse(response['event']);
}

({List<EventAttendeeDraft> original, List<EventAttendeeDraft> current})
reconcileEventAttendeesWithServer({
  required List<EventAttendeeDraft> server,
  required List<EventAttendeeDraft> desired,
}) {
  final available = List<EventAttendeeDraft>.of(server);
  final current = <EventAttendeeDraft>[];
  for (final attendee in desired) {
    var matchIndex = -1;
    if (attendee.id != null) {
      matchIndex = available.indexWhere((item) => item.id == attendee.id);
    }
    if (matchIndex < 0 && attendee.contactId != null) {
      matchIndex = available.indexWhere(
        (item) => item.contactId == attendee.contactId,
      );
    }
    if (matchIndex >= 0) {
      final matched = available.removeAt(matchIndex);
      current.add(
        EventAttendeeDraft(
          id: matched.id,
          contactId: attendee.contactId,
          nameRaw: attendee.nameRaw,
          displayName: attendee.displayName,
          role: attendee.role,
          isResolved: attendee.isResolved,
          contactSummary: attendee.contactSummary,
          contact: attendee.contact,
        ),
      );
    } else if (attendee.id != null) {
      current.add(
        EventAttendeeDraft(
          contactId: attendee.contactId,
          nameRaw: attendee.nameRaw,
          displayName: attendee.displayName,
          role: attendee.role,
          isResolved: attendee.isResolved,
          contactSummary: attendee.contactSummary,
          contact: attendee.contact,
        ),
      );
    } else {
      current.add(attendee);
    }
  }
  return (original: List<EventAttendeeDraft>.of(server), current: current);
}

List<EventAttendeeDraft>? eventAttendeesFromResponse(dynamic response) {
  if (response is! Map) return null;
  if (response.containsKey('attendees')) {
    final raw = response['attendees'];
    return raw is List ? eventAttendeeDraftsFromExisting(raw) : null;
  }
  return eventAttendeesFromResponse(response['event']);
}

class EventForm extends StatefulWidget {
  final DateTime?
  presetDate; // empty-day create → default the event to that day (09:00)
  final String? eventId; // non-null = EDIT mode (PUT instead of POST)
  final Map<String, dynamic>? existing; // event record to prefill in edit mode
  final ApiClient? api;
  final bool coreRecordsOnly;
  const EventForm({
    super.key,
    this.presetDate,
    this.eventId,
    this.existing,
    this.api,
    this.coreRecordsOnly = false,
  });
  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _start;
  // An event needs a time span: either an end_at after start, or all_day=1.
  late DateTime _end;
  bool _allDay = false;
  late List<int> _reminderOffsets;
  bool _busy = false;
  bool _attendeeSyncBlocked = false;
  String? _error;
  String? _savedCreateEventId;
  late List<EventAttendeeDraft> _originalAttendees;
  late List<EventAttendeeDraft> _attendees;
  bool get _isEdit => widget.eventId != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _originalAttendees = eventAttendeeDraftsFromExisting(e?['attendees']);
    _attendees = List<EventAttendeeDraft>.of(_originalAttendees);
    _reminderOffsets = normalizeReminderOffsets(e?['reminder_offsets_minutes']);
    if (e != null) {
      _title.text = '${e['title'] ?? ''}';
      _location.text = '${e['location'] ?? ''}';
      _desc.text = '${e['description'] ?? ''}';
      _allDay =
          e['all_day'] == 1 || e['all_day'] == true || e['all_day'] == '1';
      _start = _parseDt(e['start_at']) ?? _defaultStart();
      _end = _parseDt(e['end_at']) ?? _start.add(const Duration(hours: 1));
    } else {
      _start = _defaultStart();
      _end = _start.add(const Duration(hours: 1));
    }
    _title.addListener(_rebuild);
    _location.addListener(_rebuild);
    _desc.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  DateTime _defaultStart() => widget.presetDate != null
      ? DateTime(
          widget.presetDate!.year,
          widget.presetDate!.month,
          widget.presetDate!.day,
          9,
        )
      : _roundToHour(DateTime.now().add(const Duration(hours: 1)));
  static DateTime? _parseDt(dynamic v) => (v is String && v.isNotEmpty)
      ? DateTime.tryParse(v.replaceAll('Z', '+00:00'))?.toLocal()
      : null;
  static DateTime _roundToHour(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _desc.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _openContactForm(
    BuildContext context,
    String initialName,
  ) async {
    final receipt = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ContactForm(
          existing: initialName.isEmpty ? null : {'name': initialName},
        ),
      ),
    );
    return receipt is Map ? Map<String, dynamic>.from(receipt) : null;
  }

  Future<void> _addAttendees() async {
    final excludedIds = _attendees
        .map((attendee) => attendee.contactId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final selected = await showEventAttendeeSelector(
      context,
      api: _api,
      excludedContactIds: excludedIds,
      coreRecordsOnly: widget.coreRecordsOnly,
      onCreateContact: _openContactForm,
    );
    if (!mounted || selected == null) return;
    setState(() {
      final seen = _attendees
          .map((attendee) => attendee.contactId)
          .whereType<String>()
          .toSet();
      for (final contact in selected) {
        if (seen.add(contact.id)) {
          EventAttendeeDraft? persisted;
          for (final original in _originalAttendees) {
            if (original.id != null && original.contactId == contact.id) {
              persisted = original;
              break;
            }
          }
          _attendees.add(
            persisted?.copyWith(contact: contact) ??
                EventAttendeeDraft.fromContact(contact),
          );
        }
      }
    });
  }

  Future<void> _bindAttendee(int index) async {
    final target = _attendees[index];
    final excludedIds = _attendees
        .map((attendee) => attendee.contactId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final selected = await showEventAttendeeSelector(
      context,
      api: _api,
      excludedContactIds: excludedIds,
      initialQuery: target.nameRaw ?? target.displayName,
      singleSelect: true,
      coreRecordsOnly: widget.coreRecordsOnly,
      onCreateContact: _openContactForm,
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    final currentIndex = _attendees.indexOf(target);
    if (currentIndex < 0) return;
    setState(() {
      _attendees[currentIndex] = target.copyWith(contact: selected.first);
    });
  }

  Future<void> _pick({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 2),
      lastDate: DateTime(base.year + 3),
    );
    if (d == null || !mounted) return;
    var picked = DateTime(d.year, d.month, d.day);
    if (!_allDay) {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );
      picked = DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
    }
    setState(() {
      if (isStart) {
        _start = picked;
        // Keep end >= start (preserve the existing duration when possible).
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _pickReminders() async {
    final selected = await showReminderConfigurationSheet(
      context,
      initialOffsets: _reminderOffsets,
    );
    if (selected == null || !mounted) return;
    setState(() => _reminderOffsets = selected);
  }

  Future<void> _save() async {
    if (_busy || _attendeeSyncBlocked) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写标题');
      return;
    }
    if (!_allDay && !_end.isAfter(_start)) {
      setState(() => _error = '结束时间要晚于开始时间');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {
        'title': _title.text.trim(),
        'start_at': isoBeijing(
          _start,
          dateOnly: _allDay && !widget.coreRecordsOnly,
        ),
        if (!_allDay || widget.coreRecordsOnly) 'end_at': isoBeijing(_end),
        'all_day': widget.coreRecordsOnly ? _allDay : (_allDay ? 1 : 0),
        'location': _location.text.trim(),
        'description': _desc.text.trim(),
        if (widget.coreRecordsOnly)
          'reminder_offsets_minutes': _reminderOffsets,
        if (widget.coreRecordsOnly)
          'attendees': [
            for (final attendee in _attendees)
              {
                'name': attendee.nameRaw ?? attendee.displayName,
                'contact_id': attendee.contactId,
                'role': attendee.role,
              },
          ],
      };
      late final String savedEventId;
      if (_isEdit) {
        if (widget.coreRecordsOnly) {
          await _api.patchJson('/api/events/${widget.eventId}', body);
        } else {
          await _api.putJson('/api/events/${widget.eventId}', body);
        }
        savedEventId = widget.eventId!;
      } else if (_savedCreateEventId != null) {
        savedEventId = _savedCreateEventId!;
        if (widget.coreRecordsOnly) {
          await _api.patchJson('/api/events/$savedEventId', body);
        } else {
          await _api.putJson('/api/events/$savedEventId', body);
        }
      } else {
        final response = await _api.postJson('/api/events', body);
        savedEventId =
            eventIdFromCreateResponse(response) ??
            (throw StateError('创建事件响应缺少 event_id'));
        _savedCreateEventId = savedEventId;
      }
      if (widget.coreRecordsOnly) {
        bumpData();
        if (mounted) {
          Navigator.of(context).maybePop(
            _isEdit
                ? true
                : <String, dynamic>{
                    'event_id': savedEventId,
                    'user_skill_name': 'event',
                    'display_name': '日程',
                    'icon': '📅',
                    'payload': {'title': _title.text.trim()},
                  },
          );
        }
        return;
      }
      try {
        await syncEventAttendees(
          _api,
          eventId: savedEventId,
          original: _originalAttendees,
          current: _attendees,
        );
      } catch (e) {
        try {
          final response = await _api.getJson('/api/events/$savedEventId');
          final server =
              eventAttendeesFromResponse(response) ??
              (throw StateError('事件响应缺少 attendees'));
          final reconciled = reconcileEventAttendeesWithServer(
            server: server,
            desired: _attendees,
          );
          if (mounted) {
            setState(() {
              _originalAttendees = reconciled.original;
              _attendees = reconciled.current;
              _busy = false;
              _attendeeSyncBlocked = false;
              _error = '保存参会人失败：$e';
            });
          }
        } catch (refreshError) {
          if (mounted) {
            setState(() {
              _busy = false;
              _attendeeSyncBlocked = true;
              _error = '保存参会人失败，状态刷新失败，请重新打开事件后再试：$refreshError';
            });
          }
        }
        return;
      }
      bumpData();
      if (mounted) {
        Navigator.of(context).maybePop(
          _isEdit
              ? true
              : <String, dynamic>{
                  'event_id': savedEventId,
                  'user_skill_name': 'event',
                  'display_name': '日程',
                  'icon': '📅',
                  'payload': {'title': _title.text.trim()},
                },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  String _fmt(DateTime d) => _allDay
      ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> _previewCard() => {
    'card_type': 'event',
    'title': _title.text.trim(),
    'start_at': isoBeijing(_start, dateOnly: _allDay),
    if (!_allDay) 'end_at': isoBeijing(_end),
    'all_day': _allDay ? 1 : 0,
    'location': _location.text.trim(),
    'description': _desc.text.trim(),
    'attendees': [
      for (final attendee in _attendees)
        {
          'name': attendee.displayName,
          'display_name': attendee.displayName,
          'contact_id': attendee.contactId,
          'is_resolved': attendee.isResolved,
        },
    ],
  };

  Widget _attendeeSection(EurekaColors eu) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '参会人',
        style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
      ),
      const SizedBox(height: 8),
      for (var index = 0; index < _attendees.length; index++)
        Container(
          key: ValueKey(
            _attendees[index].id ??
                _attendees[index].contactId ??
                'attendee-$index',
          ),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: eu.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: eu.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _attendees[index].displayName,
                      style: TextStyle(
                        color: eu.textHi,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_attendees[index].contactSummary.isNotEmpty)
                      Text(
                        _attendees[index].contactSummary,
                        style: TextStyle(color: eu.textMid, fontSize: 12),
                      ),
                    if (!_attendees[index].isResolved)
                      Text(
                        '未关联联系人',
                        style: TextStyle(color: eu.textLo, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (_attendees[index].id != null && !_attendees[index].isResolved)
                TextButton(
                  onPressed: () => _bindAttendee(index),
                  child: const Text('关联'),
                ),
              IconButton(
                tooltip: '移除参会人',
                onPressed: () => setState(() => _attendees.removeAt(index)),
                icon: Icon(Icons.close, size: 18, color: eu.textLo),
              ),
            ],
          ),
        ),
      TextButton.icon(
        onPressed: _addAttendees,
        icon: Icon(Icons.add, size: 18, color: eu.brand),
        label: Text('添加参会人', style: TextStyle(color: eu.brand)),
      ),
    ],
  );

  Widget _timeBox(EurekaColors eu, String text, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: eu.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: eu.border),
          ),
          child: Text(text, style: TextStyle(color: eu.textHi, fontSize: 14)),
        ),
      );

  Widget _themeV2TimeField({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ThemeV2Typography.mono(
            fontSize: 10,
            color: tokens.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        Material(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                minHeight: ThemeV2Sizes.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.md,
                vertical: ThemeV2Spacing.md,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_outlined, size: 18, color: tokens.muted),
                  const SizedBox(width: ThemeV2Spacing.sm),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(color: tokens.foreground, fontSize: 14),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.muted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _themeV2AttendeeSection() {
    final tokens = context.themeV2;
    return Column(
      key: const ValueKey('theme-v2-event-attendees'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '参与人',
          style: ThemeV2Typography.mono(
            fontSize: 10,
            color: tokens.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        for (var index = 0; index < _attendees.length; index++)
          Container(
            key: ValueKey(
              'theme-v2-event-attendee-'
              '${_attendees[index].id ?? _attendees[index].contactId ?? index}',
            ),
            margin: const EdgeInsets.only(bottom: ThemeV2Spacing.sm),
            padding: const EdgeInsets.only(
              left: ThemeV2Spacing.md,
              top: ThemeV2Spacing.sm,
              bottom: ThemeV2Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: ThemeV2Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _attendees[index].displayName,
                        style: TextStyle(
                          color: tokens.foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_attendees[index].contactSummary.isNotEmpty)
                        Text(
                          _attendees[index].contactSummary,
                          style: TextStyle(color: tokens.muted, fontSize: 12),
                        ),
                      if (!_attendees[index].isResolved)
                        Text(
                          '未关联联系人',
                          style: TextStyle(
                            color: tokens.critical,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_attendees[index].id != null &&
                    !_attendees[index].isResolved)
                  TextButton(
                    onPressed: () => _bindAttendee(index),
                    child: const Text('关联'),
                  ),
                IconButton(
                  tooltip: '移除参与人',
                  constraints: const BoxConstraints(
                    minWidth: ThemeV2Sizes.minTouchTarget,
                    minHeight: ThemeV2Sizes.minTouchTarget,
                  ),
                  onPressed: () => setState(() => _attendees.removeAt(index)),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: tokens.muted,
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('theme-v2-event-add-contact'),
            onPressed: _addAttendees,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('添加联系人'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeV2(BuildContext context) {
    final tokens = context.themeV2;
    final previewSecondary = <String>[
      _fmt(_start),
      if (_location.text.trim().isNotEmpty) _location.text.trim(),
      if (_attendees.isNotEmpty) '${_attendees.length} 位参与人',
    ];
    return Scaffold(
      key: const ValueKey('theme-v2-event-editor'),
      backgroundColor: tokens.background,
      appBar: AppBar(
        leading: BackButton(
          key: const ValueKey('theme-v2-event-cancel'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_isEdit ? '编辑日程' : '创建日程'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IgnorePointer(
                ignoring: _busy,
                child: ListView(
                  key: const ValueKey('theme-v2-event-editor-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    ThemeV2Spacing.xl,
                    ThemeV2Spacing.sm,
                    ThemeV2Spacing.xl,
                    ThemeV2Spacing.xl,
                  ),
                  children: [
                    ThemeV2AssetCard(
                      variant: AssetCardVariant.richCard,
                      data: AssetCardViewData(
                        mark: '📅',
                        skillLabel: '日程',
                        primaryValue: _title.text.trim().isEmpty
                            ? '未命名日程'
                            : _title.text.trim(),
                        secondaryValues: previewSecondary,
                      ),
                      height: 86,
                    ),
                    const SizedBox(height: ThemeV2Spacing.xl),
                    TextField(
                      key: const ValueKey('theme-v2-event-title'),
                      controller: _title,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                        color: tokens.foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        labelText: '标题 *',
                        hintText: '日程标题',
                      ),
                    ),
                    const SizedBox(height: ThemeV2Spacing.lg),
                    Material(
                      color: tokens.surface,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: tokens.border),
                        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        key: const ValueKey('theme-v2-event-all-day'),
                        title: const Text('全天'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: ThemeV2Spacing.md,
                        ),
                        value: _allDay,
                        onChanged: (value) => setState(() => _allDay = value),
                      ),
                    ),
                    const SizedBox(height: ThemeV2Spacing.lg),
                    _themeV2TimeField(
                      key: const ValueKey('theme-v2-event-start'),
                      label: '开始时间',
                      value: _fmt(_start),
                      onTap: () => _pick(isStart: true),
                    ),
                    if (!_allDay) ...[
                      const SizedBox(height: ThemeV2Spacing.lg),
                      _themeV2TimeField(
                        key: const ValueKey('theme-v2-event-end'),
                        label: '结束时间',
                        value: _fmt(_end),
                        onTap: () => _pick(isStart: false),
                      ),
                    ],
                    const SizedBox(height: ThemeV2Spacing.lg),
                    Material(
                      color: tokens.surface,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: tokens.border),
                        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: const ValueKey('theme-v2-event-reminders'),
                        minTileHeight: ThemeV2Sizes.minTouchTarget,
                        leading: const Icon(Icons.notifications_none_rounded),
                        title: const Text('提醒'),
                        subtitle: Text(formatReminderSummary(_reminderOffsets)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _pickReminders,
                      ),
                    ),
                    const SizedBox(height: ThemeV2Spacing.lg),
                    TextField(
                      key: const ValueKey('theme-v2-event-location'),
                      controller: _location,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '地点',
                        hintText: '可选',
                      ),
                    ),
                    const SizedBox(height: ThemeV2Spacing.xl),
                    _themeV2AttendeeSection(),
                    const SizedBox(height: ThemeV2Spacing.xl),
                    MarkdownFieldEditor(
                      key: const ValueKey('theme-v2-event-description'),
                      label: '备注',
                      controller: _desc,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: ThemeV2Spacing.lg),
                      Text(
                        _error!,
                        style: TextStyle(color: tokens.critical, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                ThemeV2Spacing.xl,
                ThemeV2Spacing.sm,
                ThemeV2Spacing.xl,
                ThemeV2Spacing.md + MediaQuery.paddingOf(context).bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('theme-v2-event-save'),
                  onPressed: _busy || _attendeeSyncBlocked ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(
                      ThemeV2Sizes.minTouchTarget,
                    ),
                  ),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coreRecordsOnly) return _buildThemeV2(context);
    final eu = context.eu;
    InputDecoration dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: eu.textLo),
      isDense: true,
      filled: true,
      fillColor: eu.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: eu.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: eu.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: eu.brand),
      ),
    );
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('取消', style: TextStyle(color: eu.textMid, fontSize: 15)),
        ),
        leadingWidth: 64,
        centerTitle: true,
        title: Text(
          'EVENT',
          style: euMono(fontSize: 11, letterSpacing: 1.6, color: eu.textLo),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _busy || _attendeeSyncBlocked ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '保存',
                      style: TextStyle(
                        color: eu.brand,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 48),
          children: [
            Text(
              '预览',
              style: euMono(fontSize: 10, letterSpacing: 1.4, color: eu.textLo),
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              child: SkillCard(_previewCard(), layoutOverride: 'horizontal'),
            ),
            const SizedBox(height: 18),
            Container(height: 1, color: eu.rule),
            const SizedBox(height: 18),
            Text(
              '标题 · title *',
              style: TextStyle(
                color: eu.textLo,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: _title,
              style: TextStyle(
                color: eu.textHi,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '事件标题',
              ),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: eu.rule),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '全天',
                  style: TextStyle(
                    color: eu.textLo,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _allDay,
                  activeThumbColor: eu.brand,
                  onChanged: (v) => setState(() => _allDay = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '开始时间',
              style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
            ),
            const SizedBox(height: 6),
            _timeBox(eu, _fmt(_start), () => _pick(isStart: true)),
            if (!_allDay) ...[
              const SizedBox(height: 14),
              Text(
                '结束时间',
                style: euMono(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: eu.textLo,
                ),
              ),
              const SizedBox(height: 6),
              _timeBox(eu, _fmt(_end), () => _pick(isStart: false)),
            ],
            const SizedBox(height: 14),
            Text(
              '地点',
              style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _location,
              style: TextStyle(color: eu.textHi),
              decoration: dec('可选'),
            ),
            const SizedBox(height: 14),
            _attendeeSection(eu),
            const SizedBox(height: 14),
            // 描述 supports markdown (same editor as the asset editor) — events
            // often carry agendas / notes that want structure, not a flat field.
            Theme(
              data: buildThemeV2Theme(Theme.of(context).brightness),
              child: MarkdownFieldEditor(label: '描述', controller: _desc),
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: eu.accentRed, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// 名片 supported social platforms — a FIXED set (user picks from here, never
/// free-form). key = stored platform key (synced with backend
/// core/contacts_meta.py / spec §4.5.3a); label = 中文/品牌名; emoji = leading mark.
/// Order: China-first.
const List<({String key, String label, String emoji})> kSocialPlatforms = [
  (key: 'wechat', label: '微信', emoji: '💬'),
  (key: 'xiaohongshu', label: '小红书', emoji: '📕'),
  (key: 'x', label: 'X', emoji: '𝕏'),
  (key: 'telegram', label: 'Telegram', emoji: '✈️'),
  (key: 'linkedin', label: 'LinkedIn', emoji: '💼'),
  (key: 'instagram', label: 'Instagram', emoji: '📷'),
];

({String key, String label, String emoji}) _socialMeta(String key) =>
    kSocialPlatforms.firstWhere(
      (p) => p.key == key,
      orElse: () => (key: key, label: key, emoji: '🔗'),
    );

/// Preserve the 快创 receipt consumed by existing callers while exposing the
/// backend contact record to attendee selectors for immediate auto-selection.
Map<String, dynamic> contactCreationReceipt(
  dynamic response, {
  required String fallbackName,
}) {
  final responseMap = response is Map ? response : const <dynamic, dynamic>{};
  final rawContact = responseMap['contact'];
  final contact = rawContact is Map
      ? Map<String, dynamic>.from(rawContact)
      : <String, dynamic>{};
  final contactId = '${responseMap['contact_id'] ?? contact['id'] ?? ''}';
  return <String, dynamic>{
    'user_skill_name': 'contact',
    'display_name': '联系人',
    'icon': '👤',
    'payload': {'name': fallbackName},
    'contact_id': contactId,
    'contact': contact,
  };
}

/// Dedicated contact editor (and creator). EDIT mode when [contactId] is set
/// (PUT /api/contacts/{id}); otherwise POST /api/contacts. The contacts table
/// is the 真身 for contact data — this never routes through /api/assets.
class ContactForm extends StatefulWidget {
  final String? contactId; // non-null = EDIT mode
  final Map<String, dynamic>? existing; // contact record to prefill
  const ContactForm({super.key, this.contactId, this.existing});
  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  final _api = ApiClient();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _title = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController(); // one annotation per line (→ md)
  // socials: platform key → handle controller, only for platforms currently shown
  // (insertion-ordered). Picked from kSocialPlatforms, never free-form.
  final Map<String, TextEditingController> _socials = {};
  bool _busy = false;
  String? _error;
  bool get _isEdit => widget.contactId != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = '${e['name'] ?? ''}';
      _company.text = '${e['company'] ?? ''}';
      _title.text = '${e['title'] ?? ''}';
      _phone.text = '${e['phone'] ?? ''}';
      _email.text = '${e['email'] ?? ''}';
      final n = e['notes'];
      if (n is List) {
        _notes.text = n.map((x) => '$x').join('\n');
      } else if (n is String) {
        _notes.text = n;
      }
      final s = e['socials'];
      if (s is Map) {
        // preserve kSocialPlatforms order for a stable layout
        for (final p in kSocialPlatforms) {
          final h = s[p.key];
          if (h != null && '$h'.trim().isNotEmpty) {
            _socials[p.key] = TextEditingController(text: '$h'.trim())
              ..addListener(_rebuild);
          }
        }
      }
    }
    for (final c in [_name, _company, _title, _phone, _email, _notes]) {
      c.addListener(_rebuild);
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _company,
      _title,
      _phone,
      _email,
      _notes,
      ..._socials.values,
    ]) {
      c.dispose();
    }
    _api.close();
    super.dispose();
  }

  /// Show the platforms not yet added → tap to add a row (focus it). This is the
  /// "select from supported list" gate — no free-form platforms.
  Future<void> _addSocial() async {
    final remaining = kSocialPlatforms
        .where((p) => !_socials.containsKey(p.key))
        .toList();
    if (remaining.isEmpty) return;
    final eu = context.eu;
    final key = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: eu.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '添加社交媒体',
                  style: euMono(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: eu.textLo,
                  ),
                ),
              ),
            ),
            for (final p in remaining)
              ListTile(
                leading: Text(p.emoji, style: const TextStyle(fontSize: 20)),
                title: Text(
                  p.label,
                  style: TextStyle(
                    color: eu.textHi,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(p.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (key != null && mounted) {
      setState(
        () => _socials[key] = TextEditingController()..addListener(_rebuild),
      );
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写姓名');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final notes = _notes.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final socials = <String, String>{};
    _socials.forEach((k, c) {
      final h = c.text.trim();
      if (h.isNotEmpty) socials[k] = h;
    });
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'company': _company.text.trim(),
      'title': _title.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'notes': notes,
      'socials': socials, // full replace; supported-only enforced by backend
    };
    try {
      dynamic createResponse;
      if (_isEdit) {
        await _api.putJson('/api/contacts/${widget.contactId}', body);
      } else {
        createResponse = await _api.postJson('/api/contacts', body);
      }
      bumpData();
      if (mounted) {
        Navigator.of(context).maybePop(
          _isEdit
              ? true
              : contactCreationReceipt(
                  createResponse,
                  fallbackName: _name.text.trim(),
                ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    Map<String, dynamic> previewCard() {
      final socials = <String, String>{};
      _socials.forEach((k, c) {
        final h = c.text.trim();
        if (h.isNotEmpty) socials[k] = h;
      });
      return {
        'card_type': 'contact',
        'name': _name.text.trim(),
        'company': _company.text.trim(),
        'title': _title.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'notes': _notes.text.trim(),
        'socials': socials,
      };
    }

    InputDecoration dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: eu.textLo),
      isDense: true,
      filled: true,
      fillColor: eu.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: eu.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: eu.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: eu.brand),
      ),
    );
    Widget field(
      String label,
      TextEditingController c, {
      String hint = '可选',
      TextInputType? kb,
      int min = 1,
      int max = 1,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          style: TextStyle(color: eu.textHi),
          decoration: dec(hint),
          keyboardType: kb,
          minLines: min,
          maxLines: max,
        ),
        const SizedBox(height: 14),
      ],
    );
    Widget socialRow(String key) {
      final m = _socialMeta(key);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(m.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                m.label,
                style: TextStyle(
                  color: eu.textHi,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _socials[key],
                style: TextStyle(color: eu.textHi),
                decoration: dec('账号 / 链接'),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: eu.textLo),
              onPressed: () {
                final c = _socials.remove(key);
                setState(() {});
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => c?.dispose(),
                );
              },
            ),
          ],
        ),
      );
    }

    final remainingSocials = kSocialPlatforms
        .where((p) => !_socials.containsKey(p.key))
        .toList();
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('取消', style: TextStyle(color: eu.textMid, fontSize: 15)),
        ),
        leadingWidth: 64,
        centerTitle: true,
        title: Text(
          'CONTACT',
          style: euMono(fontSize: 11, letterSpacing: 1.6, color: eu.textLo),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '保存',
                      style: TextStyle(
                        color: eu.brand,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 48),
          children: [
            Text(
              '预览',
              style: euMono(fontSize: 10, letterSpacing: 1.4, color: eu.textLo),
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              child: SkillCard(previewCard(), layoutOverride: 'horizontal'),
            ),
            const SizedBox(height: 18),
            Container(height: 1, color: eu.rule),
            const SizedBox(height: 18),
            Text(
              '姓名 · name *',
              style: TextStyle(
                color: eu.textLo,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: _name,
              style: TextStyle(
                color: eu.textHi,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '联系人姓名',
              ),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: eu.rule),
            const SizedBox(height: 18),
            field('公司', _company),
            field('职位', _title),
            field('电话', _phone, kb: TextInputType.phone),
            field('邮箱', _email, kb: TextInputType.emailAddress),
            // 社交媒体 — pick from the supported list, store the handle only
            Text(
              '社交媒体',
              style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
            ),
            const SizedBox(height: 8),
            for (final key in _socials.keys.toList()) socialRow(key),
            if (remainingSocials.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addSocial,
                  icon: Icon(Icons.add, size: 18, color: eu.brand),
                  label: Text(
                    '添加社交媒体',
                    style: TextStyle(color: eu.brand, fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            field('备注', _notes, hint: '在哪相遇 / 怎么认识…一行一条', min: 3, max: 6),
            const SizedBox(height: 4),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: eu.accentRed, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
